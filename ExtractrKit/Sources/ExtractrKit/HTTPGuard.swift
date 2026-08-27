import Foundation

/// The response rules every fetch in the app shares: https-only redirects, HTTP 200, and a byte
/// cap taken from the declared length before the body is drained.
///
/// These were written out separately at each call site and had already drifted — only the DMG
/// download refused a redirect off https, while the yt-dlp binary, which is executed, did not.
public final class HTTPGuard: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    public enum Failure: Error, Equatable {
        case insecureRedirect
        case badStatus(Int)
        case tooLarge
    }

    private let maxBytes: Int
    private let lock = NSLock()
    private var _failure: Failure?

    public init(maxBytes: Int) {
        self.maxBytes = maxBytes
    }

    public var failure: Failure? { lock.withLock { _failure } }

    /// First failure wins: a cancelled task reports the reason it was cancelled, not a later
    /// side effect of the cancellation.
    private func record(_ failure: Failure) {
        lock.withLock { if _failure == nil { _failure = failure } }
    }

    public func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
    ) async -> URLRequest? {
        if let url = request.url, URLPolicy.isHTTPS(url) { return request }
        record(.insecureRedirect)
        return nil
    }

    public func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse
    ) async -> URLSession.ResponseDisposition {
        guard let http = response as? HTTPURLResponse else {
            record(.badStatus(-1))
            return .cancel
        }
        guard http.statusCode == 200 else {
            record(.badStatus(http.statusCode))
            return .cancel
        }
        // expectedContentLength is -1 when undeclared, so an unknown length won't false-trigger;
        // the count check after the body arrives is the backstop for a server that under-declares.
        if http.expectedContentLength > Int64(maxBytes) {
            record(.tooLarge)
            return .cancel
        }
        return .allow
    }

    /// Both the release check and the DMG download surface this, so it lives in one place.
    public static func badStatusMessage(_ code: Int) -> String {
        "The update server returned an unexpected response (status \(code))."
    }

    /// Fetches `request` under these rules. Throws `Failure` rather than the transport error
    /// whenever a rule is what stopped the request.
    public static func data(for request: URLRequest, session: URLSession, maxBytes: Int) async throws
        -> Data
    {
        let guardDelegate = HTTPGuard(maxBytes: maxBytes)
        let data: Data
        do {
            (data, _) = try await session.data(for: request, delegate: guardDelegate)
        } catch {
            if let failure = guardDelegate.failure { throw failure }
            throw error
        }
        if let failure = guardDelegate.failure { throw failure }
        guard data.count <= maxBytes else { throw Failure.tooLarge }
        return data
    }
}
