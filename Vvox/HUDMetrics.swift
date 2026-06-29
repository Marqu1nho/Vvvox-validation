//
//  HUDMetrics.swift
//  Vvox
//
//  Model + provider for the HUD's primary (live WPM) and secondary
//  (user-selectable) stats. PR2a wires the model + UI architecture; real
//  value computation (silence-excluded WPM per vvox_wpm_calculation.md,
//  day-streak tracking, persistence) lands in PR2b.
//

import Foundation

enum HUDMetricID: String, CaseIterable, Identifiable, Hashable {
    case wpmToday = "wpm_today"
    case wpmNDays = "wpm_ndays"
    case maxWPM = "max_wpm"
    case dayStreak = "day_streak"

    var id: String { rawValue }

    var defaultDisplayName: String {
        switch self {
        case .wpmToday:  return "WPM today"
        case .wpmNDays:  return "WPM N days"
        case .maxWPM:    return "max WPM"
        case .dayStreak: return "day streak"
        }
    }
}

/// One metric in the HUD's secondary-stat slot.
///
/// - `displayName` is rendered in the dropdown rows (just the name).
/// - `computedValue` is rendered in the top row when this metric is selected.
struct HUDMetric: Identifiable {
    let id: HUDMetricID
    let displayName: String
    let computedValue: String
}

/// Source of HUD metric values. PR2a returns placeholders ("—") so the UI
/// architecture is exercised correctly; PR2b backfills real values.
@MainActor
@Observable
final class HUDMetricsProvider {

    /// User-configurable N for "WPM N days". Default 7.
    var nDays: Int = 7

    /// Live WPM rendered as the bold left-of-divider value in the HUD footer.
    var currentWPMDisplay: String { "—" }

    /// All four metric options, in the locked order from
    /// vvox_hud_secondary_stat_display.md.
    var metrics: [HUDMetric] {
        HUDMetricID.allCases.map { id in
            HUDMetric(
                id: id,
                displayName: displayName(for: id),
                computedValue: computedValue(for: id)
            )
        }
    }

    func metric(_ id: HUDMetricID) -> HUDMetric {
        metrics.first { $0.id == id } ?? metrics[0]
    }

    private func displayName(for id: HUDMetricID) -> String {
        switch id {
        case .wpmNDays: return "WPM \(nDays) days"
        default:        return id.defaultDisplayName
        }
    }

    private func computedValue(for id: HUDMetricID) -> String {
        switch id {
        case .wpmToday, .wpmNDays, .maxWPM: return "— wpm"
        case .dayStreak:                     return "0-day streak"
        }
    }
}
