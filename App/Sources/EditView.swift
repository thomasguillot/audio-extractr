import ExtractrKit
import SwiftUI

struct EditView: View {
    @Environment(AppModel.self) private var model

    private static let speedPresets: [Double] = [1, 1.25, 1.5, 2]

    var body: some View {
        // The window is a fixed 370pt and cannot grow, so an error banner has to push the
        // controls into a scroll rather than off the bottom. minHeight keeps the ordinary
        // layout centred, so the scroll only appears when something is added.
        ScrollView {
            content
                .padding(20)
                .frame(minHeight: MainWindowView.contentSize.height)
        }
    }

    private var content: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 28) {
            if let message = model.errorMessage {
                ErrorBanner(message: message, detail: model.errorDetail)
            }
            HStack(spacing: 6) {
                TextField("Save as", text: $model.fileName)
                    .textFieldStyle(.roundedBorder)
                Text(".mp3")
                    .foregroundStyle(.secondary)
            }
            if let selection = model.selection {
                HStack(spacing: 8) {
                    playButton
                    WaveformView(
                        peaks: model.peaks,
                        duration: selection.duration,
                        selection: selection,
                        playheadTime: model.player?.playheadTime ?? 0,
                        peaksUnavailable: model.peaksUnavailable,
                        onMoveStart: { model.moveStart(to: $0) },
                        onMoveEnd: { model.moveEnd(to: $0) },
                        onScrub: { model.scrub(to: $0) })
                }
                // The drag tooltip is drawn above the strip, outside its own bounds.
                .zIndex(1)
            }
            HStack(spacing: 6) {
                Text("Trim")
                    .foregroundStyle(.secondary)
                TextField("Start", text: $model.startText, prompt: Text("0:00"))
                    .frame(width: 72)
                    .onSubmit { model.applyStartText() }
                Text("–").foregroundStyle(.secondary)
                TextField("End", text: $model.endText, prompt: Text(endPrompt))
                    .frame(width: 72)
                    .onSubmit { model.applyEndText() }
            }
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            speedRow
            HStack(spacing: 10) {
                Toggle("Save transcript (Experimental)", isOn: $model.saveTranscript)
                    .toggleStyle(.checkbox)
                Menu {
                    Picker("Transcript language", selection: $model.transcriptLocaleIdentifier) {
                        Text("Follow system").tag("")
                        ForEach(model.transcriptLocales, id: \.identifier) { locale in
                            Text(AppModel.displayName(locale)).tag(locale.identifier(.bcp47))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    // A bare Picker draws at its selected title's width; an expanding
                    // label is what actually pins the control.
                    Text(languageLabel).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 210)
                .disabled(!model.saveTranscript)
                Spacer()
            }
            .task { await model.loadTranscriptLocales() }
            HStack {
                Button("Back") { model.reset() }
                Spacer()
                Button("Extract MP3") { model.extract() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var speedRow: some View {
        HStack(spacing: 8) {
            Text("Speed")
                .foregroundStyle(.secondary)
            Slider(value: speedBinding, in: 0.25...2, step: 0.05)
                .accessibilityLabel("Speed")
                .accessibilityValue(Self.speedLabel(model.speed))
            Text(Self.speedLabel(model.speed))
                .monospacedDigit()
                .frame(width: 46, alignment: .leading)
            HStack(spacing: 4) {
                ForEach(Self.speedPresets, id: \.self) { preset in
                    Button(Self.speedLabel(preset)) { model.speed = preset }
                        .tint(model.speed == preset ? Color.accentColor : nil)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var speedBinding: Binding<Double> {
        Binding(
            get: { model.speed },
            set: { value in
                let stepped = (value * 20).rounded() / 20
                if stepped != model.speed { model.speed = stepped }
            })
    }

    private static func speedLabel(_ speed: Double) -> String {
        "\(speed.formatted(.number.precision(.fractionLength(0...2))))×"
    }

    private var playButton: some View {
        Button {
            model.player?.toggle()
        } label: {
            Image(systemName: model.player?.isPlaying == true ? "pause.fill" : "play.fill")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 28, height: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.player == nil)
        .keyboardShortcut(" ", modifiers: [])
        .accessibilityLabel(model.player?.isPlaying == true ? "Pause" : "Play")
    }

    private var languageLabel: String {
        guard !model.transcriptLocaleIdentifier.isEmpty else { return "Follow system" }
        return model.transcriptLocales
            .first { $0.identifier(.bcp47) == model.transcriptLocaleIdentifier }
            .map(AppModel.displayName) ?? "Follow system"
    }

    private var endPrompt: String {
        model.probe?.duration.map { TimeCode.text(from: $0) } ?? "end"
    }
}
