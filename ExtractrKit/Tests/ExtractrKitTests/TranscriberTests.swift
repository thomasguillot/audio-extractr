import Foundation
import Testing

@testable import ExtractrKit

@Suite struct TranscriberTests {
    @Test func missingFileIsReportedAsUnreadableAudio() async {
        let missing = URL(fileURLWithPath: "/nonexistent/nothing.mp3")
        do {
            _ = try await Transcriber().transcribe(
                file: missing, locale: Locale(identifier: "en-US"))
            Issue.record("expected transcribe to throw")
        } catch let error as TranscriptionError {
            guard case .audioUnreadable = error else {
                Issue.record("expected .audioUnreadable, got \(error)")
                return
            }
        } catch {
            Issue.record("expected TranscriptionError, got \(error)")
        }
    }

    @Test func shortTextIsNotTrustedForDetection() {
        let brief = Transcript(segments: [
            TranscriptSegment(start: 0, end: 1, text: "Hi.")
        ])
        #expect(Transcriber.detectLanguageCode(in: brief) == nil)
    }

    @Test func englishTextIsDetectedAsEnglish() {
        let transcript = Transcript(segments: [
            TranscriptSegment(
                start: 0, end: 10,
                text: "The transfer window is about to close and the club needs a striker.")
        ])
        #expect(Transcriber.detectLanguageCode(in: transcript) == "en")
    }

    @Test func frenchTextIsDetectedAsFrench() {
        let transcript = Transcript(segments: [
            TranscriptSegment(
                start: 0, end: 10,
                text: "Le club a dépensé une somme considérable pour recruter un attaquant.")
        ])
        #expect(Transcriber.detectLanguageCode(in: transcript) == "fr")
    }

    @Test func emptyTextDetectsNothing() {
        #expect(Transcriber.detectLanguageCode(in: Transcript(segments: [])) == nil)
    }
}
