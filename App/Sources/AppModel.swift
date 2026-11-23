import Foundation
import ExtractrKit
import Observation

@MainActor
@Observable
final class AppModel {
    enum Stage: Equatable {
        case input
        case probing
        case downloading(Double?)
        case edit
        case extracting(Double?)
        case done(URL)
    }

    static let waveformBucketCount = 300

    private(set) var stage: Stage = .input
    var urlText = ""
    var startText = ""
    var endText = ""
    var speed = 1.0 {
        didSet { player?.setRate(speed) }
    }
    var saveTranscript = false
    var transcriptLocaleIdentifier = ""
    var fileName = ""
    private(set) var probe: MediaProbe?
    private(set) var displayTitle = ""
    private(set) var probingIsRemote = false
    private(set) var selection: TrimSelection? {
        didSet { player?.setRange(selection) }
    }
    private(set) var peaks: [Float]?
    private(set) var peaksUnavailable = false
    private(set) var player: PreviewPlayer?
    private(set) var errorMessage: String?
    private(set) var errorDetail: String?
    private(set) var transcriptFailure: String?
    private(set) var transcriptFailureDetail: String?
    private(set) var transcribing = false
    private(set) var saving = false
    private(set) var transcriptLocales: [Locale] = []

    let tools: ToolLocator
    private let probeService: ProbeService
    private let extractor: Extractor
    private let downloader: AudioDownloader
    private let peakExtractor: PeakExtractor
    private let previewTranscoder: PreviewTranscoder
    private let shareResolver = FacebookShareResolver()
    private let transcriber = Transcriber()
    private var sourceFile: URL?
    private var jobDir: URL?
    private var extractionTask: Task<Void, Never>?
    private var prepareTask: Task<Void, Never>?
    private var peaksTask: Task<Void, Never>?
    private var playerTask: Task<Void, Never>?
    /// Bumped whenever a job or extraction is superseded, so late results from it are dropped.
    private var generation = 0

    init() {
        let bundledBin =
            Bundle.main.resourceURL?.appendingPathComponent("bin", isDirectory: true)
            ?? URL(fileURLWithPath: "/nonexistent")
        tools = ToolLocator(bundledBinDir: bundledBin, updatedBinDir: AppPaths.binDir())
        probeService = ProbeService(tools: tools)
        extractor = Extractor(tools: tools)
        downloader = AudioDownloader(tools: tools)
        peakExtractor = PeakExtractor(tools: tools)
        previewTranscoder = PreviewTranscoder(tools: tools)
        // Sweep scratch from crashed/quit sessions; jobs recreate it on demand.
        try? FileManager.default.removeItem(at: AppPaths.scratchRoot())
    }

    func submitURL() {
        clearError()
        do {
            let url = try URLPolicy.validated(urlText)
            begin(.remote(url))
        } catch {
            present(error)
        }
    }

    func pickFile(_ url: URL) {
        clearError()
        if let problem = Self.problem(opening: url) {
            errorMessage = problem
            errorDetail = nil
            return
        }
        begin(.localFile(url))
    }

    private static let startTimeFormat = "Start time should look like 1:23 or 0:01:23."
    private static let endTimeFormat = "End time should look like 1:23 or 0:01:23."

    /// Sets `errorMessage` and returns nil when the fields do not parse.
    private func parsedTrim() -> TrimRange? {
        let startTrimmed = startText.trimmingCharacters(in: .whitespaces)
        let start = TimeCode.seconds(from: startTrimmed)
        if !startTrimmed.isEmpty && start == nil {
            errorMessage = Self.startTimeFormat
            return nil
        }
        let endTrimmed = endText.trimmingCharacters(in: .whitespaces)
        let end = TimeCode.seconds(from: endTrimmed)
        if !endTrimmed.isEmpty && end == nil {
            errorMessage = Self.endTimeFormat
            return nil
        }
        let trim = TrimRange(start: start.map(Double.init), end: end.map(Double.init))
        do {
            try trim.validate(mediaDuration: probe?.duration)
        } catch {
            present(error)
            return nil
        }
        return trim
    }

