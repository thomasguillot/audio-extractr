import Foundation
import Testing

@testable import ExtractrKit

/// Feeds a response body in controlled chunks and records how many actually left the
/// protocol, so a cap that only rejects after the whole body is buffered is visible.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub {
        var declaredLength: Int?
        var chunk: Data
        var chunkCount: Int
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _stub = Stub(declaredLength: nil, chunk: Data(), chunkCount: 0)
    nonisolated(unsafe) private static var _delivered = 0

    static var stub: Stub {
        get { lock.withLock { _stub } }
        set { lock.withLock { _stub = newValue; _delivered = 0 } }
    }
    static var delivered: Int { lock.withLock { _delivered } }
    private static func countDelivery() { lock.withLock { _delivered += 1 } }

    private let stopped = NSLock()
    nonisolated(unsafe) private var _isStopped = false
    private var isStopped: Bool { stopped.withLock { _isStopped } }

    static func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return config
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let stub = Self.stub
        var headers: [String: String] = [:]
        if let declared = stub.declaredLength { headers["Content-Length"] = String(declared) }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            for _ in 0..<stub.chunkCount {
                if self.isStopped { return }
                Self.countDelivery()
                self.client?.urlProtocol(self, didLoad: stub.chunk)
                Thread.sleep(forTimeInterval: 0.002)
            }
            if !self.isStopped { self.client?.urlProtocolDidFinishLoading(self) }
        }
    }

    override func stopLoading() { stopped.withLock { _isStopped = true } }
}

@Suite(.serialized) struct HTTPGuardBodyTests {
    private func request() -> URLRequest { URLRequest(url: URL(string: "https://example.com/x")!) }

    /// A gzipped body declares its compressed length, so the declared-length pre-check passes
    /// and the real cap has to come from the bytes as they arrive.
    @Test(.timeLimit(.minutes(1)))
    func stopsReadingOnceTheBodyPassesTheCap() async {
        StubURLProtocol.stub = .init(
            declaredLength: 1_000, chunk: Data(repeating: 0x61, count: 10_000), chunkCount: 50)

        await #expect(throws: HTTPGuard.Failure.tooLarge) {
            _ = try await HTTPGuard.data(
                for: request(), configuration: StubURLProtocol.configuration(), maxBytes: 50_000)
        }
        // 500KB was on offer against a 50KB cap. Chunk 6 is the first to cross it, and a
        // guard that only checks the assembled body takes all 50.
        #expect(StubURLProtocol.delivered <= 10)
    }

    @Test(.timeLimit(.minutes(1)))
    func returnsABodyInsideTheCap() async throws {
        StubURLProtocol.stub = .init(
            declaredLength: 30_000, chunk: Data(repeating: 0x62, count: 10_000), chunkCount: 3)

        let data = try await HTTPGuard.data(
            for: request(), configuration: StubURLProtocol.configuration(), maxBytes: 50_000)
        #expect(data.count == 30_000)
    }
}
