import Foundation

public struct AudioDownloader: Sendable {
    private let tools: ToolLocator
    private let runner: ProcessRunner

    public init(tools: ToolLocator, runner: ProcessRunner = ProcessRunner()) {
        self.tools = tools
        self.runner = runner
    }

    public func download(
        _ url: URL, into jobDir: URL,
        onProgress: @escaping @Sendable (Double?) -> Void
    ) async throws -> URL {
        let template = jobDir.appendingPathComponent("download.%(ext)s").path
        let result = try await runner.run(
            tools.ytDlp(),
            arguments: YtDlpCommand.downloadArguments(
                url: url, outputTemplate: template, ffmpegDir: tools.ffmpegDir),
            stop: YtDlpCommand.stop,
            onStdoutLine: { line in
                if let fraction = YtDlpProgressParser.fraction(line: line) {
                    onProgress(fraction)
                }
            })
        guard result.exitCode == 0 else {
            throw ExtractorError.downloadFailed(detail: ExtractorError.tail(result.stderr))
        }
        let files = try FileManager.default.contentsOfDirectory(
            at: jobDir, includingPropertiesForKeys: nil)
        guard let downloaded = Self.findDownloaded(in: files) else {
            throw ExtractorError.downloadFailed(detail: "Downloaded file not found")
        }
        return downloaded
    }

    /// One extension, any container: the `best` fallback keeps whatever the site serves.
    /// While yt-dlp works the folder also holds .part, .ytdl and download.temp.<ext> files.
    public static func findDownloaded(in files: [URL]) -> URL? {
        files.first { file in
            guard let match = file.lastPathComponent.wholeMatch(of: /download\.([A-Za-z0-9_]+)/)
            else { return false }
            return !["part", "ytdl", "temp"].contains(match.1.lowercased())
        }
    }
}
