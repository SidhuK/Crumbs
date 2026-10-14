//
//  AppSettings.swift
//  Crumbs
//

import AppKit

/// Which modifier key, tapped twice, captures the current selection.
nonisolated enum CaptureTrigger: String, CaseIterable, Identifiable, Sendable {
    case doubleShift
    case doubleCommand
    case doubleOption
    case doubleControl
    case off

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .doubleShift: "Shift + Shift"
        case .doubleCommand: "Command + Command"
        case .doubleOption: "Option + Option"
        case .doubleControl: "Control + Control"
        case .off: "Off"
        }
    }

    var symbol: String {
        switch self {
        case .doubleShift: "⇧⇧"
        case .doubleCommand: "⌘⌘"
        case .doubleOption: "⌥⌥"
        case .doubleControl: "⌃⌃"
        case .off: ""
        }
    }

    var modifier: NSEvent.ModifierFlags? {
        switch self {
        case .doubleShift: .shift
        case .doubleCommand: .command
        case .doubleOption: .option
        case .doubleControl: .control
        case .off: nil
        }
    }
}

/// User preferences, persisted in `UserDefaults`.
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    var captureTrigger: CaptureTrigger {
        didSet { defaults.set(captureTrigger.rawValue, forKey: Keys.captureTrigger) }
    }

    var togglePanelShortcut: KeyCombo? {
        didSet { defaults.set(try? JSONEncoder().encode(togglePanelShortcut), forKey: Keys.togglePanelShortcut) }
    }

    var showPanelOnCapture: Bool {
        didSet { defaults.set(showPanelOnCapture, forKey: Keys.showPanelOnCapture) }
    }

    /// Save the app, window title and link each capture came from with the note.
    var recordCaptureSource: Bool {
        didSet { defaults.set(recordCaptureSource, forKey: Keys.recordCaptureSource) }
    }

    var markDoneAfterCopyAsList: Bool {
        didSet { defaults.set(markDoneAfterCopyAsList, forKey: Keys.markDoneAfterCopyAsList) }
    }

    var hideDoneNotes: Bool {
        didSet { defaults.set(hideDoneNotes, forKey: Keys.hideDoneNotes) }
    }

    var storageFolder: URL {
        didSet { defaults.set(storageFolder.path(percentEncoded: false), forKey: Keys.storageFolder) }
    }

    var activeList: String {
        didSet { defaults.set(activeList, forKey: Keys.activeList) }
    }

    var hasPromptedForAccessibility: Bool {
        didSet { defaults.set(hasPromptedForAccessibility, forKey: Keys.hasPromptedForAccessibility) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        captureTrigger = defaults.string(forKey: Keys.captureTrigger).flatMap(CaptureTrigger.init) ?? .doubleShift
        // A stored `null` means the user cleared the shortcut; unreadable data falls back to the default.
        if let data = defaults.data(forKey: Keys.togglePanelShortcut),
           let stored = try? JSONDecoder().decode(KeyCombo?.self, from: data) {
            togglePanelShortcut = stored
        } else {
            togglePanelShortcut = .defaultTogglePanel
        }
        showPanelOnCapture = defaults.object(forKey: Keys.showPanelOnCapture) as? Bool ?? true
        recordCaptureSource = defaults.object(forKey: Keys.recordCaptureSource) as? Bool ?? true
        markDoneAfterCopyAsList = defaults.object(forKey: Keys.markDoneAfterCopyAsList) as? Bool ?? true
        hideDoneNotes = defaults.bool(forKey: Keys.hideDoneNotes)
        storageFolder = defaults.string(forKey: Keys.storageFolder).map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? Self.defaultStorageFolder
        activeList = defaults.string(forKey: Keys.activeList) ?? "Inbox"
        hasPromptedForAccessibility = defaults.bool(forKey: Keys.hasPromptedForAccessibility)
    }

    static var defaultStorageFolder: URL {
        URL.applicationSupportDirectory.appending(path: "Crumbs", directoryHint: .isDirectory)
    }

    private enum Keys {
        static let captureTrigger = "captureTrigger"
        static let togglePanelShortcut = "togglePanelShortcut"
        static let showPanelOnCapture = "showPanelOnCapture"
        static let recordCaptureSource = "recordCaptureSource"
        static let markDoneAfterCopyAsList = "markDoneAfterCopyAsList"
        static let hideDoneNotes = "hideDoneNotes"
        static let storageFolder = "storageFolder"
        static let activeList = "activeList"
        static let hasPromptedForAccessibility = "hasPromptedForAccessibility"
    }
}
