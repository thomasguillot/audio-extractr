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
        let files = urls([
            "download.webm.part", "output.mp3", "download.m4a.ytdl", "download.temp.m4a",
            "download.f140.m4a", "download.part", "download.ytdl", "download.temp", "download.",
            "download", "xdownload.m4a", "download.m4a.part-Frag3",
        ])
        #expect(AudioDownloader.findDownloaded(in: files) == nil)
    }

    @Test func acceptsAnySingleExtension() {
        for ext in ["m4a", "webm", "mp3", "opus", "ogg", "aac", "mp4", "flv", "3gp", "unknown_video"] {
            #expect(
                AudioDownloader.findDownloaded(in: urls(["download.temp.\(ext)", "download.\(ext)"]))
                    == URL(fileURLWithPath: "/tmp/job/download.\(ext)"))
        }
    }

    private func urls(_ names: [String]) -> [URL] {
        names.map { URL(fileURLWithPath: "/tmp/job/\($0)") }
    }
}
