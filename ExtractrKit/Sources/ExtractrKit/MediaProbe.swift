import Foundation

public struct MediaProbe: Equatable, Sendable {
    public let title: String?
    public let duration: Double?

    public init(title: String?, duration: Double?) {
        self.title = title
        self.duration = duration
    }
}

public enum YtDlpProbeParser {
    private struct Payload: Decodable {
        let title: String?
        let duration: Double?
    }

    public static func parse(_ data: Data) -> MediaProbe? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return MediaProbe(title: payload.title, duration: payload.duration)
    }
}
