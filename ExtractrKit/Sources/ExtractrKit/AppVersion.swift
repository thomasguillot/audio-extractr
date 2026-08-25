/// Semantic version (MAJOR.MINOR.PATCH), tolerating a single leading `v`/`V`.
public struct AppVersion: Comparable, Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ string: String) {
        var raw = string
        if let first = raw.first, first == "v" || first == "V" {
            raw.removeFirst()
        }
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var values: [Int] = []
        for part in parts {
            guard part.allSatisfy(\.isNumber), let value = Int(part), value >= 0 else { return nil }
            values.append(value)
        }
        (major, minor, patch) = (values[0], values[1], values[2])
    }

    public var displayString: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
