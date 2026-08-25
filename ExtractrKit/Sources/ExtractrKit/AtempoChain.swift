public enum AtempoChain {
    /// Decomposes a speed into chained atempo factors, each within ffmpeg's [0.5, 2.0] range.
    public static func filter(for speed: Double) -> String? {
        guard speed > 0, speed != 1 else { return nil }
        var factors: [Double] = []
        var remaining = speed
        while remaining < 0.5 {
            factors.append(0.5)
            remaining /= 0.5
        }
        while remaining > 2.0 {
            factors.append(2.0)
            remaining /= 2.0
        }
        factors.append(remaining)
        return factors.map { "atempo=\(format($0))" }.joined(separator: ",")
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.1f", value) : "\(value)"
    }
}
