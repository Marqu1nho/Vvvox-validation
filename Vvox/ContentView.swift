//
//  ContentView.swift
//  Vvox
//

import AppKit
import Speech
import SwiftUI

struct ContentView: View {

    @State private var engine = DictationEngine()
    @State private var vocabStore = VocabContextStore()
    @Environment(\.openURL) private var openURL

    private static let docsURL = URL(string: "https://developer.apple.com/documentation/speech/dictationtranscriber")!
    private static let presetDocsURL = URL(string: "https://developer.apple.com/documentation/speech/dictationtranscriber/preset")!
    private static let speechTranscriberDocsURL = URL(string: "https://developer.apple.com/documentation/speech/speechtranscriber")!
    private static let speechTranscriberPresetDocsURL = URL(string: "https://developer.apple.com/documentation/speech/speechtranscriber/preset")!
    private static let speechFrameworkURL = URL(string: "https://developer.apple.com/documentation/speech")!

    var body: some View {
        NavigationSplitView {
            SettingsPanel(engine: engine, vocabStore: vocabStore)
                .navigationSplitViewColumnWidth(min: 360, ideal: 420, max: 520)
        } detail: {
            TranscriptPanel(engine: engine)
        }
        .navigationTitle("Vvox — DictationTranscriber Explorer")
        .toolbar { toolbarItems }
        .background {
            SpacebarPushToTalkMonitor(
                onPress: { Task { await pushToTalkPress() } },
                onRelease: { Task { await pushToTalkRelease() } }
            )
        }
        .background {
            ArrowKeyFinalizeMonitor(
                isEnabled: { engine.settings.arrowKeyFinalizeEnabled && engine.state == .listening },
                onArrowKey: { Task { await engine.finalizeNow() } }
            )
        }
        .background {
            DictationToggleHotkeyMonitor(
                onToggle: { Task { await toggleDictation() } }
            )
        }
        .task {
            await engine.loadLocales()
            engine.vocabStore = vocabStore
        }
    }

    private func pushToTalkPress() async {
        // Only start if we're not already listening / mid-transition.
        switch engine.state {
        case .idle, .ready, .error:
            await engine.startListening()
        default:
            break
        }
    }

    private func pushToTalkRelease() async {
        if engine.state == .listening {
            await engine.stopListening()
        }
    }

    private func toggleDictation() async {
        if engine.state == .listening {
            await engine.stopListening()
        } else {
            await engine.startListening()
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button("DictationTranscriber") { openURL(Self.docsURL) }
                Button("DictationTranscriber.Preset") { openURL(Self.presetDocsURL) }
                Divider()
                Button("SpeechTranscriber") { openURL(Self.speechTranscriberDocsURL) }
                Button("SpeechTranscriber.Preset") { openURL(Self.speechTranscriberPresetDocsURL) }
                Divider()
                Button("Speech framework") { openURL(Self.speechFrameworkURL) }
            } label: {
                Label("Documentation", systemImage: "book")
            }
            .help("Open Apple's developer documentation for the DictationTranscriber API.")

            Button {
                Task {
                    if engine.state == .listening {
                        await engine.stopListening()
                    } else {
                        await engine.startListening()
                    }
                }
            } label: {
                if engine.state == .listening {
                    Label("Stop", systemImage: "stop.circle.fill").foregroundStyle(.red)
                } else {
                    Label("Start", systemImage: "mic.circle.fill")
                }
            }
            .disabled(engine.state == .stopping || engine.state == .preparingAssets || engine.state == .downloading || engine.state == .requestingPermission)
            .keyboardShortcut(.return, modifiers: [.command])
            .help(engine.state == .listening
                  ? "Stop listening and finalize the current transcription. (⌘↩ or ⌘⌥V)"
                  : "Start listening on the microphone and begin live transcription. (⌘↩ or ⌘⌥V — Space also works while no text field is focused)")

            Button {
                engine.clearTranscript()
            } label: {
                Label("Clear", systemImage: "eraser")
            }
            .disabled(engine.state == .listening)
            .help("Clear the live transcript and the result event log. Disabled while listening.")
        }
    }
}

// MARK: - Spacebar push-to-talk

/// Installs a process-local NSEvent monitor that fires push/release callbacks
/// when the user presses & releases the Space key, unless a text view is the
/// first responder (so typing space in the contextual-strings editor still
/// inserts a space).
private struct SpacebarPushToTalkMonitor: NSViewRepresentable {

