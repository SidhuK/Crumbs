//
//  NotesMarkdown.swift
//  Crumbs
//

import Foundation

/// Reads and writes a list as a plain Markdown file:
///
///     ## Research
///
///     - [ ] **Negation in inherited configs.** The moment a config…
///     - [x] Three things worth locking down before it ships:
///       1. A `version` field on the format.
///       <!-- crumb {"created":"2026-10-14T12:41:00-04:00"} -->
///
/// Headings become sections, task items become notes, and lines indented by
/// two spaces continue the note above them. A note's last line may be a hidden
/// comment holding its `NoteMetadata`.
nonisolated enum NotesMarkdown {
    static let continuationIndent = "  "

    static func parse(_ source: String) -> [NoteSection] {
        let lines = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var sections: [NoteSection] = []
        var pendingLines: [String]?
        var pendingDone = false

        func flushNote() {
            guard var noteLines = pendingLines else { return }
            pendingLines = nil
            // A metadata comment is only recognized as the last line of a note with text above it.
            var metadata = NoteMetadata()
            if noteLines.count > 1, let last = noteLines.last, let parsed = NoteMetadata(markdownComment: last) {
                metadata = parsed
                noteLines.removeLast()
            }
            let text = noteLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            if sections.isEmpty {
                sections.append(NoteSection(title: ""))
            }
            sections[sections.count - 1].notes.append(Note(text: text, isDone: pendingDone, metadata: metadata))
        }

        func startNote(_ firstLine: String, done: Bool) {
            flushNote()
            pendingLines = [firstLine]
            pendingDone = done
        }

        var index = 0
        while index < lines.count {
            let line = lines[index]
            defer { index += 1 }

            if pendingLines != nil {
                if line.hasPrefix(continuationIndent) {
                    pendingLines?.append(String(line.dropFirst(continuationIndent.count)))
                    continue
                }
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    // A blank line only belongs to the note if indented text follows it.
                    let next = lines[(index + 1)...].first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    if let next, next.hasPrefix(continuationIndent) {
                        pendingLines?.append("")
                    } else {
                        flushNote()
                    }
                    continue
                }
                flushNote()
            }

            if let heading = headingTitle(line) {
                flushNote()
                sections.append(NoteSection(title: heading))
            } else if let (body, done) = taskItem(line) {
                startNote(body, done: done)
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                startNote(line.trimmingCharacters(in: .whitespaces), done: false)
            }
        }
        flushNote()
        return sections
    }

    static func serialize(_ sections: [NoteSection]) -> String {
        // Untitled sections must come first or they would merge into the heading above on reload.
        let ordered = sections.filter { $0.title.isEmpty } + sections.filter { !$0.title.isEmpty }
        var blocks: [String] = []
        for section in ordered {
            var block: [String] = []
            if !section.title.isEmpty {
                block.append("## \(section.title)")
                if !section.notes.isEmpty { block.append("") }
            }
            for note in section.notes {
                block.append(contentsOf: lines(for: note))
            }
            if !block.isEmpty { blocks.append(block.joined(separator: "\n")) }
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    private static func lines(for note: Note) -> [String] {
        let noteLines = note.text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = noteLines.first else { return [] }
        var result = ["- [\(note.isDone ? "x" : " ")] \(first)"]
        for line in noteLines.dropFirst() {
            result.append(line.isEmpty ? "" : continuationIndent + line)
        }
        if let comment = note.metadata.markdownComment {
            result.append(continuationIndent + comment)
        }
        return result
    }

    private static func headingTitle(_ line: String) -> String? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix { $0 == "#" }
        guard hashes.count <= 6 else { return nil }
        let rest = line.dropFirst(hashes.count)
        guard rest.first == " " else { return nil }
        return rest.trimmingCharacters(in: .whitespaces)
    }

    private static func taskItem(_ line: String) -> (String, Bool)? {
        guard line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") else { return nil }
        let rest = line.dropFirst(2)
        for (marker, done) in [("[ ] ", false), ("[x] ", true), ("[X] ", true)] where rest.hasPrefix(marker) {
            return (String(rest.dropFirst(marker.count)), done)
        }
        for marker in ["[ ]", "[x]", "[X]"] where rest == marker {
            return ("", marker != "[ ]")
        }
        return (String(rest), false)
    }
}
