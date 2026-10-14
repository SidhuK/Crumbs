//
//  NotesStore.swift
//  Crumbs
//

import Foundation

/// Owns the notes of the active list, keeps them in sync with the Markdown file
/// on disk, and records undo history.
@Observable
final class NotesStore {
    private(set) var sections: [NoteSection] = [] {
        didSet {
            let hasDone = sections.contains { $0.notes.contains(where: \.isDone) }
            if hasDone != hasDoneNotes { hasDoneNotes = hasDone }
        }
    }
    /// Cached so views can enable "Clear Done" without reading every note.
    private(set) var hasDoneNotes = false
    private(set) var listName: String
    private(set) var listNames: [String] = []

    /// The section that new captures and composed notes go into.
    var targetSectionID: NoteSection.ID?

    var isEmpty: Bool { sections.allSatisfy { $0.notes.isEmpty } }

    /// Problems worth telling the user about.
    enum Issue {
        case saveFailed(any Error)
        /// The list file exists but couldn't be read. It is left untouched and not saved over.
        case readFailed(list: String, any Error)
        /// The file changed on disk while there were unsaved edits; the disk version was kept as a copy.
        case conflictCopySaved(name: String)
    }

    /// Called when saving fails, a list can't be read, or a conflict copy is made.
    @ObservationIgnored var onIssue: ((Issue) -> Void)?

    /// Nil for in-memory stores (previews), which never touch the disk.
    private let files: NotesFileStore?
    @ObservationIgnored private var undoStack: [[NoteSection]] = []
    @ObservationIgnored private var redoStack: [[NoteSection]] = []
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// The file contents as last read or written, used to ignore our own writes.
    @ObservationIgnored private var lastSyncedText: String?
    /// Set when the list file couldn't be read, so an empty list is never saved over it.
    @ObservationIgnored private var isReadBlocked = false

    private static let undoLimit = 100

    init(folder: URL, listName: String) {
        let files = NotesFileStore(folder: folder)
        self.files = files
        self.listName = listName
        files.onChange = { [weak self] in self?.filesDidChange() }
        loadActiveList()
    }

    /// An in-memory store for previews.
    init(inMemory sections: [NoteSection], listName: String) {
        self.files = nil
        self.listName = listName
        self.sections = sections
        self.hasDoneNotes = sections.contains { $0.notes.contains(where: \.isDone) }
        self.listNames = [listName]
    }

    var fileURL: URL? { files?.fileURL(for: listName) }

    // MARK: - Lookup

    var allNotes: [Note] { sections.flatMap(\.notes) }

    func note(_ id: Note.ID) -> Note? {
        location(of: id).map { sections[$0.section].notes[$0.note] }
    }

    func section(containing noteID: Note.ID) -> NoteSection? {
        location(of: noteID).map { sections[$0.section] }
    }

    /// Note ids in document order, limited to `ids`.
    func ordered(_ ids: some Collection<Note.ID>) -> [Note.ID] {
        let wanted = Set(ids)
        return allNotes.map(\.id).filter(wanted.contains)
    }

    /// The section new notes go into: the chosen target, else the last section.
    var resolvedTargetSectionID: NoteSection.ID? {
        if let targetSectionID, sections.contains(where: { $0.id == targetSectionID }) {
            return targetSectionID
        }
        return sections.last?.id
    }

    private func location(of id: Note.ID) -> (section: Int, note: Int)? {
        for (sectionIndex, section) in sections.enumerated() {
            if let noteIndex = section.notes.firstIndex(where: { $0.id == id }) {
                return (sectionIndex, noteIndex)
            }
        }
        return nil
    }

    // MARK: - Notes

