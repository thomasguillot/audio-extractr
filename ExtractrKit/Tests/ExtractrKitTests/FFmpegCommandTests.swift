import Foundation
import Testing

@testable import ExtractrKit

@Suite struct AtempoChainTests {
    @Test func normalSpeedIsNil() {
        #expect(AtempoChain.filter(for: 1.0) == nil)
    }
    @Test func quarterSpeedChains() {
        #expect(AtempoChain.filter(for: 0.25) == "atempo=0.5,atempo=0.5")
    }
    @Test func inRangeSpeedsSingle() {
        #expect(AtempoChain.filter(for: 0.5) == "atempo=0.5")
        #expect(AtempoChain.filter(for: 1.5) == "atempo=1.5")
        #expect(AtempoChain.filter(for: 2.0) == "atempo=2.0")
        #expect(AtempoChain.filter(for: 0.75) == "atempo=0.75")
    }
    @Test func fineGrainedSpeedsProduceCleanFilters() {
        #expect(AtempoChain.filter(for: 1.15) == "atempo=1.15")
        #expect(AtempoChain.filter(for: 0.85) == "atempo=0.85")
        #expect(AtempoChain.filter(for: 0.35) == "atempo=0.5,atempo=0.7")
    }
}

let demuxers = [
    "mov", "mp4", "m4a", "3gp", "3g2", "mj2", "matroska", "webm", "mp3", "aac", "wav", "w64",
    "aiff", "flac", "ogg", "caf", "amr", "ac3", "eac3", "dts", "dtshd", "truehd", "mlp", "wv",
    "ape", "tta", "mpc", "mpc8", "tak", "shn", "dsf", "au", "voc", "loas", "asf", "rm", "avi",
    "mpegts", "flv", "mpeg", "mpegvideo", "dv", "mxf",
].joined(separator: ",")

/// Every `-i` must name the demuxers it may use: a playlist named .m4a otherwise opens as
/// HLS and reads local files into the output.
func expectEveryInputIsLimited(_ args: [String], sourceLocation: SourceLocation = #_sourceLocation) {
    let inputs = args.indices.filter { args[$0] == "-i" }
    #expect(!inputs.isEmpty, sourceLocation: sourceLocation)
    for index in inputs {
        #expect(index >= 2, sourceLocation: sourceLocation)
        guard index >= 2 else { continue }
        #expect(
            Array(args[(index - 2)..<index]) == ["-format_whitelist", demuxers],
            sourceLocation: sourceLocation)
    }
}

@Suite struct FFmpegCommandTests {
    let input = URL(fileURLWithPath: "/tmp/in.m4a")
    let output = URL(fileURLWithPath: "/tmp/out.mp3")