    func extract() {
        guard let sourceFile, let jobDir, stage == .edit else { return }
        clearError()
        dismissTranscriptFailure()
        applyStartText()
        applyEndText()
        guard errorMessage == nil else { return }
        guard let trim = resolvedTrim() else { return }
        player?.pause()
        stage = .extracting(nil)
        generation += 1
        let id = generation
        let plan = ExtractionPlan(sourceFile: sourceFile, trim: trim, speed: speed, jobDir: jobDir)
        let duration = probe?.duration
        let folder = Preferences().saveFolder
        let base = FilenameSanitizer.sanitize(fileName)
        extractionTask = Task {
            await runExtraction(plan, duration: duration, saveAs: base, in: folder, id: id)
        }
    }

    /// No validate() on the selection branch: TrimSelection clamps to [0, duration] and keeps
    /// the handles apart, so the bounds are unrepresentable rather than merely unvalidated.
    /// Running it here would only add TrimRange.maxSeconds, which would refuse media longer
    /// than a week that the selection had already bounded correctly.
    private func resolvedTrim() -> TrimRange? {
        if let selection { return selection.trimRange }
        return parsedTrim()
    }

    func cancel() {
        extractionTask?.cancel()
    }

    func cancelPreparation() {
        switch stage {
        case .probing, .downloading: break
        default: return
        }
        prepareTask?.cancel()
        prepareTask = nil
        cleanupJob()
        stage = .input
    }

    func reset() {
        extractionTask?.cancel()
        extractionTask = nil
        prepareTask?.cancel()
        prepareTask = nil
        cleanupJob()
        stage = .input
        probe = nil
        displayTitle = ""
        fileName = ""
        urlText = ""
        startText = ""
        endText = ""
        speed = 1.0
        saveTranscript = false
        transcriptLocaleIdentifier = ""
        transcribing = false
        saving = false
        selection = nil
        clearError()
        dismissTranscriptFailure()
    }

    private func cleanupJob() {
        generation += 1
        peaksTask?.cancel()
        peaksTask = nil
        playerTask?.cancel()
        playerTask = nil
        player?.teardown()
        player = nil
        peaks = nil
        peaksUnavailable = false
        sourceFile = nil
        if let jobDir { try? FileManager.default.removeItem(at: jobDir) }
        jobDir = nil
    }

    private static let dropFailure =
        "That item couldn't be read as a file. Try dropping a file from Finder."

    func presentDropFailure(_ error: Error? = nil) {
        errorMessage = Self.dropFailure
        errorDetail = error?.localizedDescription
    }

    private func present(_ error: Error) {
        errorMessage = error.userFacingMessage
        errorDetail = error.userFacingDetail
    }

    private func clearError() {
        errorMessage = nil
        errorDetail = nil
    }

    func dismissTranscriptFailure() {
        transcriptFailure = nil
        transcriptFailureDetail = nil
    }
}

extension AppModel {
    private func begin(_ newInput: MediaInput) {
        prepareTask?.cancel()
        cleanupJob()
        probingIsRemote = newInput.isRemote
        stage = .probing
        prepareTask = Task {
            do {
                var input = newInput
                if case let .remote(url) = newInput {
                    let resolved = try await shareResolver.resolve(url)
                    try Task.checkCancellation()
                    input = .remote(try URLPolicy.validated(resolved.absoluteString))
                }
                let result = try await probeService.probe(input)
                try Task.checkCancellation()
                probe = result
                displayTitle = result.title ?? fallbackTitle(for: input)
                fileName = FilenameSanitizer.sanitize(displayTitle)
                try await prepareSource(input)
            } catch is CancellationError {
                // Superseded or cancelled; state already reset by the canceller.
            } catch {
                guard !Task.isCancelled else { return }
                cleanupJob()
                stage = .input
                present(error)
            }
        }
    }

    private func prepareSource(_ newInput: MediaInput) async throws {
        try Task.checkCancellation()
        let dir = try AppPaths.newJobDir()
        jobDir = dir
        switch newInput {
        case let .localFile(url):
            sourceFile = url
        case let .remote(url):
            stage = .downloading(nil)
            let id = generation
            let downloaded = try await downloader.download(url, into: dir) { [weak self] fraction in
                Task { @MainActor in
                    guard let self, self.generation == id, case .downloading = self.stage
                    else { return }
                    self.stage = .downloading(fraction)
                }
            }
            try Task.checkCancellation()
            sourceFile = downloaded
            if probe?.duration == nil,
                let local = try? await probeService.probe(.localFile(downloaded)),
                let duration = local.duration
            {
                // try? also swallows CancellationError, so a cancelled prepare could
                // otherwise write this job's duration over a newer job's probe.
                try Task.checkCancellation()
                probe = MediaProbe(title: probe?.title, duration: duration)
            }
        }
        try Task.checkCancellation()
        enterEdit()
    }