    /// Unifies line endings (CRLF from pasted text would otherwise break the Markdown file) and trims.
    static func cleaned(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Adds a note stamped with the current time, and with where it was captured from, if known.
    func addNote(_ text: String, sources: [CaptureSource] = [], to sectionID: NoteSection.ID? = nil) -> Note.ID? {
        let text = Self.cleaned(text)
        guard !text.isEmpty else { return nil }
        let note = Note(text: text, metadata: NoteMetadata(created: NoteMetadata.now(), sources: sources))
        let targetID = sectionID ?? resolvedTargetSectionID
        mutate { sections in
            if let index = sections.firstIndex(where: { $0.id == targetID }) {
                sections[index].notes.append(note)
            } else {
                sections.append(NoteSection(title: "", notes: [note]))
            }
        }
        return note.id
    }

    func updateText(of id: Note.ID, to text: String, registerUndo: Bool = true) {
        let text = Self.cleaned(text)
        guard let location = location(of: id), sections[location.section].notes[location.note].text != text else {
            return
        }
        guard !text.isEmpty else {
            delete([id])
            return
        }
        let now = NoteMetadata.now()
        mutate(registerUndo: registerUndo) { sections in
            sections[location.section].notes[location.note].text = text
            sections[location.section].notes[location.note].metadata.modified = now
        }
    }

    /// Marks every note done, or un-done if they are all done already.
    func toggleDone(_ ids: [Note.ID]) {
        let notes = ids.compactMap(note)
        guard !notes.isEmpty else { return }
        setDone(ids, !notes.allSatisfy(\.isDone))
    }

    func setDone(_ ids: [Note.ID], _ done: Bool) {
        let wanted = Set(ids)
        mutate { sections in
            for s in sections.indices {
                for n in sections[s].notes.indices where wanted.contains(sections[s].notes[n].id) {
                    sections[s].notes[n].isDone = done
                }
            }
        }
    }

    func delete(_ ids: [Note.ID]) {
        let wanted = Set(ids)
        guard allNotes.contains(where: { wanted.contains($0.id) }) else { return }
        mutate { sections in
            for s in sections.indices {
                sections[s].notes.removeAll { wanted.contains($0.id) }
            }
        }
    }

    /// Joins the notes into the first one, in document order. Returns the merged note's id.
    func merge(_ ids: [Note.ID]) -> Note.ID? {
        let ordered = ordered(ids)
        guard ordered.count > 1, let firstID = ordered.first else { return nil }
        let notes = ordered.compactMap(note)
        let mergedText = notes.map(\.text).joined(separator: "\n")
        let mergedMetadata = NoteMetadata.merged(notes.map(\.metadata), at: NoteMetadata.now())
        let rest = Set(ordered.dropFirst())
        mutate { sections in
            for s in sections.indices {
                sections[s].notes.removeAll { rest.contains($0.id) }
                if let n = sections[s].notes.firstIndex(where: { $0.id == firstID }) {
                    sections[s].notes[n].text = mergedText
                    sections[s].notes[n].isDone = false
                    sections[s].notes[n].metadata = mergedMetadata
                }
            }
        }
        return firstID
    }

    /// Moves notes, keeping their order, into a section before `beforeID` or at its end.
    func move(_ ids: [Note.ID], toSection sectionID: NoteSection.ID, before beforeID: Note.ID? = nil) {
        let ordered = ordered(ids)
        guard !ordered.isEmpty, sections.contains(where: { $0.id == sectionID }) else { return }
        let moving = ordered.compactMap(note)
        let movingIDs = Set(ordered)
        // Dropping inside the moved block means "before the first note after it that stays put".
        var anchorID = beforeID
        if let beforeID, movingIDs.contains(beforeID),
           let notes = sections.first(where: { $0.id == sectionID })?.notes,
           let start = notes.firstIndex(where: { $0.id == beforeID }) {
            anchorID = notes[start...].first { !movingIDs.contains($0.id) }?.id
        }
        mutate { sections in
            for s in sections.indices {
                sections[s].notes.removeAll { movingIDs.contains($0.id) }
            }
            guard let target = sections.firstIndex(where: { $0.id == sectionID }) else { return }
            let insertAt = anchorID.flatMap { id in sections[target].notes.firstIndex { $0.id == id } }
                ?? sections[target].notes.endIndex
            sections[target].notes.insert(contentsOf: moving, at: insertAt)
        }
    }

    /// Shifts notes one step up or down, crossing into neighbouring sections at the edges.
    func shift(_ ids: [Note.ID], by offset: Int) {
        let wanted = Set(ids)
        guard !wanted.isEmpty, offset != 0 else { return }

        enum Token { case header(NoteSection), note(Note) }
        var tokens: [Token] = []
        for section in sections {
            tokens.append(.header(NoteSection(id: section.id, title: section.title)))
            tokens.append(contentsOf: section.notes.map(Token.note))
        }
        func isMoving(_ index: Int) -> Bool {
            if case .note(let note) = tokens[index] { return wanted.contains(note.id) }
            return false
        }

        var changed = false
        let indices = offset < 0 ? Array(tokens.indices) : tokens.indices.reversed()
        for index in indices where isMoving(index) {
            let neighbour = index + (offset < 0 ? -1 : 1)
            // Notes can't move above the first heading or swap with each other.
            guard neighbour > 0, neighbour < tokens.count, !isMoving(neighbour) else { continue }
            tokens.swapAt(index, neighbour)
            changed = true
        }
        guard changed else { return }

        var rebuilt: [NoteSection] = []
        for token in tokens {
            switch token {
            case .header(let section): rebuilt.append(section)
            case .note(let note): rebuilt[rebuilt.count - 1].notes.append(note)
            }
        }
        mutate { $0 = rebuilt }
    }

    func clearDone() {
        guard allNotes.contains(where: \.isDone) else { return }
        mutate { sections in
            for s in sections.indices {
                sections[s].notes.removeAll(where: \.isDone)
            }
        }
    }

    // MARK: - Sections

    @discardableResult
    func addSection(titled title: String) -> NoteSection.ID {
        let section = NoteSection(title: title)
        mutate { $0.append(section) }
        targetSectionID = section.id
        return section.id
    }

    func renameSection(_ id: NoteSection.ID, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = sections.firstIndex(where: { $0.id == id }), sections[index].title != title else { return }
        mutate { sections in
            if title.isEmpty && index > 0 {
                // An untitled section can only lead the list; fold the notes into the one above.
                sections[index - 1].notes.append(contentsOf: sections[index].notes)
                sections.remove(at: index)
            } else {
                sections[index].title = title
            }
        }
    }

    func deleteSection(_ id: NoteSection.ID) {
        guard sections.contains(where: { $0.id == id }) else { return }
        mutate { $0.removeAll { $0.id == id } }
    }

    // MARK: - Undo

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(sections)
        sections = previous
        scheduleSave()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(sections)
        sections = next
        scheduleSave()
    }

