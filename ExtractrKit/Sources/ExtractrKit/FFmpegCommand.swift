import Foundation

public enum FFmpegCommand {
    /// The demuxers an input may open as: the audio formats and the video containers we read.
    /// Without the list a playlist renamed to .m4a opens as HLS (or concat), which reads any
    /// local file it names into the output.
    public static let allowedDemuxers = [
        "mov", "mp4", "m4a", "3gp", "3g2", "mj2", "matroska", "webm", "mp3", "aac", "wav", "w64",
        "aiff", "flac", "ogg", "caf", "amr", "ac3", "eac3", "dts", "dtshd", "truehd", "mlp", "wv",
        "ape", "tta", "mpc", "mpc8", "tak", "shn", "dsf", "au", "voc", "loas", "asf", "rm", "avi",
        "mpegts", "flv", "mpeg", "mpegvideo", "dv", "mxf",
    ]

    public static let demuxerLimit = ["-format_whitelist", allowedDemuxers.joined(separator: ",")]

    /// Every `-i` in every builder goes through this.
    public static func inputArguments(_ file: URL) -> [String] {
        demuxerLimit + ["-i", file.path]
    }

    /// `-ss`/`-t` are input options so trim always measures SOURCE seconds — with an
    /// atempo filter an output-side `-t` would trim the wrong amount.
    public static func extractArguments(input: URL, output: URL, trim: TrimRange, speed: Double)
        -> [String]
    {
        var args = ["-hide_banner", "-nostdin"]
        if let start = trim.start { args += ["-ss", String(start)] }
        if let limit = trim.clipLimitSeconds { args += ["-t", String(limit)] }
        args += inputArguments(input) + ["-vn"]
        if let filter = AtempoChain.filter(for: speed) { args += ["-filter:a", filter] }
        args += [
            "-codec:a", "libmp3lame", "-b:a", "192k", "-f", "mp3",
            "-progress", "pipe:1", "-nostats", "-y", output.path,
        ]
        return args
    }

    public static func probeArguments(file: URL) -> [String] {
        ["-hide_banner"] + inputArguments(file)
    }

    /// Low rate is plenty for a ~300-bucket strip and keeps the temp PCM small.
    public static let peaksSampleRate = 2_000

    public static func pcmArguments(input: URL, output: URL) -> [String] {
        ["-hide_banner", "-nostdin"] + inputArguments(input) + [
            "-vn", "-ac", "1", "-ar", String(peaksSampleRate),
            "-f", "s16le", "-y", output.path,
        ]
    }

    public static func previewArguments(input: URL, output: URL) -> [String] {
        ["-hide_banner", "-nostdin"] + inputArguments(input) + [
            "-vn", "-codec:a", "aac", "-b:a", "128k", "-f", "ipod", "-y", output.path,
        ]
    }
}
