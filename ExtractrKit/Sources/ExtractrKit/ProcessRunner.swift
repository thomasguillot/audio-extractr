import Foundation

public struct ProcessOutput: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
}

public enum ProcessRunnerError: Error {
    case launchFailed(String)
}

// Process/Pipe predate Sendable; confined here so `onCancel` and the readers can touch them.
private final class ProcessBox: @unchecked Sendable {
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()
}

/// The only unit in the app that spawns child processes. Arguments are always
/// passed as arrays — never through a shell.
public struct ProcessRunner: Sendable {
    public init() {}

    /// Chunked rather than `FileHandle.bytes.lines`: the line iterator stalls once a single
    /// line outgrows its internal buffer, which stops draining the pipe and deadlocks the
    /// child mid-write — yt-dlp -J emits its whole JSON as one multi-hundred-KB line.
    private func drainTask(_ pipe: Pipe, onLine: (@Sendable (String) -> Void)?) -> Task<String, Never> {
        Task.detached {
            let handle = pipe.fileHandleForReading
            let chunks = AsyncStream<Data> { continuation in
                handle.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        handle.readabilityHandler = nil
                        continuation.finish()
                    } else {
                        continuation.yield(data)
                    }
                }
                continuation.onTermination = { _ in handle.readabilityHandler = nil }
            }

            var collected = Data()
            var pending = Data()
            for await chunk in chunks {
                collected.append(chunk)
                guard onLine != nil else { continue }
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 0x0A) {
                    let line = pending.subdata(in: pending.startIndex..<newline)
                    pending.removeSubrange(pending.startIndex...newline)
                    onLine?(Self.lineString(line))
                }
            }
            if let onLine, !pending.isEmpty {
                onLine(Self.lineString(pending))
            }
            return String(decoding: collected, as: UTF8.self)
        }
    }

    private static func lineString(_ data: Data) -> String {
        var line = data
        if line.last == 0x0D { line.removeLast() }
        return String(decoding: line, as: UTF8.self)
    }

    public func run(
        _ executable: URL,
        arguments: [String],
        onStdoutLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> ProcessOutput {
        let box = ProcessBox()
        box.process.executableURL = executable
        box.process.arguments = arguments
        box.process.standardInput = FileHandle.nullDevice
        box.process.standardOutput = box.stdout
        box.process.standardError = box.stderr

        // Readers must drain concurrently with the wait or a full pipe deadlocks the child.
        let outTask = drainTask(box.stdout, onLine: onStdoutLine)
        let errTask = drainTask(box.stderr, onLine: nil)

        do {
            let exitCode: Int32 = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    box.process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                    do {
                        try box.process.run()
                    } catch {
                        box.process.terminationHandler = nil
                        // Nothing else will ever close the pipes' write ends after a failed
                        // launch, so outTask/errTask would block on read() forever.
                        box.stdout.fileHandleForWriting.closeFile()
                        box.stderr.fileHandleForWriting.closeFile()
                        continuation.resume(throwing: ProcessRunnerError.launchFailed(error.localizedDescription))
                    }
                }
            } onCancel: {
                if box.process.isRunning { box.process.terminate() }
            }

            let stdout = await outTask.value
            let stderr = await errTask.value
            try Task.checkCancellation()
            return ProcessOutput(exitCode: exitCode, stdout: stdout, stderr: stderr)
        } catch {
            // Wind the drain tasks down before returning, so a throw never leaves a leaked
            // Task still blocked on I/O.
            outTask.cancel()
            errTask.cancel()
            _ = await outTask.value
            _ = await errTask.value
            throw error
        }
    }
}
