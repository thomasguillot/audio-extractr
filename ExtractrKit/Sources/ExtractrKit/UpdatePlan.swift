import Foundation

/// Pure policy deciding whether a set of releases is an installable update, and
/// what to say about it. Fail-closed: an unparseable tag, a missing `.dmg`, a
/// non-https asset URL, or a release body with no DMG SHA-256 all mean `.upToDate`.
public enum UpdatePlan {
    public struct Section: Equatable, Sendable {
        public let version: String
        public let blocks: [ReleaseNotes.Block]
    }

    public struct AvailableUpdate: Equatable, Sendable {
        public let version: AppVersion
        public let dmgURL: URL
        public let size: Int
        public let sha256: String
        public let pageURL: URL?
        public let sections: [Section]
    }

    public enum Outcome: Equatable, Sendable {
        case upToDate
        case available(AvailableUpdate)
    }

    public static func evaluate(
        current: AppVersion, releases: [GitHubRelease], skipped: String = "", interactive: Bool
    ) -> Outcome {
        let candidates = releases
            .filter { !$0.draft && !$0.prerelease }
            .compactMap { release -> (version: AppVersion, release: GitHubRelease)? in
                guard let version = AppVersion(release.tagName), version > current else { return nil }
                return (version, release)
            }
            .sorted { $0.version > $1.version }

        guard let newest = candidates.first else { return .upToDate }
        guard !isSkipped(newest.version, skipped: skipped, interactive: interactive) else {
            return .upToDate
        }
        guard let dmg = installableDMG(in: newest.release) else { return .upToDate }
        guard let sha256 = ReleaseDigest.sha256(fromBody: newest.release.body) else {
            return .upToDate
        }

        let sections =
            candidates
            .map {
                Section(
                    version: $0.version.displayString,
                    blocks: ReleaseNotes.blocks(from: $0.release.body))
            }
            .filter { !$0.blocks.isEmpty }

        return .available(
            AvailableUpdate(
                version: newest.version, dmgURL: dmg.url, size: dmg.size, sha256: sha256,
                pageURL: URLPolicy.httpsURL(newest.release.htmlURL), sections: sections))
    }

    /// An unparseable value suppresses nothing, so a corrupt preference cannot hide updates.
    public static func isSkipped(_ version: AppVersion, skipped: String) -> Bool {
        guard let skipped = AppVersion(skipped) else { return false }
        return version <= skipped
    }

    /// Skip silences background checks only.
    private static func isSkipped(_ version: AppVersion, skipped: String, interactive: Bool) -> Bool {
        guard !interactive else { return false }
        return isSkipped(version, skipped: skipped)
    }

    private static func installableDMG(in release: GitHubRelease) -> (url: URL, size: Int)? {
        guard let asset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }),
            let url = URLPolicy.httpsURL(asset.browserDownloadURL)
        else { return nil }
        return (url, asset.size)
    }
}
