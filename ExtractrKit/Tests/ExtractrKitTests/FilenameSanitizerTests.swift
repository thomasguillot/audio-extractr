import Testing

@testable import ExtractrKit

@Suite struct FilenameSanitizerTests {
    @Test func stripsIllegalCharacters() {
        #expect(FilenameSanitizer.sanitize(#"a<b>c:d"e/f\g|h?i*j"#) == "abcdefghij")
    }
    @Test func collapsesWhitespaceAndTrims() {
        #expect(FilenameSanitizer.sanitize("  My   Great\tSong  ") == "My Great Song")
    }
    @Test func slashBecomesCollapsedSpace() {
        #expect(FilenameSanitizer.sanitize("AC / DC") == "AC DC")
    }
    @Test func fallsBackToAudio() {
        #expect(FilenameSanitizer.sanitize(nil) == "audio")
        #expect(FilenameSanitizer.sanitize("") == "audio")
        #expect(FilenameSanitizer.sanitize("///") == "audio")
    }
    @Test func caps200Characters() {
        let long = String(repeating: "x", count: 300)
        #expect(FilenameSanitizer.sanitize(long).count == 200)
    }
}
