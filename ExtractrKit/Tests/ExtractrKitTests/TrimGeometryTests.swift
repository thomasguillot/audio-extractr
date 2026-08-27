import CoreGraphics
import Testing

@testable import ExtractrKit

@Suite struct TrimSelectionTests {
    @Test func initSpansWholeDuration() {
        let selection = TrimSelection(duration: 120)
        #expect(selection.start == 0)
        #expect(selection.end == 120)
    }
    @Test func negativeDurationClampsToZero() {
        let selection = TrimSelection(duration: -5)
        #expect(selection.duration == 0)
        #expect(selection.end == 0)
    }
    @Test func handlesClampToClipAndEachOther() {
        var selection = TrimSelection(duration: 100)
        selection.moveStart(to: -10)
        #expect(selection.start == 0)
        selection.moveEnd(to: 400)
        #expect(selection.end == 100)
        selection.moveEnd(to: 30)
        selection.moveStart(to: 99)
        #expect(selection.start == selection.end - TrimSelection.minimumLength)
    }
    @Test func endCannotCrossStart() {
        var selection = TrimSelection(duration: 100)
        selection.moveStart(to: 50)
        selection.moveEnd(to: 10)
        #expect(selection.end == 50 + TrimSelection.minimumLength)
    }
    @Test func trimRangeUsesOpenBoundsForUntouchedHandles() {
        var selection = TrimSelection(duration: 100)
        #expect(selection.trimRange == TrimRange(start: nil, end: nil))
        selection.moveStart(to: 10.4)
        selection.moveEnd(to: 89.6)
        #expect(selection.trimRange == TrimRange(start: 10, end: 89))
    }
    @Test func trimRangeMatchesDisplayedTimecode() {
        var selection = TrimSelection(duration: 100)
        selection.moveStart(to: 10.6)
        selection.moveEnd(to: 89.6)
        #expect(selection.trimRange == TrimRange(start: 10, end: 89))
        #expect(TimeCode.text(from: selection.start) == "0:10")
        #expect(TimeCode.text(from: selection.end) == "1:29")
    }
}

@Suite struct TrimGeometryTests {
    @Test func timeAndXRoundTrip() {
        #expect(TrimGeometry.time(atX: 50, stripWidth: 100, duration: 200) == 100)
        #expect(TrimGeometry.x(forTime: 100, stripWidth: 100, duration: 200) == 50)
    }
    @Test func timeClampsToStrip() {
        #expect(TrimGeometry.time(atX: -20, stripWidth: 100, duration: 200) == 0)
        #expect(TrimGeometry.time(atX: 150, stripWidth: 100, duration: 200) == 200)
    }
    @Test func degenerateInputsReturnZero() {
        #expect(TrimGeometry.time(atX: 10, stripWidth: 0, duration: 100) == 0)
        #expect(TrimGeometry.x(forTime: 10, stripWidth: 100, duration: 0) == 0)
    }
    @Test func snapLandsOnPlayheadWithinThreshold() {
        #expect(TrimGeometry.snap(10.4, toPlayhead: 10, threshold: 0.5) == 10)
        #expect(TrimGeometry.snap(11, toPlayhead: 10, threshold: 0.5) == 11)
    }
}
