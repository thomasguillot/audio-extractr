import ExtractrKit
import Foundation

struct Preferences {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private enum Keys {
        static let autoCheckForUpdates = "autoCheckForUpdates"
        static let autoUpdateYtDlp = "autoUpdateYtDlp"
        static let lastYtDlpCheckAt = "lastYtDlpCheckAt"
        static let saveFolderPath = "saveFolderPath"
        static let skippedUpdateVersion = "skippedUpdateVersion"
        static let transcriptFormat = "transcriptFormat"
    }

    var autoCheckForUpdates: Bool {
        get {
            if defaults.object(forKey: Keys.autoCheckForUpdates) == nil { return true }
            return defaults.bool(forKey: Keys.autoCheckForUpdates)
        }
        set { defaults.set(newValue, forKey: Keys.autoCheckForUpdates) }
    }

    var autoUpdateYtDlp: Bool {
        get {
            if defaults.object(forKey: Keys.autoUpdateYtDlp) == nil { return true }
            return defaults.bool(forKey: Keys.autoUpdateYtDlp)
        }
        set { defaults.set(newValue, forKey: Keys.autoUpdateYtDlp) }
    }

    var skippedUpdateVersion: String {
        get { defaults.string(forKey: Keys.skippedUpdateVersion) ?? "" }
        set { defaults.set(newValue, forKey: Keys.skippedUpdateVersion) }
    }

    var lastYtDlpCheckAt: Date? {
        get { defaults.object(forKey: Keys.lastYtDlpCheckAt) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastYtDlpCheckAt) }
    }

    var saveFolder: URL {
        get {
            if let path = defaults.string(forKey: Keys.saveFolderPath), !path.isEmpty {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
        }
        set { defaults.set(newValue.path, forKey: Keys.saveFolderPath) }
    }

    var transcriptFormat: TranscriptFormat {
        get {
            guard let raw = defaults.string(forKey: Keys.transcriptFormat),
                let format = TranscriptFormat(rawValue: raw)
            else { return .markdown }
            return format
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.transcriptFormat) }
    }

}
