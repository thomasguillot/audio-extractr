import CryptoKit
import ExtractrKit
import Foundation

/// Allows a redirect only when its target stays https; a non-https redirect is cancelled and recorded.
private final class DownloadRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _blocked = false
    var blockedInsecureRedirect: Bool { lock.withLock { _blocked } }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
    ) async -> URLRequest? {
        if request.url?.scheme?.lowercased() == "https" { return request }
        lock.withLock { _blocked = true }
        return nil
    }
}

/// Writes body chunks directly to a FileHandle so no in-memory buffer accumulates. Status/size
/// validation happens before any body is drained.
private final class DownloadBodyDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    // Denylist, not allowlist: an interstitial/error page served instead of the DMG is the failure
    // mode we care about; unknown or absent MIME types are allowed through.
    static let rejectedMimeTypes: Set<String> = ["text/html", "text/plain"]

    private let redirectGuard: DownloadRedirectGuard
    private let fileHandle: FileHandle
    private let maxBytes: Int
    private let expectedSize: Int
    private let onProgress: (@Sendable (Int64, Int64?) -> Void)?
    private let expectedDigest: String
    // Lock-free by URLSession ordering: the response disposition returns before any body chunk,
    // and completion fires after the last chunk — so these are never touched concurrently.
    private var received = 0
    private var errorFlag: Error?
    private var digest = SHA256()

    private let lock = NSLock()
    private var _continuation: CheckedContinuation<Void, Error>?
    private var _completionResult: Result<Void, Error>?

    init(
        redirectGuard: DownloadRedirectGuard,
        fileHandle: FileHandle,
        maxBytes: Int,
        expectedSize: Int,
        expectedDigest: String,
        onProgress: (@Sendable (Int64, Int64?) -> Void)?
    ) {
        self.redirectGuard = redirectGuard
        self.fileHandle = fileHandle
        self.maxBytes = maxBytes
        self.expectedSize = expectedSize
        self.expectedDigest = expectedDigest
        self.onProgress = onProgress
    }

    func waitForCompletion() async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                if let result = _completionResult {
                    switch result {
                    case .success: continuation.resume()
                    case .failure(let e): continuation.resume(throwing: e)
                    }
                } else {
                    _continuation = continuation
                }
            }
        }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
    ) async -> URLRequest? {
        await redirectGuard.urlSession(
            session, task: task, willPerformHTTPRedirection: response, newRequest: request)
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask,
        didReceive response: URLResponse
    ) async -> URLSession.ResponseDisposition {
        guard let http = response as? HTTPURLResponse else {
            errorFlag = UpdateDownloader.DownloadError.badStatus(-1)
            return .cancel
        }
        guard http.statusCode == 200 else {
            errorFlag = UpdateDownloader.DownloadError.badStatus(http.statusCode)
            return .cancel
        }
        // expectedContentLength is -1 when unknown, so an undeclared length won't false-trigger.
        if http.expectedContentLength > Int64(maxBytes) {
            errorFlag = UpdateDownloader.DownloadError.tooLarge
            return .cancel
        }
        if expectedSize > 0, http.expectedContentLength >= 0,
            http.expectedContentLength != Int64(expectedSize) {
            errorFlag = UpdateDownloader.DownloadError.sizeMismatch
            return .cancel
        }
        if let mimeType = response.mimeType, Self.rejectedMimeTypes.contains(mimeType.lowercased()) {
            errorFlag = UpdateDownloader.DownloadError.unexpectedContentType
            return .cancel
        }
        return .allow
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        received += data.count
        if received > maxBytes {
            dataTask.cancel()
            errorFlag = UpdateDownloader.DownloadError.tooLarge
            return
        }
        do {
            try fileHandle.write(contentsOf: data)
            digest.update(data: data)
            // Emitted after the write so reported progress never runs ahead of bytes on disk.
            onProgress?(Int64(received), expectedSize > 0 ? Int64(expectedSize) : nil)
        } catch {
            // didCompleteWithError owns the single fileHandle.close(); don't close it here.
            errorFlag = error
            dataTask.cancel()
        }
    }

    private static func hex(_ digest: SHA256Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        var closeError: Error?
        do { try fileHandle.close() } catch { closeError = error }
        let taskResult: Result<Void, Error>
        if let e = errorFlag ?? error {
            taskResult = .failure(e)
        } else if let e = closeError {
            taskResult = .failure(e)
        } else if expectedSize > 0, received != expectedSize {
            taskResult = .failure(UpdateDownloader.DownloadError.sizeMismatch)
        } else if Self.hex(digest.finalize()) != expectedDigest {
            taskResult = .failure(UpdateDownloader.DownloadError.digestMismatch)
        } else {
            taskResult = .success(())
        }
        var cont: CheckedContinuation<Void, Error>?
        lock.withLock {
            cont = _continuation
            _continuation = nil
            if cont == nil { _completionResult = taskResult }
        }
        if let cont {
            switch taskResult {
            case .success: cont.resume()
            case .failure(let e): cont.resume(throwing: e)
            }
        }
    }
}

