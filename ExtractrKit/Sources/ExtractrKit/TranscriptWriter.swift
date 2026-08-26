import Foundation

public enum TranscriptWriter {
    public static func render(
        _ transcript: Transcript, as format: TranscriptFormat, title: String
    ) -> String {
        let paragraphs = transcript.segments
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n") + "\n"
        switch format {
        case .markdown: return "# \(title)\n\n" + paragraphs
        case .plainText: return paragraphs
        }
    }
}