    /// Records the current state so a series of silent edits can be undone in one step.
    func checkpoint() {
        undoStack.append(sections)
        if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func mutate(registerUndo: Bool = true, _ change: (inout [NoteSection]) -> Void) {
        if registerUndo { checkpoint() }
        change(&sections)
        scheduleSave()
    }

    // MARK: - Lists

    struct UnsavedChangesError: LocalizedError {
        var errorDescription: String? { String(localized: "Your latest changes couldn’t be saved, so the list was left open.") }
    }

    /// Opens another list. Returns false, staying on the current list, if its unsaved edits can't be saved.
    @discardableResult
    func switchToList(_ name: String) -> Bool {
        guard saveNow() else { return false }
        listName = name
        undoStack.removeAll()
        redoStack.removeAll()
        targetSectionID = nil
        loadActiveList()
        return true
    }

    /// Creates an empty list and opens it. Fails rather than overwrite an existing file.
    func createList(named name: String) throws {
        try files?.create(list: name)
        guard switchToList(name) else { throw UnsavedChangesError() }
    }

    func renameActiveList(to name: String) throws {
        guard saveNow() else { throw UnsavedChangesError() }
        try files?.rename(list: listName, to: name)
        listName = name
        files?.startWatching(list: name)
        refreshListNames()
    }

    func trashActiveList() throws {
        saveNow()
        try files?.trash(list: listName)
        // Nothing is left to save under the trashed name.
        lastSyncedText = NotesMarkdown.serialize(sections)
        isReadBlocked = false
        let next = files?.listNames().first ?? "Inbox"
        switchToList(next)
    }

    func setFolder(_ folder: URL) -> Bool {
        guard saveNow() else { return false }
        files?.setFolder(folder)
        lastSyncedText = nil
        undoStack.removeAll()
        redoStack.removeAll()
        targetSectionID = nil
        loadActiveList()
        return true
    }

    // MARK: - Persistence

    /// Writes pending edits. Returns false if they couldn't be saved.
    @discardableResult
    func saveNow() -> Bool {
        saveTask?.cancel()
        saveTask = nil
        guard let files else { return true }
        // Never replace a file we couldn't read with what we have in memory.
        guard !isReadBlocked else { return false }
        let text = NotesMarkdown.serialize(sections)
        guard text != lastSyncedText else { return true }
        do {
            // Another app changed the file since we last read or wrote it: keep its version too.
            if let lastSyncedText, let disk = try files.read(list: listName), disk != lastSyncedText {
                let copy = try files.writeConflictCopy(disk, of: listName)
                onIssue?(.conflictCopySaved(name: copy))
            }
            try files.write(text, list: listName)
            lastSyncedText = text
            refreshListNames()
            return true
        } catch {
            onIssue?(.saveFailed(error))
            return false
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func loadActiveList() {
        guard let files else { return }
        do {
            if let text = try files.read(list: listName) {
                lastSyncedText = text
                sections = NotesMarkdown.parse(text)
            } else {
                // Make sure the list exists on disk so it shows up in Finder and the list menu.
                sections = []
                try? files.create(list: listName)
                lastSyncedText = ""
            }
            isReadBlocked = false
        } catch {
            sections = []
            lastSyncedText = nil
            isReadBlocked = true
            onIssue?(.readFailed(list: listName, error))
        }
        files.startWatching(list: listName)
        refreshListNames()
    }

    private func refreshListNames() {
        guard let files else { return }
        var names = files.listNames()
        if !names.contains(listName) { names.append(listName) }
        if names != listNames { listNames = names }
    }

    /// Picks up edits made in another editor, keeping ids stable where the text matches.
    func filesDidChange() {
        refreshListNames()
        if isReadBlocked {
            // The file may have been fixed or finished downloading.
            loadActiveList()
            return
        }
        guard let text = (try? files?.read(list: listName)) ?? nil, text != lastSyncedText else { return }
        // A local save is pending: it will notice the outside change and keep it as a conflict copy.
        guard saveTask == nil else { return }
        lastSyncedText = text
        // Undo history describes the old file; undoing would write it back over the outside edit.
        undoStack.removeAll()
        redoStack.removeAll()
        sections = Self.reconcile(old: sections, new: NotesMarkdown.parse(text))
    }

    static func reconcile(old: [NoteSection], new: [NoteSection]) -> [NoteSection] {
        var noteIDs: [String: [Note.ID]] = [:]
        for note in old.flatMap(\.notes) { noteIDs[note.text, default: []].append(note.id) }
        var sectionIDs: [String: [NoteSection.ID]] = [:]
        for section in old { sectionIDs[section.title, default: []].append(section.id) }

        return new.map { section in
            let sectionID = sectionIDs[section.title]?.isEmpty == false
                ? sectionIDs[section.title]!.removeFirst() : section.id
            let notes = section.notes.map { note in
                let id = noteIDs[note.text]?.isEmpty == false ? noteIDs[note.text]!.removeFirst() : note.id
                // Keep everything the file says about the note; only its identity carries over.
                return note.withID(id)
            }
            return NoteSection(id: sectionID, title: section.title, notes: notes)
        }
    }
}
