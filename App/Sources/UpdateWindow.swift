import AppKit
import ExtractrKit
import Foundation
import Observation
import SwiftUI

/// Sparkle-style update window: one window, four phases. Ported from Newspack Shots.
@MainActor
final class UpdateWindowController: NSObject, NSWindowDelegate {
    static let shared = UpdateWindowController()

    private var window: NSWindow?
    private var model: UpdateWindowModel?
    private var hosting: NSHostingView<UpdateWindowView>?

    func show(_ update: UpdatePlan.AvailableUpdate, currentVersion: String) {
        if let window {
            guard model?.update.version != update.version else {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                return
            }
            // A newer release landed while the window was open on an older one.
            // Closing cancels any in-flight download and clears state synchronously.
            window.close()
        }

        let model = UpdateWindowModel(update: update, currentVersion: currentVersion) { [weak self] in
            self?.window?.close()
        }
        self.model = model

        let hosting = NSHostingView(rootView: UpdateWindowView(model: model))
        let size = hosting.fittingSize
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        guard let screen else { return }
        let frame = CGRect(
            x: (screen.visibleFrame.midX - size.width / 2).rounded(),
            y: (screen.visibleFrame.midY - size.height / 2).rounded(),
            width: size.width, height: size.height)

        // Not resizable: the notes scroll inside their box.
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.delegate = self
        window.contentView = hosting
        self.hosting = hosting
        window.setFrame(frame, display: true)
        self.window = window

        trackPhase()

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// The frame is measured from the available phase, which is the shortest of the four:
    /// one row of buttons against two or three for the others. Nothing in the view can take
    /// up the slack either, since the notes box is a fixed height and the phase bars use
    /// fixedSize. Without re-fitting, Install and Relaunch falls outside the window.
    private func trackPhase() {
        guard let model else { return }
        withObservationTracking {
            _ = model.phase
        } onChange: { [weak self] in
            // onChange runs before the new value lands, so re-fit on the next turn.
            Task { @MainActor in
                self?.fitToContent()
                self?.trackPhase()
            }
        }
    }

    private func fitToContent() {
        guard let window, let hosting else { return }
        hosting.layoutSubtreeIfNeeded()
        let content = hosting.fittingSize
        guard content.height > 0 else { return }
        let target = window.frameRect(forContentRect: CGRect(origin: .zero, size: content))
        guard abs(target.height - window.frame.height) > 0.5 else { return }
        var frame = window.frame
        // Grow downward from the title bar rather than about the centre.
        frame.origin.y += frame.height - target.height
        frame.size = target.size
        window.setFrame(frame, display: true, animate: true)
    }

    func windowWillClose(_ notification: Notification) {
        model?.cancelDownload()
        model?.discardDownload()
        model = nil
        window = nil
        hosting = nil
    }
}

@MainActor
@Observable
final class UpdateWindowModel {
    enum Phase: Equatable {
        case available
        case downloading(received: Int64, total: Int64?)
        case ready(dmg: URL)
        case failed(String)
    }

    private(set) var phase: Phase = .available
    let update: UpdatePlan.AvailableUpdate
    let currentVersion: String

    private let close: () -> Void
    private let downloader = UpdateDownloader()
    private let installer = UpdateInstaller()
    private var downloadTask: Task<Void, Never>?

    init(
        update: UpdatePlan.AvailableUpdate, currentVersion: String,
        close: @escaping () -> Void
    ) {
        self.update = update
        self.currentVersion = currentVersion
        self.close = close
    }

    func dismiss() { close() }

    func skip() {
        var prefs = Preferences()
        prefs.skippedUpdateVersion = update.version.displayString
        close()
    }

