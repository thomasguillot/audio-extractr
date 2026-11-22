import Foundation

public enum YtDlpCommand {
    public static let format = "bestaudio[ext=m4a]/bestaudio[ext=webm]/bestaudio/best[height<=480]"

    /// Without this yt-dlp also reads ~/.config/yt-dlp/config and friends, so the effective
    /// arguments are not the ones built here — an --exec line there runs on every extraction.
    private static let ignoreConfig = "--ignore-config"

    /// SIGINT lets yt-dlp stop the ffmpeg running its fixup; SIGTERM would orphan it.
    public static let stop = ProcessStop.interrupt(grace: .seconds(3))

    public static func probeArguments(url: URL) -> [String] {
        [
            ignoreConfig, "-J",
            "--extractor-args", "youtube:player_client=android",
            "--no-playlist", "--no-warnings", url.absoluteString,
        ]
    }

    public static func downloadArguments(url: URL, outputTemplate: String, ffmpegDir: String)
        -> [String]
    {
        [
            ignoreConfig, url.absoluteString,
            "--extractor-args", "youtube:player_client=android",
            "-f", format,
            "--no-playlist", "--no-warnings", "--newline",
            "--ffmpeg-location", ffmpegDir,
            "-o", outputTemplate,
        ] + postprocessorInputGuards
    }

    /// The fixups yt-dlp may run on a single-format download open it through ffmpeg too, so
    /// they get the same demuxer list. yt-dlp reads a bare `ffmpeg_i` key for no
    /// postprocessor, so each one is named.
    private static let postprocessorInputGuards = [
        "FixupM4a", "FixupM3u8", "FixupTimestamp", "FixupDuration", "FixupDuplicateMoov",
        "FixupStretched",
    ].flatMap { name in
        ["--postprocessor-args", "\(name)+ffmpeg_i:" + FFmpegCommand.demuxerLimit.joined(separator: " ")]
    }
}
