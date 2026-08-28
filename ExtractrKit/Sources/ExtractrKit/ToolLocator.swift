import Foundation

/// Resolves tool binaries: a user-updated yt-dlp (written by YtDlpUpdater) wins over the
/// bundled seed; ffmpeg is bundled-only — never executed from a user-writable location.
public struct ToolLocator: Sendable {
    public let bundledBinDir: URL
    public let updatedBinDir: URL

    public init(bundledBinDir: URL, updatedBinDir: URL) {
        self.bundledBinDir = bundledBinDir
        self.updatedBinDir = updatedBinDir
    }

    public func ytDlp(fileManager: FileManager = .default) -> URL {
        let bundled = bundledBinDir.appendingPathComponent("yt-dlp")
        let updated = updatedBinDir.appendingPathComponent("yt-dlp")
        guard fileManager.isExecutableFile(atPath: updated.path) else { return bundled }
        // An app update can ship a newer seed than the copy the user self-updated to
        // earlier, and the updated one would otherwise shadow it for good.
        guard let bundledTag = TagFile.read(bundledYtDlpTagFile),
            let updatedTag = TagFile.read(updatedYtDlpTagFile)
        else { return updated }
        return YtDlpUpdater.isUpgrade(from: bundledTag, to: updatedTag) ? updated : bundled
    }

    public func ffmpeg() -> URL {
        bundledBinDir.appendingPathComponent("ffmpeg")
    }

    public var ffmpegDir: String { bundledBinDir.path }

    public var bundledYtDlpTagFile: URL {
        bundledBinDir.appendingPathComponent("yt-dlp.tag")
    }

    public var updatedYtDlpTagFile: URL {
        updatedBinDir.appendingPathComponent("yt-dlp.tag")
    }
}

enum TagFile {
    static func read(_ url: URL?) -> String? {
        guard let url, let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return tag.isEmpty ? nil : tag
    }
}
