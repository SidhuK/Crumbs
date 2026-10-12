//
//  ModifierDoubleTapMonitor.swift
//  Crumbs
//

import AppKit

/// Watches system-wide input for a modifier key tapped twice on its own
/// (for example Shift, Shift). Requires Accessibility access.
final class ModifierDoubleTapMonitor {
    var trigger: CaptureTrigger = .doubleShift {
        didSet { reset() }
    }

    var onDoubleTap: () -> Void = {}

    /// How long a single tap may be held down.
    private let maximumTapDuration: TimeInterval = 0.35
    /// Maximum gap between the release of the first tap and the release of the second.
    private let maximumTapGap: TimeInterval = 0.45

    private var monitor: Any?
    private var pressStartedAt: TimeInterval?
    private var lastTapAt: TimeInterval?

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [
            .flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel,
        ]
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(type: event.type, flags: event.modifierFlags, timestamp: event.timestamp)
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        reset()
    }

    private func reset() {
        pressStartedAt = nil
        lastTapAt = nil
    }

    /// Feeds one input event to the detector. Internal so tests can drive it directly.
    func handle(type: NSEvent.EventType, flags: NSEvent.ModifierFlags, timestamp: TimeInterval) {
        guard let target = trigger.modifier else { return }
        guard type == .flagsChanged else {
            // Any other input between taps (typing, clicking) cancels the gesture.
            reset()
            return
        }

        let held = flags.intersection([.shift, .command, .option, .control, .function])
        if held == target {
            if pressStartedAt == nil { pressStartedAt = timestamp }
        } else if held.isEmpty {
            defer { pressStartedAt = nil }
            guard let start = pressStartedAt, timestamp - start <= maximumTapDuration else {
                lastTapAt = nil
                return
            }
            if let last = lastTapAt, timestamp - last <= maximumTapGap {
                lastTapAt = nil
                onDoubleTap()
            } else {
                lastTapAt = timestamp
            }
        } else {
            // A chord such as Shift+Command is not a tap.
            reset()
        }
    }
}
