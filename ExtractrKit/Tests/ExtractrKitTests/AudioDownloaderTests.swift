import Foundation
import Testing

@testable import ExtractrKit

@Suite struct AudioDownloaderTests {
    @Test func findsCompletedDownload() {
        let files = [
            URL(fileURLWithPath: "/tmp/job/download.m4a.part"),
            URL(fileURLWithPath: "/tmp/job/peaks.pcm"),
            URL(fileURLWithPath: "/tmp/job/download.m4a"),
        ]
        #expect(
            AudioDownloader.findDownloaded(in: files)
                == URL(fileURLWithPath: "/tmp/job/download.m4a"))
    }
    @Test func ignoresPartialAndUnrelatedFiles() {
        let files = [
            URL(fileURLWithPath: "/tmp/job/download.webm.part"),
            URL(fileURLWithPath: "/tmp/job/output.mp3"),
        ]
        #expect(AudioDownloader.findDownloaded(in: files) == nil)
    }
}
