import Testing

@testable import ExtractrKit

@Suite struct TrimRangeTests {
    @Test func validRangePasses() throws {
        try TrimRange(start: 10, end: 70).validate(mediaDuration: 100)
        try TrimRange(start: nil, end: nil).validate(mediaDuration: nil)
        try TrimRange(start: 10, end: nil).validate(mediaDuration: 100)
    }
    @Test func startAfterEndFails() {
        #expect(throws: TrimRange.ValidationError.startAfterEnd) {
            try TrimRange(start: 70, end: 10).validate(mediaDuration: 100)
        }
        #expect(throws: TrimRange.ValidationError.startAfterEnd) {
            try TrimRange(start: 10, end: 10).validate(mediaDuration: 100)
        }
    }
    @Test func beyondDurationFails() {
        #expect(throws: TrimRange.ValidationError.exceedsDuration) {
            try TrimRange(start: 0, end: 200).validate(mediaDuration: 100)
        }
        #expect(throws: TrimRange.ValidationError.exceedsDuration) {
            try TrimRange(start: 150, end: nil).validate(mediaDuration: 100)
        }
    }
    @Test func tooLongFails() {
        #expect(throws: TrimRange.ValidationError.tooLong) {
            try TrimRange(start: 0, end: 700_000).validate(mediaDuration: nil)
        }
    }
    @Test func clipMath() {
        #expect(TrimRange(start: 10, end: 70).clipLimitSeconds == 60)
        #expect(TrimRange(start: nil, end: 70).clipLimitSeconds == 70)
        #expect(TrimRange(start: 10, end: nil).clipLimitSeconds == nil)
        #expect(TrimRange(start: 10, end: nil).clipSeconds(mediaDuration: 100) == 90)
        #expect(TrimRange(start: nil, end: nil).clipSeconds(mediaDuration: nil) == nil)
    }
}
