// HUDMock_LiquidGlassInline.swift
// Vvox HUD — Liquid Glass scratchpad with inline-expanding dropdown.
//
// Dropdown options are stat *names* (not values):
//   WPM today
//   WPM N days      ← N is user-editable (default 7) — accent-colored, inline TextField
//   max WPM
//   day streak
//
// In production the top row would show the live value alongside the name;
// for the mock we render the name in both the selected and alternative rows.

import SwiftUI

// MARK: - State model

enum LGInlineHUDPhase {
    case idle, transcribing, processing, done
}

private struct LGMetric: Identifiable {
    let id: String
    let label: String   // The stat's display name (e.g. "WPM today")
}

private enum LGVisualState { case hidden, visible, dismissed }

// MARK: - HUD with inline dropdown

struct LiquidGlassHUDInline: View {

    var phase: LGInlineHUDPhase = .transcribing
    var width: CGFloat = 480
    var height: CGFloat = 240
    var lastWPM: Int = 132

    @State private var selectedStatID: String = "wpm_today"
    @State private var isDropdownOpen: Bool = false
    @State private var visualState: LGVisualState = .hidden

    /// User-configurable N for "WPM N days". Default 7.
    @State private var customNDays: String = "7"

    @FocusState private var nDaysFocused: Bool

    @Namespace private var glassNamespace

    private let committed = "Hey team, just wanted to circle back on the design review — I think we should ship the HUD update this week so the rest of the org can dogfood it before Friday."
    private let volatile  = "and then we can lock in the typography pass next sprint"

    private let metrics: [LGMetric] = [
        .init(id: "wpm_today",  label: "WPM today"),
        .init(id: "wpm_ndays",  label: "WPM N days"),   // N rendered from customNDays
        .init(id: "max_wpm",    label: "max WPM"),
        .init(id: "day_streak", label: "day streak"),
    ]

    private var selectedMetric: LGMetric {
        metrics.first { $0.id == selectedStatID } ?? metrics[0]
    }

    private var alternativeMetrics: [LGMetric] {
        metrics.filter { $0.id != selectedStatID }
    }

    /// What to actually display for a metric. The N-days metric expands its
    /// "N" placeholder to whatever the user has typed (or "7" if empty).
    private func displayString(for metric: LGMetric) -> String {
        if metric.id == "wpm_ndays" {
            let n = customNDays.isEmpty ? "7" : customNDays
            return "WPM \(n) days"
        }
        return metric.label
    }

    /// Hidden sizer — pin the stat column's width to the widest possible
    /// rendering so editing N or toggling the dropdown doesn't shift the row.
    /// We pessimistically use 3-digit N for the WPM-N-days case.
    private var widestStatString: String {
        let candidates = metrics.map { m -> String in
            m.id == "wpm_ndays" ? "WPM 365 days" : m.label
        }
        return candidates.max(by: { $0.count < $1.count }) ?? ""
    }

    private var isTranscribing: Bool { phase == .transcribing }

    // HUD grows downward when the inline dropdown opens. ~22pt per extra row.
    private var hudHeight: CGFloat {
        let extraRowHeight: CGFloat = 22
        let extraRows = isDropdownOpen ? alternativeMetrics.count : 0
        return height + CGFloat(extraRows) * extraRowHeight
    }

