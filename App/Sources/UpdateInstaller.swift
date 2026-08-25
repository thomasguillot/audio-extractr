import AppKit
import Foundation
import ExtractrKit

/// Installs a downloaded update in place: mount the `.dmg`, copy the app into
/// /Applications, strip quarantine, and relaunch. Mirrors the flow Newspack
/// Shots uses — the already-trusted running app performs the swap itself, so
/// Gatekeeper doesn't re-challenge the relaunch once quarantine is cleared.
@MainActor
struct UpdateInstaller {
    enum InstallError: LocalizedError {
        case missingApp
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingApp:
                return "The update disk image doesn't contain Audio Extractr.app."
            case let .commandFailed(detail):
                return detail
            }
        }
    }

    // Hardcoded /Applications (not the running bundle path) so an app launched
    // from a translocated or read-only location still installs correctly.
    private let appName = "Audio Extractr.app"
    private let installedPath = "/Applications/Audio Extractr.app"

    /// Mounts the image, copies the app into /Applications, strips quarantine,
    /// and returns the installed path. Does not relaunch — the caller confirms,
    /// then calls `relaunch(path:)`.
    @discardableResult
    func install(dmgAt dmg: URL) throws -> String {
        let mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("audioextractr-update-\(UUID().uuidString)")
        try shell("/usr/bin/hdiutil",
                  ["attach", dmg.path, "-nobrowse", "-readonly", "-mountpoint", mountPoint.path])
        var detached = false
        defer {
            if !detached { try? shell("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"]) }
        }

        let newApp = mountPoint.appendingPathComponent(appName)
        guard FileManager.default.fileExists(atPath: newApp.path) else { throw InstallError.missingApp }

        try? FileManager.default.removeItem(atPath: installedPath)
        try shell("/usr/bin/ditto", [newApp.path, installedPath])
        // Downloaded apps carry com.apple.quarantine; strip it or Gatekeeper
        // re-blocks the relaunch.
        try? shell("/usr/bin/xattr", ["-dr", "com.apple.quarantine", installedPath])

        try? shell("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"])
        detached = true
        try? FileManager.default.removeItem(at: dmg)

        return installedPath
    }

    func relaunch(path: String) {
        let script = Process()
        script.executableURL = URL(fileURLWithPath: "/bin/sh")
        script.arguments = ["-c", UpdateRelaunch.shellScript(
            pid: ProcessInfo.processInfo.processIdentifier, appPath: path)]
        try? script.run()
        NSApplication.shared.terminate(nil)
    }

    @discardableResult
    private func shell(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw InstallError.commandFailed("\((path as NSString).lastPathComponent) failed: \(output)")
        }
        return output
    }
}
