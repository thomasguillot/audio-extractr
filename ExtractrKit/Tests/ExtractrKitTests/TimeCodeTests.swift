import Testing

@testable import ExtractrKit

@Suite struct TimeCodeTests {
    @Test func parsesForms() {
        #expect(TimeCode.seconds(from: "90") == 90)
        #expect(TimeCode.seconds(from: "1:30") == 90)
        #expect(TimeCode.seconds(from: "01:02:03") == 3723)
        #expect(TimeCode.seconds(from: " 0:05 ") == 5)
    }
    @Test func rejectsInvalid() {
        #expect(TimeCode.seconds(from: "") == nil)
        #expect(TimeCode.seconds(from: "abc") == nil)
        #expect(TimeCode.seconds(from: "1:99") == nil)
        #expect(TimeCode.seconds(from: "1:2:3:4") == nil)
        #expect(TimeCode.seconds(from: "-5") == nil)
        #expect(TimeCode.seconds(from: "1:") == nil)
    }
    @Test func formats() {
        #expect(TimeCode.text(from: 5) == "0:05")
        #expect(TimeCode.text(from: 90) == "1:30")
        #expect(TimeCode.text(from: 3723.4) == "1:02:03")
    }
    /// A field still showing what a dragged handle displays keeps the handle's fraction.
    @Test func unchangedTextKeepsTheCurrentTime() {
        #expect(TimeCode.seconds(from: "0:10", keeping: 10.6) == 10.6)
        #expect(TimeCode.seconds(from: " 0:10 ", keeping: 10.6) == 10.6)
        #expect(TimeCode.seconds(from: "0:11", keeping: 10.6) == 11)
        #expect(TimeCode.seconds(from: "nope", keeping: 10.6) == nil)
    }
    @Test func formattingNeverTraps() {
        #expect(TimeCode.text(from: .infinity) == "0:00")
        #expect(TimeCode.text(from: -.infinity) == "0:00")
        #expect(TimeCode.text(from: .nan) == "0:00")
        #expect(TimeCode.text(from: -5) == "0:00")
        #expect(!TimeCode.text(from: 3.6e20).isEmpty)
    }
    @Test func hugeNumbersReturnNilInsteadOfTrapping() {
        #expect(TimeCode.seconds(from: "9999999999999999:00:00") == nil)
        #expect(TimeCode.seconds(from: String(Int.max)) == Int.max)
    }
}
