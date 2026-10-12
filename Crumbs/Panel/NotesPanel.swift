//
//  NotesPanel.swift
//  Crumbs
//

import SwiftUI

/// A floating, non-activating panel: it can take keyboard focus without pulling
/// the app you're reading out of the foreground.
final class NotesPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .utilityWindow
        minSize = NSSize(width: 280, height: 320)
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func becomeKey() {
        let hadFocus = firstResponder !== self
        super.becomeKey()
        // On first focus AppKit picks the first text field (search). Start on the list instead,
        // so arrow keys and Space work right away. A click into a field still focuses it.
        if !hadFocus, firstResponder is NSText {
            makeFirstResponder(nil)
        }
    }

    /// Recomputes the drop shadow from the rounded content. Without this the shadow
    /// keeps the shape of whatever was drawn first, leaving gray corners.
    func refreshShadow() {
        Task { [weak self] in
            await Task.yield()
            self?.invalidateShadow()
        }
    }
}

/// Clips the panel to its rounded shape, so the window (and its shadow) has no square corners.
final class RoundedContainerView: NSView {
    init(cornerRadius: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isOpaque: Bool { false }
}

/// Lets SwiftUI content act as a handle for dragging its borderless window.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
