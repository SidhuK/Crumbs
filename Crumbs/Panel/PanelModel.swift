//
//  PanelModel.swift
//  Crumbs
//

import AppKit

/// Text inputs inside the panel that can hold keyboard focus.
enum PanelField: Hashable {
    case search
    case composer
    case noteEditor
    case sectionTitle
}

/// Actions the panel asks its window controller to perform.
protocol PanelHost: AnyObject {
    func hidePanel()
    func showSettings()
    func openEditorWindow(for noteID: Note.ID)
    func switchToList(_ name: String)
    func promptForNewList()
    func promptToRenameList()
    func confirmTrashList()
    func revealListInFinder()
}

struct PanelToast: Equatable, Identifiable {
    let id = UUID()
    var message: LocalizedStringResource
    var systemImage: String
}

/// A section as currently shown, after search and done-filtering.
struct VisibleSection: Identifiable {
    var section: NoteSection
    var notes: [Note]
    var id: NoteSection.ID { section.id }
}

/// UI state and commands for the floating panel. Selection, editing and focus live
/// here; the notes themselves live in `NotesStore`.
@Observable
final class PanelModel {
    let store: NotesStore
    let settings: AppSettings
    @ObservationIgnored weak var host: PanelHost?
    @ObservationIgnored var pasteboard: NSPasteboard = .general

    var selection: Set<Note.ID> = []
    var expanded: Set<Note.ID> = []
    private(set) var editingNoteID: Note.ID?
    /// The inline editor's current text, so it can be saved when the panel hides.
    @ObservationIgnored var editDraft = ""
    private(set) var renamingSectionID: NoteSection.ID?
    var searchText = ""
    var composerText = ""

    /// Mirrors the view's focus so keyboard routing knows where typing goes.
    var focusedField: PanelField?
    /// Bumped to ask the view to move focus; `nil` means the note list.
    private(set) var focusRequest = FocusRequest(field: nil)
    private(set) var scrollRequest: ScrollRequest?
    private(set) var toast: PanelToast?
    private(set) var flashedNoteID: Note.ID?

    @ObservationIgnored private var anchorID: Note.ID?
    @ObservationIgnored private var cursorID: Note.ID?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var flashTask: Task<Void, Never>?

    struct FocusRequest: Equatable {
        var field: PanelField?
        var token = UUID()
    }

    struct ScrollRequest: Equatable {
        var noteID: Note.ID
        var token = UUID()
    }

    init(store: NotesStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        store.onIssue = { [weak self] issue in
            switch issue {
            case .saveFailed:
                self?.showToast("Couldn’t save your notes", systemImage: "exclamationmark.triangle.fill")
            case .readFailed(let list, _):
                self?.showToast("Couldn’t read \(list).md. It was left untouched.", systemImage: "exclamationmark.triangle.fill")
            case .conflictCopySaved(let name):
                self?.showToast("Edited elsewhere too. Saved \(name).md", systemImage: "doc.on.doc")
            }
        }
    }

    // MARK: - Derived state

    var visibleSections: [VisibleSection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hideDone = settings.hideDoneNotes
        return store.sections.compactMap { section in
            let notes = section.notes.filter { note in
                (!hideDone || !note.isDone) && (query.isEmpty || note.text.localizedStandardContains(query))
            }
            if !query.isEmpty && notes.isEmpty { return nil }
            return VisibleSection(section: section, notes: notes)
        }
    }

    var visibleNoteIDs: [Note.ID] {
        visibleSections.flatMap { $0.notes.map(\.id) }
    }

    var orderedSelection: [Note.ID] {
        store.ordered(selection)
    }

    /// The active list, as a bindable property for the list picker.
    var activeListName: String {
        get { store.listName }
        set { host?.switchToList(newValue) }
    }

    var composerPlaceholder: LocalizedStringResource {
        "Add a note or a prompt (\(store.listName))"
    }

    /// The notes a context-menu command applies to: the selection if the clicked
    /// note is part of it, otherwise just that note.
    func targets(for noteID: Note.ID) -> [Note.ID] {
        selection.contains(noteID) ? orderedSelection : [noteID]
    }

    // MARK: - Focus

    func focus(_ field: PanelField?) {
        focusRequest = FocusRequest(field: field)
    }

    func focusList(selectFirst: Bool = false) {
        focus(nil)
        if selectFirst, selection.isEmpty, let first = visibleNoteIDs.first {
            select(only: first)
        }
    }

    // MARK: - Selection

    func click(_ noteID: Note.ID, modifiers: NSEvent.ModifierFlags, clickCount: Int) {
        // Clicks inside the note being edited belong to its text field.
        if editingNoteID == noteID { return }
        // Clicking another note saves the one being edited.
        commitPendingEdit()
        if focusedField != nil { focus(nil) }

        if clickCount >= 2, !modifiers.contains(.command), !modifiers.contains(.shift) {
            select(only: noteID)
            beginEditing(noteID)
            return
        }
        if modifiers.contains(.command) {
            if selection.contains(noteID) {
                selection.remove(noteID)
            } else {
                selection.insert(noteID)
            }
            anchorID = noteID
            cursorID = noteID
        } else if modifiers.contains(.shift), let anchorID {
            selectRange(from: anchorID, to: noteID)
            cursorID = noteID
        } else {
            select(only: noteID)
        }
    }

