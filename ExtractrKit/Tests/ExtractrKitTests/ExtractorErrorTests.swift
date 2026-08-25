import Testing

@testable import ExtractrKit

@Suite struct ExtractorErrorTests {
    @Test func tailKeepsLastNonEmptyLines() {
        let text = (1...30).map { "line \($0)" }.joined(separator: "\n") + "\n\n"
        let tail = ExtractorError.tail(text)
        #expect(tail.hasPrefix("line 19"))
        #expect(tail.hasSuffix("line 30"))
    }
    @Test func detailExposure() {
        #expect(ExtractorError.conversionFailed(detail: "boom").detail == "boom")
        #expect(ExtractorError.outputMissing.detail == nil)
    }
}
