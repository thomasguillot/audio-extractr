import CoreGraphics
import Foundation

/// Trim selection over the source clip. Handles clamp to [0, duration] and never cross
/// closer than `minimumLength`, so an inverted or empty extract range is unrepresentable.
public struct TrimSelection: Equatable, Sendable {
    public let duration: Double
    public private(set) var start: Double
    public private(set) var end: Double

    public static let minimumLength: Double = 1

    public init(duration: Double) {
        self.duration = max(duration, 0)
        self.start = 0
        self.end = self.duration
    }

    public mutating func moveStart(to time: Double) {
        start = min(max(time, 0), max(end - Self.minimumLength, 0))
    }

    public mutating func moveEnd(to time: Double) {
        end = max(min(time, duration), min(start + Self.minimumLength, duration))
    }

    /// Whole-second bounds for the ffmpeg pipeline; untouched handles stay open
    /// so an untrimmed extract needs no -ss/-t at all.
    public var trimRange: TrimRange {
        TrimRange(
            start: start > 0 ? Int(start.rounded(.down)) : nil,
            end: end < duration ? Int(end.rounded(.down)) : nil)
    }
}

/// Pixel ↔ time mapping for the waveform strip.
public enum TrimGeometry {
    public static func time(atX x: CGFloat, stripWidth: CGFloat, duration: Double) -> Double {
        guard stripWidth > 0, duration > 0 else { return 0 }
        let fraction = min(max(x / stripWidth, 0), 1)
        return Double(fraction) * duration
    }

    public static func x(forTime time: Double, stripWidth: CGFloat, duration: Double) -> CGFloat {
        guard duration > 0 else { return 0 }
        let fraction = min(max(time / duration, 0), 1)
        return CGFloat(fraction) * stripWidth
    }

    public static func snap(_ proposed: Double, toPlayhead playhead: Double, threshold: Double)
        -> Double
    {
        abs(proposed - playhead) <= threshold ? playhead : proposed
    }
}
