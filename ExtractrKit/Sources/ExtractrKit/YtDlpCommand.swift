import Foundation

public enum YtDlpCommand {
    public static let format = "bestaudio[ext=m4a]/bestaudio[ext=webm]/bestaudio/best[height<=480]"

    /// Without this yt-dlp also reads ~/.config/yt-dlp/config and friends, so the effective
    /// arguments are not the ones built here — an --exec line there runs on every extraction.
    private static let ignoreConfig = "--ignore-config"

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
        ]
    }
}
