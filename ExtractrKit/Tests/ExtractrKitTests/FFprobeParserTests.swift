import Foundation
import Testing

@testable import ExtractrKit

func ffprobeFixture(_ name: String) throws -> Data {
    let url = try #require(
        Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/ffprobe"))
    return try Data(contentsOf: url)
}

private func output(_ format: String) -> Data {
    Data(#"{"format": {\#(format)}}"#.utf8)
}

@Suite struct FFprobeParserTests {
    @Test(arguments: ["audio-only", "cover-art", "flac", "h264-aac", "no-audio"])
    func readsTheContainerDuration(_ name: String) throws {
        let probe = try #require(FFprobeParser.parse(try ffprobeFixture(name), title: "clip"))
        #expect(probe.title == "clip")
        #expect(probe.duration != nil)
    }

    @Test func parsesAnAudioOnlyM4A() throws {
        #expect(
            FFprobeParser.parse(try ffprobeFixture("audio-only"), title: "clip")
                == MediaProbe(title: "clip", duration: 3))
    }

    @Test func parsesAnMP3WithCoverArt() throws {
        #expect(FFprobeParser.parse(try ffprobeFixture("cover-art"), title: nil)?.duration == 1)
    }

    /// The title would have forged a 99-hour `Duration:` line in the old `ffmpeg -i` reading.
    @Test(arguments: ["hostile-tags", "hostile-tags-full"])
    func tagsWithNewlinesAndForgedLinesChangeNothing(_ name: String) throws {
        #expect(
            FFprobeParser.parse(try ffprobeFixture(name), title: "hostile")
                == MediaProbe(title: "hostile", duration: 1))
    }

    @Test func requestedOutputCarriesNoTagText() throws {
        let text = String(decoding: try ffprobeFixture("hostile-tags"), as: UTF8.self)
        #expect(!text.contains("Duration"))
        #expect(!text.contains("tags"))
    }

    @Test func aMissingDurationStillOpens() throws {
        let probe = try #require(FFprobeParser.parse(output(#""format_name": "mp3""#), title: "x"))
        #expect(probe == MediaProbe(title: "x", duration: nil))
    }

    @Test func unreadableOutputIsNil() {
        for text in ["{\n\n}\n", "", "not json", "[]", #"{"format": "x"}"#, #"{"streams": []}"#] {
            #expect(FFprobeParser.parse(Data(text.utf8), title: nil) == nil, "\(text)")
        }
    }

    @Test func truncatedOutputNeverParses() throws {
        let data = try ffprobeFixture("audio-only")
        let end = try #require(data.lastIndex(of: UInt8(ascii: "}")))
        for length in 0..<end {
            #expect(FFprobeParser.parse(data.prefix(length), title: nil) == nil, "\(length)")
        }
        #expect(FFprobeParser.parse(data, title: nil) != nil)
    }

    @Test func aPlaylistOrScriptDemuxerIsRefused() {
        for format in ["hls", "concat", "ffmetadata", "image2", "lavfi", "webm_dash_manifest", ""] {
            let data = output(#""format_name": "\#(format)", "duration": "10.000000""#)
            #expect(FFprobeParser.parse(data, title: "evil") == nil, "\(format)")
        }
        #expect(FFprobeParser.parse(output(#""format_name": 7, "duration": "1""#), title: nil) == nil)
    }

    @Test func everyAllowedContainerIsAccepted() {
        for format in [
            "mov,mp4,m4a,3gp,3g2,mj2", "matroska,webm", "mp3", "aac", "wav", "aiff", "flac", "ogg",
            "caf", "asf", "avi", "mpegts", "flv", "mpeg", "dv", "mxf", "wv", "w64", "ac3", "shn",
        ] {
            let data = output(#""format_name": "\#(format)", "duration": "4.000000""#)
            #expect(
                FFprobeParser.parse(data, title: "clip") == MediaProbe(title: "clip", duration: 4),
                "\(format)")
        }
    }

    @Test(arguments: [
        "N/A", "nan", "inf", "-inf", "-1.0", "604801.000000", "1e300", "0x1p3", "1.0abc", "",
        String(repeating: "9", count: 400),
    ])
    func anInvalidDurationIsDropped(_ raw: String) throws {
        let data = output(#""format_name": "mp3", "duration": "\#(raw)""#)
        #expect(try #require(FFprobeParser.parse(data, title: nil)).duration == nil)
    }

    @Test func aMistypedDurationIsDropped() throws {
        let data = output(#""format_name": "mp3", "duration": 12.5"#)
        #expect(try #require(FFprobeParser.parse(data, title: nil)).duration == nil)
    }

    @Test func aLongButPlausibleDurationIsKept() throws {
        let data = output(#""format_name": "mp3", "duration": "604799.000000""#)
        #expect(try #require(FFprobeParser.parse(data, title: nil)).duration == 604_799)
    }

    @Test func aFractionalDurationIsKept() throws {
        let data = output(#""format_name": "ogg", "duration": "205.430000""#)
        #expect(try #require(FFprobeParser.parse(data, title: nil)).duration == 205.43)
    }
}

@Suite struct FFprobeCommandTests {
    @Test func probeArguments() {
        #expect(
            FFprobeCommand.arguments(file: URL(fileURLWithPath: "/tmp/in.m4a")) == [
                "-v", "error", "-hide_banner", "-of", "json", "-show_entries",
                "format=format_name,duration", "-format_whitelist", demuxers, "-i", "/tmp/in.m4a",
            ])
    }

    @Test func limitsItsInputDemuxers() {
        expectEveryInputIsLimited(FFprobeCommand.arguments(file: URL(fileURLWithPath: "/tmp/in.m4a")))
    }
}
