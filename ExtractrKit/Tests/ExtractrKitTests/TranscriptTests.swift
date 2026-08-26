import Foundation
import Testing

@testable import ExtractrKit

@Suite struct TranscriptTests {
    private let sample = Transcript(segments: [
        TranscriptSegment(start: 0, end: 4, text: "Hello everybody."),
        TranscriptSegment(start: 4, end: 10, text: "Welcome to the show."),
    ])

    @Test func wordCountSpansAllSegments() {
        #expect(sample.wordCount == 6)
    }

    @Test func emptyWhenNoSegments() {
        #expect(Transcript(segments: []).isEmpty)
        #expect(!sample.isEmpty)
    }

}
