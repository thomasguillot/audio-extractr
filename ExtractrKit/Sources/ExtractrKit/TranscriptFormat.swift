public enum TranscriptFormat: String, CaseIterable, Sendable {
    case markdown
    case plainText

    public var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .plainText: "txt"
        }
    }

    public var label: String {
        switch self {
        case .markdown: "Markdown (.md)"
        case .plainText: "Plain text (.txt)"
        }
    }
}
