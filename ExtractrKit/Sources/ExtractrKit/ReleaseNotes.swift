import Foundation

/// GitHub release bodies to display blocks for the update window. Block-level
/// markdown only; inline markdown stays in the strings for the UI to render.
public enum ReleaseNotes {
    public enum Block: Equatable, Sendable {
        case heading(level: Int, text: String)
        case bullet(String)
        case paragraph(String)
    }

    public static func blocks(from body: String) -> [Block] {
        var parser = Parser()
        let lines = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        for line in lines { parser.consume(line) }
        return parser.finish()
    }
}

extension ReleaseNotes {
    /// Drops the workflow-appended install section and the `Requires macOS`
    /// line: neither means anything to someone who is already running the app.
    private struct Parser {
        private var blocks: [Block] = []
        private var paragraph: [String] = []
        private var skippingInstall = false
        private var bulletOpen = false

        mutating func consume(_ raw: String) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let heading = Self.heading(in: line) {
                consume(heading: heading)
                return
            }
            guard !skippingInstall else { return }
            if line.isEmpty {
                flushParagraph()
                bulletOpen = false
                return
            }
            if Self.isThematicBreak(line) {
                flushParagraph()
                bulletOpen = false
                return
            }
            if let bullet = Self.bullet(in: line) {
                flushParagraph()
                blocks.append(.bullet(bullet))
                bulletOpen = true
                return
            }
            if appendToOpenBullet(raw: raw, line: line) { return }
            bulletOpen = false
            guard !Self.isRequirementLine(line) else { return }
            paragraph.append(line)
        }

        mutating func finish() -> [Block] {
            flushParagraph()
            return blocks
        }

        private mutating func consume(heading: (level: Int, text: String)) {
            flushParagraph()
            bulletOpen = false
            if heading.level <= 2, Self.isInstallHeading(heading.text) {
                skippingInstall = true
                return
            }
            if skippingInstall {
                guard heading.level <= 2 else { return }
                skippingInstall = false
            }
            guard !heading.text.isEmpty else { return }
            blocks.append(.heading(level: heading.level, text: heading.text))
        }

        private mutating func appendToOpenBullet(raw: String, line: String) -> Bool {
            guard bulletOpen, raw.first?.isWhitespace == true,
                case let .bullet(text)? = blocks.last
            else { return false }
            blocks[blocks.count - 1] = .bullet(text + " " + line)
            return true
        }

        private mutating func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph = []
        }

        /// ATX only: the `#` run must be followed by a space or end of line.
        private static func heading(in line: String) -> (level: Int, text: String)? {
            guard line.hasPrefix("#") else { return nil }
            let hashes = line.prefix(while: { $0 == "#" }).count
            let rest = line.dropFirst(hashes)
            guard rest.isEmpty || rest.first == " " else { return nil }
            return (hashes, String(rest).trimmingCharacters(in: .whitespaces))
        }

        /// Prefix, not equality: real headings read `Install (unsigned app)`, `Installation`.
        private static func isInstallHeading(_ text: String) -> Bool {
            text.range(of: "install", options: [.caseInsensitive, .anchored]) != nil
        }

        /// Emphasis wraps the whole line in some releases and only the version in others.
        private static func isRequirementLine(_ line: String) -> Bool {
            let plain = line
                .replacingOccurrences(of: "*", with: "")
                .replacingOccurrences(of: "_", with: "")
                .trimmingCharacters(in: .whitespaces)
            return plain.range(of: "requires macos", options: [.caseInsensitive, .anchored]) != nil
        }

        private static func isThematicBreak(_ line: String) -> Bool {
            let marks = line.filter { !$0.isWhitespace }
            guard marks.count >= 3, let first = marks.first,
                first == "-" || first == "*" || first == "_"
            else { return false }
            return marks.allSatisfy { $0 == first }
        }

        private static func bullet(in line: String) -> String? {
            guard line.hasPrefix("- ") || line.hasPrefix("* ") else { return nil }
            return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
    }
}
