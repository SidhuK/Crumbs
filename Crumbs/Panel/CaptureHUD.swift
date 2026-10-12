//
//  CaptureHUD.swift
//  Crumbs
//

import SwiftUI

/// A small pill that appears next to the pointer to confirm a capture.
final class CaptureHUD {
    private var window: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: LocalizedStringResource, systemImage: String) {
        AccessibilityNotification.Announcement(String(localized: message)).post()
        let hosting = NSHostingView(rootView: HUDPill(message: message, systemImage: systemImage))
        let size = hosting.fittingSize
        let window = self.window ?? makeWindow()
        window.contentView = hosting
        window.setFrame(frame(for: size), display: true)

        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            window.animator().alphaValue = 1
        }

        dismissTask?.cancel()
        dismissTask = Task { [weak window] in
            try? await Task.sleep(for: .seconds(1.1))
            guard !Task.isCancelled, let window else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                window.animator().alphaValue = 0
            }
            guard !Task.isCancelled else { return }
            window.orderOut(nil)
        }
    }

    private func makeWindow() -> NSPanel {
        let window = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        self.window = window
        return window
    }

    /// Just below and to the right of the pointer, kept on screen.
    private func frame(for size: NSSize) -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        var origin = NSPoint(x: mouse.x + 14, y: mouse.y - size.height - 14)
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        }
        return NSRect(origin: origin, size: size)
    }
}

private struct HUDPill: View {
    let message: LocalizedStringResource
    let systemImage: String

    var body: some View {
        Label {
            Text(message)
        } icon: {
            Image(systemName: systemImage)
        }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.black.opacity(0.85), in: .capsule)
            .padding(4)
            .fixedSize()
    }
}