    var onPress: () -> Void
    var onRelease: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPress: onPress, onRelease: onRelease)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(referenceView: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onPress = onPress
        context.coordinator.onRelease = onRelease
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var onPress: () -> Void
        var onRelease: () -> Void
        private var monitor: Any?
        private weak var referenceView: NSView?
        private var spaceIsDown = false

        init(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
            self.onPress = onPress
            self.onRelease = onRelease
        }

        func install(referenceView: NSView) {
            self.referenceView = referenceView
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                self?.handle(event: event) ?? event
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        deinit { uninstall() }

        private func handle(event: NSEvent) -> NSEvent? {
            // 49 == kVK_Space
            guard event.keyCode == 49 else { return event }

            // Skip if a text field / text view is currently editing.
            if let window = referenceView?.window ?? NSApp.keyWindow,
               isEditingText(in: window) {
                return event
            }

            switch event.type {
            case .keyDown:
                if event.isARepeat { return nil }
                if !spaceIsDown {
                    spaceIsDown = true
                    DispatchQueue.main.async { self.onPress() }
                }
                return nil
            case .keyUp:
                if spaceIsDown {
                    spaceIsDown = false
                    DispatchQueue.main.async { self.onRelease() }
                }
                return nil
            default:
                return event
            }
        }

        private func isEditingText(in window: NSWindow) -> Bool {
            var responder: NSResponder? = window.firstResponder
            while let r = responder {
                // Only treat *editable* text views as text editing. SwiftUI's
                // Text(...).textSelection(.enabled) creates a read-only
                // NSTextView underneath; we don't want clicking on the
                // transcript to permanently silence our key handler.
                if let textView = r as? NSTextView, textView.isEditable { return true }
                if let control = r as? NSControl, control.currentEditor() != nil { return true }
                responder = r.nextResponder
            }
            return false
        }
    }
}

// MARK: - Arrow-key finalize trigger

/// Installs a process-local NSEvent monitor that fires `onArrowKey()` whenever
/// the user presses ↑ ↓ ← →, unless a text view is the first responder. Always
/// returns the event — arrow keys still navigate normally; the finalize happens
/// as a side effect.
private struct ArrowKeyFinalizeMonitor: NSViewRepresentable {

    var isEnabled: () -> Bool
    var onArrowKey: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onArrowKey: onArrowKey)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(referenceView: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onArrowKey = onArrowKey
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var isEnabled: () -> Bool
        var onArrowKey: () -> Void
        private var monitor: Any?
        private weak var referenceView: NSView?

        init(isEnabled: @escaping () -> Bool, onArrowKey: @escaping () -> Void) {
            self.isEnabled = isEnabled
            self.onArrowKey = onArrowKey
        }

        func install(referenceView: NSView) {
            self.referenceView = referenceView
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event: event) ?? event
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        deinit { uninstall() }

        private func handle(event: NSEvent) -> NSEvent? {
            // 123 ←, 124 →, 125 ↓, 126 ↑
            switch event.keyCode {
            case 123, 124, 125, 126:
                break
            default:
                return event
            }

            // Skip if a text field / text view is currently editing.
            if let window = referenceView?.window ?? NSApp.keyWindow,
               isEditingText(in: window) {
                return event
            }

            guard isEnabled() else { return event }

            DispatchQueue.main.async { self.onArrowKey() }

            // ALWAYS return the event — never consume. The user might still
            // want arrow keys to navigate the transcript / move the cursor.
            return event
        }

        private func isEditingText(in window: NSWindow) -> Bool {
            var responder: NSResponder? = window.firstResponder
            while let r = responder {
                // Only treat *editable* text views as text editing. Read-only
                // selectable Text views (textSelection(.enabled)) shouldn't
                // block our finalize trigger.
                if let textView = r as? NSTextView, textView.isEditable { return true }
                if let control = r as? NSControl, control.currentEditor() != nil { return true }
                responder = r.nextResponder
            }
            return false
        }
    }
}

// MARK: - Dictation toggle hotkey (⌘⌥V)

/// Installs a process-local NSEvent monitor that toggles dictation start/stop
/// when the user presses ⌘⌥V. Works regardless of whether a text field has
/// focus (modifier-key combo doesn't conflict with literal typing). For PR1
/// this is window-local; PR2 will promote to a global hotkey for the HUD.
private struct DictationToggleHotkeyMonitor: NSViewRepresentable {

