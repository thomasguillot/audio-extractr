import Foundation

public enum YtDlpCommand {
    public static let format = "bestaudio[ext=m4a]/bestaudio[ext=webm]/bestaudio/best[height<=480]"

    public static func probeArguments(url: URL) -> [String] {
        [
            "-J",
            "--extractor-args", "youtube:player_client=android",
            "--no-playlist", "--no-warnings", url.absoluteString,
        ]
    }

    public static func downloadArguments(url: URL, outputTemplate: String, ffmpegDir: String)
        -> [String]
    {
        [
            url.absoluteString,
            "--extractor-args", "youtube:player_client=android",
            "-f", format,
            "--no-playlist", "--no-warnings", "--newline",
            "--ffmpeg-location", ffmpegDir,
            "-o", outputTemplate,
        ]
    }
}
