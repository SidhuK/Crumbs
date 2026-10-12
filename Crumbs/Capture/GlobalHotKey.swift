//
//  GlobalHotKey.swift
//  Crumbs
//

import AppKit
import Carbon.HIToolbox

/// A recorded keyboard shortcut, stored with the label shown to the user.
nonisolated struct KeyCombo: Codable, Equatable, Sendable {
    var keyCode: UInt16
    var modifiers: UInt
    var keyLabel: String

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection([.command, .option, .control, .shift])
    }

    /// Each modifier and the key as separate labels, for drawing keycaps.
    var keycaps: [String] {
        let flags = modifierFlags
        var result: [String] = []
        if flags.contains(.control) { result.append("⌃") }
        if flags.contains(.option) { result.append("⌥") }
        if flags.contains(.shift) { result.append("⇧") }
        if flags.contains(.command) { result.append("⌘") }
        return result + [keyLabel]
    }

    var carbonModifiers: UInt32 {
        let flags = modifierFlags
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    static let defaultTogglePanel = KeyCombo(
        keyCode: UInt16(kVK_ANSI_C),
        modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue,
        keyLabel: "C"
    )

    /// Builds a combo from a key event, or returns nil when the event lacks a modifier.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let isFunctionKey = Self.functionKeyLabels[Int(event.keyCode)] != nil
        guard !flags.subtracting(.shift).isEmpty || isFunctionKey else { return nil }
        self.keyCode = event.keyCode
        self.modifiers = flags.rawValue
        self.keyLabel = Self.label(for: event)
    }

    init(keyCode: UInt16, modifiers: UInt, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    private static func label(for event: NSEvent) -> String {
        if let special = specialKeyLabels[Int(event.keyCode)] ?? functionKeyLabels[Int(event.keyCode)] {
            return special
        }
        let characters = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers ?? "?"
        return characters.uppercased()
    }

    private static let specialKeyLabels: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]

    private static let functionKeyLabels: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]
}

/// Registers system-wide hot keys through Carbon, which needs no extra permission.
final class GlobalHotKeyCenter {
    static let shared = GlobalHotKeyCenter()

    private var registrations: [UInt32: (ref: EventHotKeyRef, action: () -> Void)] = [:]
    private var handlerInstalled = false
    private static let signature: OSType = 0x4352_4D42 // "CRMB"

    private init() {}

    /// Registers `combo` under `id`, replacing any previous registration with that id.
    /// The previous registration is only released once the new one succeeds, so a combo
    /// that's taken by another app leaves the old shortcut working.
    func register(id: UInt32, combo: KeyCombo?, action: @escaping () -> Void) -> Bool {
        guard let combo else {
            unregister(id: id)
            return true
        }
        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            UInt32(combo.keyCode), combo.carbonModifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else { return false }
        unregister(id: id)
        registrations[id] = (ref, action)
        return true
    }

    func unregister(id: UInt32) {
        if let existing = registrations.removeValue(forKey: id) {
            UnregisterEventHotKey(existing.ref)
        }
    }

    fileprivate func fire(id: UInt32) {
        registrations[id]?.action()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        handlerInstalled = InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &eventType, nil, nil) == noErr
    }
}

/// Carbon delivers hot key events on the main thread.
private nonisolated func hotKeyEventHandler(
    _ handler: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
    )
    guard status == noErr else { return status }
    let id = hotKeyID.id
    MainActor.assumeIsolated {
        GlobalHotKeyCenter.shared.fire(id: id)
    }
    return noErr
}
