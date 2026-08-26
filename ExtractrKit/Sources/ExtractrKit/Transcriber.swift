import AVFoundation
import Foundation
import NaturalLanguage
import Speech

public struct Transcriber: Sendable {
    /// Below this, NLLanguageRecognizer guesses wildly: "Hi." reads as Catalan.
    private static let minimumWordsForDetection = 10

    public init() {}

    public static func supportedLocales() async -> [Locale] {
        await SpeechTranscriber.supportedLocales
    }

    public static func detectLanguageCode(in transcript: Transcript) -> String? {
        guard transcript.wordCount >= minimumWordsForDetection else { return nil }
        let text = transcript.segments.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    public func transcribe(file: URL, locale: Locale) async throws -> Transcript {
        // Opened first: no point resolving a locale or fetching a model for an unreadable file.
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: file)
        } catch {
            throw TranscriptionError.audioUnreadable(detail: error.localizedDescription)
        }

        let supported = await Self.supportedLocales()
        guard let resolved = TranscriptLocale.match(locale, in: supported) else {
            throw TranscriptionError.localeUnsupported(locale.identifier(.bcp47))
        }

        let module = SpeechTranscriber(locale: resolved, preset: .transcription)
        try await installModelIfNeeded(module, locale: resolved)

        let analyzer = SpeechAnalyzer(modules: [module])

        // Must start before analyzeSequence: results stream from the module, and a task
        // started afterwards misses them.
        let collector = Task { () -> [TranscriptSegment] in
            var collected: [TranscriptSegment] = []
            for try await result in module.results where result.isFinal {
                collected.append(
                    TranscriptSegment(
                        start: result.range.start.seconds,
                        end: result.range.end.seconds,
                        text: String(result.text.characters)))
            }
            return collected
        }

        do {
            _ = try await analyzer.analyzeSequence(from: audioFile)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch is CancellationError {
            collector.cancel()
            await analyzer.cancelAndFinishNow()
            throw CancellationError()
        } catch {
            collector.cancel()
            await analyzer.cancelAndFinishNow()
            throw TranscriptionError.modelUnavailable(detail: error.localizedDescription)
        }

        let segments: [TranscriptSegment]
        do {
            segments = try await collector.value
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw TranscriptionError.modelUnavailable(detail: error.localizedDescription)
        }

        let transcript = Transcript(segments: segments)
        guard !transcript.isEmpty else { throw TranscriptionError.emptyTranscript }
        return transcript
    }

    private func installModelIfNeeded(_ module: SpeechTranscriber, locale: Locale) async throws {
        // A request comes back live even when the model is installed, so only ask when it is not.
        let installed = await SpeechTranscriber.installedLocales
        guard !installed.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) })
        else { return }
        do {
            guard
                let request = try await AssetInventory.assetInstallationRequest(
                    supporting: [module])
            else { throw TranscriptionError.modelUnavailable(detail: "") }
            try await request.downloadAndInstall()
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.modelUnavailable(detail: error.localizedDescription)
        }
    }
}
