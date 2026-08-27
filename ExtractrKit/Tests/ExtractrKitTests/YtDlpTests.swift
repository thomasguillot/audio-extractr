import Foundation
import Testing

@testable import ExtractrKit

@Suite struct YtDlpProbeParserTests {
    @Test func parsesTitleAndDuration() {
        let json = #"{"title": "My Video", "duration": 123.4, "other": true}"#
        let probe = YtDlpProbeParser.parse(Data(json.utf8))
        #expect(probe == MediaProbe(title: "My Video", duration: 123.4))
    }
    @Test func toleratesMissingFields() {
        let probe = YtDlpProbeParser.parse(Data(#"{"id": "x"}"#.utf8))
        #expect(probe == MediaProbe(title: nil, duration: nil))
    }
    @Test func integerDurationDecodes() {
        let probe = YtDlpProbeParser.parse(Data(#"{"duration": 120}"#.utf8))
        #expect(probe?.duration == 120)
    }
    @Test func invalidJSONIsNil() {
        #expect(YtDlpProbeParser.parse(Data("not json".utf8)) == nil)
    }
}

@Suite struct YtDlpCommandTests {
    let url = URL(string: "https://example.com/watch?v=1")!

    @Test func probeArguments() {
        #expect(
            YtDlpCommand.probeArguments(url: url) == [
                "--ignore-config", "-J",
                "--extractor-args", "youtube:player_client=android",
                "--no-playlist", "--no-warnings", "https://example.com/watch?v=1",
            ])
    }
    @Test func downloadArguments() {
        let args = YtDlpCommand.downloadArguments(
            url: url, outputTemplate: "/tmp/job/download.%(ext)s", ffmpegDir: "/app/bin")
        #expect(
            args == [
                "--ignore-config", "https://example.com/watch?v=1",
                "--extractor-args", "youtube:player_client=android",
                "-f", "bestaudio[ext=m4a]/bestaudio[ext=webm]/bestaudio/best[height<=480]",
                "--no-playlist", "--no-warnings", "--newline",
                "--ffmpeg-location", "/app/bin",
                "-o", "/tmp/job/download.%(ext)s",
            ])
    }
}
