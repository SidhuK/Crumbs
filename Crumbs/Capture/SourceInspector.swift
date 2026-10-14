//
//  SourceInspector.swift
//  Crumbs
//

import AppKit

/// Reads where a capture is coming from: the frontmost app, its focused window's
/// title, and the web page or document shown there.
///
/// Uses the Accessibility access Crumbs already has, only at the moment of a capture,
/// and gives up quickly so a slow or hung app can't hold the capture up.
enum SourceInspector {
    /// The source as far as it's known before the copy, and the app to ask again afterwards.
    struct Inspection {
        var source: CaptureSource
        var processID: pid_t
    }

    /// How long a single Accessibility request may take before it's abandoned.
    private static let requestTimeout: Float = 0.25

    static func inspectFrontmostApp() -> Inspection? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier
        else { return nil }

        var source = CaptureSource(
            app: app.localizedName,
            bundleID: app.bundleIdentifier,
            capturedAt: NoteMetadata.now()
        )
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        if let window = element(appElement, kAXFocusedWindowAttribute) {
            source.title = string(window, kAXTitleAttribute).flatMap { $0.isEmpty ? nil : $0 }
            // Document windows (Preview, editors) and some browsers name what they show.
            source.url = url(window, kAXDocumentAttribute).flatMap(acceptable)
        }
        return Inspection(source: source, processID: app.processIdentifier)
    }

    /// Finds the page shown in a browser-style window by looking for its web area.
    /// Bounded in time and size, since some windows have very large element trees.
    static func webPageURL(processID: pid_t, budget: Duration = .milliseconds(300)) -> URL? {
        let appElement = AXUIElementCreateApplication(processID)
        guard let window = element(appElement, kAXFocusedWindowAttribute) else { return nil }

        let clock = ContinuousClock()
        let deadline = clock.now + budget
        var queue = [window]
        var visited = 0
        while !queue.isEmpty, visited < 600, clock.now < deadline {
            let node = queue.removeFirst()
            visited += 1
            if string(node, kAXRoleAttribute) == "AXWebArea" {
                // The first web area is the page itself; ones inside it are frames.
                if let found = url(node, kAXURLAttribute).flatMap(acceptable), !found.isFileURL {
                    return found
                }
                continue
            }
            queue.append(contentsOf: children(node))
        }
        return nil
    }

    /// Keeps links worth recording: web pages and local files, not app-internal schemes.
    static func acceptable(_ url: URL) -> URL? {
        switch url.scheme?.lowercased() {
        case "http", "https", "file": url
        default: nil
        }
    }

    // MARK: - Accessibility helpers

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, requestTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    private static func url(_ element: AXUIElement, _ attribute: String) -> URL? {
        let value = value(element, attribute)
        if let url = value as? URL { return url }
        if let string = value as? String, !string.isEmpty { return URL(string: string) }
        return nil
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        guard let value = value(element, kAXChildrenAttribute) as? [AnyObject] else { return [] }
        return value.compactMap { child in
            CFGetTypeID(child) == AXUIElementGetTypeID() ? (child as! AXUIElement) : nil
        }
    }
}
