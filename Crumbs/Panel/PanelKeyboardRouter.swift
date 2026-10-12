//
//  PanelKeyboardRouter.swift
//  Crumbs
//

import AppKit
import Carbon.HIToolbox

/// Maps key presses in the panel to note commands. Runs before the event reaches
/// SwiftUI, so shortcuts work even though the app never becomes active.
struct PanelKeyboardRouter {
    let model: PanelModel
    let panel: NotesPanel

    /// Returns true when the event was handled and should be swallowed.
    func handle(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = Int(event.keyCode)
        let character = event.charactersIgnoringModifiers?.lowercased() ?? ""

        // Shortcuts available everywhere in the panel.
        switch (modifiers, character) {
        case (.command, "f"):
            model.focus(.search)
            return true
        case (.command, "n"):
            model.focus(.composer)
            return true
        case (.command, ","):
            model.host?.showSettings()
            return true
        case (.command, "w"):
            model.host?.hidePanel()
            return true
        default:
            break
        }

        // While an input method is composing (Japanese, Chinese…), Return confirms and
        // Escape cancels the composition; those keys belong to the text view.
        if let textView = panel.firstResponder as? NSTextView, textView.hasMarkedText() {
            return false
        }

        if key == kVK_Escape {
            if !model.handleEscape() { model.host?.hidePanel() }
            return true
        }

        if panel.firstResponder is NSText {
            // From the search field, ↓ or ↩ moves into the results.
            if model.focusedField == .search, modifiers.isEmpty, key == kVK_DownArrow || key == kVK_Return {
                model.focusList(selectFirst: true)
                return true
            }
            return false
        }

        return handleListKey(key: key, character: character, modifiers: modifiers)
    }

    private func handleListKey(key: Int, character: String, modifiers: NSEvent.ModifierFlags) -> Bool {
        let selection = model.orderedSelection

        switch key {
        case kVK_UpArrow, kVK_DownArrow:
            let delta = key == kVK_UpArrow ? -1 : 1
            if modifiers == [.option, .command] {
                model.shiftSelection(by: delta)
            } else {
                model.moveCursor(by: delta, extending: modifiers.contains(.shift))
            }
            return true
        case kVK_RightArrow where modifiers.isEmpty:
            model.setExpanded(selection, true)
            return true
        case kVK_LeftArrow where modifiers.isEmpty:
            model.setExpanded(selection, false)
            return true
        case kVK_Space where modifiers.isEmpty:
            model.toggleDone(selection)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if modifiers == .command, let first = selection.first {
                model.openInWindow(first)
            } else if modifiers.isEmpty {
                if let first = selection.first {
                    model.beginEditing(first)
                } else {
                    model.focus(.composer)
                }
            }
            return true
        case kVK_Delete, kVK_ForwardDelete:
            guard modifiers.isEmpty || modifiers == .command else { return false }
            model.delete(selection)
            return true
        default:
            break
        }

        switch (modifiers, character) {
        case (.command, "c"):
            model.copy(selection)
        case ([.command, .shift], "c"):
            model.copyAsList(selection)
        case ([.command, .shift], "m"):
            model.merge(selection)
        case (.command, "a"):
            model.selectAll()
        case (.command, "v"):
            model.paste()
        case (.command, "z"):
            model.undo()
        case ([.command, .shift], "z"):
            model.redo()
        default:
            return false
        }
        return true
    }
}
