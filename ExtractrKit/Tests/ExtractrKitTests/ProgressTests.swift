import Testing

@testable import ExtractrKit

@Suite struct YtDlpProgressParserTests {
    @Test func parsesPercent() {
        #expect(YtDlpProgressParser.fraction(line: "[download]  12.3% of 4.5MiB at 1MiB/s") == 0.123)
        #expect(YtDlpProgressParser.fraction(line: "[download] 100% of 4.5MiB") == 1.0)
    }
    @Test func ignoresOtherLines() {
        #expect(YtDlpProgressParser.fraction(line: "[youtube] extracting") == nil)
        #expect(YtDlpProgressParser.fraction(line: "") == nil)
    }
    @Test func clampsAboveHundred() {
        #expect(YtDlpProgressParser.fraction(line: "[download] 100.2% of ~4MiB") == 1.0)
    }
}

@Suite struct FFmpegProgressParserTests {
    @Test func parsesOutTime() {
        #expect(
            FFmpegProgressParser.fraction(line: "out_time_us=30000000", expectedOutputSeconds: 60)
                == 0.5)
        #expect(
            FFmpegProgressParser.fraction(line: "out_time_ms=30000000", expectedOutputSeconds: 60)
                == 0.5)
    }
    @Test func clampsToOne() {
        #expect(
            FFmpegProgressParser.fraction(line: "out_time_us=90000000", expectedOutputSeconds: 60)
                == 1.0)
    }
    @Test func nilWithoutExpectation() {
        #expect(FFmpegProgressParser.fraction(line: "out_time_us=1", expectedOutputSeconds: nil) == nil)
        #expect(FFmpegProgressParser.fraction(line: "out_time_us=1", expectedOutputSeconds: 0) == nil)
    }
    @Test func ignoresOtherKeys() {
        #expect(FFmpegProgressParser.fraction(line: "bitrate=192k", expectedOutputSeconds: 60) == nil)
    }
}
