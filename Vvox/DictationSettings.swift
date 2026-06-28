//
//  DictationSettings.swift
//  Vvox
//
//  A value type capturing every configurable knob exposed by the
//  SpeechAnalyzer's DictationTranscriber AND SpeechTranscriber modules
//  (plus the SpeechAnalyzer options and AnalysisContext that affect them).
//

import Foundation
import Speech

struct DictationSettings: Equatable {

    // MARK: Engine type

    enum EngineType: String, CaseIterable, Identifiable, Hashable {
        case dictation
        case speech

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .dictation: return "DictationTranscriber"
            case .speech:    return "SpeechTranscriber"
            }
        }
    }

    // MARK: DictationTranscriber preset

    enum PresetChoice: String, CaseIterable, Identifiable, Hashable {
        case phrase
        case shortDictation
        case progressiveShortDictation
        case longDictation
        case progressiveLongDictation
        case timeIndexedLongDictation
        case custom

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .phrase: return "phrase"
            case .shortDictation: return "shortDictation"
            case .progressiveShortDictation: return "progressiveShortDictation"
            case .longDictation: return "longDictation"
            case .progressiveLongDictation: return "progressiveLongDictation"
            case .timeIndexedLongDictation: return "timeIndexedLongDictation"
            case .custom: return "Custom (your toggles)"
            }
        }

        var subtitle: String {
            switch self {
            case .phrase: return "Short phrase, no punctuation"
            case .shortDictation: return "≤ ~1 min, punctuation"
            case .progressiveShortDictation: return "≤ ~1 min, live, volatile + frequentFinalization"
            case .longDictation: return "> 1 min, punctuation"
            case .progressiveLongDictation: return "> 1 min, live, volatile"
            case .timeIndexedLongDictation: return "> 1 min, with audio time-codes"
            case .custom: return "Use the toggles below as the source of truth"
            }
        }

        var preset: DictationTranscriber.Preset? {
            switch self {
            case .phrase: return .phrase
            case .shortDictation: return .shortDictation
            case .progressiveShortDictation: return .progressiveShortDictation
            case .longDictation: return .longDictation
            case .progressiveLongDictation: return .progressiveLongDictation
            case .timeIndexedLongDictation: return .timeIndexedLongDictation
            case .custom: return nil
            }
        }
    }

    // MARK: SpeechTranscriber preset

    enum SpeechPresetChoice: String, CaseIterable, Identifiable, Hashable {
        case transcription
        case transcriptionWithAlternatives
        case timeIndexedTranscriptionWithAlternatives
        case progressiveTranscription
        case timeIndexedProgressiveTranscription
        case custom

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .transcription: return "transcription"
            case .transcriptionWithAlternatives: return "transcriptionWithAlternatives"
            case .timeIndexedTranscriptionWithAlternatives: return "timeIndexedTranscriptionWithAlternatives"
            case .progressiveTranscription: return "progressiveTranscription"
            case .timeIndexedProgressiveTranscription: return "timeIndexedProgressiveTranscription"
            case .custom: return "Custom (your toggles)"
            }
        }

        var subtitle: String {
            switch self {
            case .transcription: return "Final-only results"
            case .transcriptionWithAlternatives: return "Final results with alternates"
            case .timeIndexedTranscriptionWithAlternatives: return "Final results with alternates + audio time-codes"
            case .progressiveTranscription: return "Live, volatile + fastResults"
            case .timeIndexedProgressiveTranscription: return "Live + audio time-codes"
            case .custom: return "Use the toggles below as the source of truth"
            }
        }

        var preset: SpeechTranscriber.Preset? {
            switch self {
            case .transcription: return .transcription
            case .transcriptionWithAlternatives: return .transcriptionWithAlternatives
            case .timeIndexedTranscriptionWithAlternatives: return .timeIndexedTranscriptionWithAlternatives
            case .progressiveTranscription: return .progressiveTranscription
            case .timeIndexedProgressiveTranscription: return .timeIndexedProgressiveTranscription
            case .custom: return nil
            }
        }
    }

    // MARK: SpeechAnalyzer.Options

    enum PriorityChoice: String, CaseIterable, Identifiable, Hashable {
        case background, utility, low, medium, high, userInitiated
        var id: String { rawValue }

        var taskPriority: TaskPriority {
            switch self {
            case .background: return .background
            case .utility: return .utility
            case .low: return .low
            case .medium: return .medium
            case .high: return .high
            case .userInitiated: return .userInitiated
            }
        }
    }

    enum RetentionChoice: String, CaseIterable, Identifiable, Hashable {
        case whileInUse
        case lingering
        case processLifetime

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .whileInUse: return "whileInUse (default — release on dealloc)"
            case .lingering: return "lingering (cache briefly for next session)"
            case .processLifetime: return "processLifetime (keep until app exits)"
            }
        }

        var modelRetention: SpeechAnalyzer.Options.ModelRetention {
            switch self {
            case .whileInUse: return .whileInUse
            case .lingering: return .lingering
            case .processLifetime: return .processLifetime
            }
        }
    }

    // MARK: Stored knobs

    var engineType: EngineType = .dictation

    var presetChoice: PresetChoice = .progressiveShortDictation

    var localeIdentifier: String = Locale.current.identifier(.bcp47)

    // ContentHint (DictationTranscriber only)
    var shortForm: Bool = true
    var farField: Bool = false
    var atypicalSpeech: Bool = false

    // TranscriptionOption (DictationTranscriber)
    var punctuation: Bool = false
    var emoji: Bool = false
    var etiquetteReplacements: Bool = false

    // ReportingOption (DictationTranscriber)
    var volatileResults: Bool = true
    var frequentFinalization: Bool = true
    var alternativeTranscriptions: Bool = false

    // ResultAttributeOption (DictationTranscriber)
    var audioTimeRange: Bool = false
    var transcriptionConfidence: Bool = true

    // MARK: SpeechTranscriber custom knobs

    var speechPresetChoice: SpeechPresetChoice = .progressiveTranscription

    // SpeechTranscriber.TranscriptionOption (etiquetteReplacements only)
    var speech_etiquetteReplacements: Bool = false

    // SpeechTranscriber.ReportingOption
    var speech_volatileResults: Bool = true
    var speech_fastResults: Bool = true
    var speech_alternativeTranscriptions: Bool = false

    // SpeechTranscriber.ResultAttributeOption
    var speech_audioTimeRange: Bool = false
    var speech_transcriptionConfidence: Bool = true

    // SpeechAnalyzer.Options
    var priority: PriorityChoice = .userInitiated
    var modelRetention: RetentionChoice = .processLifetime
    var preheat: Bool = true

    // AnalysisContext.contextualStrings (.general tag) - comma separated UI input
    var contextualStringsRaw: String = ""

    // Active VocabContext whose words are unioned with contextualStringsRaw.
    var activeContextID: UUID? = nil

    // MARK: Finalization controls (do NOT require a transcriber restart)

    // When ON, an auto-finalize task asks the analyzer to finalize anything
    // older than `autoFinalizeSeconds` behind the latest yielded audio sample.
    var autoFinalizeEnabled: Bool = false
    var autoFinalizeSeconds: Double = 1.5

    // When ON, pressing any arrow key while a session is active forces an
    // immediate finalize. Arrow keys still navigate normally.
    var arrowKeyFinalizeEnabled: Bool = true

    // MARK: Resolved values

    var locale: Locale { Locale(identifier: localeIdentifier) }

    var contextualStrings: [String] {
        contextualStringsRaw
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var contentHints: Set<DictationTranscriber.ContentHint> {
        if case let .some(preset) = presetChoice.preset {
            return preset.contentHints
        }
        var hints: Set<DictationTranscriber.ContentHint> = []
        if shortForm { hints.insert(.shortForm) }
        if farField { hints.insert(.farField) }
        if atypicalSpeech { hints.insert(.atypicalSpeech) }
        return hints
    }

    var transcriptionOptions: Set<DictationTranscriber.TranscriptionOption> {
        if case let .some(preset) = presetChoice.preset {
            return preset.transcriptionOptions
        }
        var opts: Set<DictationTranscriber.TranscriptionOption> = []
        if punctuation { opts.insert(.punctuation) }
        if emoji { opts.insert(.emoji) }
        if etiquetteReplacements { opts.insert(.etiquetteReplacements) }
        return opts
    }

    var reportingOptions: Set<DictationTranscriber.ReportingOption> {
        if case let .some(preset) = presetChoice.preset {
            return preset.reportingOptions
        }
        var opts: Set<DictationTranscriber.ReportingOption> = []
        if volatileResults { opts.insert(.volatileResults) }
        if frequentFinalization { opts.insert(.frequentFinalization) }
        if alternativeTranscriptions { opts.insert(.alternativeTranscriptions) }
        return opts
    }

    var attributeOptions: Set<DictationTranscriber.ResultAttributeOption> {
        if case let .some(preset) = presetChoice.preset {
            return preset.attributeOptions
        }
        var opts: Set<DictationTranscriber.ResultAttributeOption> = []
        if audioTimeRange { opts.insert(.audioTimeRange) }
        if transcriptionConfidence { opts.insert(.transcriptionConfidence) }
        return opts
    }

    // MARK: SpeechTranscriber resolved values

    var speechTranscriptionOptions: Set<SpeechTranscriber.TranscriptionOption> {
        if case let .some(preset) = speechPresetChoice.preset {
            return preset.transcriptionOptions
        }
        var opts: Set<SpeechTranscriber.TranscriptionOption> = []
        if speech_etiquetteReplacements { opts.insert(.etiquetteReplacements) }
        return opts
    }

    var speechReportingOptions: Set<SpeechTranscriber.ReportingOption> {
        if case let .some(preset) = speechPresetChoice.preset {
            return preset.reportingOptions
        }
        var opts: Set<SpeechTranscriber.ReportingOption> = []
        if speech_volatileResults { opts.insert(.volatileResults) }
        if speech_fastResults { opts.insert(.fastResults) }
        if speech_alternativeTranscriptions { opts.insert(.alternativeTranscriptions) }
        return opts
    }

    var speechAttributeOptions: Set<SpeechTranscriber.ResultAttributeOption> {
        if case let .some(preset) = speechPresetChoice.preset {
            return preset.attributeOptions
        }
        var opts: Set<SpeechTranscriber.ResultAttributeOption> = []
        if speech_audioTimeRange { opts.insert(.audioTimeRange) }
        if speech_transcriptionConfidence { opts.insert(.transcriptionConfidence) }
        return opts
    }

    // MARK: Transcriber fingerprint
    //
    // Hashes only the fields that require building a fresh transcriber /
    // SpeechAnalyzer. Mid-session toggles like `autoFinalizeEnabled`,
    // `autoFinalizeSeconds`, and `arrowKeyFinalizeEnabled` are intentionally
    // omitted so they can mutate freely without tearing down the session.
    var transcriberFingerprint: AnyHashable {
        AnyHashable(TranscriberInputs(
            engineType: engineType,
            presetChoice: presetChoice,
            speechPresetChoice: speechPresetChoice,
            localeIdentifier: localeIdentifier,
            shortForm: shortForm,
            farField: farField,
            atypicalSpeech: atypicalSpeech,
            punctuation: punctuation,
            emoji: emoji,
            etiquetteReplacements: etiquetteReplacements,
            volatileResults: volatileResults,
            frequentFinalization: frequentFinalization,
            alternativeTranscriptions: alternativeTranscriptions,
            audioTimeRange: audioTimeRange,
            transcriptionConfidence: transcriptionConfidence,
            speech_etiquetteReplacements: speech_etiquetteReplacements,
            speech_volatileResults: speech_volatileResults,
            speech_fastResults: speech_fastResults,
            speech_alternativeTranscriptions: speech_alternativeTranscriptions,
            speech_audioTimeRange: speech_audioTimeRange,
            speech_transcriptionConfidence: speech_transcriptionConfidence,
            priority: priority,
            modelRetention: modelRetention,
            preheat: preheat,
            contextualStringsRaw: contextualStringsRaw,
            activeContextID: activeContextID
        ))
    }

    private struct TranscriberInputs: Hashable {
        let engineType: EngineType
        let presetChoice: PresetChoice
        let speechPresetChoice: SpeechPresetChoice
        let localeIdentifier: String
        let shortForm: Bool
        let farField: Bool
        let atypicalSpeech: Bool
        let punctuation: Bool
        let emoji: Bool
        let etiquetteReplacements: Bool
        let volatileResults: Bool
        let frequentFinalization: Bool
        let alternativeTranscriptions: Bool
        let audioTimeRange: Bool
        let transcriptionConfidence: Bool
        let speech_etiquetteReplacements: Bool
        let speech_volatileResults: Bool
        let speech_fastResults: Bool
        let speech_alternativeTranscriptions: Bool
        let speech_audioTimeRange: Bool
        let speech_transcriptionConfidence: Bool
        let priority: PriorityChoice
        let modelRetention: RetentionChoice
        let preheat: Bool
        let contextualStringsRaw: String
        let activeContextID: UUID?
    }

    // After choosing a DictationTranscriber preset, mirror its booleans into
    // the toggles so the user can flip to .custom and continue tweaking from
    // the preset baseline.
    mutating func syncTogglesFromPreset() {
        guard let preset = presetChoice.preset else { return }
        shortForm = preset.contentHints.contains(.shortForm)
        farField = preset.contentHints.contains(.farField)
        atypicalSpeech = preset.contentHints.contains(.atypicalSpeech)

        punctuation = preset.transcriptionOptions.contains(.punctuation)
        emoji = preset.transcriptionOptions.contains(.emoji)
        etiquetteReplacements = preset.transcriptionOptions.contains(.etiquetteReplacements)

        volatileResults = preset.reportingOptions.contains(.volatileResults)
        frequentFinalization = preset.reportingOptions.contains(.frequentFinalization)
        alternativeTranscriptions = preset.reportingOptions.contains(.alternativeTranscriptions)

        audioTimeRange = preset.attributeOptions.contains(.audioTimeRange)
        transcriptionConfidence = preset.attributeOptions.contains(.transcriptionConfidence)
    }

    // SpeechTranscriber analogue of syncTogglesFromPreset.
    mutating func syncSpeechTogglesFromPreset() {
        guard let preset = speechPresetChoice.preset else { return }
        speech_etiquetteReplacements = preset.transcriptionOptions.contains(.etiquetteReplacements)

        speech_volatileResults = preset.reportingOptions.contains(.volatileResults)
        speech_fastResults = preset.reportingOptions.contains(.fastResults)
        speech_alternativeTranscriptions = preset.reportingOptions.contains(.alternativeTranscriptions)

        speech_audioTimeRange = preset.attributeOptions.contains(.audioTimeRange)
        speech_transcriptionConfidence = preset.attributeOptions.contains(.transcriptionConfidence)
    }
}
