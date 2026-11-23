import Foundation

public enum FacebookShareError: Error, Equatable {
    case loginRequired
}

public protocol RedirectTracing: Sendable {
    /// `url` first, then each redirect target in order.
    func hops(from url: URL) async throws -> [URL]
}

/// Facebook's share links (`/share/v/…`, `/share/r/…`, `fb.watch/…`) have no yt-dlp extractor,
/// and a logged-out `fb.watch` link loops on a login redirect there. Following them here hands
/// yt-dlp the video URL itself, or turns the login wall into a clear message.
public struct FacebookShareResolver: Sendable {
    public static let maxRedirects = 5
    static let facebookHosts: Set<String> = [
        "facebook.com", "www.facebook.com", "m.facebook.com", "web.facebook.com",
    ]
    private static let loginHosts = facebookHosts.union(["fb.watch", "www.fb.watch"])
    private static let loginPaths: Set<String> = ["login", "login.php", "checkpoint"]

    private let tracer: any RedirectTracing

    public init(tracer: any RedirectTracing = URLSessionRedirectTracer()) {
        self.tracer = tracer
    }

    /// Returns `url` unchanged unless it is a share link that leads to a supported video URL,
    /// and throws only for a login wall. Anything else still goes to yt-dlp as it was: its
    /// generic extractor often gets the redirect where a plain request is refused. The result
    /// still has to pass `URLPolicy.validated(_:)` before it reaches yt-dlp.
    public func resolve(_ url: URL) async throws -> URL {
        guard Self.isShareLink(url) else { return url }
        let hops: [URL]
        do {
            hops = try await tracer.hops(from: url)
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            return url
        }
        try Task.checkCancellation()
        return try Self.evaluate(hops) ?? url
    }

    public static func isShareLink(_ url: URL) -> Bool {
        guard URLPolicy.isHTTPS(url), let host = host(of: url), let parts = pathParts(of: url)
        else { return false }
        if host == "fb.watch" { return parts.count == 1 && isCode(parts[0]) }
        return facebookHosts.contains(host) && parts.count == 3 && parts[0] == "share"
            && (parts[1] == "v" || parts[1] == "r") && isCode(parts[2])
    }

    /// A hop past which there is nothing left to learn, so the tracer stops following.
    /// Leaving Facebook settles it too: nothing off its hosts is ever requested.
    public static func settles(_ url: URL) -> Bool {
        guard URLPolicy.isHTTPS(url), let host = host(of: url), loginHosts.contains(host) else {
            return true
        }
        return isLoginPage(url) || videoURL(url) != nil
    }

    static func evaluate(_ hops: [URL]) throws -> URL? {
        guard hops.count > 1, hops.count <= maxRedirects + 1, hops.allSatisfy(URLPolicy.isHTTPS),
            let last = hops.last
        else { return nil }
        if isLoginPage(last) { throw FacebookShareError.loginRequired }
        return videoURL(last)
    }

    static func isLoginPage(_ url: URL) -> Bool {
        guard let host = host(of: url), loginHosts.contains(host),
            let first = pathParts(of: url)?.first
        else { return false }
        return loginPaths.contains(first.lowercased())
    }

    /// The shapes yt-dlp's Facebook extractors accept, rebuilt without tracking parameters.
    /// `/videos/<id>` has no extractor of its own, so it becomes the equivalent `/watch/?v=<id>`.
    static func videoURL(_ url: URL) -> URL? {
        guard URLPolicy.isHTTPS(url), let host = host(of: url), facebookHosts.contains(host),
            let parts = pathParts(of: url)
        else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        switch parts.count {
        case 1 where parts[0] == "watch":
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            guard let id = query?.first(where: { $0.name == "v" })?.value, isDigits(id) else {
                return nil
            }
            components.path = "/watch/"
            components.queryItems = [URLQueryItem(name: "v", value: id)]
        case 2 where parts[0] == "reel" && isDigits(parts[1]):
            components.path = "/reel/\(parts[1])"
        case 2 where parts[0] == "videos" && isDigits(parts[1]):
            components.path = "/watch/"
            components.queryItems = [URLQueryItem(name: "v", value: parts[1])]
        case 3 where parts[1] == "videos" && isPageName(parts[0]) && isDigits(parts[2]):
            components.path = "/\(parts[0])/videos/\(parts[2])/"
        default:
            return nil
        }
        return components.url
    }

    private static func host(of url: URL) -> String? {
        guard var host = url.host(percentEncoded: false)?.lowercased() else { return nil }
        if host.hasSuffix(".") { host.removeLast() }
        return host
    }

    /// nil for a path with an empty segment, so `//share/v/x` is not read as `/share/v/x`.
    private static func pathParts(of url: URL) -> [String]? {
        var path = url.path(percentEncoded: false)
        guard path.hasPrefix("/") else { return path.isEmpty ? [] : nil }
        path.removeFirst()
        if path.hasSuffix("/") { path.removeLast() }
        if path.isEmpty { return [] }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return parts.contains(where: \.isEmpty) ? nil : parts
    }

    private static func isDigits(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 32 && s.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func isCode(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 64
            && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }

    private static func isPageName(_ s: String) -> Bool {
        isCode(s.replacingOccurrences(of: ".", with: "")) && s != "share"
    }
}

/// Follows redirects with HEAD, then GET when HEAD is refused, and stops at the first hop
/// that settles the answer, so the destination page itself is never fetched or read.
public struct URLSessionRedirectTracer: RedirectTracing {
    /// A current Safari string with nothing specific to this app or machine.
    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    public init() {}

    public func hops(from url: URL) async throws -> [URL] {
        let head = try await trace(url, method: "HEAD")
        if head.count > 1 { return head }
        return try await trace(url, method: "GET")
    }

    private func trace(_ url: URL, method: String) async throws -> [URL] {
        let recorder = HopRecorder(start: url)
        let session = URLSession(
            configuration: Self.configuration, delegate: recorder, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpMethod = method
        let (bytes, _) = try await session.bytes(for: request)
        bytes.task.cancel()
        return recorder.hops
    }

    private static var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent, "Accept": "text/html"]
        return configuration
    }
}

private final class HopRecorder: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _hops: [URL]

    init(start: URL) {
        _hops = [start]
    }

    var hops: [URL] { lock.withLock { _hops } }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let next = request.url else { return nil }
        let redirects: Int = lock.withLock {
            _hops.append(next)
            return _hops.count - 1
        }
        guard redirects < FacebookShareResolver.maxRedirects,
            !FacebookShareResolver.settles(next)
        else { return nil }
        return request
    }
}
