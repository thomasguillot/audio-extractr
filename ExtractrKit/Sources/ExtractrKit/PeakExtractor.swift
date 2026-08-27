import Foundation

public struct PeakExtractor: Sendable {
    private let tools: ToolLocator
    private let runner: ProcessRunner

    public init(tools: ToolLocator, runner: ProcessRunner = ProcessRunner()) {
        self.tools = tools
        self.runner = runner
    }

    public func peaks(for file: URL, count: Int, jobDir: URL) async throws -> [Float] {
        let pcm = jobDir.appendingPathComponent("peaks.pcm")
        defer { try? FileManager.default.removeItem(at: pcm) }
        let result = try await runner.run(
            tools.ffmpeg(), arguments: FFmpegCommand.pcmArguments(input: file, output: pcm))
        guard result.exitCode == 0 else {
            throw ExtractorError.probeFailed(detail: ExtractorError.tail(result.stderr))
        }
        let data = try Data(contentsOf: pcm)
        return WaveformPeaks.buckets(fromPCM: data, count: count)
    }
}
