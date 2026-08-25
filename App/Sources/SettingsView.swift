import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(UpdateController.self) private var updates
    @Environment(YtDlpUpdateController.self) private var ytDlp
    @State private var autoCheck = Preferences().autoCheckForUpdates
    @State private var autoYtDlp = Preferences().autoUpdateYtDlp
    @State private var saveFolder = Preferences().saveFolder

    var body: some View {
        Form {
            Section {
                LabeledContent("Save MP3s to") {
                    HStack(spacing: 8) {
                        Text(saveFolder.path.replacingOccurrences(
                            of: NSHomeDirectory(), with: "~"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…") { chooseSaveFolder() }
                    }
                }
            }
            Section {
                Toggle("Check for app updates automatically", isOn: $autoCheck)
                    .onChange(of: autoCheck) {
                        var prefs = Preferences()
                        prefs.autoCheckForUpdates = autoCheck
                    }
                Button("Check Now") { Task { await updates.checkNow(userInitiated: true) } }
            }
            Section {
                Toggle("Keep yt-dlp up to date", isOn: $autoYtDlp)
                    .onChange(of: autoYtDlp) {
                        var prefs = Preferences()
                        prefs.autoUpdateYtDlp = autoYtDlp
                    }
                LabeledContent("yt-dlp version", value: ytDlp.installedTag ?? "unknown")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .onAppear { NSApplication.shared.activate(ignoringOtherApps: true) }
    }

    private func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = saveFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var prefs = Preferences()
        prefs.saveFolder = url
        saveFolder = url
    }
}
