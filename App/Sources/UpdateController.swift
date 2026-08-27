import AppKit
import ExtractrKit
import Foundation
import Observation

@MainActor
@Observable
final class UpdateController {
    private let currentVersion: AppVersion?
    private let fetcher: ReleaseFetcher
    private weak var appModel: AppModel?

    private enum CheckKind { case interactive, background }
    private var inFlight: Set<CheckKind> = []
    /// Held until the app next goes idle. Only one background check runs per launch, so
    /// dropping this would cost the session its update prompt entirely.
    private var pendingUpdate: UpdatePlan.AvailableUpdate?

    init(
        appModel: AppModel? = nil,
        fetcher: ReleaseFetcher = ReleaseFetcher(repoSlug: "thomasguillot/audio-extractr"),
        bundleVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String
    ) {
        self.appModel = appModel
        self.fetcher = fetcher
        self.currentVersion = bundleVersion.flatMap(AppVersion.init)
        observeStage()
    }

    /// `onChange` runs before the new value lands and fires only once, so the read
    /// hops to the next main-actor turn and re-arms every time.
    private func observeStage() {
        withObservationTracking { _ = appModel?.stage } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeStage()
                self.flushPendingUpdate()
            }
        }
    }

    func checkNow(userInitiated: Bool) async {
        // Fail safe: an unparseable own version can't be compared, so never report a spurious update.
        guard let current = currentVersion else {
            if userInitiated { showUpToDate() }
            return
        }
        // A second Check Now collapses into the first; an interactive check never waits on a background one.
        let kind: CheckKind = userInitiated ? .interactive : .background
        guard !inFlight.contains(.interactive), userInitiated || inFlight.isEmpty else { return }
        inFlight.insert(kind)
        defer { inFlight.remove(kind) }

        do {
            let releases = try await fetcher.fetchReleases()
            let outcome = UpdatePlan.evaluate(
                current: current, releases: releases,
                skipped: Preferences().skippedUpdateVersion, interactive: userInitiated)
            switch outcome {
            case .upToDate:
                if userInitiated { showUpToDate() }
            case let .available(update):
                present(update, deferrable: !userInitiated)
            }
        } catch {
            if userInitiated {
                showFailure(error.localizedDescription)
            } else {
                print("Update check failed: \(error.localizedDescription)")
            }
        }
    }

    private func flushPendingUpdate() {
        guard let pending = pendingUpdate, let stage = appModel?.stage, Self.isIdle(stage) else {
            return
        }
        // Re-read: automatic checks may have been turned off while the update was held.
        guard Preferences().autoCheckForUpdates else { return }
        pendingUpdate = nil
        // The user may have skipped this version from a window opened while it was held.
        let skipped = Preferences().skippedUpdateVersion
        guard !UpdatePlan.isSkipped(pending.version, skipped: skipped) else { return }
        present(pending, deferrable: false)
    }

    /// A window stealing focus over the waveform is worse than waiting for the next launch.
    private static func isIdle(_ stage: AppModel.Stage) -> Bool {
        switch stage {
        case .input, .done: return true
        case .probing, .downloading, .edit, .extracting: return false
        }
    }

    private func present(_ update: UpdatePlan.AvailableUpdate, deferrable: Bool) {
        if deferrable, let stage = appModel?.stage, !Self.isIdle(stage) {
            pendingUpdate = update
            return
        }
        pendingUpdate = nil
        UpdateWindowController.shared.show(
            update, currentVersion: currentVersion?.displayString ?? "")
    }

    private func activate() { NSApplication.shared.activate(ignoringOtherApps: true) }

    private func showUpToDate() {
        activate()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "You're up to date"
        let version = currentVersion?.displayString ?? ""
        alert.informativeText = "Audio Extractr \(version) is the latest version."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showFailure(_ message: String) {
        activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Update check failed"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
