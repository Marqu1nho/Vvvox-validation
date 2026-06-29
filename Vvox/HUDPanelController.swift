//
//  HUDPanelController.swift
//  Vvox
//
//  Owns the floating HUD NSPanel. PR2a: chromeless, nonactivating, resizable
//  panel hosting HUDView via NSHostingView, summoned from the main window's
//  toolbar. PR2b promotes to global ⌃⌥V activation + AX anchoring above the
//  focused text element + clipboard-preserving ⌘V paste.
//

import AppKit
import SwiftUI

@MainActor
final class HUDPanelController {

    private let engine: DictationEngine
    private let metrics: HUDMetricsProvider
    private var panel: NSPanel?

    init(engine: DictationEngine, metrics: HUDMetricsProvider) {
        self.engine = engine
        self.metrics = metrics
    }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let panel = ensurePanel()
        // Bring to front WITHOUT activating Vvox — keeps focus on whatever
        // app the user was in. Critical for PR2b's AX anchoring where the
        // panel will read the OTHER app's focused text element.
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: Internal

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let initialSize = NSSize(width: 520, height: 280)
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: screenFrame.midX - initialSize.width / 2,
            y: screenFrame.maxY - initialSize.height - 80
        )

        let p = NSPanel(
            contentRect: NSRect(origin: origin, size: initialSize),
            styleMask: [.nonactivatingPanel, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.hidesOnDeactivate = false
        // Only become key when something inside needs typing (e.g. the
        // editable transcript or the inline N-days field). Prevents the
        // chrome from stealing focus on mere clicks.
        p.becomesKeyOnlyIfNeeded = true
        p.worksWhenModal = false
        p.minSize = NSSize(width: 360, height: 180)

        let hostView = NSHostingView(rootView: HUDView(engine: engine, metrics: metrics))
        hostView.autoresizingMask = [.width, .height]
        p.contentView = hostView

        self.panel = p
        return p
    }
}
