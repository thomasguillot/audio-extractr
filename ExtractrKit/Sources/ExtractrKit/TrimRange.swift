public struct TrimRange: Equatable, Sendable {
    public enum ValidationError: Error, Equatable {
        case startAfterEnd
        case exceedsDuration
        case tooLong
    }

    public static let maxSeconds: Double = 604_800

    public var start: Double?
    public var end: Double?

    public init(start: Double? = nil, end: Double? = nil) {
        self.start = start
        self.end = end
    }

    public func validate(mediaDuration: Double?) throws {
        for value in [start, end].compactMap({ $0 }) where value > Self.maxSeconds {
            throw ValidationError.tooLong
        }
        if let start, let end, end <= start { throw ValidationError.startAfterEnd }
        if let mediaDuration {
            // +1s slack: probed durations are often fractionally shorter than the tail.
            if let end, end > mediaDuration + 1 { throw ValidationError.exceedsDuration }
            if let start, start >= mediaDuration { throw ValidationError.exceedsDuration }
        }
    }

    /// Source seconds ffmpeg should read (`-t`).
    public var clipLimitSeconds: Double? {
        end.map { $0 - (start ?? 0) }
    }

    /// Source seconds that will be processed, using the probed duration as the fallback end.
    public func clipSeconds(mediaDuration: Double?) -> Double? {
        let effectiveEnd = end ?? mediaDuration
        guard let effectiveEnd else { return nil }
        return effectiveEnd - (start ?? 0)
    }
}
