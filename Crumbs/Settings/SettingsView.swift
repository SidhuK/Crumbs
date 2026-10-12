//
//  SettingsView.swift
//  Crumbs
//

import ServiceManagement
import SwiftUI

/// Actions the Settings window needs from the app.
struct SettingsActions {
    var chooseStorageFolder: () -> Void
    var resetStorageFolder: () -> Void
    var revealStorageFolder: () -> Void
    var setHotKeysSuspended: (Bool) -> Void
}

private enum SettingsLayout {
    static let width: CGFloat = 520
}

// MARK: - General

struct GeneralSettingsPane: View {
    @Bindable var settings: AppSettings
    let permission: AccessibilityPermission
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section {
                AppHeader()
            }

            Section("Capturing") {
                Toggle(isOn: $settings.showPanelOnCapture) {
                    Text("Show the panel after capturing")
                    Text("Bring the panel forward when it's hidden, so you can see what you saved.")
                }
            }

            Section("Notes") {
                Toggle(isOn: $settings.markDoneAfterCopyAsList) {
                    Text("Mark notes as done after Copy as List")
                    Text("Notes you send to a chat are checked off automatically.")
                }
                Toggle(isOn: $settings.hideDoneNotes) {
                    Text("Hide done notes")
                    Text("Done notes stay in your Markdown file until you clear them.")
                }
            }

            Section("System") {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { updateLaunchAtLogin() }
            }

            Section {
                PermissionRow(permission: permission)
            } header: {
                Text("Permissions")
            } footer: {
                Text("Accessibility access lets Crumbs notice the capture shortcut and copy your selection from other apps. Nothing leaves your Mac.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsLayout.width, height: 660)
        .onAppear {
            permission.refresh()
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func updateLaunchAtLogin() {
        let enabled = SMAppService.mainApp.status == .enabled
        guard launchAtLogin != enabled else { return }
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = enabled
        }
    }
}

private struct AppHeader: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Crumbs")
                    .font(.title2.weight(.semibold))
                Text("Save what you'll need later, from any app.")
                    .foregroundStyle(.secondary)
                Text("Version \(version)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct PermissionRow: View {
    let permission: AccessibilityPermission

    var body: some View {
        LabeledContent {
            if permission.isTrusted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Allow Access…") {
                    permission.request()
                    permission.openSystemSettings()
                }
            }
        } label: {
            Label {
                Text("Accessibility")
                Text(permission.isTrusted ? "Capturing works in every app." : "Required to capture text from other apps.")
            } icon: {
                Image(systemName: "accessibility")
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(.blue.gradient, in: .rect(cornerRadius: 6))
            }
        }
    }
}

// MARK: - Shortcuts

struct ShortcutSettingsPane: View {
    @Bindable var settings: AppSettings
    let actions: SettingsActions

    private let panelShortcuts: [(name: LocalizedStringResource, keys: [String])] = [
        ("Copy", ["⌘", "C"]),
        ("Copy as List", ["⇧", "⌘", "C"]),
        ("Mark as Done", ["Space"]),
        ("Edit", ["↩"]),
        ("Edit in New Window", ["⌘", "↩"]),
        ("Merge Notes", ["⇧", "⌘", "M"]),
        ("Move Up or Down", ["⌥", "⌘", "↑↓"]),
        ("Expand or Collapse", ["→", "←"]),
        ("Delete", ["⌫"]),
        ("Paste as Note", ["⌘", "V"]),
        ("New Note", ["⌘", "N"]),
        ("Search", ["⌘", "F"]),
        ("Undo", ["⌘", "Z"]),
        ("Hide Panel", ["Esc"]),
    ]

