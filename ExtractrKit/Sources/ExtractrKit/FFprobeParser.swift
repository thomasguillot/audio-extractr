import Foundation

/// Reads the JSON `FFprobeCommand.arguments` asks for. A duration that is missing, mistyped
/// or out of range reads as absent.
public enum FFprobeParser {
    private struct Output: Decodable {
        let format: Format?
    }

    private struct Format: Decodable {
        let formatName: String?
        let duration: String?

        enum CodingKeys: String, CodingKey {
            case formatName = "format_name", duration
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            formatName = (try? container.decodeIfPresent(String.self, forKey: .formatName)) ?? nil
            duration = (try? container.decodeIfPresent(String.self, forKey: .duration)) ?? nil
        }
    }

    /// Nil when the output is not ffprobe's JSON, or names a demuxer outside
    /// `FFmpegCommand.allowedDemuxers`.
    public static func parse(_ data: Data, title: String?) -> MediaProbe? {
        guard let output = try? JSONDecoder().decode(Output.self, from: data),
            let format = output.format, isAllowed(format.formatName)
        else { return nil }
        return MediaProbe(title: title, duration: seconds(format.duration))
    }

    private static func isAllowed(_ formatName: String?) -> Bool {
        guard let formatName else { return false }
        return !Set(formatName.split(separator: ",").map(String.init))
            .isDisjoint(with: FFmpegCommand.allowedDemuxers)
    }

    private static func seconds(_ text: String?) -> Double? {
        guard let text, text.wholeMatch(of: /\d+(?:\.\d+)?/) != nil, let value = Double(text)
        else { return nil }
        return MediaDuration.bounded(value)
    }
}
