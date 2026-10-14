//
//  SelectionCapturer.swift
//  Crumbs
//

import AppKit
import Carbon.HIToolbox

/// Grabs the current selection from whichever app is frontmost.
///
/// It sends that app a Copy command, reads the rich text it puts on the pasteboard,
/// then puts the user's original clipboard back. If the app ignores Copy, it falls
/// back to the Accessibility "selected text" attribute.
///
/// When asked, it also notes where the selection came from (see `SourceInspector`).
final class SelectionCapturer {
    struct Capture {
        var text: String
        var source: CaptureSource?
    }

    enum Outcome {
        case captured(Capture)
        case nothingSelected
        case permissionRequired
    }

    func captureSelection(recordSource: Bool) async -> Outcome {
        guard AXIsProcessTrusted() else { return .permissionRequired }

        // Read before copying, while the source app is certainly the one in front.
        var inspection = recordSource ? SourceInspector.inspectFrontmostApp() : nil

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        let initialChangeCount = pasteboard.changeCount

        postCopyShortcut()

        var didCopy = false
        for _ in 0..<50 {
            try? await Task.sleep(for: .milliseconds(10))
            if Task.isCancelled { break }
            if pasteboard.changeCount != initialChangeCount {
                didCopy = true
                break
            }
        }

        var text: String?
        if didCopy {
            // Some apps clear the pasteboard and write each flavor separately.
            try? await Task.sleep(for: .milliseconds(40))
            let clipping = RichTextMarkdown.Clipping(pasteboard)
            // Restore before converting: HTML import spins the run loop, and nothing else
            // should see the copied selection in place of the user's clipboard meanwhile.
            snapshot.restore(to: pasteboard)
            text = RichTextMarkdown.markdown(from: clipping)
            // A page URL the browser put on the pasteboard is the most reliable link.
            if let sourceURL = clipping.sourceURL.flatMap(SourceInspector.acceptable) {
                inspection?.source.url = sourceURL
            }
        } else {
            restoreIfCopiedLate(snapshot, changeCount: initialChangeCount, pasteboard: pasteboard)
        }

        if text?.isEmpty ?? true {
            text = Self.accessibilitySelectedText().map(RichTextMarkdown.normalizePlainText)
        }

        guard let text, !text.isEmpty else { return .nothingSelected }
        if var found = inspection, found.source.url == nil {
            found.source.url = SourceInspector.webPageURL(processID: found.processID)
            inspection = found
        }
        return .captured(Capture(text: text, source: inspection?.source))
    }

    /// A slow app may still answer the synthetic ⌘C after we stopped waiting. Watch a
    /// little longer and put the user's clipboard back if it does.
    private func restoreIfCopiedLate(_ snapshot: PasteboardSnapshot, changeCount: Int, pasteboard: NSPasteboard) {
        Task {
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(50))
                if Task.isCancelled { return }
                if pasteboard.changeCount != changeCount {
                    snapshot.restore(to: pasteboard)
                    return
                }
            }
        }
    }

    // MARK: - Synthetic ⌘C

    private func postCopyShortcut() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode = Self.keyCode(for: "c") ?? CGKeyCode(kVK_ANSI_C)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    /// Finds the key that types `character` in the current keyboard layout, so ⌘C
    /// still means Copy on layouts such as Dvorak.
    private static func keyCode(for character: Character) -> CGKeyCode? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { buffer -> CGKeyCode? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            for keyCode in 0..<CGKeyCode(128) {
                var deadKeyState: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length, &characters
                )
                if status == noErr, length > 0,
                   String(utf16CodeUnits: characters, count: length).lowercased() == String(character) {
                    return keyCode
                }
            }
            return nil
        }
    }

    // MARK: - Accessibility fallback

    private static func accessibilitySelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }

        let element = focused as! AXUIElement
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success else {
            return nil
        }
        return selected as? String
    }
}

/// A copy of every item and flavor on a pasteboard, so it can be put back untouched.
private struct PasteboardSnapshot {
    private let items: [[(NSPasteboard.PasteboardType, Data)]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            }
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.map { flavors in
            let item = NSPasteboardItem()
            for (type, data) in flavors {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restored.isEmpty {
            pasteboard.writeObjects(restored)
        }
    }
}
