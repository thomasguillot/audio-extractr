import Foundation

public struct ReleaseFetcher: Sendable {
    public enum FetchError: Error, Equatable {
        case invalidRepository
        case insecureURL
        case insecureRedirect
        case badStatus(Int)
        case tooLarge

        init(_ failure: HTTPGuard.Failure) {
            switch failure {
            case .insecureRedirect: self = .insecureRedirect
            case let .badStatus(code): self = .badStatus(code)
            case .tooLarge: self = .tooLarge
            }
        }
    }

    private static let maxBytes = 1024 * 1024

    /// `URL(string:)` escapes a malformed slug rather than failing, so the slug is vetted first.
    private static let slugCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._"
    )

    private let repoSlug: String

    public init(repoSlug: String) {
        self.repoSlug = repoSlug
    }

    public func fetchLatest() async throws -> GitHubRelease {
        guard Self.isValidSlug(repoSlug) else { throw FetchError.invalidRepository }
        let endpoint = "https://api.github.com/repos/\(repoSlug)/releases/latest"
        guard let url = URLPolicy.httpsURL(endpoint) else { throw FetchError.insecureURL }
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
        return URLPolicy.httpsURL(
            "https://api.github.com/repos/\(repoSlug)/releases?per_page=\(clamped)")
    }

    /// Exactly `owner/repo`. URLSession resolves dot-segments while building the request,
    /// so a slug carrying them would reach a different endpoint than the one composed here.
    private static func isValidSlug(_ slug: String) -> Bool {
        let parts = slug.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part != "." && part != ".."
                && part.unicodeScalars.allSatisfy(slugCharacters.contains)
        }
    }

    private func get<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let data = try await HTTPGuard.data(for: request, maxBytes: Self.maxBytes)
            return try JSONDecoder().decode(T.self, from: data)
        } catch let failure as HTTPGuard.Failure {
            throw FetchError(failure)
        }
    }
}

extension ReleaseFetcher.FetchError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidRepository:
            return "The update source isn't set up correctly, so the check was canceled."
        case .insecureURL:
            return "The update check address isn't secure, so the check was canceled."
        case .insecureRedirect:
            return "The update check was redirected to an insecure address and was canceled."
        case let .badStatus(code):
            return HTTPGuard.badStatusMessage(code)
        case .tooLarge:
            return "The update information was larger than expected, so the check was canceled."
        }
    }
}
