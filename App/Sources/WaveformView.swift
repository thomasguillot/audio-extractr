import ExtractrKit
import SwiftUI

struct WaveformView: View {
    private static let handleWidth: CGFloat = 14
    private static let railHeight: CGFloat = 4
    private static let stripHeight: CGFloat = 56

    let peaks: [Float]?
    let duration: Double
    let selection: TrimSelection
    let playheadTime: Double
    let peaksUnavailable: Bool
    let onMoveStart: (Double) -> Void
    let onMoveEnd: (Double) -> Void
    let onScrub: (Double) -> Void

    @State private var draggingHandle: Handle?
    @State private var dragGrabOffset: CGFloat = 0
    private enum Handle { case start, end }

    private var accent: Color { Color(nsColor: .controlAccentColor) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let startX = TrimGeometry.x(
                forTime: selection.start, stripWidth: width, duration: duration)
            let endX = TrimGeometry.x(
                forTime: selection.end, stripWidth: width, duration: duration)
            let playheadX = TrimGeometry.x(
                forTime: playheadTime, stripWidth: width, duration: duration)
            let snapThreshold = TrimGeometry.time(atX: 8, stripWidth: width, duration: duration)
            ZStack(alignment: .topLeading) {
                strip(width: width, startX: startX, endX: endX)
                ForEach([0, Self.stripHeight - Self.railHeight], id: \.self) { y in
                    Rectangle().fill(accent)
                        .frame(width: max(endX - startX, 0), height: Self.railHeight)
                        .offset(x: startX, y: y)
                        .allowsHitTesting(false)
                }
                Rectangle().fill(Color(nsColor: .systemRed))
                    .frame(width: 1, height: Self.stripHeight)
                    .offset(x: playheadX)
                    .allowsHitTesting(false)
                handle(atX: startX, kind: .start) { x in
                    let proposed = TrimGeometry.time(
                        atX: x, stripWidth: width, duration: duration)
                    onMoveStart(TrimGeometry.snap(
                        proposed, toPlayhead: playheadTime, threshold: snapThreshold))
                }
                handle(atX: endX, kind: .end) { x in
                    let proposed = TrimGeometry.time(
                        atX: x, stripWidth: width, duration: duration)
                    onMoveEnd(TrimGeometry.snap(
                        proposed, toPlayhead: playheadTime, threshold: snapThreshold))
                }
                if let dragging = draggingHandle {
                    dragTooltip(for: dragging, startX: startX, endX: endX, stripWidth: width)
                }
            }
            .coordinateSpace(name: "strip")
        }
        .frame(height: Self.stripHeight)
        .padding(.horizontal, Self.handleWidth)
    }

    private func strip(width: CGFloat, startX: CGFloat, endX: CGFloat) -> some View {
        Canvas { context, size in
            guard let peaks, !peaks.isEmpty else { return }
            let barWidth = size.width / CGFloat(peaks.count)
            for (index, peak) in peaks.enumerated() {
                let barHeight = max(CGFloat(peak) * (size.height - 8), 2)
                let x = CGFloat(index) * barWidth
                let rect = CGRect(
                    x: x, y: (size.height - barHeight) / 2,
                    width: max(barWidth - 1, 0.5), height: barHeight)
                let inSelection = x + barWidth / 2 >= startX && x + barWidth / 2 <= endX
                context.fill(
                    Path(rect),
                    with: .color(inSelection ? accent : accent.opacity(0.25)))
            }
        }
        .frame(height: Self.stripHeight)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            if peaks == nil, !peaksUnavailable {
                ProgressView().controlSize(.small)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("strip"))
                .onChanged { value in
                    onScrub(TrimGeometry.time(
                        atX: value.location.x, stripWidth: width, duration: duration))
                })
    }

    private func dragTooltip(
        for handle: Handle, startX: CGFloat, endX: CGFloat, stripWidth: CGFloat
    ) -> some View {
        let time = handle == .start ? selection.start : selection.end
        let centerX = handle == .start
            ? startX - Self.handleWidth / 2
            : endX + Self.handleWidth / 2
        return Text(TimeCode.text(from: time))
            .font(.caption.monospacedDigit().weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(.black.opacity(0.75)))
            .position(x: min(max(centerX, 30), stripWidth - 30), y: -16)
            .allowsHitTesting(false)
    }

    private func handle(
        atX x: CGFloat, kind: Handle, onDrag: @escaping (CGFloat) -> Void
    ) -> some View {
        let leading = kind == .start
        return UnevenRoundedRectangle(
            topLeadingRadius: leading ? 6 : 0,
            bottomLeadingRadius: leading ? 6 : 0,
            bottomTrailingRadius: leading ? 0 : 6,
            topTrailingRadius: leading ? 0 : 6,
            style: .continuous)
            .fill(accent)
            .overlay {
                HStack(spacing: 2.5) {
                    Capsule().frame(width: 1.5, height: 16)
                    Capsule().frame(width: 1.5, height: 16)
                }
                .foregroundStyle(.black.opacity(0.35))
            }
            .frame(width: Self.handleWidth, height: Self.stripHeight)
            .offset(x: leading ? x - Self.handleWidth : x)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("strip"))
                    .onChanged { value in
                        // Keep the grabbed point under the cursor; mapping raw
                        // location to the edge would jump it on mouse-down.
                        if draggingHandle != kind {
                            draggingHandle = kind
                            dragGrabOffset = value.startLocation.x - x
                        }
                        onDrag(value.location.x - dragGrabOffset)
                    }
                    .onEnded { _ in draggingHandle = nil })
    }
}
