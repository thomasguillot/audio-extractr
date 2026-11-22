import Foundation

public enum TimeCode {
    /// "SS", "M:SS", or "H:MM:SS" → total seconds. Fields after the first must be 0–59.
    public static func seconds(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count),
            parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) })
        else { return nil }
        let values = parts.compactMap { Int($0) }
        guard values.count == parts.count else { return nil }
        if values.dropFirst().contains(where: { $0 > 59 }) { return nil }
        var total = 0
        for value in values {
            let (multiplied, mulOverflow) = total.multipliedReportingOverflow(by: 60)
            if mulOverflow { return nil }
            let (added, addOverflow) = multiplied.addingReportingOverflow(value)
            if addOverflow { return nil }
            total = added
        }
        return total
    }

    /// `current` when the text still reads as it, so committing a field that only shows a
    /// dragged handle keeps the handle's fraction; otherwise the typed time.
    public static func seconds(from text: String, keeping current: Double) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed == self.text(from: current) { return current }
        return seconds(from: trimmed).map(Double.init)
    }

    /// Total: a non-finite or negative time reads as zero, and a huge one is clamped.
    public static func text(from seconds: Double) -> String {
        let total = seconds.isFinite ? Int(min(max(seconds, 0), 1e15).rounded(.down)) : 0
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
