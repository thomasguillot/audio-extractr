import Foundation

public enum FFmpegProbeParser {
    /// Nil when ffmpeg could not open the input at all, or opened it as a demuxer outside
    /// `FFmpegCommand.allowedDemuxers`.
    public static func parse(stderr text: String, title: String?) -> MediaProbe? {
        guard isAllowedInput(lines(text)) else { return nil }
        return MediaProbe(title: title, duration: FFmpegDurationParser.duration(fromStderr: text))
    }

    private static func isAllowedInput(_ lines: [Substring]) -> Bool {
        guard let line = lines.first(where: { $0.hasPrefix("Input #") }),
            let input = line.prefixMatch(of: #/Input #\d+, ([a-z0-9_,]+), from /#)
        else { return false }
        return !Set(input.1.split(separator: ",").map(String.init))
            .isDisjoint(with: FFmpegCommand.allowedDemuxers)
    }

    /// "\n" only: ffmpeg prints U+2028 and U+0085 inside tag values unescaped, and Swift
    /// would otherwise break a line on them.
    static func lines(_ text: String) -> [Substring] {
        text.split(separator: "\n")
    }
}
