//
//  AccessibilityPermission.swift
//  Crumbs
//

import AppKit

/// Tracks whether Crumbs may watch for the capture shortcut and copy from other apps.
@Observable
final class AccessibilityPermission {
    private(set) var isTrusted: Bool
    /// Fixed state for previews, which must not depend on this Mac's settings.
    private let isFixed: Bool

    init() {
        isTrusted = AXIsProcessTrusted()
        isFixed = false
    }

    init(previewTrusted: Bool) {
        isTrusted = previewTrusted
        isFixed = true
    }

    @ObservationIgnored private var pollTask: Task<Void, Never>?

    /// Shows the system prompt that adds Crumbs to the Accessibility list.
    func request() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        startPolling()
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        startPolling()
    }

    func refresh() {
        guard !isFixed else { return }
        isTrusted = AXIsProcessTrusted()
    }

    /// Polls until access is granted. macOS posts no reliable notification for this change.
    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                let trusted = AXIsProcessTrusted()
                if trusted != self.isTrusted { self.isTrusted = trusted }
                if trusted {
                    self.pollTask = nil
                    return
                }
            }
        }
    }
}
