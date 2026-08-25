import AVFoundation
import Observation

@MainActor
@Observable
final class PreviewPlayer {
    private let player: AVPlayer
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var rate: Float = 1
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
            Task { @MainActor [weak self] in self?.isPlaying = false }
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

    private func play() {
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
