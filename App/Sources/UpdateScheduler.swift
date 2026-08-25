import Foundation

@MainActor
final class UpdateScheduler {
    static let launchDelay: TimeInterval = 600

    private let controller: UpdateController
    private let prefs = Preferences()
    private var timer: Timer?

    init(controller: UpdateController) { self.controller = controller }

    func start() {
        timer?.invalidate()
        timer = nil
        guard prefs.autoCheckForUpdates else { return }
        let t = Timer(timeInterval: Self.launchDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                // Re-read the preference: it may have been disabled during the wait.
                guard Preferences().autoCheckForUpdates else { return }
                await self?.controller.checkNow(userInitiated: false)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }
}
