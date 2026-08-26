import Foundation
import Testing

@testable import ExtractrKit

@Suite struct TranscriptWriterTests {
    private let sample = Transcript(segments: [
        TranscriptSegment(start: 0, end: 2.28, text: " Hello everybody. "),
        TranscriptSegment(start: 2.28, end: 12.54, text: "Welcome to the show."),
    ])

    @Test func markdownLeadsWithATitleThenParagraphs() {
        let output = TranscriptWriter.render(sample, as: .markdown, title: "Episode 1")
        #expect(output == "# Episode 1\n\nHello everybody.\n\nWelcome to the show.\n")
    }

    @Test func plainTextHasNoTitleAndNoMarkup() {
        let output = TranscriptWriter.render(sample, as: .plainText, title: "Episode 1")
        #expect(output == "Hello everybody.\n\nWelcome to the show.\n")
    }



    @Test func blankSegmentsAreDropped() {
        let padded = Transcript(segments: [
            TranscriptSegment(start: 0, end: 1, text: "   "),
            TranscriptSegment(start: 1, end: 2, text: "Real."),
        ])
        #expect(TranscriptWriter.render(padded, as: .plainText, title: "x") == "Real.\n")
    }


    @Test func extensionsMatchTheFormat() {
        #expect(TranscriptFormat.markdown.fileExtension == "md")
        #expect(TranscriptFormat.plainText.fileExtension == "txt")
    }
}
