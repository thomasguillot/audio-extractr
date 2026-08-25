public enum ExtractorError: Error, Equatable {
    case probeFailed(detail: String)
    case downloadFailed(detail: String)
    case conversionFailed(detail: String)
    case outputMissing

    public var detail: String? {
        switch self {
        case let .probeFailed(detail), let .downloadFailed(detail), let .conversionFailed(detail):
            return detail.isEmpty ? nil : detail
        case .outputMissing:
            return nil
        }
    }

    public static func tail(_ text: String, maxLines: Int = 12) -> String {
        text.split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .suffix(maxLines)
            .joined(separator: "\n")
    }
}
