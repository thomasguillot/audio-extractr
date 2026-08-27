import Foundation
import Testing

@testable import ExtractrKit

@Suite struct AppVersionTests {
    @Test func parsesAndCompares() throws {
        let a = try #require(AppVersion("v1.2.3"))
        let b = try #require(AppVersion("1.10.0"))
        #expect(a < b)
        #expect(AppVersion("1.2") == nil)
        #expect(AppVersion("x.y.z") == nil)
        #expect(AppVersion("2026.07.04") != nil)
    }
}

@Suite struct UpdatePlanTests {
    static let digest = String(repeating: "ab", count: 32)

    /// Real releases carry the digest under the install heading, which `ReleaseNotes` strips,
    /// so appending it here leaves the block assertions measuring the notes alone.
    static func body(_ notes: String, digest: String? = digest) -> String {
        guard let digest else { return notes }
        return "\(notes)\n\n## Install (unsigned app)\n\n**DMG SHA-256**\n`\(digest)`"
    }

    func release(
        tag: String, body: String = "- Something", assetName: String = "AudioExtractr-9.9.9.dmg",
        url: String = "https://github.com/x/y.dmg", prerelease: Bool = false, draft: Bool = false,
        digest: String? = digest
    ) -> GitHubRelease {
        GitHubRelease(
            tagName: tag, htmlURL: "https://github.com/x/y/releases/tag/\(tag)",
            assets: [
                .init(
                    name: assetName, browserDownloadURL: url, size: 42)
            ],
            body: Self.body(body, digest: digest), prerelease: prerelease, draft: draft)
    }

    func evaluate(
        _ releases: [GitHubRelease], current: String = "1.0.0", skipped: String = "",
        interactive: Bool = true
    ) throws -> UpdatePlan.Outcome {
        let version = try #require(AppVersion(current))
        return UpdatePlan.evaluate(
            current: version, releases: releases, skipped: skipped, interactive: interactive)
    }

    func available(_ outcome: UpdatePlan.Outcome) throws -> UpdatePlan.AvailableUpdate {
        guard case let .available(update) = outcome else {
            Issue.record("expected .available, got \(outcome)")
            throw CancellationError()
        }
        return update
    }

    @Test func versionRenders() throws {
        #expect(try #require(AppVersion("v1.2.3")).displayString == "1.2.3")
    }

    @Test func newestReleaseWins() throws {
        let update = try available(
            try evaluate([release(tag: "v1.1.0"), release(tag: "v1.3.0"), release(tag: "v1.2.0")]))
        #expect(update.version == AppVersion("1.3.0"))
        #expect(update.size == 42)
        #expect(update.dmgURL.absoluteString == "https://github.com/x/y.dmg")
        #expect(update.pageURL?.absoluteString == "https://github.com/x/y/releases/tag/v1.3.0")
        #expect(update.sha256 == Self.digest)
    }

    /// The digest is the only integrity check on an unsigned DMG, so a release without one
    /// is not installable.
    @Test func aReleaseWithNoPublishedDigestIsNotOffered() throws {
        let outcome = try evaluate([release(tag: "v1.3.0", digest: nil)])
        #expect(outcome == .upToDate)
    }

    @Test func aMalformedDigestIsNotOffered() throws {
        let outcome = try evaluate([release(tag: "v1.3.0", digest: "not-a-sha")])
        #expect(outcome == .upToDate)
    }

    @Test func sectionsCoverEveryVersionAboveCurrentNewestFirst() throws {
        let update = try available(
            try evaluate([
                release(tag: "v1.1.0", body: "- One"),
                release(tag: "v0.9.0", body: "- Old"),
                release(tag: "v1.2.0", body: "- Two"),
            ]))
        #expect(update.sections.map(\.version) == ["1.2.0", "1.1.0"])
        #expect(update.sections[0].blocks == [.bullet("Two")])
        #expect(update.sections[1].blocks == [.bullet("One")])
    }

    @Test func sectionsWithNothingToSayAreOmitted() throws {
        let update = try available(
            try evaluate([release(tag: "v1.2.0", body: "- Two"), release(tag: "v1.1.0", body: "")]))
        #expect(update.sections.map(\.version) == ["1.2.0"])
    }

    @Test func draftsAndPrereleasesAreIgnored() throws {
        #expect(
            try evaluate([release(tag: "v2.0.0", draft: true), release(tag: "v3.0.0", prerelease: true)])
                == .upToDate)
    }

    @Test func failsClosedOnBadTagMissingDMGOrInsecureURL() throws {
        #expect(try evaluate([release(tag: "v0.9.0")]) == .upToDate)
        #expect(try evaluate([release(tag: "nightly")]) == .upToDate)
        #expect(try evaluate([]) == .upToDate)
        #expect(try evaluate([release(tag: "v2.0.0", assetName: "notes.txt")]) == .upToDate)
        #expect(try evaluate([release(tag: "v2.0.0", url: "http://insecure/x.dmg")]) == .upToDate)
    }

    @Test func skipSilencesBackgroundChecksOnly() throws {
        let releases = [release(tag: "v1.1.0")]
        #expect(try evaluate(releases, skipped: "1.1.0", interactive: false) == .upToDate)
        #expect(try evaluate(releases, skipped: "1.1.0", interactive: true) != .upToDate)
    }

    @Test func aNewerReleaseDefeatsTheSkippedVersion() throws {
        #expect(try evaluate([release(tag: "v1.2.0")], skipped: "1.1.0", interactive: false) != .upToDate)
    }

    @Test func emptyOrUnparseableSkipSuppressesNothing() throws {
        let releases = [release(tag: "v1.1.0")]
        #expect(try evaluate(releases, skipped: "", interactive: false) != .upToDate)
        #expect(try evaluate(releases, skipped: "garbage", interactive: false) != .upToDate)
    }

    @Test func skipCoverageIsQueryableOnItsOwn() throws {
        let skipped = "1.1.0"
        #expect(UpdatePlan.isSkipped(try #require(AppVersion("1.1.0")), skipped: skipped))
        #expect(UpdatePlan.isSkipped(try #require(AppVersion("1.0.5")), skipped: skipped))
        #expect(!UpdatePlan.isSkipped(try #require(AppVersion("1.2.0")), skipped: skipped))
        #expect(!UpdatePlan.isSkipped(try #require(AppVersion("1.1.0")), skipped: ""))
        #expect(!UpdatePlan.isSkipped(try #require(AppVersion("1.1.0")), skipped: "garbage"))
    }
}

