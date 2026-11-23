import Foundation

public struct MediaProbe: Equatable, Sendable {
    public let title: String?
    public let duration: Double?
    /// Live now or scheduled: there is no finished recording to save.
    public let isLive: Bool
    public let isPlaylist: Bool

    public init(title: String?, duration: Double?, isLive: Bool = false, isPlaylist: Bool = false) {
        self.title = title
        self.duration = duration
        self.isLive = isLive
        self.isPlaylist = isPlaylist
    }
}

public enum YtDlpProbeParser {
    private struct Payload: Decodable {
        let title: String?
        let duration: Double?
        let isLive: Bool?
        let liveStatus: String?
        let type: String?

        enum CodingKeys: String, CodingKey {
            case title, duration
            case isLive = "is_live", liveStatus = "live_status", type = "_type"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            duration = try container.decodeIfPresent(Double.self, forKey: .duration)
                .flatMap(MediaDuration.bounded)
            isLive = try? container.decodeIfPresent(Bool.self, forKey: .isLive)
            liveStatus = try? container.decodeIfPresent(String.self, forKey: .liveStatus)
            type = try? container.decodeIfPresent(String.self, forKey: .type)
        }
    }

    public static func parse(_ data: Data) -> MediaProbe? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return MediaProbe(
            title: payload.title, duration: payload.duration,
            isLive: payload.isLive == true
                || ["is_live", "is_upcoming"].contains(payload.liveStatus ?? ""),
            isPlaylist: ["playlist", "multi_video"].contains(payload.type ?? ""))
    }
}
