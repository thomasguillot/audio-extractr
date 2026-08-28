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
    private var _body = Data()
    private var _continuation: CheckedContinuation<Data, Error>?
    private var _finished = false

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

    /// The cap that actually bounds memory. `expectedContentLength` is the declared, still
    /// compressed length, and URLSession inflates transparently, so a small gzip can arrive
    /// as an arbitrarily large body.
    public func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data
    ) {
        let overCap: Bool = lock.withLock {
            _body.append(data)
            return _body.count > maxBytes
        }
        guard overCap else { return }
        record(.tooLarge)
        dataTask.cancel()
    }

    public func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
    ) {
        if let failure { return finish(.failure(failure)) }
        if let error { return finish(.failure(error)) }
        finish(.success(lock.withLock { _body }))
    }

    /// Resumes once: a cancelled task reports through didCompleteWithError as well.
    private func finish(_ result: Result<Data, Error>) {
        let continuation: CheckedContinuation<Data, Error>? = lock.withLock {
            guard !_finished else { return nil }
            _finished = true
            defer { _continuation = nil }
            return _continuation
        }
        guard let continuation else { return }
        switch result {
        case let .success(data): continuation.resume(returning: data)
        case let .failure(error): continuation.resume(throwing: error)
        }
    }

    /// Fetches `request` under these rules. Throws `Failure` rather than the transport error
    /// whenever a rule is what stopped the request.
    ///
    /// The session is created here rather than injected: the byte cap needs per-chunk
    /// delegate callbacks, which only a session-level delegate receives, and URLSession.shared
    /// cannot take one at all.
    public static func data(
        for request: URLRequest, configuration: URLSessionConfiguration = .ephemeral,
        maxBytes: Int
    ) async throws -> Data {
        let guardDelegate = HTTPGuard(maxBytes: maxBytes)
        let session = URLSession(
            configuration: configuration, delegate: guardDelegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            guardDelegate.lock.withLock { guardDelegate._continuation = continuation }
            session.dataTask(with: request).resume()
        }
    }
}
