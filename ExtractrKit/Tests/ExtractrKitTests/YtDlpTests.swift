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
    @Test func absurdDurationsAreDropped() {
        for duration in ["1e300", "-5", "604801"] {
            let probe = YtDlpProbeParser.parse(Data(#"{"title": "x", "duration": \#(duration)}"#.utf8))
            #expect(probe?.title == "x")
            #expect(probe?.duration == nil, "\(duration)")
        }
    }
    @Test func liveAndUpcomingStreamsAreLive() throws {
        for json in [
            #"{"is_live": true}"#, #"{"live_status": "is_live"}"#,
            #"{"live_status": "is_upcoming", "is_live": false}"#,
        ] {
            #expect(try #require(YtDlpProbeParser.parse(Data(json.utf8))).isLive, "\(json)")
        }
        for json in [
            #"{"is_live": false, "live_status": "was_live"}"#, #"{"live_status": "not_live"}"#,
            #"{"title": "x"}"#, #"{"is_live": null, "live_status": null}"#,
            #"{"is_live": "yes", "live_status": 3}"#,
        ] {
            #expect(try #require(YtDlpProbeParser.parse(Data(json.utf8))).isLive == false, "\(json)")
        }
    }
    @Test func playlistsAreFlagged() throws {
        for type in ["playlist", "multi_video"] {
            let json = #"{"_type": "\#(type)", "title": "Mix", "entries": []}"#
            #expect(try #require(YtDlpProbeParser.parse(Data(json.utf8))).isPlaylist)
        }
        #expect(try #require(YtDlpProbeParser.parse(Data(#"{"_type": "video"}"#.utf8))).isPlaylist == false)
        #expect(try #require(YtDlpProbeParser.parse(Data(#"{"id": "x"}"#.utf8))).isPlaylist == false)
    }
    @Test func onlyASingleRecordingPassesTheProbe() throws {
        #expect(throws: ExtractorError.liveStream) {
            try ProbeService.check(MediaProbe(title: nil, duration: nil, isLive: true))
        }
        #expect(throws: ExtractorError.playlist) {
            try ProbeService.check(MediaProbe(title: nil, duration: nil, isPlaylist: true))
        }
        try ProbeService.check(MediaProbe(title: "x", duration: 10))
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
                "--no-playlist", "--flat-playlist", "--no-warnings", "https://example.com/watch?v=1",
            ])
    }
    @Test func ytDlpIsInterruptedBeforeItIsTerminated() {
        guard case let .interrupt(grace) = YtDlpCommand.stop else {
            Issue.record("yt-dlp must get SIGINT first")
            return
        }
        #expect(grace == .seconds(3))
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
                "--postprocessor-args", "FixupM4a+ffmpeg_i:-format_whitelist \(demuxers)",
                "--postprocessor-args", "FixupM3u8+ffmpeg_i:-format_whitelist \(demuxers)",
                "--postprocessor-args", "FixupTimestamp+ffmpeg_i:-format_whitelist \(demuxers)",
                "--postprocessor-args", "FixupDuration+ffmpeg_i:-format_whitelist \(demuxers)",
                "--postprocessor-args", "FixupDuplicateMoov+ffmpeg_i:-format_whitelist \(demuxers)",
                "--postprocessor-args", "FixupStretched+ffmpeg_i:-format_whitelist \(demuxers)",
            ])
    }
}