struct UpdateDownloader: Sendable {
    enum DownloadError: Error {
        case insecureURL, insecureRedirect, badStatus(Int), tooLarge, writeFailed
        case sizeMismatch, unexpectedContentType, digestMismatch
    }

    private static let maxBytes = 500 * 1024 * 1024

    private let session: URLSession
    private nonisolated(unsafe) let fileManager: FileManager

    init(session: URLSession = .shared, fileManager: FileManager = .default) {
        self.session = session
        self.fileManager = fileManager
    }

    /// Streams the `.dmg` to a unique temp file and returns its path. The caller
    /// (UpdateInstaller) mounts and installs from it. Every https, size and content-type guard
    /// runs before any byte is written, and the SHA-256 is checked before the path is returned,
    /// so no caller ever sees a file that failed verification.
    func downloadToTemp(
        dmgURL: URL, expectedSize: Int, expectedSHA256: String,
        onProgress: (@Sendable (Int64, Int64?) -> Void)? = nil
    ) async throws -> URL {
        guard dmgURL.scheme?.lowercased() == "https" else { throw DownloadError.insecureURL }
        if expectedSize > Self.maxBytes { throw DownloadError.tooLarge }

        var request = URLRequest(url: dmgURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 120

        let tempURL = fileManager.temporaryDirectory
            .appendingPathComponent("audioextractr-update-\(UUID().uuidString).dmg")
        let fileHandle = try makeWritableTempFile(at: tempURL)

        let redirectGuard = DownloadRedirectGuard()
        let delegate = DownloadBodyDelegate(
            redirectGuard: redirectGuard, fileHandle: fileHandle, maxBytes: Self.maxBytes,
            expectedSize: expectedSize, expectedDigest: expectedSHA256.lowercased(),
            onProgress: onProgress)
        let task = session.dataTask(with: request)
        task.delegate = delegate
        task.resume()

        do {
            try await withTaskCancellationHandler {
                try await delegate.waitForCompletion()
            } onCancel: {
                task.cancel()
            }
        } catch {
            task.cancel()
            try? fileManager.removeItem(at: tempURL)
            if redirectGuard.blockedInsecureRedirect { throw DownloadError.insecureRedirect }
            throw error
        }
        // Even if the delegate finished before cancellation propagated, refuse to install.
        if Task.isCancelled { try? fileManager.removeItem(at: tempURL); throw CancellationError() }
        if redirectGuard.blockedInsecureRedirect {
            try? fileManager.removeItem(at: tempURL)
            throw DownloadError.insecureRedirect
        }

        return tempURL
    }

    private func makeWritableTempFile(at url: URL) throws -> FileHandle {
        guard fileManager.createFile(atPath: url.path, contents: nil) else {
            throw DownloadError.writeFailed
        }
        do {
            return try FileHandle(forWritingTo: url)
        } catch {
            try? fileManager.removeItem(at: url)
            throw error
        }
    }
}

extension UpdateDownloader.DownloadError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .insecureURL:
            return "The update download link isn't secure, so the download was canceled."
        case .insecureRedirect:
            return "The update download was redirected to an insecure address and was canceled."
        case let .badStatus(code):
            return HTTPGuard.badStatusMessage(code)
        case .tooLarge:
            return "The update download is larger than expected, so it was canceled."
        case .writeFailed:
            return "The update couldn't be saved to a temporary file."
        case .sizeMismatch:
            return "The update download didn't match the size the release advertised, so it was canceled."
        case .unexpectedContentType:
            return "The update server returned a web page instead of the update disk image."
        case .digestMismatch:
            return "The update download didn't match the checksum the release published, so it was canceled."
        }
    }
}
