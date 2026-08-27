/// Subset of `GET /repos/{owner}/{repo}/releases` used to detect, describe and locate an update.
public struct GitHubRelease: Codable, Sendable, Equatable {
    public let tagName: String
    public let htmlURL: String
    public let assets: [Asset]
    public let body: String
    public let prerelease: Bool
    public let draft: Bool

    public init(
        tagName: String, htmlURL: String, assets: [Asset],
        body: String = "", prerelease: Bool = false, draft: Bool = false
    ) {
        self.tagName = tagName
        self.htmlURL = htmlURL
        self.assets = assets
        self.body = body
        self.prerelease = prerelease
        self.draft = draft
    }

    // Every field but the tag is optional in practice: a null body, or a payload
    // from the yt-dlp repo, must still decode.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        htmlURL = try container.decodeIfPresent(String.self, forKey: .htmlURL) ?? ""
        assets = try container.decodeIfPresent([Asset].self, forKey: .assets) ?? []
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        prerelease = try container.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
        draft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? false
    }

    public struct Asset: Codable, Sendable, Equatable {
        public let name: String
        public let browserDownloadURL: String
        public let size: Int

        public init(name: String, browserDownloadURL: String, size: Int) {
            self.name = name
            self.browserDownloadURL = browserDownloadURL
            self.size = size
        }

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case size
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
        case body
        case prerelease
        case draft
    }
}