    @Test func fullPlan() {
        let args = FFmpegCommand.extractArguments(
            input: input, output: output, trim: TrimRange(start: 10, end: 70), speed: 0.25)
        #expect(
            args == [
                "-hide_banner", "-nostdin", "-ss", "10", "-t", "60",
                "-format_whitelist", demuxers, "-i", "/tmp/in.m4a",
                "-vn", "-filter:a", "atempo=0.5,atempo=0.5", "-codec:a", "libmp3lame",
                "-b:a", "192k", "-f", "mp3", "-progress", "pipe:1", "-nostats", "-y",
                "/tmp/out.mp3",
            ])
    }
    @Test func defaultsOmitTrimAndFilter() {
        let args = FFmpegCommand.extractArguments(
            input: input, output: output, trim: TrimRange(), speed: 1.0)
        #expect(!args.contains("-ss"))
        #expect(!args.contains("-t"))
        #expect(!args.contains("-filter:a"))
    }
    @Test func probeArguments() {
        #expect(
            FFmpegCommand.probeArguments(file: input)
                == ["-hide_banner", "-format_whitelist", demuxers, "-i", "/tmp/in.m4a"])
    }
    @Test func pcmArgumentsDecodeMonoS16LE() {
        let args = FFmpegCommand.pcmArguments(
            input: URL(fileURLWithPath: "/tmp/in.m4a"),
            output: URL(fileURLWithPath: "/tmp/peaks.pcm"))
        #expect(args == [
            "-hide_banner", "-nostdin", "-format_whitelist", demuxers, "-i", "/tmp/in.m4a", "-vn",
            "-ac", "1", "-ar", String(FFmpegCommand.peaksSampleRate),
            "-f", "s16le", "-y", "/tmp/peaks.pcm",
        ])
    }
    @Test func previewArgumentsProduceM4A() {
        let args = FFmpegCommand.previewArguments(
            input: URL(fileURLWithPath: "/tmp/in.webm"),
            output: URL(fileURLWithPath: "/tmp/preview.m4a"))
        #expect(args == [
            "-hide_banner", "-nostdin", "-format_whitelist", demuxers, "-i", "/tmp/in.webm", "-vn",
            "-codec:a", "aac", "-b:a", "128k", "-f", "ipod", "-y", "/tmp/preview.m4a",
        ])
    }
    @Test func everyBuilderLimitsItsInputDemuxers() {
        expectEveryInputIsLimited(
            FFmpegCommand.extractArguments(
                input: input, output: output, trim: TrimRange(start: 2, end: 5), speed: 1.5))
        expectEveryInputIsLimited(
            FFmpegCommand.extractArguments(input: input, output: output, trim: TrimRange(), speed: 1))
        expectEveryInputIsLimited(FFmpegCommand.probeArguments(file: input))
        expectEveryInputIsLimited(FFmpegCommand.pcmArguments(input: input, output: output))
        expectEveryInputIsLimited(FFmpegCommand.previewArguments(input: input, output: output))
    }
}

@Suite struct FFmpegProbeParserTests {
    @Test func aPlaylistOrScriptDemuxerIsRefused() {
        for format in ["hls", "concat", "ffmetadata", "image2", "lavfi", "webm_dash_manifest"] {
            let stderr = """
                Input #0, \(format), from 'evil.m4a':
                  Duration: 00:00:10.00, start: 0.000000, bitrate: 0 kb/s
                  Stream #0:0: Audio: mp3, 44100 Hz, stereo, fltp, 128 kb/s
                """
            #expect(FFmpegProbeParser.parse(stderr: stderr, title: "evil") == nil, "\(format)")
        }
    }
    @Test func everyAllowedContainerIsAccepted() {
        for format in [
            "mov,mp4,m4a,3gp,3g2,mj2", "matroska,webm", "mp3", "aac", "wav", "aiff", "flac", "ogg",
            "caf", "asf", "avi", "mpegts", "flv", "mpeg", "dv", "mxf", "wv", "w64", "ac3",
        ] {
            let stderr = """
                Input #0, \(format), from 'clip':
                  Duration: 00:00:04.00, start: 0.000000, bitrate: 128 kb/s
                """
            #expect(
                FFmpegProbeParser.parse(stderr: stderr, title: "clip")
                    == MediaProbe(title: "clip", duration: 4), "\(format)")
        }
    }
    @Test func theInputLineMustStartALine() {
        let stderr = """
            [hls @ 0x1] title: Input #0, mp3, from 'x':
            Input #0, hls, from 'evil.mp3':
              Duration: 00:00:10.00, start: 0.000000, bitrate: 0 kb/s
            """
        #expect(FFmpegProbeParser.parse(stderr: stderr, title: nil) == nil)
    }
    @Test func anUnopenableFileIsNil() {
        #expect(FFmpegProbeParser.parse(stderr: "x.m4a: Invalid data found when processing input", title: nil) == nil)
        #expect(FFmpegProbeParser.parse(stderr: "", title: nil) == nil)
    }
}

@Suite struct FFmpegDurationParserTests {
    @Test func parsesDurationLine() {
        let stderr = "Input #0, mov\n  Duration: 00:03:25.43, start: 0.0, bitrate: 128 kb/s\n"
        #expect(FFmpegDurationParser.duration(fromStderr: stderr) == 205.43)
    }
    @Test func missingDurationIsNil() {
        #expect(FFmpegDurationParser.duration(fromStderr: "no duration here") == nil)
    }
}
