import Foundation
import Testing

@testable import ExtractrKit

@Suite struct WaveformPeaksTests {
    private func pcm(_ samples: [Int16]) -> Data {
        samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    @Test func emptyDataYieldsZeroBuckets() {
        #expect(WaveformPeaks.buckets(fromPCM: Data(), count: 4) == [0, 0, 0, 0])
    }
    @Test func zeroCountYieldsEmpty() {
        #expect(WaveformPeaks.buckets(fromPCM: pcm([100]), count: 0).isEmpty)
    }
    @Test func peaksLandInTheirBuckets() {
        let data = pcm([0, 16384, 0, 0, -32768, 0, 0, 0])
        let buckets = WaveformPeaks.buckets(fromPCM: data, count: 2)
        #expect(abs(buckets[0] - 0.5) < 0.01)
        #expect(abs(buckets[1] - 1.0) < 0.01)
    }
    @Test func negativePeaksCountViaMagnitude() {
        let buckets = WaveformPeaks.buckets(fromPCM: pcm([-16384, 8192]), count: 1)
        #expect(abs(buckets[0] - 0.5) < 0.01)
    }
    @Test func fewerSamplesThanBucketsLeavesTrailingZeros() {
        let buckets = WaveformPeaks.buckets(fromPCM: pcm([32767]), count: 3)
        #expect(buckets[0] > 0.99)
        #expect(buckets[1] == 0)
        #expect(buckets[2] == 0)
    }
    @Test func oddTrailingByteIsIgnored() {
        var data = pcm([16384])
        data.append(0x7F)
        let buckets = WaveformPeaks.buckets(fromPCM: data, count: 1)
        #expect(abs(buckets[0] - 0.5) < 0.01)
    }
}
