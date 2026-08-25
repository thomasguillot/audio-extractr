import Foundation

public enum FFmpegCommand {
    /// `-ss`/`-t` are input options so trim always measures SOURCE seconds — with an
    /// atempo filter an output-side `-t` would trim the wrong amount.
    public static func extractArguments(input: URL, output: URL, trim: TrimRange, speed: Double)
        -> [String]
    {
        var args = ["-hide_banner", "-nostdin"]
        if let start = trim.start { args += ["-ss", String(start)] }
        if let limit = trim.clipLimitSeconds { args += ["-t", String(limit)] }
        args += ["-i", input.path, "-vn"]
        if let filter = AtempoChain.filter(for: speed) { args += ["-filter:a", filter] }
        args += [
            "-codec:a", "libmp3lame", "-b:a", "192k", "-f", "mp3",
            "-progress", "pipe:1", "-nostats", "-y", output.path,
        ]
        return args
    }

    public static func probeArguments(file: URL) -> [String] {
        ["-hide_banner", "-i", file.path]
    }

    /// Low rate is plenty for a ~300-bucket strip and keeps the temp PCM small.
    public static let peaksSampleRate = 2_000

    public static func pcmArguments(input: URL, output: URL) -> [String] {
        [
            "-hide_banner", "-nostdin", "-i", input.path, "-vn",
            "-ac", "1", "-ar", String(peaksSampleRate),
            "-f", "s16le", "-y", output.path,
        ]
    }

    public static func previewArguments(input: URL, output: URL) -> [String] {
        [
            "-hide_banner", "-nostdin", "-i", input.path, "-vn",
            "-codec:a", "aac", "-b:a", "128k", "-f", "ipod", "-y", output.path,
        ]
    }
}
