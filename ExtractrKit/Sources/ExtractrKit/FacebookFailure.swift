/// yt-dlp's Facebook failures that deserve better than a generic "couldn't be read".
public enum FacebookFailure: Equatable, Sendable {
    case loginRequired
    case unreadable

    public static func classify(_ stderr: String) -> FacebookFailure? {
        let lines = stderr.split(whereSeparator: \.isNewline)
            .filter { $0.contains("ERROR: [facebook") }
        if lines.contains(where: {
            $0.contains("only available for registered users") || $0.contains("You must log in")
        }) {
            return .loginRequired
        }
        if lines.contains(where: { $0.contains("Cannot parse data") }) { return .unreadable }
        return nil
    }
}
