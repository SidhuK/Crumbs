//
//  PanelStyle.swift
//  Crumbs
//

import SwiftUI

enum PanelStyle {
    static let panelCornerRadius: CGFloat = 30
    static let horizontalInset: CGFloat = 12
    /// A light gray wash on the glass, so white cards stand out over any background.
    static let panelTint = NSColor(name: "CrumbsPanelTint") { @Sendable appearance in
        appearance.isDark
            ? NSColor(white: 0.12, alpha: 0.55)
            : NSColor(white: 0.80, alpha: 0.8)
    }

    static let cardFill = Color(nsColor: NSColor(name: "CrumbsCardFill") { @Sendable appearance in
        appearance.isDark
            ? NSColor(white: 1, alpha: 0.09)
            : NSColor(white: 1, alpha: 0.9)
    })
    static let cardShape = RoundedRectangle(cornerRadius: 16, style: .continuous)
}

enum NoteText {
    /// Renders inline Markdown (bold, italics, code, links) and keeps line breaks.
    static func attributed(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }
}

private extension NSAppearance {
    nonisolated var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
