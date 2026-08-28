import Foundation
import Testing

@testable import ExtractrKit

@Suite struct ToolLocatorTests {
    @Test func prefersExecutableUpdatedYtDlp() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tl-\(UUID().uuidString)")
        let bundled = tmp.appendingPathComponent("bundled")
        let updated = tmp.appendingPathComponent("updated")
        try FileManager.default.createDirectory(at: updated, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let locator = ToolLocator(bundledBinDir: bundled, updatedBinDir: updated)
        #expect(locator.ytDlp() == bundled.appendingPathComponent("yt-dlp"))

        let updatedTool = updated.appendingPathComponent("yt-dlp")
        FileManager.default.createFile(
            atPath: updatedTool.path, contents: Data("x".utf8),
            attributes: [.posixPermissions: 0o755])
        #expect(locator.ytDlp() == updatedTool)
    }
    /// An app update ships a newer bundled seed than a yt-dlp the user self-updated to
    /// earlier. Preferring the updated copy unconditionally would run the older extractor.
    @Test func bundledSeedWinsWhenNewerThanTheUpdatedCopy() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tl-\(UUID().uuidString)")
        let bundled = tmp.appendingPathComponent("bundled")
        let updated = tmp.appendingPathComponent("updated")
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: updated, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let updatedTool = updated.appendingPathComponent("yt-dlp")
        FileManager.default.createFile(
            atPath: updatedTool.path, contents: Data("x".utf8),
            attributes: [.posixPermissions: 0o755])
        try "2026.08.10".write(
            to: updated.appendingPathComponent("yt-dlp.tag"), atomically: true, encoding: .utf8)

        let locator = ToolLocator(bundledBinDir: bundled, updatedBinDir: updated)
        try "2026.07.01".write(to: locator.bundledYtDlpTagFile, atomically: true, encoding: .utf8)
        #expect(locator.ytDlp() == updatedTool)

        try "2026.09.05".write(to: locator.bundledYtDlpTagFile, atomically: true, encoding: .utf8)
        #expect(locator.ytDlp() == bundled.appendingPathComponent("yt-dlp"))
    }
    @Test func ffmpegIsAlwaysBundled() {
        let locator = ToolLocator(
            bundledBinDir: URL(fileURLWithPath: "/app/bin"),
            updatedBinDir: URL(fileURLWithPath: "/support/bin"))
        #expect(locator.ffmpeg() == URL(fileURLWithPath: "/app/bin/ffmpeg"))
        #expect(locator.ffmpegDir == "/app/bin")
    }
    @Test func jobDirsAreUniqueAndCreated() throws {
        let a = try AppPaths.newJobDir()
        let b = try AppPaths.newJobDir()
        defer {
            try? FileManager.default.removeItem(at: a)
            try? FileManager.default.removeItem(at: b)
        }
        #expect(a != b)
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: a.path, isDirectory: &isDir) && isDir.boolValue)
    }
}
