import SwiftUI

struct MainWindowView: View {
    static let contentSize = CGSize(width: 640, height: 370)

    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.stage {
            case .input:
                InputView()
            case .probing:
                ProbingView()
            case let .downloading(fraction):
                DownloadingView(fraction: fraction)
            case .edit:
                EditView()
            case let .extracting(fraction):
                ExtractingView(fraction: fraction)
            case let .done(url):
                DoneView(savedURL: url)
            }
        }
        .frame(width: Self.contentSize.width, height: Self.contentSize.height)
        .alert(
            "Transcript not saved",
            isPresented: Binding(
                get: { model.transcriptFailure != nil },
                set: { if !$0 { model.dismissTranscriptFailure() } })
        ) {
            Button("OK") { model.dismissTranscriptFailure() }
        } message: {
            Text(
                [model.transcriptFailure, model.transcriptFailureDetail]
                    .compactMap { $0 }
                    .joined(separator: "\n\n"))
        }
    }
}
