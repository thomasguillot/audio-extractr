import Foundation

public enum FFmpegDurationParser {
    public static func duration(fromStderr text: String) -> Double? {
        guard let match = text.firstMatch(of: /Duration:\s*(\d+):(\d+):(\d+)\.(\d+)/),
            let h = Double(match.1), let m = Double(match.2),
            let s = Double(match.3), let cs = Double(match.4)
        else { return nil }
        return h * 3600 + m * 60 + s + cs / 100
    }
}
