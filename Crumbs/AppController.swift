//
//  AppController.swift
//  Crumbs
//

import AppKit

/// Wires capture, hot keys, the panel and its windows together.
final class AppController {
    let settings = AppSettings()
    let permission = AccessibilityPermission()
    let store: NotesStore
    let model: PanelModel

    private let panelController: PanelController
    private let capturer = SelectionCapturer()
    private let doubleTapMonitor = ModifierDoubleTapMonitor()
    private let hud = CaptureHUD()
    private let noteWindows: NoteWindowManager
    private var settingsWindow: SettingsWindowController?
    private var isCapturing = false
    private var observationTasks: [Task<Void, Never>] = []
    /// The shortcut that is actually registered, restored if a new one can't be.
    private var activeShortcut: KeyCombo?

    private static let togglePanelHotKeyID: UInt32 = 1

    init() {
        store = NotesStore(folder: settings.storageFolder, listName: settings.activeList)
        model = PanelModel(store: store, settings: settings)
        panelController = PanelController(model: model, permission: permission)
        noteWindows = NoteWindowManager(store: store)
        model.host = self
    }

    /// UI tests drive the panel directly; they shouldn't install system-wide hooks on the test Mac.
    private var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("-uiTesting") }

    func start() {
        guard !isUITesting else {
            panelController.show(focus: false)
            return
        }
        doubleTapMonitor.trigger = settings.captureTrigger
        doubleTapMonitor.onDoubleTap = { [weak self] in self?.captureSelection() }
        doubleTapMonitor.start()
        registerHotKeys()
        observeChanges()

        if !permission.isTrusted {
            if settings.hasPromptedForAccessibility {
                permission.startPolling()
            } else {
                settings.hasPromptedForAccessibility = true
                permission.request()
            }
        }
        panelController.show(focus: false)
    }

    func showPanel() {
        panelController.show(focus: true)
    }

    func willTerminate() {
        observationTasks.forEach { $0.cancel() }
        store.saveNow()
    }

    // MARK: - Capture

    private func captureSelection() {
        // Shift-Shift while typing in the panel itself shouldn't copy from the panel.
        guard !isCapturing, !panelController.isKey else { return }
        isCapturing = true
        Task {
            defer { isCapturing = false }
            switch await capturer.captureSelection() {
            case .captured(let text):
                model.didCapture(text)
                if settings.showPanelOnCapture, !panelController.isVisible {
                    panelController.show(focus: false)
                }
                hud.show("Captured", icon: .asterisk)
            case .nothingSelected:
                hud.show("Nothing Selected", icon: .symbol("text.cursor"))
            case .permissionRequired:
                hud.show("Allow Accessibility Access", icon: .symbol("hand.raised.fill"))
                permission.request()
                panelController.show(focus: false)
            }
        }
    }

    // MARK: - Hot keys and settings

    private func registerHotKeys() {
        let combo = settings.togglePanelShortcut
        let registered = GlobalHotKeyCenter.shared.register(id: Self.togglePanelHotKeyID, combo: combo) { [weak self] in
            self?.panelController.toggle()
        }
        if registered {
            activeShortcut = combo
        } else if let combo {
            // Another app owns this combination: keep the previous shortcut and say why.
            hud.show("\(combo.keycaps.joined()) is used by another app", icon: .symbol("exclamationmark.triangle.fill"))
            settings.togglePanelShortcut = activeShortcut
        }
    }

    private func observeChanges() {
        let settings = settings
        let permission = permission
        observationTasks = [
            Task { [weak self] in
                for await trigger in Observations({ settings.captureTrigger }) {
                    guard let self else { return }
                    self.doubleTapMonitor.trigger = trigger
                }
            },
            Task { [weak self] in
                for await _ in Observations({ settings.togglePanelShortcut }) {
                    guard let self else { return }
                    self.registerHotKeys()
                }
            },
            Task { [weak self] in
                for await trusted in Observations({ permission.isTrusted }) where trusted {
                    guard let self else { return }
                    // Global monitors installed before access was granted never fire; reinstall.
                    self.doubleTapMonitor.start()
                }
            },
        ]
    }

    // MARK: - Storage

    private func chooseStorageFolder() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Use Folder")
        panel.message = String(localized: "Choose where Crumbs keeps its Markdown files.")
        panel.directoryURL = settings.storageFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setStorageFolder(url)
    }

    private func setStorageFolder(_ url: URL) {
        guard url != settings.storageFolder, store.setFolder(url) else { return }
        settings.storageFolder = url
        model.clearSelection()
    }

    private func makeSettingsWindow() -> SettingsWindowController {
        SettingsWindowController(
            settings: settings,
            permission: permission,
            store: store,
            actions: SettingsActions(
                chooseStorageFolder: { [weak self] in self?.chooseStorageFolder() },
                resetStorageFolder: { [weak self] in self?.setStorageFolder(AppSettings.defaultStorageFolder) },
                revealStorageFolder: { [weak self] in self?.revealListInFinder() },
                setHotKeysSuspended: { [weak self] suspended in
                    guard let self else { return }
                    if suspended {
                        GlobalHotKeyCenter.shared.unregister(id: Self.togglePanelHotKeyID)
                    } else {
                        self.registerHotKeys()
                    }
                }
            )
        )
    }
}

// MARK: - PanelHost

extension AppController: PanelHost {
    func hidePanel() {
        panelController.hide()
    }

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = makeSettingsWindow()
        }
        settingsWindow?.show()
    }

    func openEditorWindow(for noteID: Note.ID) {
        noteWindows.open(noteID)
    }

    func switchToList(_ name: String) {
        guard name != store.listName, store.switchToList(name) else { return }
        settings.activeList = name
        model.clearSelection()
        model.searchText = ""
    }

    func promptForNewList() {
        guard let input = Prompts.text(title: "New List", message: "Lists are saved as Markdown files.", confirmTitle: "Create")
        else { return }
        let name = Prompts.listFileName(input)
        guard !name.isEmpty else { return }
        // List names are file names, and the file system usually ignores letter case.
        if let existing = store.listNames.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            switchToList(existing)
            return
        }
        do {
            try store.createList(named: name)
            settings.activeList = name
            model.clearSelection()
            model.searchText = ""
        } catch {
            Prompts.error("Couldn't create the list.", error)
        }
        panelController.show(focus: true)
    }

    func promptToRenameList() {
        guard let input = Prompts.text(title: "Rename List", defaultValue: store.listName, confirmTitle: "Rename")
        else { return }
        let name = Prompts.listFileName(input)
        guard !name.isEmpty, name != store.listName else { return }
        do {
            try store.renameActiveList(to: name)
            settings.activeList = name
        } catch {
            Prompts.error("Couldn't rename the list.", error)
        }
        panelController.show(focus: true)
    }

    func confirmTrashList() {
        guard Prompts.confirm(
            title: "Move “\(store.listName)” to the Trash?",
            message: "You can restore the Markdown file from the Trash.",
            confirmTitle: "Move to Trash"
        ) else { return }
        do {
            try store.trashActiveList()
            settings.activeList = store.listName
            model.clearSelection()
        } catch {
            Prompts.error("Couldn't move the list to the Trash.", error)
        }
        panelController.show(focus: true)
    }

    func revealListInFinder() {
        store.saveNow()
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL ?? settings.storageFolder])
    }
}
