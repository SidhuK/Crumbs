//
//  Prompts.swift
//  Crumbs
//

import AppKit

/// Small modal prompts for the rare actions that need typed input or confirmation.
enum Prompts {
    static func text(
        title: LocalizedStringResource,
        message: LocalizedStringResource? = nil,
        defaultValue: String = "",
        confirmTitle: LocalizedStringResource
    ) -> String? {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: title)
        alert.informativeText = message.map { String(localized: $0) } ?? ""
        alert.addButton(withTitle: String(localized: confirmTitle))
        alert.addButton(withTitle: String(localized: "Cancel"))

        let field = NSTextField(string: defaultValue)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func confirm(
        title: LocalizedStringResource,
        message: LocalizedStringResource,
        confirmTitle: LocalizedStringResource
    ) -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: title)
        alert.informativeText = String(localized: message)
        alert.addButton(withTitle: String(localized: confirmTitle))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func error(_ title: LocalizedStringResource, _ error: Error) {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: title)
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    /// Turns user input into a safe file name for a list.
    static func listFileName(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
    }
}
