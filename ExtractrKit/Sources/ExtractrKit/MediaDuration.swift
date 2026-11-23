public enum MediaDuration {
    /// Longer than this is a forged header, not a recording.
    public static let maximumSeconds = TrimRange.maxSeconds

    static func bounded(_ value: Double) -> Double? {
        value.isFinite && (0...maximumSeconds).contains(value) ? value : nil
    }
}
