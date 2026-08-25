import Foundation

public struct ReleaseFetcher: Sendable {
    public enum FetchError: Error, Equatable {
        case invalidRepository
        case insecureURL
        case badStatus(Int)
        case tooLarge
    }

    private static let maxBytes = 1024 * 1024

    /// `URL(string:)` escapes a malformed slug rather than failing, so the slug is vetted first.
    private static let slugCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._/"
    )

    private let repoSlug: String
    private let session: URLSession

    public init(repoSlug: String, session: URLSession = .shared) {
        self.repoSlug = repoSlug
        self.session = session
    }

    public func fetchLatest() async throws -> GitHubRelease {
        guard Self.isValidSlug(repoSlug) else { throw FetchError.invalidRepository }
        let endpoint = "https://api.github.com/repos/\(repoSlug)/releases/latest"
        guard let url = URL(string: endpoint), url.scheme?.lowercased() == "https" else {
            throw FetchError.insecureURL
        }
        return try await get(GitHubRelease.self, from: url)
    }

    /// Newest releases first, as GitHub returns them. Drafts and prereleases are
    /// included here and filtered by `UpdatePlan`.
    public func fetchReleases(perPage: Int = 30) async throws -> [GitHubRelease] {
        guard Self.isValidSlug(repoSlug) else { throw FetchError.invalidRepository }
        guard let url = Self.releasesEndpoint(repoSlug: repoSlug, perPage: perPage) else {
            throw FetchError.insecureURL
        }
        return try await get([GitHubRelease].self, from: url)
    }

    public static func releasesEndpoint(repoSlug: String, perPage: Int) -> URL? {
        guard isValidSlug(repoSlug) else { return nil }
        let clamped = min(max(perPage, 1), 100)
        let endpoint = "https://api.github.com/repos/\(repoSlug)/releases?per_page=\(clamped)"
        guard let url = URL(string: endpoint), url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    private static func isValidSlug(_ slug: String) -> Bool {
        slug.unicodeScalars.allSatisfy(slugCharacters.contains)
    }

    private func get<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else { throw FetchError.badStatus(-1) }
        guard http.statusCode == 200 else { throw FetchError.badStatus(http.statusCode) }
        guard data.count <= Self.maxBytes else { throw FetchError.tooLarge }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

extension ReleaseFetcher.FetchError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidRepository:
            return "The update source isn't set up correctly, so the check was canceled."
        case .insecureURL:
            return "The update check address isn't secure, so the check was canceled."
        case let .badStatus(code):
            return "The update server returned an unexpected response (status \(code))."
        case .tooLarge:
            return "The update information was larger than expected, so the check was canceled."
        }
    }
}
