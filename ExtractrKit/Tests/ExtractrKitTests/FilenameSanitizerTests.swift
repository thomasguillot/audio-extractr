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
    @Test func dropsTheFacebookViewCountPrefix() {
        #expect(
            FilenameSanitizer.sanitize("9.9K views · 339 reactions | The Slapathon | Beast Camp")
                == "The Slapathon Beast Camp")
        #expect(FilenameSanitizer.sanitize("1.2M views · 45K reactions | Clip") == "Clip")
    }
    @Test func dropsASingularCount() {
        #expect(FilenameSanitizer.sanitize("1 view · 1 reaction | Clip") == "Clip")
        #expect(FilenameSanitizer.sanitize("1 view · 12 reactions | Clip") == "Clip")
        #expect(FilenameSanitizer.sanitize("40 views · 1 reaction | Clip") == "Clip")
    }
    @Test func keepsAnOrdinaryPipe() {
        #expect(FilenameSanitizer.sanitize("Part 1 | Intro") == "Part 1 Intro")
    }
}
