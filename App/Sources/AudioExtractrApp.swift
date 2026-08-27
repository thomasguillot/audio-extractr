import SwiftUI

@main
struct AudioExtractrApp: App {
    @State private var model: AppModel
    @State private var updateController: UpdateController
    @State private var ytDlpController: YtDlpUpdateController
    private let updateScheduler: UpdateScheduler

    init() {
        let model = AppModel()
        let updates = UpdateController(appModel: model)
        _model = State(initialValue: model)
        _updateController = State(initialValue: updates)
        _ytDlpController = State(initialValue: YtDlpUpdateController(tools: model.tools))
        updateScheduler = UpdateScheduler(controller: updates)
    }

    var body: some Scene {
        Window("Audio Extractr", id: "main") {
            MainWindowView()
                .environment(model)
                .environment(updateController)
                .environment(ytDlpController)
                .onAppear {
                    updateScheduler.start()
                    ytDlpController.runIfDue()
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await updateController.checkNow(userInitiated: true) }
                }
            }
            CommandGroup(replacing: .help) {
                Link(
                    "Audio Extractr Website",
                    destination: URL(string: "https://thomasguillot.github.io/audio-extractr/")!)
            }
        }

        Settings {
            SettingsView()
                .environment(updateController)
                .environment(ytDlpController)
        }
    }
}