    func select(only noteID: Note.ID) {
        selection = [noteID]
        anchorID = noteID
        cursorID = noteID
    }

    func selectAll() {
        selection = Set(visibleNoteIDs)
        anchorID = visibleNoteIDs.first
        cursorID = visibleNoteIDs.last
    }

    func clearSelection() {
        selection.removeAll()
        anchorID = nil
        cursorID = nil
    }

    func moveCursor(by delta: Int, extending: Bool) {
        let ids = visibleNoteIDs
        guard !ids.isEmpty else { return }
        let current = cursorID.flatMap { ids.firstIndex(of: $0) }
        let next: Int
        if let current {
            next = min(max(current + delta, 0), ids.count - 1)
        } else {
            next = delta > 0 ? 0 : ids.count - 1
        }
        let nextID = ids[next]
        if extending, let anchorID, ids.contains(anchorID) {
            selectRange(from: anchorID, to: nextID)
            cursorID = nextID
        } else {
            select(only: nextID)
        }
        scroll(to: nextID)
    }

    private func selectRange(from start: Note.ID, to end: Note.ID) {
        let ids = visibleNoteIDs
        guard let a = ids.firstIndex(of: start), let b = ids.firstIndex(of: end) else { return }
        selection = Set(ids[min(a, b)...max(a, b)])
    }

    private func scroll(to noteID: Note.ID) {
        scrollRequest = ScrollRequest(noteID: noteID)
    }

    /// Drops state for notes that no longer exist, and limits the selection to notes that
    /// are visible, so commands never act on notes hidden by search or "Hide Done".
    func pruneState() {
        let existing = Set(store.allNotes.map(\.id))
        let visible = Set(visibleNoteIDs)
        if !selection.isSubset(of: visible) { selection.formIntersection(visible) }
        if let anchorID, !visible.contains(anchorID) { self.anchorID = nil }
        if let cursorID, !visible.contains(cursorID) { self.cursorID = nil }
        if !expanded.isSubset(of: existing) { expanded.formIntersection(existing) }
        if let editingNoteID, !existing.contains(editingNoteID) { self.editingNoteID = nil }
    }

    // MARK: - Commands

    func copy(_ ids: [Note.ID]) {
        let notes = store.ordered(ids).compactMap(store.note)
        guard !notes.isEmpty else { return }
        writeToPasteboard(notes.map(\.text).joined(separator: "\n\n"))
        showToast("Copied \(notes.count) Notes", systemImage: "doc.on.doc")
    }

    /// Copies notes as a numbered list, ready to paste into a chat.
    func copyAsList(_ ids: [Note.ID]) {
        let ordered = store.ordered(ids)
        let notes = ordered.compactMap(store.note)
        guard !notes.isEmpty else {
            showToast("Select notes to copy", systemImage: "info.circle")
            return
        }
        let list = notes.enumerated().map { index, note in
            let lines = note.text.split(separator: "\n", omittingEmptySubsequences: false)
            let marker = "\(index + 1). "
            let indent = String(repeating: " ", count: marker.count)
            let rest = lines.dropFirst().map { $0.isEmpty ? "" : indent + $0 }
            return ([marker + (lines.first ?? "")] + rest).joined(separator: "\n")
        }.joined(separator: "\n")
        writeToPasteboard(list)
        if settings.markDoneAfterCopyAsList {
            store.setDone(ordered, true)
        }
        showToast("Copied as List", systemImage: "checkmark.circle.fill")
    }

    func toggleDone(_ ids: [Note.ID]) {
        store.toggleDone(ids)
        pruneState()
    }

    func delete(_ ids: [Note.ID]) {
        guard !ids.isEmpty else { return }
        let visible = visibleNoteIDs
        let nextID = visible.firstIndex { ids.contains($0) }.flatMap { first in
            visible[first...].first { !ids.contains($0) } ?? visible[..<first].last
        }
        store.delete(ids)
        pruneState()
        if let nextID, !selection.isEmpty || ids.count == 1 {
            select(only: nextID)
        }
        showToast("Deleted \(ids.count) Notes · ⌘Z to Undo", systemImage: "trash")
    }

    func merge(_ ids: [Note.ID]) {
        guard ids.count > 1, let merged = store.merge(ids) else { return }
        pruneState()
        select(only: merged)
        expanded.insert(merged)
        showToast("Merged \(ids.count) Notes", systemImage: "arrow.triangle.merge")
    }

    func move(_ ids: [Note.ID], toSection sectionID: NoteSection.ID) {
        store.move(ids, toSection: sectionID)
        store.targetSectionID = sectionID
        if let first = ids.first { scroll(to: first) }
    }

