import Foundation

public struct ProbeService: Sendable {
    private let tools: ToolLocator
    private let runner: ProcessRunner

    public init(tools: ToolLocator, runner: ProcessRunner = ProcessRunner()) {
        self.tools = tools
        self.runner = runner
    }

    /// Far above what the requested fields come to; past it the JSON is cut and fails to decode.
    static let probeStdoutLimit = 1 << 20

    /// Throws `.liveStream` for a live or upcoming stream and `.playlist` for a link to a
    /// playlist.
    public func probe(_ input: MediaInput) async throws -> MediaProbe {
        switch input {
        case let .remote(url):
            let result = try await runner.run(
                tools.ytDlp(), arguments: YtDlpCommand.probeArguments(url: url),
                stop: YtDlpCommand.stop)
            guard result.exitCode == 0, let probe = YtDlpProbeParser.parse(Data(result.stdout.utf8))
            else { throw ExtractorError.probeFailed(detail: ExtractorError.tail(result.stderr)) }
            try Self.check(probe)
            return probe
        case let .localFile(url):
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ExtractorError.probeFailed(detail: "File not found: \(url.path)")
            }
            let result = try await runner.run(
                tools.ffprobe(), arguments: FFprobeCommand.arguments(file: url),
                stdoutLimit: Self.probeStdoutLimit)
            let title = url.deletingPathExtension().lastPathComponent
            guard result.exitCode == 0,
                let probe = FFprobeParser.parse(
                    Data(result.stdout.utf8), title: title.isEmpty ? nil : title)
            else { throw ExtractorError.probeFailed(detail: ExtractorError.tail(result.stderr)) }
            return probe
        }
    }

    static func check(_ probe: MediaProbe) throws {
        if probe.isPlaylist { throw ExtractorError.playlist }
        if probe.isLive { throw ExtractorError.liveStream }
    }
}
