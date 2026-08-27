import Foundation
import Testing

@testable import ExtractrKit

@Suite struct SHA256SumsTests {
    let sums = """
        0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef  yt-dlp
        fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210  yt-dlp_macos
        """

    @Test func findsHash() {
        #expect(
            SHA256Sums.hash(for: "yt-dlp_macos", in: sums)
                == "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210")
    }
    @Test func missingFileIsNil() {
        #expect(SHA256Sums.hash(for: "nope", in: sums) == nil)
    }
}

@Suite struct YtDlpReleaseAssetsTests {
    @Test func locatesBinaryAndSums() throws {
        let release = GitHubRelease(
            tagName: "2026.07.04", htmlURL: "https://github.com/yt-dlp/yt-dlp",
            assets: [
                .init(name: "yt-dlp_macos", browserDownloadURL: "https://github.com/a", size: 1),
                .init(name: "SHA2-256SUMS", browserDownloadURL: "https://github.com/b", size: 1),
            ])
        let located = try #require(YtDlpReleaseAssets.locate(in: release))
        #expect(located.tag == "2026.07.04")
        #expect(located.binaryURL.absoluteString == "https://github.com/a")
        #expect(located.sumsURL.absoluteString == "https://github.com/b")
    }
    @Test func missingOrInsecureAssetsAreNil() {
        let insecure = GitHubRelease(
            tagName: "t", htmlURL: "https://x",
            assets: [
                .init(name: "yt-dlp_macos", browserDownloadURL: "http://github.com/a", size: 1),
                .init(name: "SHA2-256SUMS", browserDownloadURL: "https://github.com/b", size: 1),
            ])
        #expect(YtDlpReleaseAssets.locate(in: insecure) == nil)
        #expect(YtDlpReleaseAssets.locate(in: GitHubRelease(tagName: "t", htmlURL: "https://x", assets: [])) == nil)
    }
}

@Suite struct YtDlpUpgradePolicyTests {
    @Test func acceptsANewerTag() {
        #expect(YtDlpUpdater.isUpgrade(from: "2026.07.04", to: "2026.08.19"))
    }
    @Test func rejectsTheSameTag() {
        #expect(!YtDlpUpdater.isUpgrade(from: "2026.07.04", to: "2026.07.04"))
    }
    @Test(arguments: ["2026.07.03", "2026.06.04", "2025.07.04"])
    func rejectsAReplayedOlderTag(_ candidate: String) {
        #expect(!YtDlpUpdater.isUpgrade(from: "2026.07.04", to: candidate))
    }
    @Test func firstInstallHasNothingToCompare() {
        #expect(YtDlpUpdater.isUpgrade(from: nil, to: "2026.07.04"))
        #expect(YtDlpUpdater.isUpgrade(from: "", to: "2026.07.04"))
    }
    @Test func unparseableTagsFallBackToInequality() {
        #expect(YtDlpUpdater.isUpgrade(from: "nightly", to: "2026.07.04"))
        #expect(!YtDlpUpdater.isUpgrade(from: "nightly", to: "nightly"))
    }
}
