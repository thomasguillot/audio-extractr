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
    @Test func hugeNumbersReturnNilInsteadOfTrapping() {
        #expect(TimeCode.seconds(from: "9999999999999999:00:00") == nil)
        #expect(TimeCode.seconds(from: String(Int.max)) == Int.max)
    }
}
