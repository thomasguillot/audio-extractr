import SwiftUI

struct ProbingView: View {
    @Environment(AppModel.self) private var model
    @State private var phase = 0

    private var status: String {
        switch phase {
        case 0: return model.probingIsRemote ? "Contacting the site…" : "Reading the file…"
        case 1: return "Reading media info…"
        default: return "Still working — some sites take a moment…"
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            Text("Fetching media info")
                .font(.headline)
            ProgressView()
                .progressViewStyle(.linear)
                .frame(maxWidth: 320)
            Text(status)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .animation(.default, value: phase)
            Button("Cancel") { model.cancelPreparation() }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .task {
            try? await Task.sleep(for: .seconds(3))
            phase = 1
            try? await Task.sleep(for: .seconds(5))
            phase = 2
        }
    }
}
