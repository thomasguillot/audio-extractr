import AVFoundation
import ExtractrKit
import Observation

@MainActor
@Observable
final class PreviewPlayer {
    private let player: AVPlayer
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var rate: Float = 1
    private var range: TrimSelection?
    private(set) var isPlaying = false
    private(set) var playheadTime: Double = 0

    /// Plays the source directly when AVFoundation can read it; otherwise
    /// falls back to `transcode` (m4a preview copy). Nil when both fail.
    static func make(
        for file: URL, transcode: () async throws -> URL
    ) async -> PreviewPlayer? {
        let asset = AVURLAsset(url: file)
        if (try? await asset.load(.isPlayable)) == true {
            return PreviewPlayer(url: file)
        }
        guard let preview = try? await transcode() else { return nil }
        return PreviewPlayer(url: preview)
    }

    private init(url: URL) {
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .spectral
        player = AVPlayer(playerItem: item)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                if time.seconds.isFinite { self?.playheadTime = time.seconds }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isPlaying = false
                self?.rewind()
            }
        }
    }

    func toggle() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    /// A non-zero `player.rate` also starts playback, so only push it while already playing.
    func setRate(_ newRate: Double) {
        rate = Float(newRate)
        if isPlaying { player.rate = rate }
    }

    /// The preview is of the selection, so playback stops at its end rather than the
    /// file's. forwardPlaybackEndTime posts didPlayToEndTime there, which is what rewinds.
    func setRange(_ range: TrimSelection?) {
        self.range = range
        guard let range, let item = player.currentItem else { return }
        item.forwardPlaybackEndTime = CMTime(seconds: range.end, preferredTimescale: 600)
    }

    /// The playhead is drawn at its fraction of the strip, so leaving it on the end parks
    /// it under the right edge and it reads as having vanished.
    private func rewind() {
        let start = range?.start ?? 0
        player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
        playheadTime = start
    }

    /// Playback can go no further: the end of the selection, or of the file without one.
    private var isAtEnd: Bool {
        if let range { return player.currentTime().seconds >= range.end }
        guard let item = player.currentItem, item.duration.isNumeric else { return false }
        return player.currentTime() >= item.duration
    }

    private func play() {
        // Also reached by scrubbing to the very end: AVPlayer will not restart from there
        // on rate alone, so this would otherwise set isPlaying with nothing happening.
        if isAtEnd { rewind() }
        player.rate = rate
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func seek(to seconds: Double) {
        playheadTime = seconds
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func teardown() {
        pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }
}
