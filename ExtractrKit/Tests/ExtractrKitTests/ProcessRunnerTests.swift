import Foundation
import Testing

@testable import ExtractrKit

@Suite struct ProcessRunnerTests {
    let runner = ProcessRunner()

    @Test func capturesStdoutAndExitCode() async throws {
        let result = try await runner.run(URL(fileURLWithPath: "/bin/echo"), arguments: ["hello"])
        #expect(result.exitCode == 0)
        #expect(result.stdout == "hello\n")
    }
    @Test func capturesNonZeroExit() async throws {
        let result = try await runner.run(URL(fileURLWithPath: "/usr/bin/false"), arguments: [])
        #expect(result.exitCode != 0)
    }
    @Test func capturesStderr() async throws {
        let result = try await runner.run(
            URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo oops 1>&2"])
        #expect(result.stderr == "oops\n")
    }
    @Test func streamsLines() async throws {
        let collected = LineCollector()
        _ = try await runner.run(
            URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "printf 'a\\nb\\n'"],
            onStdoutLine: { collected.append($0) })
        #expect(collected.lines == ["a", "b"])
    }
    // yt-dlp -J emits its whole JSON as one multi-hundred-KB line; a reader that
    // stalls on lines larger than the pipe buffer deadlocks the child mid-write.
    @Test(.timeLimit(.minutes(1))) func largeSingleLineOutputDoesNotDeadlock() async throws {
        let result = try await runner.run(
            URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "head -c 600000 /dev/zero | tr '\\0' 'a'; echo"])
        #expect(result.exitCode == 0)
        #expect(result.stdout.count == 600_001)
    }
    /// Only the tail of stderr is ever shown, so a child flooding it cannot grow memory.
    @Test(.timeLimit(.minutes(1))) func stderrKeepsOnlyTheTail() async throws {
        let script = "{ head -c 300000 /dev/zero | tr '\\0' 'a'; echo; echo END; } 1>&2"
        let result = try await runner.run(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script])
        #expect(result.stderr.utf8.count == ProcessRunner.defaultStderrLimit)
        #expect(result.stderr.hasSuffix("a\nEND\n"))
        let small = try await runner.run(
            URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script], stderrLimit: 10)
        #expect(small.stderr == "aaaaa\nEND\n")
    }
    @Test(.timeLimit(.minutes(1))) func stdoutStopsAtItsCapButLinesStillStream() async throws {
        let collected = LineCollector()
        let result = try await runner.run(
            URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "head -c 5000 /dev/zero | tr '\\0' 'a'; echo; echo last"],
            stdoutLimit: 100, onStdoutLine: { collected.append($0) })
        #expect(result.exitCode == 0)
        #expect(result.stdout == String(repeating: "a", count: 100))
        #expect(collected.lines.last == "last")
        #expect(ProcessRunner.defaultStdoutLimit == 32 << 20)
    }
    @Test func theLocalProbeKeepsTheWholeHeader() {
        #expect(ProbeService.probeStderrLimit == 4 << 20)
    }
    @Test func missingExecutableThrows() async {
        await #expect(throws: ProcessRunnerError.self) {
            try await runner.run(URL(fileURLWithPath: "/no/such/tool"), arguments: [])
        }
    }
    /// `onCancel` can run before or during `run()`, when the process is not yet running.
    /// A cancel that lands there must still stop the child from starting, or the task
    /// reports cancelled while yt-dlp or ffmpeg carries on to completion.
    @Test(.timeLimit(.minutes(1)))
    func cancelBeforeLaunchNeverStartsTheChild() async throws {
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("processrunner-cancel-\(UUID().uuidString)")
        let gate = Gate()
        let task = Task {
            await gate.wait()
            return try await runner.run(
                URL(fileURLWithPath: "/usr/bin/touch"), arguments: [marker.path])
        }
        task.cancel()
        await gate.open()

        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        try? FileManager.default.removeItem(at: marker)
    }
    private func marker() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("processrunner-\(UUID().uuidString)")
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// yt-dlp stops its own ffmpeg fixup on SIGINT; SIGTERM kills it outright and orphans it.
    @Test(.timeLimit(.minutes(1))) func interruptibleCancelSendsSIGINTFirst() async throws {
        let file = marker()
        let registry = ProcessRegistry()
        let runner = ProcessRunner(registry: registry)
        let task = Task {
            try await runner.run(
                URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "trap 'touch \(file.path); exit 3' INT; sleep 5 >/dev/null 2>&1 & wait"],
                stop: .interrupt(grace: .seconds(5)))
        }
        try await waitUntil { registry.count == 1 }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        _ = try? await task.value
        #expect(FileManager.default.fileExists(atPath: file.path))
        try? FileManager.default.removeItem(at: file)
    }

    @Test(.timeLimit(.minutes(1))) func aChildIgnoringSIGINTIsTerminatedAfterTheGrace() async throws {
        let registry = ProcessRegistry()
        let runner = ProcessRunner(registry: registry)
        let start = ContinuousClock.now
        let task = Task {
            try await runner.run(
                URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "trap '' INT; sleep 5 >/dev/null 2>&1 & wait"],
                stop: .interrupt(grace: .milliseconds(300)))
        }
        try await waitUntil { registry.count == 1 }
        task.cancel()
        _ = try? await task.value
        #expect(ContinuousClock.now - start < .seconds(4))
        #expect(registry.count == 0)
    }

    /// The app's quit path: every live child is stopped before the app exits.
    @Test(.timeLimit(.minutes(1))) func terminateAllStopsEveryLiveChild() async throws {
        let file = marker()
        let registry = ProcessRegistry()
        let runner = ProcessRunner(registry: registry)
        let plain = Task {
            try await runner.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"])
        }
        let interruptible = Task {
            try await runner.run(
                URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "trap 'touch \(file.path); exit 3' INT; sleep 5 >/dev/null 2>&1 & wait"],
                stop: .interrupt(grace: .seconds(5)))
        }
        try await waitUntil { registry.count == 2 }
        try await Task.sleep(for: .milliseconds(100))
        let start = ContinuousClock.now
        registry.terminateAll(grace: .seconds(2))
        #expect(ContinuousClock.now - start < .seconds(3))
        #expect(try await plain.value.exitCode != 0)
        #expect(try await interruptible.value.exitCode == 3)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(registry.count == 0)
        try? FileManager.default.removeItem(at: file)
    }

    @Test func cancellationTerminatesQuickly() async throws {
        let start = ContinuousClock.now
        let task = Task {
            try await runner.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"])
        }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        _ = try? await task.value
        #expect(ContinuousClock.now - start < .seconds(5))
    }
}

final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [String] = []
    var lines: [String] { lock.withLock { _lines } }
    func append(_ line: String) { lock.withLock { _lines.append(line) } }
}

/// Cancellation-transparent gate: `Task.sleep` would throw on an already-cancelled
/// task, so the body under test would never be reached.
actor Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false

    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}
