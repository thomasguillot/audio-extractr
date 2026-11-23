import SwiftUI

struct ExtractingView: View {
    @Environment(AppModel.self) private var model
    let fraction: Double?

    var body: some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.headline)
            Group {
                if let fraction, !model.transcribing, !model.saving {
                    ProgressView(value: fraction)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
            }
            .frame(maxWidth: 320)
            Button("Cancel") { model.cancel() }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }

    private var title: String {
        if model.transcribing { return "Writing transcript…" }
        return model.saving ? "Saving…" : "Converting…"
    }
}
