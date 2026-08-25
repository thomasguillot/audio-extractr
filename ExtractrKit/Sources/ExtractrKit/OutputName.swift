import Foundation

public enum OutputName {
    /// First free "<base>.<ext>", "<base> 2.<ext>", … in `folder`; never overwrites.
    public static func available(
        base: String, ext: String, in folder: URL, exists: (URL) -> Bool
    ) -> URL {
        var attempt = 1
        while true {
            let name = attempt == 1 ? "\(base).\(ext)" : "\(base) \(attempt).\(ext)"
            let candidate = folder.appendingPathComponent(name)
            if !exists(candidate) { return candidate }
            attempt += 1
        }
    }
}
