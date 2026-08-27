import Foundation

public enum YtDlpProgressParser {
    public static func fraction(line: String) -> Double? {
        guard let match = line.firstMatch(of: /\[download\]\s+([0-9.]+)%/),
            let percent = Double(match.1)
        else { return nil }
        let result = percent / 100
        let rounded = (result * 1e10).rounded() / 1e10
        return min(rounded, 1)
    }
}

public enum FFmpegProgressParser {
    /// `-progress pipe:1` key/value lines. Both out_time_us and the legacy
    /// out_time_ms key carry MICROseconds.
    public static func fraction(line: String, expectedOutputSeconds: Double?) -> Double? {
        guard let expected = expectedOutputSeconds, expected > 0 else { return nil }
        guard let match = line.firstMatch(of: /^out_time_(?:us|ms)=(\d+)$/),
            let micros = Double(match.1)
        else { return nil }
        return min(micros / 1_000_000 / expected, 1)
    }
}
