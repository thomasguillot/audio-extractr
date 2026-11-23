import Foundation

public enum FilenameSanitizer {
    public static func sanitize(_ title: String?) -> String {
        guard let title else { return "audio" }
        // Facebook titles lead with "9.9K views · 339 reactions | ".
        let untagged = title.replacing(#/^[^|]*\bviews? · [^|]*\breactions? \| /#, with: "")
        let illegal = CharacterSet(charactersIn: "<>:\"/\\|?*")
        let kept = untagged.unicodeScalars.filter { !illegal.contains($0) }
        var result = String(String.UnicodeScalarView(kept))
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespaces)
        result = String(result.prefix(200))
        return result.isEmpty ? "audio" : result
    }
}
