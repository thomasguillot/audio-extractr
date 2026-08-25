import SwiftUI

struct DownloadingView: View {
    @Environment(AppModel.self) private var model
    let fraction: Double?

    var body: some View {
        VStack(spacing: 14) {
            Text("Downloading audio")
                .font(.headline)
            Group {
                if let fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
            }
            .frame(maxWidth: 320)
            Text("Fetching the audio so you can trim it here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Cancel") { model.cancelPreparation() }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}
