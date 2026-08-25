import Foundation
import Testing

@testable import ExtractrKit

@Suite struct OutputNameTests {
    private let folder = URL(fileURLWithPath: "/tmp/out", isDirectory: true)

    @Test func firstAttemptKeepsPlainName() {
        let url = OutputName.available(base: "Episode", ext: "mp3", in: folder) { _ in false }
        #expect(url.lastPathComponent == "Episode.mp3")
    }
    @Test func collisionsAppendCounterFromTwo() {
        let taken = ["Episode.mp3", "Episode 2.mp3"]
        let url = OutputName.available(base: "Episode", ext: "mp3", in: folder) {
            taken.contains($0.lastPathComponent)
        }
        #expect(url.lastPathComponent == "Episode 3.mp3")
    }
}
