//
//  EditableTranscriptView.swift
//  Vvox
//
//  Editable transcript surface. SwiftUI wrapper around a custom NSTextView that:
//  - Renders the engine's committed text as editable, primary-label color.
//  - Renders the volatile tail as a non-editable, non-selectable trailing run
//    in a distinct off-gray color (tertiary label).
//  - Remaps unmodified ← / → to extend selection by WORD, ↑ / ↓ by LINE.
//    Modified arrow combos (⌘, ⌥, ⇧, etc.) pass through untouched.
//  - Remaps backspace (with empty selection) to delete the previous WORD.
//  - Calls `onEditGateway()` before any user-driven edit so the engine can
//    finalize whatever volatile content is pending.
//

import AppKit
import SwiftUI

struct EditableTranscriptView: NSViewRepresentable {

    let committed: AttributedString
    let volatile: AttributedString
    let onEditGateway: () -> Void
    var resetSignal: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(onEditGateway: onEditGateway)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = VvoxEditableTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .preferredFont(forTextStyle: .title3)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.delegate = context.coordinator
        textView.typingAttributes = [
            .foregroundColor: NSColor.labelColor,
            .font: textView.font ?? NSFont.preferredFont(forTextStyle: .title3)
        ]
        textView.editGatewayHandler = { [weak coordinator = context.coordinator] in
            coordinator?.handleEditGateway()
        }

        context.coordinator.textView = textView
        context.coordinator.lastResetSignal = resetSignal

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        context.coordinator.applyState(committed: committed, volatile: volatile)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.onEditGateway = onEditGateway
        if context.coordinator.lastResetSignal != resetSignal {
            context.coordinator.lastResetSignal = resetSignal
            context.coordinator.resetToCommitted(committed: committed, volatile: volatile)
        } else {
            context.coordinator.applyState(committed: committed, volatile: volatile)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {

        var onEditGateway: () -> Void
        weak var textView: VvoxEditableTextView?

        var lastResetSignal: Int = 0

        // The committed region lives at [0, committedLength). The volatile
        // tail lives at [committedLength, committedLength + volatileLength).
        private var committedLength: Int = 0
        private var volatileLength: Int = 0

        // The engine.committedText string we last appended FROM. Used to
        // compute the delta when the engine emits new committed content.
        // NOT updated by user edits — user edits diverge intentionally and
        // the engine's next emission will still append at the end.
        private var lastSyncedCommittedString: String = ""

        init(onEditGateway: @escaping () -> Void) {
            self.onEditGateway = onEditGateway
        }

        func handleEditGateway() {
            onEditGateway()
        }

        func resetToCommitted(committed: AttributedString, volatile: AttributedString) {
            guard let textView, let storage = textView.textStorage else { return }
            storage.setAttributedString(NSAttributedString())
            committedLength = 0
            volatileLength = 0
            lastSyncedCommittedString = ""
            applyState(committed: committed, volatile: volatile)
            textView.setSelectedRange(NSRange(location: committedLength, length: 0))
        }

        func applyState(committed: AttributedString, volatile: AttributedString) {
            guard let textView, let storage = textView.textStorage else { return }
            let font = textView.font ?? NSFont.preferredFont(forTextStyle: .title3)

            let currentCommittedString = String(committed.characters)

            // Detect engine reset (clearTranscript or new session): if the
            // current committed string no longer extends what we last saw,
            // wipe and start over from the new state.
            if !currentCommittedString.hasPrefix(lastSyncedCommittedString) {
                storage.setAttributedString(NSAttributedString())
                committedLength = 0
                volatileLength = 0
                lastSyncedCommittedString = ""
            }

            // Append committed delta at the end of the committed region
            // (before the volatile tail).
            if currentCommittedString.count > lastSyncedCommittedString.count {
                let delta = String(currentCommittedString[lastSyncedCommittedString.endIndex...])
                let attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: NSColor.labelColor,
                    .font: font
                ]
                let attrDelta = NSAttributedString(string: delta, attributes: attrs)
                storage.insert(attrDelta, at: committedLength)
                committedLength += attrDelta.length
                lastSyncedCommittedString = currentCommittedString
            }

            // Replace the volatile tail with the latest tentative content.
            let volatileBase = String(volatile.characters)
            let volatileToRender: String
            if committedLength > 0 && !volatileBase.isEmpty {
                volatileToRender = " " + volatileBase
            } else {
                volatileToRender = volatileBase
            }
            let volatileAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.tertiaryLabelColor,
                .font: font
            ]
            let attrVolatile = NSAttributedString(string: volatileToRender, attributes: volatileAttrs)
            let currentVolatileRange = NSRange(location: committedLength, length: volatileLength)
            storage.replaceCharacters(in: currentVolatileRange, with: attrVolatile)
            volatileLength = attrVolatile.length
        }

        // MARK: NSTextViewDelegate

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            // Reject any edit that extends INTO the volatile tail. Insertions
            // at the volatile boundary (length 0 at committedLength) are
            // allowed — they push the volatile range rightward.
            let volatileStart = committedLength
            if NSMaxRange(affectedCharRange) > volatileStart { return false }
            // Surface the user's intent so the engine can finalize.
            onEditGateway()
            return true
        }

        func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRanges oldSelectedCharRanges: [NSValue], toCharacterRanges newSelectedCharRanges: [NSValue]) -> [NSValue] {
            // Clamp selection so it can't extend into the volatile tail.
            let volatileStart = committedLength
            return newSelectedCharRanges.map { value in
                let range = value.rangeValue
                let clampedStart = min(range.location, volatileStart)
                let clampedEnd = min(NSMaxRange(range), volatileStart)
                return NSValue(range: NSRange(location: clampedStart, length: max(0, clampedEnd - clampedStart)))
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, let storage = textView.textStorage else { return }
            // After a user edit in the committed region, volatile is still at
            // the trailing end. Recompute committedLength from storage length.
            committedLength = max(0, storage.length - volatileLength)
        }
    }
}

// MARK: - Custom NSTextView

final class VvoxEditableTextView: NSTextView {

    var editGatewayHandler: (() -> Void)?

    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(NSResponder.moveLeft(_:)):
            editGatewayHandler?()
            super.doCommand(by: #selector(NSResponder.moveWordLeftAndModifySelection(_:)))
        case #selector(NSResponder.moveRight(_:)):
            editGatewayHandler?()
            super.doCommand(by: #selector(NSResponder.moveWordRightAndModifySelection(_:)))
        case #selector(NSResponder.moveUp(_:)):
            editGatewayHandler?()
            super.doCommand(by: #selector(NSResponder.moveUpAndModifySelection(_:)))
        case #selector(NSResponder.moveDown(_:)):
            editGatewayHandler?()
            super.doCommand(by: #selector(NSResponder.moveDownAndModifySelection(_:)))
        case #selector(NSResponder.deleteBackward(_:)):
            editGatewayHandler?()
            if selectedRange().length == 0 {
                super.doCommand(by: #selector(NSResponder.deleteWordBackward(_:)))
            } else {
                super.doCommand(by: selector)
            }
        default:
            super.doCommand(by: selector)
        }
    }
}
