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

    /// Fresh per-extraction scratch directory; callers remove it when the job ends.
    public static func newJobDir(fileManager: FileManager = .default) throws -> URL {
        let dir = fileManager.temporaryDirectory
            .appendingPathComponent("AudioExtractr", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
