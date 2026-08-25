import AppKit
import SwiftUI

struct DoneView: View {
    @Environment(AppModel.self) private var model
    let savedURL: URL

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, options: .nonRepeating)
                .accessibilityHidden(true)
            Text("Saved \(savedURL.lastPathComponent)")
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            HStack {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([savedURL])
                }
                Button("Extract Another") { model.reset() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}
