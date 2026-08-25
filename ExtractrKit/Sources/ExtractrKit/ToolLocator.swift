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
        let updated = updatedBinDir.appendingPathComponent("yt-dlp")
        if fileManager.isExecutableFile(atPath: updated.path) { return updated }
        return bundledBinDir.appendingPathComponent("yt-dlp")
    }

    public func ffmpeg() -> URL {
        bundledBinDir.appendingPathComponent("ffmpeg")
    }

    public var ffmpegDir: String { bundledBinDir.path }

    public var bundledYtDlpTagFile: URL {
        bundledBinDir.appendingPathComponent("yt-dlp.tag")
    }
}
