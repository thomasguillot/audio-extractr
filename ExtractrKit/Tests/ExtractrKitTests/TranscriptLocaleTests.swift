import Foundation
import Testing

@testable import ExtractrKit

@Suite struct TranscriptLocaleTests {
    private let supported = [
        Locale(identifier: "en-US"), Locale(identifier: "en-GB"), Locale(identifier: "fr-FR"),
    ]

    @Test func exactLocaleMatches() {
        #expect(TranscriptLocale.match(Locale(identifier: "fr-FR"), in: supported)?
            .identifier(.bcp47) == "fr-FR")
    }

    @Test func languageOnlyFallsBackToTheFirstSupportedRegion() {
        #expect(TranscriptLocale.match(Locale(identifier: "fr"), in: supported)?
            .identifier(.bcp47) == "fr-FR")
    }

    @Test func unsupportedLanguageDoesNotMatch() {
        #expect(TranscriptLocale.match(Locale(identifier: "ja-JP"), in: supported) == nil)
    }

    @Test func agreementKeepsTheAssumedLocale() {
        let verdict = TranscriptLocale.verdict(
            assumedLanguageCode: "en", detectedLanguageCode: "en")
        #expect(verdict == .keep)
    }

    @Test func disagreementTriggersARetry() {
        let verdict = TranscriptLocale.verdict(
            assumedLanguageCode: "en", detectedLanguageCode: "fr")
        #expect(verdict == .retry(languageCode: "fr"))
    }

    @Test func aScriptSuffixIsNotADisagreement() {
        let verdict = TranscriptLocale.verdict(
            assumedLanguageCode: "zh", detectedLanguageCode: "zh-Hans")
        #expect(verdict == .keep)
    }

    @Test func noDetectionKeepsTheAssumedLocale() {
        let verdict = TranscriptLocale.verdict(
            assumedLanguageCode: "en", detectedLanguageCode: nil)
        #expect(verdict == .keep)
    }
}
