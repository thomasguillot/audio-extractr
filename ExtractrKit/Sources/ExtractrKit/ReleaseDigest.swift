import Foundation

/// Pulls the DMG SHA-256 the release notes publish.
///
/// The body is not a trustworthy channel on its own — it arrives over the same connection as the
/// asset URL, so this stops a tampered or swapped asset host, not an attacker who can rewrite the
/// whole API response. It is the strongest check available while the DMG stays unsigned.
public enum ReleaseDigest {
    /// The first 64-hex token after a "SHA-256" marker, lowercased. The marker is required so an
    /// unrelated digest elsewhere in the notes is never mistaken for the DMG's.
    public static func sha256(fromBody body: String) -> String? {
        guard let marker = body.firstMatch(of: /(?i)sha2?[\s\-]*256/) else { return nil }
        let after = body[marker.range.upperBound...]
        guard let hex = after.firstMatch(of: /\b([0-9a-fA-F]{64})\b/) else { return nil }
        return String(hex.1).lowercased()
    }
}
