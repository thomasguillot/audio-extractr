import Foundation

public enum FFmpegDurationParser {
    /// Longer than this is a forged header, not a recording.
    public static let maximumSeconds = TrimRange.maxSeconds

    /// Read only from the container's own `  Duration: …` line, exactly two spaces in: tag
    /// values print deeper, so a title cannot stand in for it.
    public static func duration(fromStderr text: String) -> Double? {
        guard let line = FFmpegProbeParser.lines(text).first(where: { $0.hasPrefix("  Duration: ") }),
            let match = line.prefixMatch(of: #/  Duration: (\d+):(\d{2}):(\d{2})\.(\d+)/#),
            let h = Double(match.1), let m = Double(match.2), let s = Double(match.3),
            let fraction = Double("0." + match.4)
        else { return nil }
        return bounded(h * 3600 + m * 60 + s + fraction)
    }

    static func bounded(_ value: Double) -> Double? {
        value.isFinite && (0...maximumSeconds).contains(value) ? value : nil
    }
}
