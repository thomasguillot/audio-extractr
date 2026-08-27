import CryptoKit
import Foundation

public enum SHA256Sums {
    /// Lines look like "<64-hex>  <filename>" (one or more spaces, optional leading '*').
    public static func hash(for filename: String, in sums: String) -> String? {
        for line in sums.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { continue }
            let name = parts[1].hasPrefix("*") ? parts[1].dropFirst() : parts[1][...]
            if name == filename { return String(parts[0]) }
        }
        return nil
    }
}

public enum YtDlpReleaseAssets {
    public struct Located: Equatable, Sendable {
        public let tag: String
        public let binaryURL: URL
        public let sumsURL: URL
    }

    public static let binaryAssetName = "yt-dlp_macos"
    public static let sumsAssetName = "SHA2-256SUMS"

    public static func locate(in release: GitHubRelease) -> Located? {
        func httpsURL(named name: String) -> URL? {
            guard let asset = release.assets.first(where: { $0.name == name }) else { return nil }
            return URLPolicy.httpsURL(asset.browserDownloadURL)
        }
        guard let binary = httpsURL(named: binaryAssetName),
            let sums = httpsURL(named: sumsAssetName)
        else { return nil }
        return Located(tag: release.tagName, binaryURL: binary, sumsURL: sums)
    }
}

public struct YtDlpUpdater: Sendable {
    public enum UpdateError: Error, Equatable {
        case assetsMissing
        case hashMissing
        case hashMismatch
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

    private static let maxBinaryBytes = 200 * 1024 * 1024
    private static let maxSumsBytes = 1024 * 1024

    /// yt-dlp tags are dates (`2026.07.04`), which `AppVersion` orders correctly. Comparing
    /// rather than testing inequality stops a replayed older release being installed over a
    /// newer one. Tags that don't parse fall back to inequality so an upstream format change
    /// can't wedge the updater.
    static func isUpgrade(from installed: String?, to candidate: String) -> Bool {
        guard let installed, !installed.isEmpty else { return true }
        guard let old = AppVersion(installed), let new = AppVersion(candidate) else {
            return candidate != installed
        }
        return new > old
    }

    private let binDir: URL
    private let bundledTagFile: URL?
    private let fetcher: ReleaseFetcher
    private let session: URLSession

    public init(
        binDir: URL,
        bundledTagFile: URL? = nil,
        fetcher: ReleaseFetcher = ReleaseFetcher(repoSlug: "yt-dlp/yt-dlp"),
        session: URLSession = .shared
    ) {
        self.binDir = binDir
        self.bundledTagFile = bundledTagFile
        self.fetcher = fetcher
        self.session = session
    }

    public func installedTag() -> String? {
        let updated = binDir.appendingPathComponent("yt-dlp.tag")
        if let tag = try? String(contentsOf: updated, encoding: .utf8) {
            return tag.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let bundledTagFile,
            let tag = try? String(contentsOf: bundledTagFile, encoding: .utf8)
        else { return nil }
        return tag.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns the newly installed tag, or nil when already current. A failed
    /// verification throws before anything replaces the previous binary.
    @discardableResult
    public func updateIfNeeded() async throws -> String? {
        let release = try await fetcher.fetchLatest()
        guard let assets = YtDlpReleaseAssets.locate(in: release) else {
            throw UpdateError.assetsMissing
        }
        guard Self.isUpgrade(from: installedTag(), to: assets.tag) else { return nil }

        let sumsData = try await fetch(assets.sumsURL, maxBytes: Self.maxSumsBytes)
        guard
            let expected = SHA256Sums.hash(
                for: YtDlpReleaseAssets.binaryAssetName,
                in: String(decoding: sumsData, as: UTF8.self))
        else { throw UpdateError.hashMissing }

        let binaryData = try await fetch(assets.binaryURL, maxBytes: Self.maxBinaryBytes)
        let actual = SHA256.hash(data: binaryData).map { String(format: "%02x", $0) }.joined()
        guard actual == expected.lowercased() else { throw UpdateError.hashMismatch }

        let fm = FileManager.default
        try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
        let staged = binDir.appendingPathComponent("yt-dlp.new")
        try binaryData.write(to: staged, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staged.path)
        let destination = binDir.appendingPathComponent("yt-dlp")
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: staged)
        } else {
            try fm.moveItem(at: staged, to: destination)
        }
        try Data(assets.tag.utf8).write(
            to: binDir.appendingPathComponent("yt-dlp.tag"), options: .atomic)
        return assets.tag
    }

    private func fetch(_ url: URL, maxBytes: Int) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 300
        do {
            return try await HTTPGuard.data(for: request, session: session, maxBytes: maxBytes)
        } catch let failure as HTTPGuard.Failure {
            throw UpdateError(failure)
        }
    }
}