    private let rimGradient = LinearGradient(
        stops: [
            .init(color: Color(red: 0.655, green: 0.545, blue: 0.980), location: 0.00),  // #A78BFA
            .init(color: Color(red: 0.498, green: 0.820, blue: 0.961), location: 0.33),  // #7FD1F5
            .init(color: Color(red: 0.369, green: 0.918, blue: 0.831), location: 0.60),  // #5EEAD4
            .init(color: Color(red: 0.976, green: 0.659, blue: 0.831), location: 1.00),  // #F9A8D4
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    var body: some View {
        ZStack {
            rim
            glassCard
        }
        .frame(width: width, height: hudHeight)
        .opacity(visualState == .visible ? 1 : 0.06)
        .blur(radius: visualState == .visible ? 0 : 10)
        .scaleEffect(visualState == .visible ? 1 : 1.04)
        .offset(y: visualState == .visible ? 0 : -12)
        .animation(.easeOut(duration: 0.38), value: visualState)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: hudHeight)
        .onAppear {
            DispatchQueue.main.async {
                visualState = (phase == .done) ? .dismissed : .visible
            }
        }
        .onChange(of: phase) { _, newPhase in
            visualState = (newPhase == .done) ? .dismissed : .visible
        }
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
        case .transcribing:        return 0.26 + amp * 0.22
        case .idle, .processing:   return 0.20 + breathe * 0.26
        case .done:                return 0
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
    }

    // MARK: Header — centered VVOX chip

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

    // MARK: Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                (
                    Text(committed)
                        .foregroundStyle(.primary)
                    + Text(" ")
                    + Text(volatile)
                        .foregroundStyle(.tertiary)
                        .italic()
                    + caretText
                )
                .font(.system(.title3, design: .rounded))
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id("end")
            }
            .opacity(phase == .idle ? 0.5 : 1)
            .padding(.horizontal, 20)
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
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
        }
    }

    private var caretText: Text {
        guard isTranscribing else { return Text("") }
        return Text(" ▏").foregroundColor(.accentColor)
    }

    // MARK: Footer — keycaps left, stats area (inline-expanding) right

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

    // MARK: Stats — left-aligned inline dropdown (option names only)

    private var statsArea: some View {
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
            GridRow {
                Text("\(lastWPM) WPM")
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

    /// Background pill shape for the selected-stat label.
    private var selectedStatBackground: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(.white.opacity(isDropdownOpen ? 0.12 : 0))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(.white.opacity(isDropdownOpen ? 0.16 : 0), lineWidth: 0.5)
            )
    }

    /// Inline N-days editor: "WPM [TextField] days".
    private var nDaysContent: some View {
        HStack(spacing: 0) {
            Text("WPM ")
                .foregroundStyle(.secondary)
            TextField("7", text: $customNDays)
                .textFieldStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
                .multilineTextAlignment(.center)
                .focused($nDaysFocused)
            Text(" days")
                .foregroundStyle(.secondary)
        }
        .font(.system(.caption, design: .monospaced))
    }

    /// Plain text display of the selected metric.
    private var metricTextContent: some View {
        Text(displayString(for: selectedMetric))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
    }

    /// The currently selected stat. Tapping toggles the dropdown.
    /// Special case: when the selected metric is "WPM N days", the N is
    /// rendered as an inline TextField so the user can edit it.
    @ViewBuilder
    private var selectedStatLabel: some View {
        Group {
            if selectedMetric.id == "wpm_ndays" {
                nDaysContent
            } else {
                metricTextContent
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(selectedStatBackground)
        .contentShape(Rectangle())
        .onTapGesture {
            // If the user is mid-edit on N, don't hijack the tap to toggle.
            guard !nDaysFocused else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                isDropdownOpen.toggle()
            }
        }
    }

    /// An alternative stat in the dropdown — just the name, no inline editor.
    /// Tapping selects it and collapses the dropdown.
    private func alternativeStatLabel(_ metric: LGMetric) -> some View {
        Text(displayString(for: metric))
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

// MARK: - Previews

private struct LGStage<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(64)
            .background(darkStageBackground)
    }
}

private var darkStageBackground: some View {
    ZStack {
        Color(red: 0.09, green: 0.09, blue: 0.09)
        RadialGradient(
            colors: [
                Color(red: 0.28, green: 0.28, blue: 0.28).opacity(0.55),
                .clear
            ],
            center: .init(x: 0.28, y: 0.22),
            startRadius: 0, endRadius: 520
        )
        RadialGradient(
            colors: [.clear, Color.black.opacity(0.35)],
            center: .center,
            startRadius: 360, endRadius: 900
        )
    }
}

#Preview("Inline · Transcribing · Dark") {
    LGStage { LiquidGlassHUDInline(phase: LGInlineHUDPhase.transcribing) }
        .frame(width: 720, height: 500)
        .preferredColorScheme(.dark)
}

#Preview("Inline · Idle · Dark") {
    LGStage { LiquidGlassHUDInline(phase: LGInlineHUDPhase.idle) }
        .frame(width: 720, height: 500)
        .preferredColorScheme(.dark)
}

#Preview("Inline · Transcribing · Light") {
    LiquidGlassHUDInline(phase: LGInlineHUDPhase.transcribing)
        .padding(64)
        .frame(width: 720, height: 500)
        .background(
            RadialGradient(
                colors: [Color(red: 0.91, green: 0.94, blue: 0.99),
                         Color(red: 0.86, green: 0.89, blue: 0.92)],
                center: .init(x: 0.22, y: 0),
                startRadius: 0, endRadius: 900
            )
        )
        .preferredColorScheme(.light)
}

/// Interactive preview — exercise the summon/dissolve and the inline
/// dropdown. Tap the selected stat to expand. Select "WPM N days", then
/// click the accent-colored N to edit it. Live Preview required.
private struct LGInteractiveStage: View {
    @State private var phase: LGInlineHUDPhase = .transcribing
    var body: some View {
        VStack(spacing: 24) {
            LiquidGlassHUDInline(phase: phase)
            Button {
                phase = (phase == .done) ? .transcribing : .done
            } label: {
                Text(phase == .done ? "Summon HUD" : "Dissolve HUD")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(64)
        .background(darkStageBackground)
    }
}

#Preview("Inline · Interactive · Dark") {
    LGInteractiveStage()
        .frame(width: 720, height: 600)
        .preferredColorScheme(.dark)
}
