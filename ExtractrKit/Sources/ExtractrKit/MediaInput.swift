import Foundation

public enum MediaInput: Equatable, Sendable {
    case remote(URL)
    case localFile(URL)

    public var isRemote: Bool {
        if case .remote = self { return true }
        return false
    }
}
