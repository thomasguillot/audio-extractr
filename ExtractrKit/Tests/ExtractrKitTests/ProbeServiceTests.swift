import Foundation
import Testing

@testable import ExtractrKit

/// A stand-in `ffprobe` that records its arguments and prints a canned reply. No `ffmpeg`
/// sits beside it, so a probe that still ran ffmpeg would fail to launch.
private struct FakeFFprobe {
    let root: URL
    let bin: URL
    let input: URL

    init(stdout: Data, exitCode: Int32 = 0, stderr: String = "") throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ps-\(UUID().uuidString)")
        bin = root.appendingPathComponent("bin")
        input = root.appendingPathComponent("clip one.m4a")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try stdout.write(to: bin.appendingPathComponent("reply.json"))
        try Data("x".utf8).write(to: input)
        let script = """
            #!/bin/sh
            printf '%s\\n' "$@" > "$(dirname "$0")/args"
            cat "$(dirname "$0")/reply.json"
            printf '%s' '\(stderr)' 1>&2
            exit \(exitCode)
            """
        FileManager.default.createFile(
            atPath: bin.appendingPathComponent("ffprobe").path, contents: Data(script.utf8),
            attributes: [.posixPermissions: 0o755])
    }

    var service: ProbeService {
        ProbeService(
            tools: ToolLocator(bundledBinDir: bin, updatedBinDir: root.appendingPathComponent("updated")))
    }

    var recordedArguments: [String] {
        get throws {
            try String(contentsOf: bin.appendingPathComponent("args"), encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

@Suite struct ProbeServiceTests {
    @Test func probesALocalFileWithTheBundledFFprobe() async throws {
        let fake = try FakeFFprobe(stdout: try ffprobeFixture("audio-only"))
        defer { fake.remove() }
        let probe = try await fake.service.probe(.localFile(fake.input))
        #expect(probe == MediaProbe(title: "clip one", duration: 3))
        #expect(try fake.recordedArguments == FFprobeCommand.arguments(file: fake.input))
    }

    @Test func aFailedProbeReportsFFprobesError() async throws {
        let fake = try FakeFFprobe(
            stdout: Data("{\n\n}\n".utf8), exitCode: 1, stderr: "clip: Invalid data found")
        defer { fake.remove() }
        await #expect(throws: ExtractorError.probeFailed(detail: "clip: Invalid data found")) {
            try await fake.service.probe(.localFile(fake.input))
        }
    }

    @Test func aNonZeroExitFailsEvenWithUsableOutput() async throws {
        let fake = try FakeFFprobe(stdout: try ffprobeFixture("audio-only"), exitCode: 1)
        defer { fake.remove() }
        await #expect(throws: ExtractorError.probeFailed(detail: "")) {
            try await fake.service.probe(.localFile(fake.input))
        }
    }

    /// The cap keeps the head, so oversized output is cut mid-document and cannot decode.
    @Test func outputOverTheCapFailsClosed() async throws {
        var padded = try ffprobeFixture("audio-only")
        padded.insert(
            contentsOf: Data(repeating: UInt8(ascii: " "), count: ProbeService.probeStdoutLimit), at: 1)
        let fake = try FakeFFprobe(stdout: padded)
        defer { fake.remove() }
        await #expect(throws: ExtractorError.probeFailed(detail: "")) {
            try await fake.service.probe(.localFile(fake.input))
        }
    }

    @Test func aMissingFileIsNotProbed() async throws {
        let fake = try FakeFFprobe(stdout: try ffprobeFixture("audio-only"))
        defer { fake.remove() }
        let missing = fake.root.appendingPathComponent("gone.m4a")
        await #expect(throws: ExtractorError.probeFailed(detail: "File not found: \(missing.path)")) {
            try await fake.service.probe(.localFile(missing))
        }
        #expect(!FileManager.default.fileExists(atPath: fake.bin.appendingPathComponent("args").path))
    }
}

private let repoBinaries = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Support/binaries")

private let realBinaries =
    ProcessInfo.processInfo.environment["EXTRACTR_BIN_DIR"]
    .map { URL(fileURLWithPath: $0) } ?? repoBinaries

/// One second of a 440 Hz tone as 16-bit mono PCM, so the audio-only build needs no source filter.
private func writeTone(to url: URL, rate: Int = 8_000) throws {
    let samples = (0..<rate).map { Int16(sin(Double($0) * 2 * .pi * 440 / Double(rate)) * 8_000) }
    var data = Data()
    func append<T: FixedWidthInteger>(_ value: T) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
    data.append(contentsOf: Array("RIFF".utf8))
    append(UInt32(36 + samples.count * 2))
    data.append(contentsOf: Array("WAVEfmt ".utf8))
    append(UInt32(16))
    append(UInt16(1))
    append(UInt16(1))
    append(UInt32(rate))
    append(UInt32(rate * 2))
    append(UInt16(2))
    append(UInt16(16))
    data.append(contentsOf: Array("data".utf8))
    append(UInt32(samples.count * 2))
    for sample in samples { append(sample) }
    try data.write(to: url)
}

/// Runs the real ffmpeg and ffprobe end to end, once both are in `Support/binaries` (or in
/// `EXTRACTR_BIN_DIR`).
@Suite(
    .enabled(
        if: ["ffmpeg", "ffprobe"].allSatisfy {
            FileManager.default.isExecutableFile(atPath: realBinaries.appendingPathComponent($0).path)
        }))
struct ProbeServiceBinaryTests {
    let tools = ToolLocator(bundledBinDir: realBinaries, updatedBinDir: realBinaries)

    private func withTempDir(_ body: (URL) async throws -> Void) async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("psb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try await body(dir)
    }

    @Test(.timeLimit(.minutes(1))) func probesAWAVAndAnMP3WithAForgedTitle() async throws {
        try await withTempDir { dir in
            let wav = dir.appendingPathComponent("tone.wav")
            let mp3 = dir.appendingPathComponent("tagged.mp3")
            try writeTone(to: wav)
            let encode = try await ProcessRunner().run(
                tools.ffmpeg(),
                arguments: ["-hide_banner", "-nostdin"] + FFmpegCommand.inputArguments(wav) + [
                    "-codec:a", "libmp3lame", "-metadata",
                    "title=x\n  Duration: 99:00:00.00, start: 5.000000", "-y", mp3.path,
                ])
            #expect(encode.exitCode == 0)

            let service = ProbeService(tools: tools)
            let tone = try await service.probe(.localFile(wav))
            #expect(tone == MediaProbe(title: "tone", duration: 1))
            let tagged = try await service.probe(.localFile(mp3))
            #expect(tagged.title == "tagged")
            #expect(tagged.duration.map { abs($0 - 1) < 0.1 } == true)
        }
    }

    @Test(.timeLimit(.minutes(1))) func aPlaylistRenamedToM4AIsRefused() async throws {
        try await withTempDir { dir in
            let playlist = dir.appendingPathComponent("evil.m4a")
            try Data("#EXTM3U\n#EXTINF:1,\nfile:///etc/hosts\n#EXT-X-ENDLIST\n".utf8).write(to: playlist)
            await #expect {
                try await ProbeService(tools: tools).probe(.localFile(playlist))
            } throws: { error in
                guard case .probeFailed = error as? ExtractorError else { return false }
                return true
            }
        }
    }
}
