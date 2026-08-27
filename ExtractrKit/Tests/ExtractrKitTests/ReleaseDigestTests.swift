import Testing

@testable import ExtractrKit

@Suite struct ReleaseDigestTests {
    let digest = "0b886d873b0992abc0a010b105b0d3c3b8109cf782fc839c57295fe1a8093b15"

    @Test func readsTheShippedReleaseFormat() {
        let body = """
            Audio Extractr can now write a transcript alongside the MP3.

            **Requires macOS 26 (Tahoe) or later · Apple Silicon**.

            **DMG SHA-256**
            `\(digest)`
            """
        #expect(ReleaseDigest.sha256(fromBody: body) == digest)
    }

    @Test(arguments: ["SHA-256", "SHA256", "sha-256", "SHA2-256", "sha 256"])
    func toleratesMarkerSpellings(_ marker: String) {
        #expect(ReleaseDigest.sha256(fromBody: "\(marker): \(digest)") == digest)
    }

    @Test func normalisesCase() {
        #expect(ReleaseDigest.sha256(fromBody: "SHA-256 \(digest.uppercased())") == digest)
    }

    @Test func requiresTheMarker() {
        #expect(ReleaseDigest.sha256(fromBody: "A bare hash \(digest) with no label") == nil)
    }

    @Test func ignoresADigestPrecedingTheMarker() {
        let body = "commit \(String(repeating: "a", count: 64))\n\nDMG SHA-256\n`\(digest)`"
        #expect(ReleaseDigest.sha256(fromBody: body) == digest)
    }

    @Test func missingOrMalformedIsNil() {
        #expect(ReleaseDigest.sha256(fromBody: "") == nil)
        #expect(ReleaseDigest.sha256(fromBody: "No notes here.") == nil)
        #expect(ReleaseDigest.sha256(fromBody: "SHA-256: not-a-hash") == nil)
        #expect(ReleaseDigest.sha256(fromBody: "SHA-256 \(String(repeating: "a", count: 63))") == nil)
    }
}