@Suite struct GitHubReleaseDecodingTests {
    @Test func decodesListWithBodiesAndFlags() throws {
        let json = """
            [
              {"tag_name":"v0.3.0","html_url":"https://github.com/x/y/releases/tag/v0.3.0",
               "body":"## What's new\\n- Update window","prerelease":false,"draft":true,"assets":[]},
              {"tag_name":"v0.2.0","html_url":"https://github.com/x/y/releases/tag/v0.2.0",
               "body":null,"prerelease":true,"assets":[]}
            ]
            """
        let releases = try JSONDecoder().decode([GitHubRelease].self, from: Data(json.utf8))
        #expect(releases.count == 2)
        #expect(releases[0].body == "## What's new\n- Update window")
        #expect(releases[0].draft)
        #expect(!releases[0].prerelease)
        #expect(releases[1].body.isEmpty)
        #expect(releases[1].prerelease)
        #expect(!releases[1].draft)
    }

    @Test func memberwiseInitStillTakesThreeArguments() {
        let release = GitHubRelease(tagName: "v1.0.0", htmlURL: "https://github.com/x", assets: [])
        #expect(release.body.isEmpty)
        #expect(!release.prerelease)
        #expect(!release.draft)
    }

    /// `Asset` gets the synthesized decoder, so any field it declares is required. A nested
    /// asset that throws takes the whole release with it and silently stops update checks.
    @Test func anAssetDecodesFromOnlyTheFieldsWeRead() throws {
        let json = #"""
            {"tag_name": "v1.2.3", "assets": [
              {"name": "a.dmg", "browser_download_url": "https://x/a.dmg", "size": 7}
            ]}
            """#
        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
        #expect(release.assets.map(\.name) == ["a.dmg"])
        #expect(release.assets[0].size == 7)
    }
}

@Suite struct ReleasesEndpointTests {
    @Test func buildsListEndpoint() throws {
        let url = try #require(ReleaseFetcher.releasesEndpoint(repoSlug: "a/b", perPage: 30))
        #expect(url.absoluteString == "https://api.github.com/repos/a/b/releases?per_page=30")
    }

    @Test func clampsPerPageToGitHubsRange() throws {
        let low = try #require(ReleaseFetcher.releasesEndpoint(repoSlug: "a/b", perPage: 0))
        let high = try #require(ReleaseFetcher.releasesEndpoint(repoSlug: "a/b", perPage: 500))
        #expect(low.absoluteString.hasSuffix("per_page=1"))
        #expect(high.absoluteString.hasSuffix("per_page=100"))
    }

    @Test func rejectsASlugThatBreaksTheURL() {
        #expect(ReleaseFetcher.releasesEndpoint(repoSlug: "a b/c d", perPage: 30) == nil)
    }
}

@Suite struct FetchErrorTests {
    @Test func aMalformedSlugIsReportedAsSuchNotAsInsecure() async {
        let fetcher = ReleaseFetcher(repoSlug: "a b/c d")
        await #expect(throws: ReleaseFetcher.FetchError.invalidRepository) {
            _ = try await fetcher.fetchReleases()
        }
        await #expect(throws: ReleaseFetcher.FetchError.invalidRepository) {
            _ = try await fetcher.fetchLatest()
        }
    }

    @Test func everyCaseReadsAsASentence() {
        let errors: [ReleaseFetcher.FetchError] = [
            .invalidRepository, .insecureURL, .badStatus(404), .tooLarge,
        ]
        for error in errors {
            let message = error.localizedDescription
            #expect(!message.isEmpty)
            #expect(!message.contains("FetchError"))
            #expect(message.hasSuffix("."))
        }
        #expect(ReleaseFetcher.FetchError.badStatus(404).localizedDescription.contains("404"))
    }
}

@Suite struct HTTPGuardFailureMappingTests {
    /// Both fetchers keep their own error taxonomy, so the shared guard's failures have to
    /// arrive as the case each one already surfaces to the user.
    @Test func releaseFetcherMapsEveryFailure() {
        #expect(ReleaseFetcher.FetchError(.insecureRedirect) == .insecureRedirect)
        #expect(ReleaseFetcher.FetchError(.badStatus(503)) == .badStatus(503))
        #expect(ReleaseFetcher.FetchError(.tooLarge) == .tooLarge)
    }

    @Test func ytDlpUpdaterMapsEveryFailure() {
        #expect(YtDlpUpdater.UpdateError(.insecureRedirect) == .insecureRedirect)
        #expect(YtDlpUpdater.UpdateError(.badStatus(404)) == .badStatus(404))
        #expect(YtDlpUpdater.UpdateError(.tooLarge) == .tooLarge)
    }

    @Test func badStatusMessageNamesTheCode() {
        #expect(HTTPGuard.badStatusMessage(418).contains("418"))
        #expect(ReleaseFetcher.FetchError.badStatus(418).localizedDescription
            == HTTPGuard.badStatusMessage(418))
    }
}
