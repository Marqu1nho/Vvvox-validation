//
//  HUDView.swift
//  Vvox
//
//  Production HUD surface — Liquid Glass chrome + editable transcript bound
//  to the live DictationEngine. Adapted from the design mockup at
//  Vvox/_design_mockups/HUDMock_LiquidGlassInline.swift. PR2a wiring;
//  PR2b promotes to global hotkey + AX anchoring + clipboard paste.
//

import SwiftUI

enum HUDPhase {
    case idle, transcribing
}

struct HUDView: View {

    let engine: DictationEngine
    @Bindable var metrics: HUDMetricsProvider

    @State private var selectedStatID: HUDMetricID = .wpmToday
    @State private var isDropdownOpen: Bool = false
    @State private var transcriptResetSignal: Int = 0

    @FocusState private var nDaysFocused: Bool

    @Namespace private var glassNamespace

    private var phase: HUDPhase {
        engine.state == .listening ? .transcribing : .idle
    }
    private var isTranscribing: Bool { phase == .transcribing }

    private var selectedMetric: HUDMetric { metrics.metric(selectedStatID) }
    private var alternativeMetrics: [HUDMetric] {
        metrics.metrics.filter { $0.id != selectedStatID }
    }

    /// Pessimistic widest stat string so editing N or swapping selection
    /// doesn't shift the row. Sized for the longest possible PR2a rendering.
    private let widestStatString: String = "— wpm · last 365 days"

    private let rimGradient = LinearGradient(
        stops: [
            .init(color: Color(red: 0.655, green: 0.545, blue: 0.980), location: 0.00),
            .init(color: Color(red: 0.498, green: 0.820, blue: 0.961), location: 0.33),
            .init(color: Color(red: 0.369, green: 0.918, blue: 0.831), location: 0.60),
            .init(color: Color(red: 0.976, green: 0.659, blue: 0.831), location: 1.00),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    var body: some View {
        ZStack {
            rim
            glassCard
        }
        .padding(12)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isDropdownOpen)
    }

    // MARK: Rim

    private var rim: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let amp = isTranscribing ? voiceEnvelope(t) : 0
            let breathe = (sin(t / 6.5 * 2 * .pi) + 1) / 2

            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(rimGradient)
                .padding(-12)
                .blur(radius: isTranscribing ? 20 + amp * 10 : 24)
                .scaleEffect(isTranscribing ? 1 + amp * 0.015 : 1)
                .opacity(rimOpacity(amp: amp, breathe: breathe))
        }
        .allowsHitTesting(false)
    }

    private func rimOpacity(amp: Double, breathe: Double) -> Double {
        switch phase {
        case .transcribing: return 0.26 + amp * 0.22
        case .idle:         return 0.20 + breathe * 0.26
        }
    }

    private func voiceEnvelope(_ t: Double) -> Double {
        let speaking = sin(t * 0.85) > -0.45
        let raw = speaking
            ? 0.35 + 0.40 * abs(sin(t * 5.5)) + 0.12 * abs(sin(t * 11.0))
            : 0.08
        return min(1, max(0, raw))
    }

    // MARK: Glass card

    private var glassCard: some View {
        GlassEffectContainer(spacing: 18) {
            VStack(spacing: 0) {
                header
                transcript
                    .frame(maxHeight: .infinity)
                footer
            }
            .glassEffect(
                .regular.tint(.accentColor.opacity(0.08)),
                in: .rect(cornerRadius: 22, style: .continuous)
            )
            .glassEffectID("hud.surface", in: glassNamespace)
        }
        .opacity(0.92)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, options: .repeating, isActive: isTranscribing)
                    .accessibilityLabel("Recording")

                Text("VVOX")
                    .font(.system(.caption2, design: .rounded).weight(.regular))
                    .textCase(.uppercase)
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(.regular, in: .capsule)
            .glassEffectID("hud.chip", in: glassNamespace)
            Spacer()
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: Transcript — bound to live engine

    private var transcript: some View {
        EditableTranscriptView(
            committed: engine.committedText,
            volatile: engine.volatileText,
            onEditGateway: { Task { await engine.finalizeNow() } },
            resetSignal: transcriptResetSignal
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.06),
                    .init(color: .black, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    // MARK: Footer

    private var footer: some View {
        HStack(alignment: .top) {
            keycapRow
                .padding(.top, 2)
            Spacer(minLength: 0)
            statsArea
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    private var keycapRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "keyboard")
                .font(.system(size: 11, weight: .medium))
            keyCap("⌃")
            keyCap("⌥")
            keyCap("V")
            Text("to paste")
        }
        .font(.system(.caption, design: .rounded))
        .foregroundStyle(.secondary)
    }

    private func keyCap(_ glyph: String) -> some View {
        Text(glyph)
            .font(.system(.caption2, design: .rounded).weight(.semibold))
            .foregroundStyle(.primary)
            .frame(minWidth: 18, minHeight: 18)
            .padding(.horizontal, 4)
            .glassEffect(.regular, in: .rect(cornerRadius: 5, style: .continuous))
    }

    // MARK: Stats

    private var statsArea: some View {
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
            GridRow {
                Text("\(metrics.currentWPMDisplay) WPM")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.primary)
                    .gridColumnAlignment(.trailing)

                Text("│")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)

                ZStack(alignment: .leading) {
                    Text(widestStatString)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .hidden()
                    selectedStatLabel
                }
                .gridColumnAlignment(.leading)
            }

            if isDropdownOpen {
                ForEach(alternativeMetrics) { metric in
                    GridRow {
                        Color.clear.frame(width: 0, height: 0)
                        Color.clear.frame(width: 0, height: 0)
                        alternativeStatLabel(metric)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal:   .opacity.combined(with: .move(edge: .top))
                            ))
                    }
                }
            }
        }
    }

    private var selectedStatBackground: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(.white.opacity(isDropdownOpen ? 0.12 : 0))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(.white.opacity(isDropdownOpen ? 0.16 : 0), lineWidth: 0.5)
            )
    }

    /// Inline editor for the "WPM N days" metric when it's the selected one.
    /// Renders: `<computed value> · last [N] days`, with N as an inline
    /// accent-colored TextField bound to `metrics.nDays`.
    private var nDaysContent: some View {
        HStack(spacing: 0) {
            Text("\(selectedMetric.computedValue) · last ")
                .foregroundStyle(.secondary)
            TextField("7", value: $metrics.nDays, format: .number)
                .textFieldStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)
                .multilineTextAlignment(.center)
                .focused($nDaysFocused)
            Text(" days")
                .foregroundStyle(.secondary)
        }
        .font(.system(.caption, design: .monospaced))
    }

    private var metricValueContent: some View {
        Text(selectedMetric.computedValue)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var selectedStatLabel: some View {
        Group {
            if selectedMetric.id == .wpmNDays {
                nDaysContent
            } else {
                metricValueContent
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(selectedStatBackground)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !nDaysFocused else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                isDropdownOpen.toggle()
            }
        }
    }

    private func alternativeStatLabel(_ metric: HUDMetric) -> some View {
        Text(metric.displayName)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    selectedStatID = metric.id
                    isDropdownOpen = false
                }
            }
    }
}
