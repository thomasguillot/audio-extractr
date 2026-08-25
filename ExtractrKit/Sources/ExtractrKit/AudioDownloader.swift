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

    public static func findDownloaded(in files: [URL]) -> URL? {
        files.first {
            $0.lastPathComponent.hasPrefix("download.")
                && !$0.lastPathComponent.hasSuffix(".part")
        }
    }
}
