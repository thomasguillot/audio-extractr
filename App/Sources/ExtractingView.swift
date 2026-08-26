import SwiftUI

struct ExtractingView: View {
    @Environment(AppModel.self) private var model
    let fraction: Double?

    var body: some View {
        VStack(spacing: 14) {
            Text(model.transcribing ? "Writing transcript…" : "Converting…")
                .font(.headline)
            Group {
                if let fraction, !model.transcribing {
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
}
