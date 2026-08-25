import Foundation

public enum FilenameSanitizer {
    public static func sanitize(_ title: String?) -> String {
        guard let title else { return "audio" }
        let illegal = CharacterSet(charactersIn: "<>:\"/\\|?*")
        let kept = title.unicodeScalars.filter { !illegal.contains($0) }
        var result = String(String.UnicodeScalarView(kept))
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespaces)
        result = String(result.prefix(200))
        return result.isEmpty ? "audio" : result
    }
}