    private func enterEdit() {
        selection = probe?.duration.map(TrimSelection.init)
        startText = ""
        endText = ""
        stage = .edit
        loadPeaks()
        loadPlayer()
    }

    private func loadPeaks() {
        guard let sourceFile, let jobDir else { return }
        peaks = nil
        peaksUnavailable = false
        peaksTask = Task { [peakExtractor] in
            let result = try? await peakExtractor.peaks(
                for: sourceFile, count: Self.waveformBucketCount, jobDir: jobDir)
            guard !Task.isCancelled else { return }
            peaks = result
            peaksUnavailable = result == nil
        }
    }

    private func loadPlayer() {
        guard let sourceFile, let jobDir else { return }
        playerTask = Task { [previewTranscoder] in
            let made = await PreviewPlayer.make(for: sourceFile) {
                try Task.checkCancellation()
                return try await previewTranscoder.transcode(sourceFile, jobDir: jobDir)
            }
            guard !Task.isCancelled else { made?.teardown(); return }
            made?.setRate(speed)
            made?.setRange(selection)
            player = made
        }
    }

    private func fallbackTitle(for input: MediaInput) -> String {
        if case let .localFile(url) = input { return url.deletingPathExtension().lastPathComponent }
        return "audio"
    }
}

extension AppModel {
    func moveStart(to time: Double) {
        guard var current = selection else { return }
        current.moveStart(to: time)
        selection = current
        syncTextFromSelection()
    }

    func moveEnd(to time: Double) {
        guard var current = selection else { return }
        current.moveEnd(to: time)
        selection = current
        syncTextFromSelection()
    }

    func scrub(to time: Double) {
        player?.seek(to: time)
    }

    func applyStartText() {
        guard let current = selection else { return }
        apply(
            startText, current: current.start, whenEmpty: 0, message: Self.startTimeFormat,
            move: moveStart)
    }

    func applyEndText() {
        guard let current = selection else { return }
        apply(
            endText, current: current.end, whenEmpty: current.duration,
            message: Self.endTimeFormat, move: moveEnd)
    }

    private func apply(
        _ text: String, current: Double, whenEmpty: Double, message: String,
        move: (Double) -> Void
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            move(whenEmpty)
        } else if let seconds = TimeCode.seconds(from: trimmed, keeping: current) {
            move(seconds)
        } else {
            errorMessage = message
            errorDetail = nil
            syncTextFromSelection()
        }
    }

    private func syncTextFromSelection() {
        guard let selection else { return }
        startText = selection.start > 0 ? TimeCode.text(from: selection.start) : ""
        endText = selection.end < selection.duration ? TimeCode.text(from: selection.end) : ""
    }
}

private struct SaveFailure: Error {
    let underlying: Error
}

