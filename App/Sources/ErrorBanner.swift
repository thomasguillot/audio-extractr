import SwiftUI

struct ErrorBanner: View {
    let message: String
    let detail: String?
    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.primary)
            if let detail {
                Button(showDetail ? "Hide Details" : "Show Details") { showDetail.toggle() }
                    .buttonStyle(.link)
                    .font(.caption)
                if showDetail {
                    Text(detail)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}
