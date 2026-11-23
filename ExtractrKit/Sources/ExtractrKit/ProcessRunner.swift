import Foundation

public struct ProcessOutput: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
}

public enum ProcessRunnerError: Error {
    case launchFailed(String)
}

/// How a child is stopped on cancel or quit.
public enum ProcessStop: Sendable {
    case terminate
    /// SIGINT, then SIGTERM once `grace` passes: yt-dlp stops its own ffmpeg on SIGINT,
    /// while SIGTERM kills it outright and leaves that ffmpeg running.
    case interrupt(grace: Duration)
}

// Process/Pipe predate Sendable; confined here so `onCancel` and the readers can touch them.
private final class ProcessBox: @unchecked Sendable {
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()
    let stop: ProcessStop

    private let lock = NSLock()
    private var launched = false
    private var cancelled = false

    init(stop: ProcessStop) {
        self.stop = stop
    }

    /// Launch and cancel share a lock so neither can land in the other's window: a cancel
    /// that arrives first stops the launch, and one that arrives after always sees a
    /// process it can terminate. Terminating an unlaunched Process raises.
    func launch() throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return false }
        try process.run()
        launched = true
        return true
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        guard launched, process.isRunning else { return }
        switch stop {
        case .terminate:
            process.terminate()
        case let .interrupt(grace):
            process.interrupt()
            DispatchQueue.global().asyncAfter(deadline: .now() + grace.timeInterval) {
                self.forceTerminate()
            }
        }
    }

    func forceTerminate() {
        lock.lock()
        defer { lock.unlock() }
        if launched, process.isRunning { process.terminate() }
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return launched && process.isRunning
    }
}

/// Every child ProcessRunner has running, so quitting can stop them all.
public final class ProcessRegistry: @unchecked Sendable {
    public static let shared = ProcessRegistry()

    private let lock = NSLock()
    private var boxes: [ObjectIdentifier: ProcessBox] = [:]

    public init() {}

    public var count: Int { lock.withLock { boxes.count } }

    fileprivate func insert(_ box: ProcessBox) {
        lock.withLock { boxes[ObjectIdentifier(box)] = box }
    }

    fileprivate func remove(_ box: ProcessBox) {
        _ = lock.withLock { boxes.removeValue(forKey: ObjectIdentifier(box)) }
    }

    /// Blocks for at most `grace`, so it fits in `applicationWillTerminate`.
    public func terminateAll(grace: Duration = .seconds(2)) {
        let live = lock.withLock { Array(boxes.values) }
        for box in live { box.cancel() }
        let deadline = ContinuousClock.now + grace
        while live.contains(where: \.isRunning), ContinuousClock.now < deadline {
            usleep(20_000)
        }
        for box in live { box.forceTerminate() }
    }
}

extension Duration {
    fileprivate var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}

/// The only unit in the app that spawns child processes. Arguments are always
/// passed as arrays — never through a shell.
public struct ProcessRunner: Sendable {
    private let registry: ProcessRegistry

    public init(registry: ProcessRegistry = .shared) {
        self.registry = registry
    }

    /// Enough for yt-dlp's -J of a long video; the head is kept.
    public static let defaultStdoutLimit = 32 << 20
    /// Only the tail of stderr is ever shown.
    public static let defaultStderrLimit = 64 << 10

    /// Chunked rather than `FileHandle.bytes.lines`: the line iterator stalls once a single
    /// line outgrows its internal buffer, which stops draining the pipe and deadlocks the
    /// child mid-write — yt-dlp -J emits its whole JSON as one multi-hundred-KB line.
    private func drainTask(
        _ pipe: Pipe, limit: Int, keepTail: Bool, onLine: (@Sendable (String) -> Void)?
    ) -> Task<String, Never> {
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
                if keepTail {
                    collected.append(chunk)
                    if collected.count > limit * 2 { collected = collected.suffix(limit) }
                } else if collected.count < limit {
                    collected.append(chunk.prefix(limit - collected.count))
                }
                guard onLine != nil else { continue }
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 0x0A) {
                    let line = pending.subdata(in: pending.startIndex..<newline)
                    pending.removeSubrange(pending.startIndex...newline)
                    onLine?(Self.lineString(line))
                }
                if pending.count > limit { pending.removeAll() }
            }
            if let onLine, !pending.isEmpty {
                onLine(Self.lineString(pending))
            }
            if keepTail { collected = collected.suffix(limit) }
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
        stdoutLimit: Int = defaultStdoutLimit,
        stderrLimit: Int = defaultStderrLimit,
        stop: ProcessStop = .terminate,
        onStdoutLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> ProcessOutput {
        let box = ProcessBox(stop: stop)
        let registry = registry
        box.process.executableURL = executable
        box.process.arguments = arguments
        box.process.standardInput = FileHandle.nullDevice
        box.process.standardOutput = box.stdout
        box.process.standardError = box.stderr

        // Readers must drain concurrently with the wait or a full pipe deadlocks the child.
        let outTask = drainTask(
            box.stdout, limit: stdoutLimit, keepTail: false, onLine: onStdoutLine)
        let errTask = drainTask(box.stderr, limit: stderrLimit, keepTail: true, onLine: nil)

        do {
            let exitCode: Int32 = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    box.process.terminationHandler = { process in
                        registry.remove(box)
                        continuation.resume(returning: process.terminationStatus)
                    }
                    // Nothing else will ever close the pipes' write ends when the child does
                    // not start, so outTask/errTask would block on read() forever.
                    func abandon(_ error: Error) {
                        box.process.terminationHandler = nil
                        box.stdout.fileHandleForWriting.closeFile()
                        box.stderr.fileHandleForWriting.closeFile()
                        continuation.resume(throwing: error)
                    }
                    do {
                        registry.insert(box)
                        guard try box.launch() else {
                            registry.remove(box)
                            return abandon(CancellationError())
                        }
                    } catch {
                        registry.remove(box)
                        abandon(ProcessRunnerError.launchFailed(error.localizedDescription))
                    }
                }
            } onCancel: {
                box.cancel()
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
