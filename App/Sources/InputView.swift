import SwiftUI
import UniformTypeIdentifiers

struct InputView: View {
    @Environment(AppModel.self) private var model
    @State private var showImporter = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 16) {
            if let message = model.errorMessage {
                ErrorBanner(message: message, detail: model.errorDetail)
            }
            HStack(spacing: 8) {
                TextField("Paste a link to grab its audio", text: $model.urlText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if canFetch { model.submitURL() } }
                Button("Fetch") { model.submitURL() }
                    .disabled(!canFetch)
            }
            Text("or")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            DropZone(showImporter: $showImporter)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audiovisualContent]) { result in
            if case let .success(url) = result { model.pickFile(url) }
        }
    }

    private var canFetch: Bool {
        !model.urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct DropZone: View {
    @Environment(AppModel.self) private var model
    @Binding var showImporter: Bool
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Drop an audio or video file")
                .foregroundStyle(.secondary)
            Button("Browse…") { showImporter = true }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            isTargeted ? Color.accentColor.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard model.stage != .probing else { return false }
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                Task { @MainActor in
                    if let url {
                        model.pickFile(url)
                    } else {
                        model.presentDropFailure(error)
                    }
                }
            }
            return true
        }
    }
}
