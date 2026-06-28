//
//  DictationEngine.swift
//  Vvox
//
//  Wraps SpeechAnalyzer + DictationTranscriber and exposes its full lifecycle
//  (asset install -> mic capture -> live transcription -> finalize) to SwiftUI.
//

import AVFoundation
import CoreMedia
import Foundation
import Speech
import SwiftUI

@MainActor
@Observable
final class DictationEngine {

    // MARK: Public state

    enum LifecycleState: Equatable {
        case idle
        case requestingPermission
        case preparingAssets
        case downloading
        case ready
        case listening
        case stopping
        case error(String)

        var label: String {
            switch self {
            case .idle: return "Idle"
            case .requestingPermission: return "Requesting microphone permission…"
            case .preparingAssets: return "Checking speech assets…"
            case .downloading: return "Downloading speech model…"
            case .ready: return "Ready"
            case .listening: return "Listening"
            case .stopping: return "Stopping…"
            case .error(let msg): return "Error: \(msg)"
            }
        }

        var isBusy: Bool {
            switch self {
            case .listening, .stopping, .requestingPermission, .preparingAssets, .downloading:
                return true
            case .idle, .ready, .error:
                return false
            }
        }
    }

    struct ResultEvent: Identifiable, Hashable {
        let id = UUID()
        let timestamp: Date
        let isFinal: Bool
        let text: AttributedString
        let alternatives: [AttributedString]
        let rangeStart: Double?
        let rangeEnd: Double?
        let resultsFinalizationTime: Double?
        let averageConfidence: Float?
    }

    var settings = DictationSettings() {
        didSet { settingsChanged(from: oldValue) }
    }

    var state: LifecycleState = .idle

    var installedLocalesDictation: [Locale] = []
    var supportedLocalesDictation: [Locale] = []
    var installedLocalesSpeech: [Locale] = []
    var supportedLocalesSpeech: [Locale] = []
    var localesLoaded = false

    // Engine-aware computed views for the UI.
    var installedLocales: [Locale] {
        settings.engineType == .speech ? installedLocalesSpeech : installedLocalesDictation
    }
    var supportedLocales: [Locale] {
        settings.engineType == .speech ? supportedLocalesSpeech : supportedLocalesDictation
    }

    // The most recent finalized text accumulated since session start.
    var committedText: AttributedString = AttributedString("")
    // The current volatile (tentative) tail.
    var volatileText: AttributedString = AttributedString("")
    // From SpeechAnalyzer.volatileRange (mirrored via the change handler).
    var volatileRangeStart: Double?
    var volatileRangeEnd: Double?

    // Every result the transcriber emits, newest first.
    var resultLog: [ResultEvent] = []

    // Latest non-fatal status message (e.g. asset download progress).
    var statusMessage: String?

    // Vocabulary context store. Set after init by ContentView.
    var vocabStore: VocabContextStore?

    // MARK: Volatile-dwell-time instrumentation

    // Wall-clock when audio at a given range.start was first observed in a
    // volatile result. Cleared when the same range.start is finalized.
    private var volatileFirstSeen: [CMTime: Date] = [:]

    // Captured dwell durations (seconds). Capped at 500 entries; oldest dropped.
    var dwellSamples: [TimeInterval] = []

    // MARK: Internal

    private var audioEngine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var converterTargetFormat: AVAudioFormat?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzer: SpeechAnalyzer?

    // Wraps whichever transcriber type is active for this session.
    private enum ActiveTranscriber {
        case dictation(DictationTranscriber)
        case speech(SpeechTranscriber)
        var asModule: any SpeechModule {
            switch self {
            case .dictation(let t): return t
            case .speech(let t): return t
            }
        }
    }
    private var activeTranscriber: ActiveTranscriber?

    private var resultsTask: Task<Void, Never>?
    private var analyzeTask: Task<Void, Never>?
    private var autoFinalizeTask: Task<Void, Never>?

    // Latest sample time the audio tap has yielded, used by the auto-finalize
    // task to compute a cutoff. Mutated from the audio tap thread; only read
    // inside MainActor-isolated code paths (and we accept the tiny race —
    // worst case we finalize a few ms behind reality).
    @ObservationIgnored
    nonisolated(unsafe) private var latestAudioTime: CMTime?

    init() {}

    // MARK: Locale discovery