    func moveToNewSection(_ ids: [Note.ID]) {
        let sectionID = store.addSection(titled: String(localized: "New Section"))
        store.move(ids, toSection: sectionID)
        beginRenaming(sectionID)
    }

    func shiftSelection(by offset: Int) {
        store.shift(orderedSelection, by: offset)
        if let cursorID { scroll(to: cursorID) }
    }

    func toggleExpanded(_ noteID: Note.ID) {
        guard store.note(noteID)?.isMultiline == true else { return }
        if expanded.contains(noteID) {
            expanded.remove(noteID)
        } else {
            expanded.insert(noteID)
        }
    }

    func setExpanded(_ ids: [Note.ID], _ isExpanded: Bool) {
        for id in ids where store.note(id)?.isMultiline == true {
            if isExpanded { expanded.insert(id) } else { expanded.remove(id) }
        }
    }

    /// Pastes the clipboard as a new note in the target section.
    func paste() {
        guard let text = RichTextMarkdown.markdown(from: .init(pasteboard)), let id = store.addNote(text) else { return }
        select(only: id)
        scroll(to: id)
        flash(id)
    }

    func undo() {
        store.undo()
        pruneState()
    }

    func redo() {
        store.redo()
        pruneState()
    }

    // MARK: - Editing

    func beginEditing(_ noteID: Note.ID) {
        if editingNoteID != noteID { commitPendingEdit() }
        guard let note = store.note(noteID) else { return }
        select(only: noteID)
        editDraft = note.text
        editingNoteID = noteID
        focus(.noteEditor)
        scroll(to: noteID)
    }

    func commitEdit(_ text: String) {
        guard let editingNoteID else { return }
        store.updateText(of: editingNoteID, to: text)
        self.editingNoteID = nil
        pruneState()
        focus(nil)
    }

    func cancelEdit() {
        editingNoteID = nil
        focus(nil)
    }

    /// Saves an in-progress inline edit, e.g. when the panel hides mid-edit.
    func commitPendingEdit() {
        if editingNoteID != nil { commitEdit(editDraft) }
    }

    func openInWindow(_ noteID: Note.ID) {
        commitPendingEdit()
        host?.openEditorWindow(for: noteID)
    }

    func submitComposer() {
        guard let id = store.addNote(composerText) else { return }
        composerText = ""
        scroll(to: id)
        flash(id)
    }

    // MARK: - Sections

    func addSection() {
        let id = store.addSection(titled: "")
        beginRenaming(id)
    }

    func beginRenaming(_ sectionID: NoteSection.ID) {
        renamingSectionID = sectionID
        focus(.sectionTitle)
    }

    func commitRename(_ title: String) {
        guard let renamingSectionID else { return }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        store.renameSection(renamingSectionID, to: title.isEmpty ? String(localized: "Untitled") : title)
        self.renamingSectionID = nil
        focus(nil)
    }

    func cancelRename() {
        guard let renamingSectionID else { return }
        // A brand-new section that was never named gets a placeholder title.
        if store.sections.first(where: { $0.id == renamingSectionID })?.title.isEmpty == true {
            store.renameSection(renamingSectionID, to: String(localized: "Untitled"))
        }
        self.renamingSectionID = nil
        focus(nil)
    }

    func deleteSection(_ sectionID: NoteSection.ID) {
        let count = store.sections.first { $0.id == sectionID }?.notes.count ?? 0
        store.deleteSection(sectionID)
        pruneState()
        showToast(count == 0 ? "Section Deleted" : "Deleted Section and \(count) Notes · ⌘Z to Undo", systemImage: "trash")
    }

    // MARK: - Capture

    func didCapture(_ text: String) {
        guard let id = store.addNote(text) else { return }
        scroll(to: id)
        flash(id)
    }

    // MARK: - Escape

    /// Backs out of the innermost state. Returns false when there is nothing left to dismiss.
    func handleEscape() -> Bool {
        if editingNoteID != nil {
            cancelEdit()
            return true
        }
        if renamingSectionID != nil {
            cancelRename()
            return true
        }
        switch focusedField {
        case .search:
            if searchText.isEmpty { focus(nil) } else { searchText = "" }
            return true
        case .composer:
            focus(nil)
            return true
        default:
            break
        }
        if !selection.isEmpty {
            clearSelection()
            return true
        }
        if !searchText.isEmpty {
            searchText = ""
            return true
        }
        return false
    }

    // MARK: - Feedback

    func showToast(_ message: LocalizedStringResource, systemImage: String) {
        let toast = PanelToast(message: message, systemImage: systemImage)
        self.toast = toast
        AccessibilityNotification.Announcement(String(localized: message)).post()
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled, self?.toast?.id == toast.id else { return }
            self?.toast = nil
        }
    }

    private func flash(_ noteID: Note.ID) {
        flashedNoteID = noteID
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.flashedNoteID = nil
        }
    }

    private func writeToPasteboard(_ string: String) {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}
