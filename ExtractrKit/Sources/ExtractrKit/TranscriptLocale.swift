import Foundation

public enum TranscriptLocale {
    public enum Verdict: Equatable, Sendable {
        case keep
        case retry(languageCode: String)
    }

    public static func match(_ candidate: Locale, in supported: [Locale]) -> Locale? {
        let wanted = candidate.identifier(.bcp47)
        if let exact = supported.first(where: { $0.identifier(.bcp47) == wanted }) { return exact }
        guard let language = candidate.language.languageCode?.identifier else { return nil }
        return supported.first { $0.language.languageCode?.identifier == language }
    }

    public static func verdict(
        assumedLanguageCode: String,
        detectedLanguageCode: String?
    ) -> Verdict {
        guard let detected = detectedLanguageCode,
            primarySubtag(detected) != primarySubtag(assumedLanguageCode)
        else { return .keep }
        return .retry(languageCode: detected)
    }

    private static func primarySubtag(_ code: String) -> Substring {
        code.split(separator: "-").first ?? ""
    }
}