    func loadLocales() async {
        async let dictInstalled = DictationTranscriber.installedLocales
        async let dictSupported = DictationTranscriber.supportedLocales
        async let speechInstalled = SpeechTranscriber.installedLocales
        async let speechSupported = SpeechTranscriber.supportedLocales

        installedLocalesDictation = await dictInstalled.sorted { $0.identifier < $1.identifier }
        supportedLocalesDictation = await dictSupported.sorted { $0.identifier < $1.identifier }
        installedLocalesSpeech = await speechInstalled.sorted { $0.identifier < $1.identifier }
        supportedLocalesSpeech = await speechSupported.sorted { $0.identifier < $1.identifier }
        localesLoaded = true

        // Default the locale to one supported by the currently selected engine.
        let supported = settings.engineType == .speech ? supportedLocalesSpeech : supportedLocalesDictation
        let installed = settings.engineType == .speech ? installedLocalesSpeech : installedLocalesDictation
        if !supported.contains(where: { $0.identifier == settings.localeIdentifier }) {
            let match: Locale? = settings.engineType == .speech
                ? await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
                : await DictationTranscriber.supportedLocale(equivalentTo: Locale.current)
            if let match {
                settings.localeIdentifier = match.identifier(.bcp47)
            } else if let first = installed.first ?? supported.first {
                settings.localeIdentifier = first.identifier(.bcp47)
            }
        }
    }

    // MARK: Lifecycle

    func startListening() async {
        guard state != .listening else { return }
        await stopListening()
        committedText = AttributedString("")
        volatileText = AttributedString("")
        volatileRangeStart = nil
        volatileRangeEnd = nil
        resultLog.removeAll()
        statusMessage = nil
        latestAudioTime = nil
        volatileFirstSeen.removeAll()

        do {
            state = .requestingPermission
            try await ensureMicrophonePermission()

            state = .preparingAssets
            let active = makeActiveTranscriber()
            self.activeTranscriber = active

            try await installAssetsIfNeeded(for: [active.asModule])

            try await beginSession(active: active)
            state = .listening
        } catch {
            state = .error(error.localizedDescription)
            await cleanup()
        }
    }

    func stopListening() async {
        guard analyzer != nil || audioEngine != nil else {
            state = .idle
            return
        }
        state = .stopping

        // Stop pulling audio from the mic first.
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil

        // End the input stream so the analyzer knows no more audio is coming.
        inputContinuation?.finish()
        inputContinuation = nil

        // Drain the analyzer.
        if let analyzer {
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                // Analysis may already have been cancelled; ignore.
            }
        }