extension AppModel {
    private static func problem(opening url: URL) -> String? {
        guard url.isFileURL else { return dropFailure }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return dropFailure
        }
        if isDirectory.boolValue { return "That's a folder. Choose an audio or video file instead." }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            return "That file couldn't be opened. Check that you have permission to read it."
        }
        return nil
    }

    private func runExtraction(
        _ plan: ExtractionPlan, duration: Double?, saveAs base: String, in folder: URL, id: Int
    ) async {
        defer {
            if generation == id {
                extractionTask = nil
                saving = false
            }
        }
        do {
            let saved = try await convertAndSave(
                plan, duration: duration, as: base, in: folder, id: id)
            if saveTranscript {
                transcribing = true
                await runTranscription(mp3: saved, plan: plan)
                guard generation == id else { return }
                transcribing = false
            }
            extractionTask = nil
            stage = .done(saved)
            cleanupJob()
        } catch {
            guard generation == id else { return }
            if case .extracting = stage { stage = .edit }
            if let failure = error as? SaveFailure {
                errorMessage = "Couldn't save to your chosen folder. Pick another in Settings."
                errorDetail = failure.underlying.localizedDescription
            } else if !(error is CancellationError), !Task.isCancelled {
                present(error)
            }
        }
    }

    private func convertAndSave(
        _ plan: ExtractionPlan, duration: Double?, as base: String, in folder: URL, id: Int
    ) async throws -> URL {
        let tempMP3 = try await extractor.extract(
            plan: plan, expectedDuration: duration
        ) { [weak self] fraction in
            Task { @MainActor in
                guard let self, self.generation == id, case .extracting = self.stage
                else { return }
                self.stage = .extracting(fraction)
            }
        }
        try Task.checkCancellation()
        saving = true
        let saved: URL
        do {
            saved = try await Self.save(tempMP3, as: base, in: folder)
        } catch {
            throw SaveFailure(underlying: error)
        }
        guard !Task.isCancelled, generation == id else {
            try? FileManager.default.removeItem(at: saved)
            throw CancellationError()
        }
        saving = false
        return saved
    }

    /// Off the main actor: a move to another volume is a full copy, which can take minutes.
    private nonisolated static func save(_ file: URL, as base: String, in folder: URL)
        async throws -> URL
    {
        try await Task.detached(priority: .userInitiated) {
            let manager = FileManager.default
            try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = OutputName.available(base: base, ext: "mp3", in: folder) {
                manager.fileExists(atPath: $0.path)
            }
            try manager.moveItem(at: file, to: destination)
            return destination
        }.value
    }
}

extension AppModel {
    private func runTranscription(mp3: URL, plan: ExtractionPlan) async {
        do {
            let audio = try await transcriptionAudio(mp3: mp3, plan: plan)
            let locale = resolvedTranscriptLocale()
            var transcript = try await transcriber.transcribe(file: audio, locale: locale)

            if case let .retry(languageCode) = TranscriptLocale.verdict(
                assumedLanguageCode: locale.language.languageCode?.identifier ?? "",
                detectedLanguageCode: Transcriber.detectLanguageCode(in: transcript))
            {
                try Task.checkCancellation()
                let retryLocale = Locale(identifier: languageCode)
                if let better = try? await transcriber.transcribe(file: audio, locale: retryLocale),
                    better.wordCount > transcript.wordCount
                {
                    transcript = better
                }
            }

            try Task.checkCancellation()
            try write(transcript, beside: mp3)
        } catch is CancellationError {
            // A cancelled job leaves no transcript and raises no alert.
        } catch {
            guard !Task.isCancelled else { return }
            transcriptFailure = error.userFacingMessage
            transcriptFailureDetail = error.userFacingDetail
        }
    }

    /// Transcribe 1.0x audio: the atempo filter distorts speech and costs accuracy.
    private func transcriptionAudio(mp3: URL, plan: ExtractionPlan) async throws -> URL {
        guard plan.speed != 1 else { return mp3 }
        let dir = plan.jobDir.appendingPathComponent("transcribe", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let normal = ExtractionPlan(sourceFile: plan.sourceFile, trim: plan.trim, speed: 1, jobDir: dir)
        return try await extractor.extract(plan: normal, expectedDuration: probe?.duration) { _ in }
    }

    private func resolvedTranscriptLocale() -> Locale {
        transcriptLocaleIdentifier.isEmpty
            ? Locale.current : Locale(identifier: transcriptLocaleIdentifier)
    }

    func loadTranscriptLocales() async {
        guard transcriptLocales.isEmpty else { return }
        transcriptLocales = await Transcriber.supportedLocales()
            .sorted { Self.displayName($0) < Self.displayName($1) }
    }

    static func displayName(_ locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    private func write(_ transcript: Transcript, beside mp3: URL) throws {
        let format = Preferences().transcriptFormat
        let base = mp3.deletingPathExtension().lastPathComponent
        let destination = OutputName.available(
            base: base, ext: format.fileExtension, in: mp3.deletingLastPathComponent()
        ) { FileManager.default.fileExists(atPath: $0.path) }
        let body = TranscriptWriter.render(transcript, as: format, title: base)
        try body.write(to: destination, atomically: true, encoding: .utf8)
    }
}
