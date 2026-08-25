import Foundation

public struct PreviewTranscoder: Sendable {
    private let tools: ToolLocator
    private let runner: ProcessRunner

    public init(tools: ToolLocator, runner: ProcessRunner = ProcessRunner()) {
        self.tools = tools
        self.runner = runner
    }

    /// m4a copy for AVFoundation playback when the source container isn't natively readable.
    public func transcode(_ file: URL, jobDir: URL) async throws -> URL {
        let output = jobDir.appendingPathComponent("preview.m4a")
        let result = try await runner.run(
            tools.ffmpeg(), arguments: FFmpegCommand.previewArguments(input: file, output: output))
        guard result.exitCode == 0 else {
            throw ExtractorError.conversionFailed(detail: ExtractorError.tail(result.stderr))
        }
        return output
    }
}