        await cleanup()
        state = .idle
    }

    func clearTranscript() {
        committedText = AttributedString("")
        volatileText = AttributedString("")
        resultLog.removeAll()
    }

    // MARK: Session building

    private func makeActiveTranscriber() -> ActiveTranscriber {
        switch settings.engineType {
        case .dictation:
            if let preset = settings.presetChoice.preset {
                return .dictation(DictationTranscriber(locale: settings.locale, preset: preset))
            }
            return .dictation(DictationTranscriber(
                locale: settings.locale,
                contentHints: settings.contentHints,
                transcriptionOptions: settings.transcriptionOptions,
                reportingOptions: settings.reportingOptions,
                attributeOptions: settings.attributeOptions
            ))
        case .speech:
            if let preset = settings.speechPresetChoice.preset {
                return .speech(SpeechTranscriber(locale: settings.locale, preset: preset))
            }
            return .speech(SpeechTranscriber(
                locale: settings.locale,
                transcriptionOptions: settings.speechTranscriptionOptions,
                reportingOptions: settings.speechReportingOptions,
                attributeOptions: settings.speechAttributeOptions
            ))
        }
    }

    private func installAssetsIfNeeded(for modules: [any SpeechModule]) async throws {
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                state = .downloading
                statusMessage = "Downloading speech model for \(settings.localeIdentifier)…"
                try await request.downloadAndInstall()
                statusMessage = "Speech model installed."
            } else {
                statusMessage = "Speech model already installed."
            }
        } catch {
            throw error
        }
    }

    private func beginSession(active: ActiveTranscriber) async throws {
        let module: any SpeechModule = active.asModule

        // 1. Mic
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        guard nativeFormat.sampleRate > 0 else {
            throw NSError(domain: "Vvox", code: -1, userInfo: [NSLocalizedDescriptionKey: "Microphone is not available."])
        }

        // 2. Best format the analyzer can take
        let bestFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [module],
            considering: nativeFormat
        ) ?? nativeFormat

        let needsConversion = !bestFormat.isEqual(nativeFormat)
        if needsConversion {
            converter = AVAudioConverter(from: nativeFormat, to: bestFormat)
            converterTargetFormat = bestFormat
        } else {
            converter = nil
            converterTargetFormat = nativeFormat
        }

        // 3. Input async sequence for the analyzer
        let (inputSequence, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.inputContinuation = continuation

        // 4. Analysis context (contextual strings)
        let context = AnalysisContext()
        let editorWords = settings.contextualStrings
        let vocabWords = vocabStore?.context(for: settings.activeContextID)?.words ?? []
        var seen = Set<String>()
        var merged: [String] = []
        for word in editorWords + vocabWords {
            if seen.insert(word).inserted {
                merged.append(word)
            }
        }
        if !merged.isEmpty {
            context.contextualStrings = [.general: merged]
        }

        // 5. Analyzer options
        let options = SpeechAnalyzer.Options(
            priority: settings.priority.taskPriority,
            modelRetention: settings.modelRetention.modelRetention
        )

        // 6. Volatile-range change handler — drives the live UI's "volatile vs. committed" boundary
        let volatileHandler: @Sendable (CMTimeRange, Bool, Bool) -> Void = { [weak self] range, _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.volatileRangeStart = range.start.seconds
                self.volatileRangeEnd = range.end.seconds
            }
        }

        let analyzer = SpeechAnalyzer(
            inputSequence: inputSequence,
            modules: [module],
            options: options,
            analysisContext: context,
            volatileRangeChangedHandler: volatileHandler
        )
        self.analyzer = analyzer

        // 7. (Optional) Preheat
        if settings.preheat {
            try? await analyzer.prepareToAnalyze(in: converterTargetFormat)
        }

        // 8. Start consuming results — branch on the active transcriber type.
        resultsTask = Task { [weak self, active] in
            switch active {
            case .dictation(let t): await self?.consumeDictationResults(from: t)
            case .speech(let t):    await self?.consumeSpeechResults(from: t)
            }
        }

        // 9. Install tap on the microphone
        let captureFormat = nativeFormat
        let targetFormat = converterTargetFormat ?? nativeFormat
        let converter = self.converter
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: captureFormat) { [continuation, weak self] buffer, when in
            let inputBuffer: AVAudioPCMBuffer
            if let converter, !targetFormat.isEqual(captureFormat) {
                let ratio = targetFormat.sampleRate / captureFormat.sampleRate
                let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 512)
                guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
                    return
                }
                var consumed = false
                var error: NSError?
                converter.convert(to: convertedBuffer, error: &error) { _, status in
                    if consumed {
                        status.pointee = .noDataNow
                        return nil
                    }
                    consumed = true
                    status.pointee = .haveData
                    return buffer
                }
                if error != nil { return }
                inputBuffer = convertedBuffer
            } else {
                inputBuffer = buffer
            }

            // Don't pass bufferStartTime — the converted buffer's time-base differs
            // from the capture clock, and the analyzer treats each buffer as
            // immediately following the previous one, which is what we want for
            // a continuous live-mic stream.
            _ = targetFormat

            // Track the latest audio time we've yielded (capture-clock based).
            // Used ONLY by the auto-finalize task to compute a cutoff. Do NOT
            // pass this to AnalyzerInput — the analyzer treats successive
            // buffers as contiguous and synthesizes its own timeline.
            if when.sampleRate > 0 {
                self?.latestAudioTime = CMTime(
                    value: when.sampleTime,
                    timescale: CMTimeScale(when.sampleRate)
                )
            }

            continuation.yield(AnalyzerInput(buffer: inputBuffer))
        }

        try engine.start()
        self.audioEngine = engine

        // 10. Auto-finalize loop — gated by `settings.autoFinalizeEnabled`
        //     so the toggle can flip mid-session without a restart.
        autoFinalizeTask = Task { [weak self] in
            await self?.runAutoFinalizeLoop()
        }
    }

    private func runAutoFinalizeLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return }
            guard settings.autoFinalizeEnabled, state == .listening else { continue }
            guard let latest = latestAudioTime else { continue }
            let dwell = CMTime(
                seconds: settings.autoFinalizeSeconds,
                preferredTimescale: 600
            )
            let cutoff = latest - dwell
            guard cutoff.isValid, cutoff.seconds > 0 else { continue }
            try? await analyzer?.finalize(through: cutoff)
        }
    }

    /// Force the analyzer to commit everything it has consumed as final.
    /// Recording continues — this only affects pending volatile output.
    func finalizeNow() async {
        guard analyzer != nil else { return }
        try? await analyzer?.finalize(through: nil)
    }

    /// Reset the volatile-dwell-time stats. Safe to call at any time.
    func resetDwellStats() {
        dwellSamples.removeAll()
        volatileFirstSeen.removeAll()
    }

    // MARK: Dwell stats (computed)

    var dwellCount: Int { dwellSamples.count }

    var dwellMeanMs: Double? {
        guard !dwellSamples.isEmpty else { return nil }
        let sum = dwellSamples.reduce(0, +)
        return (sum / Double(dwellSamples.count)) * 1000
    }

    var dwellMedianMs: Double? { percentileMs(0.5) }
    var dwellP90Ms: Double? { percentileMs(0.9) }

    var dwellMaxMs: Double? {
        guard let m = dwellSamples.max() else { return nil }
        return m * 1000
    }

    private func percentileMs(_ p: Double) -> Double? {
        guard !dwellSamples.isEmpty else { return nil }
        let sorted = dwellSamples.sorted()
        let idx = max(0, min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded())))
        return sorted[idx] * 1000
    }

    private func consumeDictationResults(from transcriber: DictationTranscriber) async {
        do {
            for try await result in transcriber.results {
                let event = makeEvent(from: result)
                await MainActor.run { self.handle(event: event, result: result) }
            }
        } catch {
            await MainActor.run {
                self.state = .error("Result stream: \(error.localizedDescription)")
            }
        }
    }

    private func consumeSpeechResults(from transcriber: SpeechTranscriber) async {
        do {
            for try await result in transcriber.results {
                let event = makeEvent(from: result)
                await MainActor.run { self.handle(event: event, result: result) }
            }
        } catch {
            await MainActor.run {
                self.state = .error("Result stream: \(error.localizedDescription)")
            }
        }
    }

    private func handle<R: TranscribedResult>(event: ResultEvent, result: R) {
        resultLog.insert(event, at: 0)
        if resultLog.count > 200 {
            resultLog.removeLast(resultLog.count - 200)
        }

        // Dwell-time instrumentation: track how long each chunk of audio sits
        // in the volatile state before being finalized.
        let rangeStart = result.range.start
        if !result.isFinal {
            if volatileFirstSeen[rangeStart] == nil {
                volatileFirstSeen[rangeStart] = Date()
            }
        } else {
            if let firstSeen = volatileFirstSeen.removeValue(forKey: rangeStart) {
                let dwell = Date().timeIntervalSince(firstSeen)
                dwellSamples.append(dwell)
                if dwellSamples.count > 500 {
                    dwellSamples.removeFirst(dwellSamples.count - 500)
                }
            }
        }

        if result.isFinal {
            // Append to committed; clear volatile tail.
            if !committedText.characters.isEmpty {
                committedText += AttributedString(" ")
            }
            committedText += result.text
            volatileText = AttributedString("")
        } else {
            // Replace the volatile tail with the latest tentative text.
            volatileText = result.text
        }
    }

    private func makeEvent<R: TranscribedResult>(from result: R) -> ResultEvent {
        let range = result.range
        let start = range.start.isValid ? range.start.seconds : nil
        let end = range.end.isValid ? range.end.seconds : nil
        let finalization = result.resultsFinalizationTime
        let finalizationSeconds = finalization.isValid ? finalization.seconds : nil

        var confidenceSum: Float = 0
        var confidenceCount: Int = 0
        for run in result.text.runs {
            if let confidence = run[AttributeScopes.SpeechAttributes.ConfidenceAttribute.self] {
                confidenceSum += Float(confidence)
                confidenceCount += 1
            }
        }
        let averageConfidence: Float? = confidenceCount > 0
            ? confidenceSum / Float(confidenceCount)
            : nil

        return ResultEvent(
            timestamp: Date(),
            isFinal: result.isFinal,
            text: result.text,
            alternatives: result.alternatives,
            rangeStart: start,
            rangeEnd: end,
            resultsFinalizationTime: finalizationSeconds,
            averageConfidence: averageConfidence
        )
    }

    // MARK: Helpers

    private func ensureMicrophonePermission() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                throw NSError(domain: "Vvox", code: 1, userInfo: [NSLocalizedDescriptionKey: "Microphone access denied."])
            }
        case .denied, .restricted:
            throw NSError(domain: "Vvox", code: 2, userInfo: [NSLocalizedDescriptionKey: "Microphone access denied. Enable it in System Settings → Privacy & Security → Microphone."])
        @unknown default:
            throw NSError(domain: "Vvox", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unknown microphone authorization state."])
        }
    }

    private func cleanup() async {
        resultsTask?.cancel()
        resultsTask = nil
        analyzeTask?.cancel()
        analyzeTask = nil
        autoFinalizeTask?.cancel()
        autoFinalizeTask = nil
        analyzer = nil
        activeTranscriber = nil
        converter = nil
        converterTargetFormat = nil
        latestAudioTime = nil
    }

    private func settingsChanged(from old: DictationSettings) {
        // Restart only when fields that bake into the DictationTranscriber /
        // SpeechAnalyzer change. Mid-session controls like auto-finalize and
        // the arrow-key trigger are excluded from the fingerprint so they can
        // mutate freely without tearing down the running session.
        guard state == .listening else { return }
        if old.transcriberFingerprint != settings.transcriberFingerprint {
            Task { await self.stopListening() }
        }
    }
}

// MARK: - Generic result handling

/// A minimal facade over the two transcriber result types so we can share
/// `makeEvent` and `handle` across DictationTranscriber and SpeechTranscriber
/// without duplicating their bodies.
private protocol TranscribedResult: SpeechModuleResult {
    var text: AttributedString { get }
    var alternatives: [AttributedString] { get }
}

extension DictationTranscriber.Result: TranscribedResult {}
extension SpeechTranscriber.Result: TranscribedResult {}
