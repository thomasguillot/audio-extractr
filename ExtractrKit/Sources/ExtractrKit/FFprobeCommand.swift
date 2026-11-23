import Foundation

public enum FFprobeCommand {
    static let entries = "format=format_name,duration"

    /// No tags are requested, so no text from inside the file reaches the output.
    public static func arguments(file: URL) -> [String] {
        ["-v", "error", "-hide_banner", "-of", "json", "-show_entries", entries]
            + FFmpegCommand.inputArguments(file)
    }
}
