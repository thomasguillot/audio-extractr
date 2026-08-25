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
                .init(name: "yt-dlp_macos", browserDownloadURL: "https://github.com/a",
                      contentType: "application/octet-stream", size: 1),
                .init(name: "SHA2-256SUMS", browserDownloadURL: "https://github.com/b",
                      contentType: "text/plain", size: 1),
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
                .init(name: "yt-dlp_macos", browserDownloadURL: "http://github.com/a",
                      contentType: "x", size: 1),
                .init(name: "SHA2-256SUMS", browserDownloadURL: "https://github.com/b",
                      contentType: "x", size: 1),
            ])
        #expect(YtDlpReleaseAssets.locate(in: insecure) == nil)
        #expect(YtDlpReleaseAssets.locate(in: GitHubRelease(tagName: "t", htmlURL: "https://x", assets: [])) == nil)
    }
}