    func startDownload() {
        guard case .available = phase else { return }
        phase = .downloading(received: 0, total: update.size > 0 ? Int64(update.size) : nil)
        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let dmg = try await self.downloader.downloadToTemp(
                    dmgURL: self.update.dmgURL, expectedSize: self.update.size,
                    expectedSHA256: self.update.sha256,
                    onProgress: { received, total in
                        Task { @MainActor [weak self] in
                            // One Task per chunk, and Tasks are unordered: never go backwards.
                            guard let self, case let .downloading(shown, _) = self.phase,
                                received >= shown
                            else { return }
                            self.phase = .downloading(received: received, total: total)
                        }
                    })
                self.phase = .ready(dmg: dmg)
            } catch is CancellationError {
                self.phase = .available
            } catch let error as URLError where error.code == .cancelled {
                self.phase = .available
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
    }

    /// A downloaded image is ours to clean up until `install` consumes it.
    func discardDownload() {
        guard case let .ready(dmg) = phase else { return }
        try? FileManager.default.removeItem(at: dmg)
        phase = .available
    }

    func installAndRelaunch() {
        guard case let .ready(dmg) = phase else { return }
        do {
            let path = try installer.install(dmgAt: dmg)
            installer.relaunch(path: path)
        } catch {
            try? FileManager.default.removeItem(at: dmg)
            phase = .failed(error.localizedDescription)
        }
    }

    func openReleasePage() {
        guard let pageURL = update.pageURL else { return }
        NSWorkspace.shared.open(pageURL)
        close()
    }
}

private struct UpdateWindowView: View {
    let model: UpdateWindowModel

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 8) {
                Text("A new version of Audio Extractr is available!")
                    .font(.headline)
                Text(
                    "Audio Extractr \(model.update.version.displayString) is now available. "
                        + "You have \(model.currentVersion). Would you like to install it now?"
                )
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
                if !model.update.sections.isEmpty {
                    Text("Release Notes:")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.top, 4)
                    notesBox
                }
                bottomBar
                    .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(width: 540)
        .onExitCommand { model.dismiss() }
    }

    private var notesBox: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.update.sections.indices, id: \.self) { index in
                    let section = model.update.sections[index]
                    if model.update.sections.count > 1 {
                        Text(section.version)
                            .font(.system(size: 13, weight: .bold))
                            .padding(.top, index == 0 ? 0 : 6)
                    }
                    ForEach(section.blocks.indices, id: \.self) { block in
                        blockView(section.blocks[block])
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .frame(height: 190)
        .background(.background)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator, lineWidth: 1))
    }

    @ViewBuilder
    private func blockView(_ block: ReleaseNotes.Block) -> some View {
        switch block {
        case let .heading(_, text):
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .padding(.top, 2)
        case let .paragraph(text):
            inline(text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        case let .bullet(text):
            HStack(alignment: .top, spacing: 6) {
                Text("•").font(.system(size: 12))
                inline(text)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Inline-only: a block construct left in a note must not restyle the row.
    private func inline(_ markdown: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: markdown, options: options) {
            return Text(attributed)
        }
        return Text(markdown)
    }

    @ViewBuilder
    private var bottomBar: some View {
        switch model.phase {
        case .available:
            HStack {
                Button("Skip This Version") { model.skip() }
                Spacer()
                Button("Remind Me Later") { model.dismiss() }
                Button("Install Update") { model.startDownload() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        case let .downloading(received, total):
            downloadingBar(received: received, total: total)
        case .ready:
            readyBar
        case let .failed(message):
            failedBar(message)
        }
    }

    private func downloadingBar(received: Int64, total: Int64?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Downloading update…")
                .font(.system(size: 12, weight: .semibold))
            HStack(spacing: 10) {
                if let total {
                    ProgressView(value: Double(received), total: Double(total))
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                Button("Cancel") { model.cancelDownload() }
            }
            if let total {
                Text(
                    "\(ByteCountFormatter.string(fromByteCount: received, countStyle: .file)) of "
                        + "\(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var readyBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The update is ready. Audio Extractr will quit, install it, and relaunch.")
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Install and Relaunch") { model.installAndRelaunch() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func failedBar(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Update failed")
                .font(.system(size: 12, weight: .semibold))
            ScrollView {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 90)
            HStack {
                Spacer()
                if model.update.pageURL != nil {
                    Button("Open Release Page") { model.openReleasePage() }
                }
                Button("Close") { model.dismiss() }
            }
        }
    }
}
