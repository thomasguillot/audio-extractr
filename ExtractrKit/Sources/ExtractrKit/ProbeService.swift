import Foundation

public struct ProbeService: Sendable {
    private let tools: ToolLocator
    private let runner: ProcessRunner

    public init(tools: ToolLocator, runner: ProcessRunner = ProcessRunner()) {
        self.tools = tools
        self.runner = runner
    }

    /// The whole of `ffmpeg -i`'s stderr is the header the parser reads, head first.
    static let probeStderrLimit = 4 << 20

    public func probe(_ input: MediaInput) async throws -> MediaProbe {
        switch input {
        case let .remote(url):
            let result = try await runner.run(
                tools.ytDlp(), arguments: YtDlpCommand.probeArguments(url: url),
                stop: YtDlpCommand.stop)
            guard result.exitCode == 0, let probe = YtDlpProbeParser.parse(Data(result.stdout.utf8))
            else { throw ExtractorError.probeFailed(detail: ExtractorError.tail(result.stderr)) }
            return probe
        case let .localFile(url):
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ExtractorError.probeFailed(detail: "File not found: \(url.path)")
            }
            // ffmpeg -i with no output exits non-zero by design; the Duration line still prints.
            let result = try await runner.run(
                tools.ffmpeg(), arguments: FFmpegCommand.probeArguments(file: url),
                stderrLimit: Self.probeStderrLimit)
            let title = url.deletingPathExtension().lastPathComponent
            guard
                let probe = FFmpegProbeParser.parse(
                    stderr: result.stderr, title: title.isEmpty ? nil : title)
            else { throw ExtractorError.probeFailed(detail: ExtractorError.tail(result.stderr)) }
            return probe
        }
    }
}
