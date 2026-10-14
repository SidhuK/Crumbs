//
//  NoteRow.swift
//  Crumbs
//

import SwiftUI

struct NoteRow: View {
    let note: Note
    let isSelected: Bool
    let isExpanded: Bool
    let isEditing: Bool
    let isFlashing: Bool
    @FocusState.Binding var focus: PanelField?
    @Environment(PanelModel.self) private var model

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button(note.isDone ? "Mark as Not Done" : "Mark as Done",
                   systemImage: note.isDone ? "checkmark.circle.fill" : "circle") {
                model.toggleDone([note.id])
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.system(size: 15, weight: .light))
            .foregroundStyle(note.isDone ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .contentTransition(.symbolEffect(.replace))
            .animation(.smooth(duration: 0.2), value: note.isDone)

            if isEditing {
                NoteEditField(noteID: note.id, initialText: note.text, focus: $focus)
            } else {
                NoteContent(note: note, isExpanded: isExpanded, showsDetails: isExpanded || isSelected)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    // VoiceOver's default action selects, like a click.
                    .accessibilityAction { model.click(note.id, modifiers: [], clickCount: 1) }
                    .accessibilityAction(named: "Edit") { model.beginEditing(note.id) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelStyle.cardFill, in: PanelStyle.cardShape)
        .overlay {
            PanelStyle.cardShape
                .strokeBorder(.tint, lineWidth: 2)
                .opacity(isSelected || isEditing ? 1 : (isFlashing ? 0.55 : 0))
        }
        .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
        .contentShape(PanelStyle.cardShape)
        .onTapGesture {
            // A plain tap gesture so modifier keys and double clicks can be read.
            let event = NSApp.currentEvent
            model.click(note.id, modifiers: event?.modifierFlags ?? [], clickCount: event?.clickCount ?? 1)
        }
        .contextMenu {
            NoteContextMenu(noteID: note.id, isExpanded: isExpanded)
        }
        .animation(.smooth(duration: 0.2), value: isFlashing)
        .animation(.smooth(duration: 0.2), value: isExpanded)
        // Keep the checkbox, "more lines" button and editor as separate elements.
        .accessibilityElement(children: .contain)
    }
}

private struct NoteContent: View {
    let note: Note
    let isExpanded: Bool
    /// Shows where and when the note was captured, for the expanded or selected note.
    let showsDetails: Bool
    @Environment(PanelModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(NoteText.attributed(isExpanded ? note.text : note.title))
                .font(.system(size: 13))
                .lineSpacing(2)
                .lineLimit(isExpanded ? nil : 3)
                .strikethrough(note.isDone)
                .foregroundStyle(note.isDone ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if showsDetails, let details = detailsCaption {
                Text(verbatim: details)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(note.metadata.sources.first?.title ?? "")
            }

            if note.isMultiline {
                Button {
                    model.toggleExpanded(note.id)
                } label: {
                    Text(isExpanded ? "Show Less" : moreLinesLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var moreLinesLabel: LocalizedStringResource {
        "\(note.extraLineCount) more lines"
    }

    /// "Safari · example.com · Oct 14, 2026 at 12:41 PM · Edited Oct 15, 2026 at 9:02 AM"
    private var detailsCaption: String? {
        let metadata = note.metadata
        var parts: [String] = []
        if let label = metadata.sources.first?.label {
            let others = metadata.sources.count - 1
            parts.append(others > 0 ? "\(label) +\(others)" : label)
        }
        if let created = metadata.created ?? metadata.sources.first?.capturedAt {
            parts.append(created.formatted(date: .abbreviated, time: .shortened))
        }
        if let modified = metadata.modified {
            parts.append(String(localized: "Edited \(modified.formatted(date: .abbreviated, time: .shortened))"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private struct NoteEditField: View {
    let noteID: Note.ID
    @FocusState.Binding var focus: PanelField?
    @Environment(PanelModel.self) private var model
    @State private var draft: String

    /// `initialText` only seeds the draft when editing begins.
    init(noteID: Note.ID, initialText: String, focus: FocusState<PanelField?>.Binding) {
        self.noteID = noteID
        self._focus = focus
        self.draft = initialText
    }

    var body: some View {
        TextField("Note", text: $draft, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .lineLimit(1...14)
            .focused($focus, equals: .noteEditor)
            .onSubmit { model.commitEdit(draft) }
            .onChange(of: draft) { model.editDraft = draft }
            .onChange(of: focus) { old, new in
                // Clicking elsewhere saves the edit.
                if old == .noteEditor, new != .noteEditor, model.editingNoteID == noteID {
                    model.commitEdit(draft)
                }
            }
    }
}

struct NoteContextMenu: View {
    let noteID: Note.ID
    let isExpanded: Bool
    @Environment(PanelModel.self) private var model

    var body: some View {
        let targets = model.targets(for: noteID)
        let notes = targets.compactMap(model.store.note)
        let allDone = !notes.isEmpty && notes.allSatisfy(\.isDone)

        Button("Copy") { model.copy(targets) }
            .keyboardShortcut("c", modifiers: .command)
        Button("Copy as List") { model.copyAsList(targets) }
            .keyboardShortcut("c", modifiers: [.command, .shift])

        if let sourceURL = model.store.note(noteID)?.metadata.sources.lazy.compactMap(\.url).first {
            Divider()

            Button("Open Source") { model.openSource(sourceURL) }
            Button("Copy Source Link") { model.copySourceLink(sourceURL) }
        }

        Divider()

        Button(allDone ? "Mark as Not Done" : "Mark as Done") { model.toggleDone(targets) }
            .keyboardShortcut(.space, modifiers: [])
        Button(isExpanded ? "Collapse" : "Expand") { model.toggleExpanded(noteID) }
            .disabled(model.store.note(noteID)?.isMultiline != true)

        Divider()

        Button("Edit") { model.beginEditing(noteID) }
            .keyboardShortcut(.return, modifiers: [])
        Button("Edit in New Window") { model.openInWindow(noteID) }
            .keyboardShortcut(.return, modifiers: .command)
        Button("Merge Notes") { model.merge(targets) }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(targets.count < 2)
        Menu("Move to") {
            ForEach(model.store.sections) { section in
                Button {
                    model.move(targets, toSection: section.id)
                } label: {
                    if section.title.isEmpty {
                        Text("No Section")
                    } else {
                        Text(verbatim: section.title)
                    }
                }
                .disabled(notes.allSatisfy { model.store.section(containing: $0.id)?.id == section.id })
            }
            Divider()
            Button("New Section…") { model.moveToNewSection(targets) }
        }

        Divider()

        Button("Delete", role: .destructive) { model.delete(targets) }
            .keyboardShortcut(.delete, modifiers: [])
    }
}
