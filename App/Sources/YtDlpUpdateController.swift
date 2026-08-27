import ExtractrKit
import Foundation
import Observation

@MainActor
@Observable
final class YtDlpUpdateController {
    private(set) var installedTag: String?
    private let tools: ToolLocator

    init(tools: ToolLocator) {
        self.tools = tools
        refreshTag()
    }

    private var updater: YtDlpUpdater {
        YtDlpUpdater(binDir: AppPaths.binDir(), bundledTagFile: tools.bundledYtDlpTagFile)
    }

    func refreshTag() {
        installedTag = updater.installedTag()
    }

    func runIfDue() {
        var prefs = Preferences()
        guard prefs.autoUpdateYtDlp else { return }
        if let last = prefs.lastYtDlpCheckAt, Date().timeIntervalSince(last) < 86_400 { return }
        prefs.lastYtDlpCheckAt = Date()
        let updater = updater
        Task {
            if let tag = try? await updater.updateIfNeeded() {
                installedTag = tag
            }
        }
    }
}
