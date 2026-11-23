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
        if self as? FacebookShareError == .loginRequired {
            return "Facebook wants you to sign in before it opens this link. Open it in your browser and paste the video page's address instead."
        }
        if let e = self as? ExtractorError {
            switch FacebookFailure.classify(e.detail ?? "") {
            case .loginRequired:
                return "Facebook wants you to sign in to see this video. Audio Extractr only works with public videos."
            case .unreadable:
                return "Facebook didn't share this video. It may be private or removed. If it plays in your browser without signing in, try again later."
            case nil:
                break
            }
            switch e {
            case .probeFailed:
                return "This link or file isn't supported or couldn't be read."
            case .downloadFailed:
                return "The download failed. Check the link and your connection, then try again."
            case .conversionFailed:
                return "Converting to MP3 failed."
            case .outputMissing:
                return "Converting finished but no MP3 was produced. Please try again."
            case .liveStream:
                return "Live streams can't be saved. Try again once the stream has ended."
            case .playlist:
                return "This link is a playlist. Paste a link to a single video or track instead."
            }
        }
        if let e = self as? TranscriptionError {
            switch e {
            case .localeUnsupported:
                return "Transcription doesn't support this language yet. The MP3 was still saved."
            case .modelUnavailable:
                return "The transcript couldn't be created. If the language model still needs downloading, check your connection and try again. The MP3 was still saved."
            case .audioUnreadable:
                return "The audio couldn't be read for transcription. The MP3 was still saved."
            case .emptyTranscript:
                return "No speech was found in this audio, so no transcript was written. The MP3 was still saved."
            }
        }
        return "Something went wrong. Please try again."
    }

    var userFacingDetail: String? {
        if let e = self as? TranscriptionError { return e.detail }
        return (self as? ExtractorError)?.detail
    }
}
