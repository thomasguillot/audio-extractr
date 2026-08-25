import Foundation

public enum WaveformPeaks {
    /// Raw s16le mono PCM → `count` normalised (0…1) per-bucket peak magnitudes.
    public static func buckets(fromPCM data: Data, count: Int) -> [Float] {
        guard count > 0 else { return [] }
        var peaks = [Float](repeating: 0, count: count)
        let sampleCount = data.count / 2
        guard sampleCount > 0 else { return peaks }
        data.withUnsafeBytes { raw in
            for index in 0..<sampleCount {
                // loadUnaligned: Data slices give no 2-byte alignment guarantee.
                let sample = raw.loadUnaligned(fromByteOffset: index * 2, as: Int16.self)
                let bucket = min(index * count / sampleCount, count - 1)
                let value = abs(Float(sample)) / 32768
                if value > peaks[bucket] { peaks[bucket] = value }
            }
        }
        return peaks
    }
}
