import ExtractrKit
import Foundation

extension Error {
    // User-facing message for error surfaces; never leaks raw enum/case names.
    var userFacingMessage: String {
        if let e = self as? URLPolicyError {
            switch e {
            case .empty:
                return "Paste a link first."
            case .tooLong:
                return "That link is too long."
            case .invalid:
                return "That doesn't look like a complete web address. Include the full URL, like https://example.com/watch."
            case .insecureScheme:
                return "Only https:// links are supported."
            case .blockedHost:
                return "Local and private-network addresses aren't supported."
            }
        }
        if let e = self as? TrimRange.ValidationError {
            switch e {
            case .startAfterEnd:
                return "The start time needs to be before the end time."
            case .exceedsDuration:
                return "The trim times are past the end of the media."
            case .tooLong:
                return "That trim range is longer than a week — check the times."
            }
        }
        if let e = self as? ExtractorError {
            switch e {
            case .probeFailed:
                return "This link or file isn't supported or couldn't be read."
            case .downloadFailed:
                return "The download failed. Check the link and your connection, then try again."
            case .conversionFailed:
                return "Converting to MP3 failed."
            case .outputMissing:
                return "Converting finished but no MP3 was produced. Please try again."
            }
        }
        return "Something went wrong. Please try again."
    }

    var userFacingDetail: String? {
        (self as? ExtractorError)?.detail
    }
}
