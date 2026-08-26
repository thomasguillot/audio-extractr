public enum TranscriptionError: Error, Equatable {
    case localeUnsupported(String)
    case modelUnavailable(detail: String)
    case audioUnreadable(detail: String)
    case emptyTranscript

    public var detail: String? {
        switch self {
        case let .modelUnavailable(detail), let .audioUnreadable(detail):
            return detail.isEmpty ? nil : detail
        case .localeUnsupported, .emptyTranscript:
            return nil
        }
    }
}
