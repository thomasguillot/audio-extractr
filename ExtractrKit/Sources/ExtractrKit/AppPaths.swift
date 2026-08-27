import Foundation

public enum AppPaths {
    public static func supportRoot(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("AudioExtractr", isDirectory: true)
    }

    public static func binDir(root: URL) -> URL {
        root.appendingPathComponent("bin", isDirectory: true)
    }

    public static func binDir(fileManager: FileManager = .default) -> URL {
        binDir(root: supportRoot(fileManager: fileManager))
    }

    /// Parent of every job directory. `AppModel` sweeps this at launch to clear what a
    /// crashed session left behind, so the two must not spell the path out separately.
    public static func scratchRoot(fileManager: FileManager = .default) -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent("AudioExtractr", isDirectory: true)
    }

    /// Fresh per-extraction scratch directory; callers remove it when the job ends.
    public static func newJobDir(fileManager: FileManager = .default) throws -> URL {
        let dir = scratchRoot(fileManager: fileManager)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
