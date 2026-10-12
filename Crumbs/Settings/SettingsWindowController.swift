//
//  SettingsWindowController.swift
//  Crumbs
//

import SwiftUI

/// The Settings window: a standard macOS preferences window with toolbar panes.
///
/// It's built with `NSTabViewController` (toolbar tab style) rather than SwiftUI's
/// `Settings` scene, because a menu bar app can't reliably open that scene from its
/// floating panel. Each pane is still a SwiftUI view.
final class SettingsWindowController {
    private let settings: AppSettings
    private let permission: AccessibilityPermission
    private let store: NotesStore
    private let actions: SettingsActions
    private var window: NSWindow?

    init(settings: AppSettings, permission: AccessibilityPermission, store: NotesStore, actions: SettingsActions) {
        self.settings = settings
        self.permission = permission
        self.store = store
        self.actions = actions
    }

    func show() {
        NSApp.activate()
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.crossfade, .allowUserInteraction]
        for pane in SettingsPane.allCases {
            tabs.addTabViewItem(makeItem(for: pane))
        }

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    private func makeItem(for pane: SettingsPane) -> NSTabViewItem {
        let controller = NSHostingController(rootView: paneView(for: pane))
        controller.sizingOptions = [.preferredContentSize]
        // The selected pane's title becomes the window title.
        controller.title = String(localized: pane.title)

        let item = NSTabViewItem(viewController: controller)
        item.label = String(localized: pane.title)
        item.image = NSImage(systemSymbolName: pane.systemImage, accessibilityDescription: String(localized: pane.title))
        return item
    }

    @ViewBuilder
    private func paneView(for pane: SettingsPane) -> some View {
        switch pane {
        case .general:
            GeneralSettingsPane(settings: settings, permission: permission)
        case .shortcuts:
            ShortcutSettingsPane(settings: settings, actions: actions)
        case .storage:
            StorageSettingsPane(settings: settings, store: store, actions: actions)
        }
    }
}

enum SettingsPane: CaseIterable {
    case general
    case shortcuts
    case storage

    var title: LocalizedStringResource {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        case .storage: "Storage"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "command"
        case .storage: "folder"
        }
    }
}