    var body: some View {
        Form {
            Section {
                Picker(selection: $settings.captureTrigger) {
                    ForEach(CaptureTrigger.allCases) { trigger in
                        Text(trigger.title).tag(trigger)
                    }
                } label: {
                    Text("Capture selection")
                    Text("Select text in any app, then tap the key twice.")
                }
                LabeledContent {
                    ShortcutRecorder(combo: $settings.togglePanelShortcut, onRecordingChange: actions.setHotKeysSuspended)
                } label: {
                    Text("Show or hide the panel")
                    Text("Works from any app.")
                }
            } header: {
                Text("Everywhere")
            }

            Section("In the Panel") {
                ForEach(panelShortcuts, id: \.keys) { shortcut in
                    LabeledContent {
                        Keycaps(keys: shortcut.keys)
                    } label: {
                        Text(shortcut.name)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsLayout.width, height: 620)
    }
}

/// Keys drawn as small keycaps, like the shortcut hints in macOS menus.
struct Keycaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(verbatim: key)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 22, minHeight: 20)
                    .padding(.horizontal, key.count > 1 ? 6 : 0)
                    .background(.background, in: .rect(cornerRadius: 5))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(.separator)
                    }
                    .shadow(color: .black.opacity(0.08), radius: 0, y: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.joined(separator: " "))
    }
}

/// Click, then press a key combination to set a global shortcut.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?
    var onRecordingChange: (Bool) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var closeObserver: NSObjectProtocol?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Group {
                    if isRecording {
                        Text("Type Shortcut…")
                            .foregroundStyle(.tint)
                    } else if let combo {
                        Keycaps(keys: combo.keycaps)
                    } else {
                        Text("Record Shortcut")
                    }
                }
                .frame(minWidth: 120, minHeight: 22)
            }
            .help(isRecording ? "Press a key combination, or Esc to cancel" : "Click to record a new shortcut")

            if combo != nil, !isRecording {
                Button("Clear Shortcut", systemImage: "xmark.circle.fill") {
                    combo = nil
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        // Only listen to the window the recorder lives in (Settings is key when its button is clicked).
        guard let window = NSApp.keyWindow else { return }
        isRecording = true
        onRecordingChange(true)

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === window else {
                // Typing anywhere else ends recording and goes through untouched.
                stopRecording()
                return event
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let character = event.charactersIgnoringModifiers?.lowercased()
            if flags == .command, character == "w" || character == "q" {
                // Keep ⌘W and ⌘Q working instead of recording them.
                stopRecording()
                return event
            }
            if event.keyCode == 53 { // Escape
                stopRecording()
            } else if let recorded = KeyCombo(event: event) {
                combo = recorded
                stopRecording()
            } else {
                NSSound.beep()
            }
            return nil
        }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            MainActor.assumeIsolated { stopRecording() }
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
        closeObserver = nil
        if isRecording {
            isRecording = false
            onRecordingChange(false)
        }
    }
}

// MARK: - Storage

struct StorageSettingsPane: View {
    let settings: AppSettings
    let store: NotesStore
    let actions: SettingsActions

    private var folderPath: String {
        settings.storageFolder.path(percentEncoded: false)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    HStack {
                        Button("Show in Finder", action: actions.revealStorageFolder)
                        Button("Change…", action: actions.chooseStorageFolder)
                    }
                } label: {
                    Label {
                        Text(settings.storageFolder.lastPathComponent)
                        Text(verbatim: (folderPath as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(folderPath)
                    } icon: {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: folderPath))
                            .resizable()
                            .frame(width: 32, height: 32)
                    }
                }
            } header: {
                Text("Notes Folder")
            } footer: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Each list is a plain Markdown file. Edit them in any app and Crumbs picks up the changes.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if settings.storageFolder != AppSettings.defaultStorageFolder {
                        Button("Use Default", action: actions.resetStorageFolder)
                            .controlSize(.small)
                    }
                }
            }

            Section("Lists") {
                ForEach(store.listNames, id: \.self) { name in
                    LabeledContent {
                        if name == store.listName {
                            Text("Open")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.tint)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.tint.opacity(0.12), in: .capsule)
                        }
                    } label: {
                        Label {
                            Text(verbatim: name)
                            Text(verbatim: "\(name).md")
                        } icon: {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsLayout.width, height: 380)
    }
}

#if DEBUG
private let previewActions = SettingsActions(
    chooseStorageFolder: {},
    resetStorageFolder: {},
    revealStorageFolder: {},
    setHotKeysSuspended: { _ in }
)

#Preview("General") {
    GeneralSettingsPane(settings: .preview(), permission: AccessibilityPermission(previewTrusted: true))
}

#Preview("Shortcuts") {
    ShortcutSettingsPane(settings: .preview(), actions: previewActions)
}

#Preview("Storage") {
    StorageSettingsPane(
        settings: .preview(),
        store: .preview(),
        actions: previewActions
    )
}
#endif
