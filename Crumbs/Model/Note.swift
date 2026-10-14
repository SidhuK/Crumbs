//
//  Note.swift
//  Crumbs
//

import Foundation

/// A single captured crumb. `text` is Markdown; the first line acts as the title.
nonisolated struct Note: Identifiable, Hashable, Sendable {
    private(set) var id: UUID
    var text: String
    var isDone: Bool

    init(id: UUID = UUID(), text: String, isDone: Bool = false) {
        self.id = id
        self.text = text
        self.isDone = isDone
    }

    /// The first line of the note.
    var title: String {
        String(text.prefix { $0 != "\n" })
    }

    /// Number of lines after the first one. Note text is trimmed, so there are no trailing blank lines.
    var extraLineCount: Int {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return max(0, lines.count - 1)
    }

    var isMultiline: Bool { extraLineCount > 0 }

    /// A copy with a different identity and every other field unchanged, so callers that
    /// re-identify notes (reconciling a reloaded file) never drop fields added later.
    func withID(_ id: UUID) -> Note {
        var copy = self
        copy.id = id
        return copy
    }
}

/// A titled group of notes. Only the first section of a list may be untitled.
nonisolated struct NoteSection: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var notes: [Note]

    init(id: UUID = UUID(), title: String, notes: [Note] = []) {
        self.id = id
        self.title = title
        self.notes = notes
    }
}