    var onToggle: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onToggle: onToggle)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onToggle = onToggle
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var onToggle: () -> Void
        private var monitor: Any?

        init(onToggle: @escaping () -> Void) {
            self.onToggle = onToggle
        }

        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event: event) ?? event
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        deinit { uninstall() }

        private func handle(event: NSEvent) -> NSEvent? {
            // 9 == kVK_ANSI_V
            guard event.keyCode == 9 else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods == [.command, .option] else { return event }
            if event.isARepeat { return nil }
            DispatchQueue.main.async { self.onToggle() }
            // Consume — don't let the V character leak into any text view.
            return nil
        }
    }
}

// MARK: - Settings panel

private struct SettingsPanel: View {

    @Bindable var engine: DictationEngine
    @Bindable var vocabStore: VocabContextStore

    @State private var showingContextEditor = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Status", value: engine.state.label)
                if let status = engine.statusMessage {
                    LabeledContent("Detail", value: status)
                }
            } header: { Text("Session") }

            Section {
                Picker("Engine", selection: $engine.settings.engineType) {
                    ForEach(DictationSettings.EngineType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                Text("DictationTranscriber: older lineage; what iOS keyboard dictation uses. SpeechTranscriber: newer, general-purpose; what Notes' Transcribe Audio uses. Different option sets surface for each.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: { Text("Engine") }

            if engine.settings.engineType == .dictation {
                Section {
                    presetPicker
                    localePicker
                } header: { Text("Locale & Preset") }

                Section {
                    Toggle("shortForm — audio is ≲ 1 minute", isOn: $engine.settings.shortForm)
                    Toggle("farField — speaker is distant from mic", isOn: $engine.settings.farField)
                    Toggle("atypicalSpeech — heavy accent / lisp / etc.", isOn: $engine.settings.atypicalSpeech)
                    Text("ContentHint values modify the algorithm. customizedLanguage(_:) requires an SFSpeechLanguageModel and is omitted from this UI.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: { Text("DictationTranscriber.ContentHint") }
                    .disabled(engine.settings.presetChoice != .custom)

                Section {
                    Toggle("punctuation — auto-punctuate", isOn: $engine.settings.punctuation)
                    Toggle("emoji — recognize spoken emoji names", isOn: $engine.settings.emoji)
                    Toggle("etiquetteReplacements — censor expletives", isOn: $engine.settings.etiquetteReplacements)
                } header: { Text("DictationTranscriber.TranscriptionOption") }
                    .disabled(engine.settings.presetChoice != .custom)

                Section {
                    Toggle("volatileResults — emit tentative results", isOn: $engine.settings.volatileResults)
                    Toggle("frequentFinalization — bias toward responsiveness", isOn: $engine.settings.frequentFinalization)
                    Toggle("alternativeTranscriptions — return alternates", isOn: $engine.settings.alternativeTranscriptions)
                    Text("volatileResults is the source of 'volatile' (yellow) text. frequentFinalization shortens the time before volatile becomes committed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: { Text("DictationTranscriber.ReportingOption") }
                    .disabled(engine.settings.presetChoice != .custom)

                Section {
                    Toggle("audioTimeRange — embed CMTimeRange per word", isOn: $engine.settings.audioTimeRange)
                    Toggle("transcriptionConfidence — embed 0…1 confidence", isOn: $engine.settings.transcriptionConfidence)
                } header: { Text("DictationTranscriber.ResultAttributeOption") }
                    .disabled(engine.settings.presetChoice != .custom)
            } else {
                Section {
                    Picker("Preset", selection: $engine.settings.speechPresetChoice) {
                        ForEach(DictationSettings.SpeechPresetChoice.allCases) { c in
                            Text(c.rawValue).tag(c)
                        }
                    }
                    .onChange(of: engine.settings.speechPresetChoice) { _, _ in
                        engine.settings.syncSpeechTogglesFromPreset()
                    }
                    localePicker
                    Text("SpeechTranscriber doesn't accept ContentHints — there's no shortForm / farField / atypicalSpeech equivalent.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: { Text("Locale & Preset") }

                Section {
                    Toggle("etiquetteReplacements — censor expletives", isOn: $engine.settings.speech_etiquetteReplacements)
                    Text("SpeechTranscriber only exposes one TranscriptionOption. Punctuation is implicit and always on; emoji recognition isn't available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: { Text("SpeechTranscriber.TranscriptionOption") }
                    .disabled(engine.settings.speechPresetChoice != .custom)

                Section {
                    Toggle("volatileResults — emit tentative results", isOn: $engine.settings.speech_volatileResults)
                    Toggle("fastResults — smaller context window, faster commits", isOn: $engine.settings.speech_fastResults)
                    Toggle("alternativeTranscriptions — return alternates", isOn: $engine.settings.speech_alternativeTranscriptions)
                    Text("fastResults is SpeechTranscriber's equivalent of DictationTranscriber's frequentFinalization — \"reduces result latency by using a smaller context window.\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: { Text("SpeechTranscriber.ReportingOption") }
                    .disabled(engine.settings.speechPresetChoice != .custom)

                Section {
                    Toggle("audioTimeRange — embed CMTimeRange per word", isOn: $engine.settings.speech_audioTimeRange)
                    Toggle("transcriptionConfidence — embed 0…1 confidence", isOn: $engine.settings.speech_transcriptionConfidence)
                } header: { Text("SpeechTranscriber.ResultAttributeOption") }
                    .disabled(engine.settings.speechPresetChoice != .custom)
            }

            Section {
                Button("Finalize now") {
                    Task { await engine.finalizeNow() }
                }
                .disabled(engine.state != .listening)
                .help("Force the analyzer to commit everything it has consumed as final. Recording continues.")

                Toggle("Auto-finalize older than", isOn: $engine.settings.autoFinalizeEnabled)
                    .help("When ON, the analyzer is continually asked to finalize any audio older than the threshold below. Lower thresholds give snappier commits but more chances to mis-commit a still-changing volatile word; higher thresholds let the model self-correct longer at the cost of latency.")
                Slider(value: $engine.settings.autoFinalizeSeconds, in: 0.5...3.0, step: 0.1) {
                    Text("seconds")
                } minimumValueLabel: {
                    Text("0.5s")
                } maximumValueLabel: {
                    Text("3.0s")
                }
                LabeledContent("Current threshold", value: String(format: "%.1fs", engine.settings.autoFinalizeSeconds))

                Toggle("Finalize when arrow keys are pressed", isOn: $engine.settings.arrowKeyFinalizeEnabled)
                    .help("When ON, pressing ↑↓←→ during a session forces an immediate finalize, so you can edit the transcript without the model replacing your changes. Arrow keys still navigate normally — they just trigger a finalize as a side effect.")
            } header: { Text("Finalization Controls") }

            Section {
                Picker("Task priority", selection: $engine.settings.priority) {
                    ForEach(DictationSettings.PriorityChoice.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Model retention", selection: $engine.settings.modelRetention) {
                    ForEach(DictationSettings.RetentionChoice.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("Preheat with prepareToAnalyze(in:)", isOn: $engine.settings.preheat)
            } header: { Text("SpeechAnalyzer.Options") }

            Section {
                LabeledContent("Samples", value: "\(engine.dwellCount)")
                LabeledContent("Mean", value: formatDwell(engine.dwellMeanMs))
                LabeledContent("Median", value: formatDwell(engine.dwellMedianMs))
                LabeledContent("p90", value: formatDwell(engine.dwellP90Ms))
                LabeledContent("Max", value: formatDwell(engine.dwellMaxMs))
                Button("Reset stats") { engine.resetDwellStats() }
                    .help("Clear the captured dwell-time samples and any pending volatile observations.")
                Text("Measures how long each chunk of audio sits in the volatile state before the analyzer finalizes it. Use this to pick a sensible 'auto-finalize older than' threshold.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: { Text("Volatile Dwell Stats") }

            Section {
                Picker("Active context", selection: $engine.settings.activeContextID) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(vocabStore.contexts) { context in
                        Text(context.name).tag(Optional(context.id))
                    }
                }
                Button("Edit contexts…") {
                    showingContextEditor = true
                }
                Text("The active context's words are added to whatever's in the text editor below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: { Text("Vocabulary Context") }

            Section {
                TextEditor(text: $engine.settings.contextualStringsRaw)
                    .frame(minHeight: 60, maxHeight: 100)
                    .font(.system(.body, design: .monospaced))
                Text("Comma- or newline-separated. Applied to AnalysisContext.contextualStrings[.general]. Keep total under 100 short phrases.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: { Text("AnalysisContext.contextualStrings") }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingContextEditor) {
            ContextEditorSheet(vocabStore: vocabStore)
        }
    }

    private var presetPicker: some View {
        Picker("Preset", selection: $engine.settings.presetChoice) {
            ForEach(DictationSettings.PresetChoice.allCases) { choice in
                VStack(alignment: .leading) {
                    Text(choice.displayName)
                    Text(choice.subtitle).font(.caption2).foregroundStyle(.secondary)
                }
                .tag(choice)
            }
        }
        .pickerStyle(.menu)
        .onChange(of: engine.settings.presetChoice) { _, _ in
            engine.settings.syncTogglesFromPreset()
        }
    }

    @ViewBuilder
    private var localePicker: some View {
        if engine.localesLoaded {
            Picker("Locale", selection: $engine.settings.localeIdentifier) {
                Section("Installed (\(engine.installedLocales.count))") {
                    ForEach(engine.installedLocales, id: \.identifier) { locale in
                        Text(localeLabel(locale, installed: true))
                            .tag(locale.identifier(.bcp47))
                    }
                }
                Section("Supported, downloadable (\(downloadableCount))") {
                    ForEach(downloadableLocales, id: \.identifier) { locale in
                        Text(localeLabel(locale, installed: false))
                            .tag(locale.identifier(.bcp47))
                    }
                }
            }
            .pickerStyle(.menu)
        } else {
            ProgressView("Loading locales…")
        }
    }

    private var downloadableLocales: [Locale] {
        let installedIDs = Set(engine.installedLocales.map(\.identifier))
        return engine.supportedLocales.filter { !installedIDs.contains($0.identifier) }
    }

    private var downloadableCount: Int { downloadableLocales.count }

    private func localeLabel(_ locale: Locale, installed: Bool) -> String {
        let id = locale.identifier
        let display = Locale.current.localizedString(forIdentifier: id) ?? id
        return "\(display) — \(id)" + (installed ? "" : " (downloads on start)")
    }

    private func formatDwell(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value)) ms"
    }
}

// MARK: - Transcript panel

private struct TranscriptPanel: View {

    let engine: DictationEngine

    @State private var transcriptResetSignal = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            transcriptHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    liveTranscript
                    Divider()
                    eventLog
                }
                .padding()
            }
        }
    }

    private var transcriptHeader: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(engine.state == .listening ? .red : .secondary.opacity(0.5))
                .frame(width: 10, height: 10)
                .symbolEffect(.pulse, isActive: engine.state == .listening)
            Text(engine.state.label).font(.headline)
            Spacer()
            Text("⌘⌥V or ⌘↩ to toggle (Space while no field focused)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Press ⌘⌥V or ⌘↩ to toggle dictation. Spacebar push-to-talk works only when no text field has focus.")
            volatileRangeView
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var volatileRangeView: some View {
        Group {
            if let start = engine.volatileRangeStart, let end = engine.volatileRangeEnd {
                Text(String(format: "Volatile range: %.2fs — %.2fs (%.2fs window)", start, end, max(0, end - start)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.orange)
            } else {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var liveTranscript: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Live transcript").font(.title3.bold())
                Spacer()
                Button {
                    transcriptResetSignal &+= 1
                } label: {
                    Label("Reset to streaming", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .help("Discard your edits and re-mirror the engine's committed text. Use this if you've made local edits you want to throw away.")
                legend
            }
            EditableTranscriptView(
                committed: engine.committedText,
                volatile: engine.volatileText,
                onEditGateway: { Task { await engine.finalizeNow() } },
                resetSignal: transcriptResetSignal
            )
            .frame(minHeight: 160, maxHeight: 360)
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            Label("committed (editable)", systemImage: "pencil")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.primary)
                .font(.caption)
            Label("volatile", systemImage: "waveform")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private var eventLog: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Result events").font(.title3.bold())
                Spacer()
                Text("\(engine.resultLog.count) total")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if engine.resultLog.isEmpty {
                Text("No results yet. Press Start and speak.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(engine.resultLog) { event in
                        ResultEventRow(event: event)
                    }
                }
            }
        }
    }
}

// MARK: - Result row

private struct ResultEventRow: View {

    let event: DictationEngine.ResultEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                tag(event.isFinal ? "FINAL" : "VOLATILE",
                    color: event.isFinal ? .green : .orange)
                Text(event.timestamp, format: .dateTime.hour().minute().second().secondFraction(.fractional(3)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let start = event.rangeStart, let end = event.rangeEnd {
                    Text(String(format: "range %.2fs–%.2fs", start, end))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let finalization = event.resultsFinalizationTime {
                    Text(String(format: "finalized through %.2fs", finalization))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let conf = event.averageConfidence {
                    Text(String(format: "avg conf %.2f", conf))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text(event.text)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(event.isFinal ? Color.green.opacity(0.08) : Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            if event.alternatives.count > 1 {
                DisclosureGroup("Alternatives (\(event.alternatives.count - 1))") {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(event.alternatives.dropFirst().indices, id: \.self) { idx in
                            Text(event.alternatives[idx])
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.caption)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.bold().monospaced())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

#Preview {
    ContentView()
}
