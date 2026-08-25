import Foundation

public struct Extractor: Sendable {
    private let tools: ToolLocator
    private let runner: ProcessRunner

    public init(tools: ToolLocator, runner: ProcessRunner = ProcessRunner()) {
        self.tools = tools
        self.runner = runner
    }

    public func extract(
        plan: ExtractionPlan,
        expectedDuration: Double?,
        onProgress: @escaping @Sendable (Double?) -> Void
    ) async throws -> URL {
        let clip = plan.trim.clipSeconds(mediaDuration: expectedDuration)
        let expectedOutputSeconds = clip.map { $0 / plan.speed }
        let output = plan.jobDir.appendingPathComponent("output.mp3")
        let result = try await runner.run(
            tools.ffmpeg(),
            arguments: FFmpegCommand.extractArguments(
                input: plan.sourceFile, output: output, trim: plan.trim, speed: plan.speed),
            onStdoutLine: { line in
                if let fraction = FFmpegProgressParser.fraction(
                    line: line, expectedOutputSeconds: expectedOutputSeconds)
                {
                    onProgress(fraction)
                }
            })
        guard result.exitCode == 0 else {
            throw ExtractorError.conversionFailed(detail: ExtractorError.tail(result.stderr))
        }
        guard FileManager.default.fileExists(atPath: output.path) else {
            throw ExtractorError.outputMissing
        }
        return output
    }
}
