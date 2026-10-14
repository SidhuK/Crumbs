//
//  PanelController.swift
//  Crumbs
//

import SwiftUI

/// Creates the floating notes panel and routes keyboard input to it.
final class PanelController {
    let panel: NotesPanel
    private let model: PanelModel
    private var keyMonitor: Any?
    private var resizeObserver: NSObjectProtocol?

    private static let frameName = "CrumbsNotesPanel"

    init(model: PanelModel, permission: AccessibilityPermission) {
        self.model = model
        panel = NotesPanel(contentRect: Self.defaultFrame())

        let hostingView = NSHostingView(
            rootView: PanelRootView()
                .environment(model)
                .environment(permission)
        )
        hostingView.sizingOptions = []

        let glass = NSGlassEffectView()
        glass.cornerRadius = PanelStyle.panelCornerRadius
        glass.tintColor = PanelStyle.panelTint
        glass.contentView = hostingView

        let container = RoundedContainerView(cornerRadius: PanelStyle.panelCornerRadius)
        glass.frame = container.bounds
        glass.autoresizingMask = [.width, .height]
        container.addSubview(glass)
        panel.contentView = container

        if !panel.setFrameUsingName(Self.frameName) {
            panel.setFrame(Self.defaultFrame(), display: false)
        }
        panel.setFrameAutosaveName(Self.frameName)

        installKeyMonitor()
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.panel.refreshShadow()
            }
        }
    }

    /// Floating keeps the panel above other apps' windows; otherwise it's layered like
    /// any other window, so clicking another app covers it until it's shown again.
    var keepsOnTop: Bool {
        get { panel.isFloatingPanel }
        set { panel.isFloatingPanel = newValue }
    }

    var isVisible: Bool { panel.isVisible }
    var isKey: Bool { panel.isKeyWindow }

    /// Shows the panel. With `focus`, it also takes keyboard input, without
    /// activating the app so the window you were reading stays in front.
    func show(focus: Bool) {
        if focus {
            panel.makeKeyAndOrderFront(nil)
            if model.focusedField == nil {
                panel.makeFirstResponder(nil)
            }
        } else {
            panel.orderFrontRegardless()
        }
        panel.refreshShadow()
    }

    func hide() {
        model.commitPendingEdit()
        panel.orderOut(nil)
    }

    func toggle() {
        if panel.isVisible && panel.isKeyWindow {
            hide()
        } else {
            show(focus: true)
        }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            let router = PanelKeyboardRouter(model: self.model, panel: self.panel)
            return router.handle(event) ? nil : event
        }
    }

    /// Tall and narrow, against the right edge of the main screen.
    private static func defaultFrame() -> NSRect {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 340, height: min(640, visible.height - 80))
        return NSRect(
            x: visible.maxX - size.width - 24,
            y: visible.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
