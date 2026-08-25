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

@Suite struct FFmpegCommandTests {
    let input = URL(fileURLWithPath: "/tmp/in.m4a")
    let output = URL(fileURLWithPath: "/tmp/out.mp3")

    @Test func fullPlan() {
        let args = FFmpegCommand.extractArguments(
            input: input, output: output, trim: TrimRange(start: 10, end: 70), speed: 0.25)
        #expect(
            args == [
                "-hide_banner", "-nostdin", "-ss", "10", "-t", "60", "-i", "/tmp/in.m4a",
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
        #expect(FFmpegCommand.probeArguments(file: input) == ["-hide_banner", "-i", "/tmp/in.m4a"])
    }
    @Test func pcmArgumentsDecodeMonoS16LE() {
        let args = FFmpegCommand.pcmArguments(
            input: URL(fileURLWithPath: "/tmp/in.m4a"),
            output: URL(fileURLWithPath: "/tmp/peaks.pcm"))
        #expect(args == [
            "-hide_banner", "-nostdin", "-i", "/tmp/in.m4a", "-vn",
            "-ac", "1", "-ar", String(FFmpegCommand.peaksSampleRate),
            "-f", "s16le", "-y", "/tmp/peaks.pcm",
        ])
    }
    @Test func previewArgumentsProduceM4A() {
        let args = FFmpegCommand.previewArguments(
            input: URL(fileURLWithPath: "/tmp/in.webm"),
            output: URL(fileURLWithPath: "/tmp/preview.m4a"))
        #expect(args == [
            "-hide_banner", "-nostdin", "-i", "/tmp/in.webm", "-vn",
            "-codec:a", "aac", "-b:a", "128k", "-f", "ipod", "-y", "/tmp/preview.m4a",
        ])
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
