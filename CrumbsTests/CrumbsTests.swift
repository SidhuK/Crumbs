//
//  CrumbsTests.swift
//  CrumbsTests
//

import AppKit
import Foundation
import Testing
@testable import Crumbs

struct NotesMarkdownTests {
    @Test func parsesSectionsTasksAndContinuationLines() {
        let source = """
        ## Research

        - [ ] **Negation in inherited configs.** The moment a config can extend a base
        - [x] Three things worth locking down before it ships:
          1. A `version` field on the format.

          2. An effective-config command.

        ## Configuration Formats

        - [ ] Use **TOML**
        """
        let sections = NotesMarkdown.parse(source)

        #expect(sections.map(\.title) == ["Research", "Configuration Formats"])
        #expect(sections[0].notes.count == 2)
        #expect(sections[0].notes[0].text == "**Negation in inherited configs.** The moment a config can extend a base")
        #expect(sections[0].notes[0].isDone == false)
        #expect(sections[0].notes[1].isDone)
        #expect(sections[0].notes[1].text == """
        Three things worth locking down before it ships:
        1. A `version` field on the format.

        2. An effective-config command.
        """)
        #expect(sections[1].notes.map(\.text) == ["Use **TOML**"])
    }

    @Test func roundTripsThroughSerialize() {
        let sections = [
            NoteSection(title: "", notes: [Note(text: "Loose note")]),
            NoteSection(title: "Ideas", notes: [
                Note(text: "First line\n  indented detail\n\nafter a blank", isDone: true),
                Note(text: "Plain"),
            ]),
            NoteSection(title: "Empty"),
        ]
        let reparsed = NotesMarkdown.parse(NotesMarkdown.serialize(sections))

        #expect(reparsed.map(\.title) == sections.map(\.title))
        #expect(reparsed.map { $0.notes.map(\.text) } == sections.map { $0.notes.map(\.text) })
        #expect(reparsed.map { $0.notes.map(\.isDone) } == sections.map { $0.notes.map(\.isDone) })
    }

    @Test func roundTripsLinesThatLookLikeMarkdown() {
        let tricky = "First line\n- [ ] not a task\n# not a heading\n    indented code\n\n\nafter blank lines"
        let sections = [
            NoteSection(title: "Ideas", notes: [Note(text: tricky), Note(text: "Second")]),
        ]
        let reparsed = NotesMarkdown.parse(NotesMarkdown.serialize(sections))
        #expect(reparsed.map(\.title) == ["Ideas"])
        #expect(reparsed.first?.notes.map(\.text) == [tricky, "Second"])
    }

    @Test func treatsLooseLinesAndBulletsAsNotes() {
        let sections = NotesMarkdown.parse("Just a thought\n- bullet item\n* [X] done item\n")
        #expect(sections.count == 1)
        #expect(sections[0].title.isEmpty)
        #expect(sections[0].notes.map(\.text) == ["Just a thought", "bullet item", "done item"])
        #expect(sections[0].notes.map(\.isDone) == [false, false, true])
    }
}

@MainActor
struct RichTextMarkdownTests {
    private func attributed(html: String) throws -> NSAttributedString {
        try NSAttributedString(
            data: Data(html.utf8),
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil
        )
    }

    private func run(_ text: String, font: NSFont) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font])
    }

    @Test func convertsBoldItalicAndCodeRuns() throws {
        let body = NSFont.systemFont(ofSize: 13)
        let bold = NSFont.boldSystemFont(ofSize: 13)
        let italic = NSFontManager.shared.convert(body, toHaveTrait: .italicFontMask)
        let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        let text = NSMutableAttributedString()
        text.append(run("Use ", font: body))
        text.append(run("TOML as the default ", font: bold))
        text.append(run("format", font: italic))
        text.append(run(" with ", font: body))
        text.append(run("tool config check", font: mono))

        let converted = RichTextMarkdown.markdown(from: text)
        let markdown = try #require(converted)
        #expect(markdown == "Use **TOML as the default** *format* with `tool config check`")
    }

    @Test func returnsNilForAllMonospacedText() {
        let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let converted = RichTextMarkdown.markdown(from: run("let x = 1\nlet y = 2", font: mono))
        #expect(converted == nil)
    }

    @Test func keepsListsFromHTML() throws {
        let html = """
        <p>Three things <b>worth</b> locking down:</p>
        <ol><li>A version field.</li><li>An effective-config command.</li></ol>
        """
        let attributed = try attributed(html: html)
        let converted = RichTextMarkdown.markdown(from: attributed)
        let markdown = try #require(converted)
        #expect(markdown == "Three things **worth** locking down:\n1. A version field.\n2. An effective-config command.")
    }

    @Test func keepsWebLinksAndDropsScriptLinks() throws {
        let body = NSFont.systemFont(ofSize: 13)
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: "Read the ", attributes: [.font: body]))
        text.append(NSAttributedString(string: "docs", attributes: [.font: body, .link: URL(string: "https://example.com/docs")!]))
        text.append(NSAttributedString(string: " not ", attributes: [.font: body]))
        text.append(NSAttributedString(string: "this", attributes: [.font: body, .link: "javascript:alert(1)"]))

        let converted = RichTextMarkdown.markdown(from: text)
        let markdown = try #require(converted)
        #expect(markdown == "Read the [docs](https://example.com/docs) not this")
    }

    @Test func convertsStrikethroughAndBulletMarkers() throws {
        let body = NSFont.systemFont(ofSize: 13)
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: "\t•\tFirst\n", attributes: [.font: body]))
        text.append(NSAttributedString(string: "\t•\t", attributes: [.font: body]))
        text.append(NSAttributedString(string: "Second", attributes: [.font: body, .strikethroughStyle: NSUnderlineStyle.single.rawValue]))

        let converted = RichTextMarkdown.markdown(from: text)
        let markdown = try #require(converted)
        #expect(markdown == "- First\n- ~~Second~~")
    }

    @Test func keepsOrderedListNumbersAsWritten() throws {
        let html = "<ol start=\"5\"><li>Fifth</li><li>Sixth</li></ol>"
        let attributed = try attributed(html: html)
        let markdown = try #require(RichTextMarkdown.markdown(from: attributed))
        #expect(markdown == "5. Fifth\n6. Sixth")
    }

    @Test func escapesBracketsInLinkText() throws {
        let body = NSFont.systemFont(ofSize: 13)
        let text = NSAttributedString(string: "a]b", attributes: [.font: body, .link: URL(string: "https://x.com")!])
        let markdown = try #require(RichTextMarkdown.markdown(from: text))
        #expect(markdown == "[a\\]b](https://x.com)")
    }

    @Test func escapesMarkdownCharactersInPlainRuns() throws {
        let converted = RichTextMarkdown.markdown(from: run("2 * 3", font: .systemFont(ofSize: 13)))
        let markdown = try #require(converted)
        #expect(markdown == "2 \\* 3")
    }
}

/// Adds a note and returns its id, failing the test if nothing was added.
@MainActor
private func added(_ store: NotesStore, _ text: String, to section: NoteSection.ID? = nil) throws -> Note.ID {
    let id = store.addNote(text, to: section)
    return try #require(id)
}

/// Gives each test its own empty folder and deletes it afterwards.
struct TemporaryFolder: SuiteTrait, TestTrait, TestScoping {
    @TaskLocal static var current: URL?

    var isRecursive: Bool { true }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
        guard testCase != nil else {
            try await function()
            return
        }
        let folder = URL.temporaryDirectory.appending(path: "CrumbsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        try await Self.$current.withValue(folder) {
            try await function()
        }
    }
}

@MainActor
@Suite(TemporaryFolder())
struct NotesStoreTests {
    private func makeStore() throws -> NotesStore {
        NotesStore(folder: try #require(TemporaryFolder.current), listName: "Test")
    }

    @Test func addsToTargetSectionAndPersists() throws {
        let store = try makeStore()
        let research = store.addSection(titled: "Research")
        store.addSection(titled: "Formats")
        store.targetSectionID = research
        _ = try added(store, "Captured idea")
        store.saveNow()

        let fileURL = try #require(store.fileURL)
        let saved = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(saved == "## Research\n\n- [ ] Captured idea\n\n## Formats\n")
    }

    @Test func mergeJoinsNotesInDocumentOrder() throws {
        let store = try makeStore()
        let a = try added(store, "How should configuration migrations work?")
        let b = try added(store, "Should plugins own their configuration schema?")
        let merged = store.merge([b, a])
        let texts = store.allNotes.map(\.text)

        #expect(merged == a)
        #expect(texts == ["How should configuration migrations work?\nShould plugins own their configuration schema?"])
    }

    @Test func shiftCrossesSectionBoundaries() throws {
        let store = try makeStore()
        let first = store.addSection(titled: "One")
        let note = try added(store, "Moving note", to: first)
        _ = try added(store, "Stays", to: first)
        let second = store.addSection(titled: "Two")

        store.shift([note], by: 1)
        store.shift([note], by: 1)
        let afterDown = store.section(containing: note)?.id
        #expect(afterDown == second)

        store.shift([note], by: -1)
        let afterUp = store.section(containing: note)?.id
        let firstTexts = store.sections[0].notes.map(\.text)
        #expect(afterUp == first)
        #expect(firstTexts == ["Stays", "Moving note"])
    }

    @Test func undoAndRedoDeletion() throws {
        let store = try makeStore()
        let id = try added(store, "Keep me")
        store.delete([id])
        let emptyAfterDelete = store.isEmpty
        store.undo()
        let restored = store.note(id)?.text
        store.redo()
        let emptyAfterRedo = store.isEmpty

        #expect(emptyAfterDelete)
        #expect(restored == "Keep me")
        #expect(emptyAfterRedo)
    }

    @Test func emptyingANoteDeletesIt() throws {
        let store = try makeStore()
        let id = try added(store, "Temporary")
        store.updateText(of: id, to: "   \n")
        let remaining = store.note(id)
        #expect(remaining == nil)
    }

    @Test func clearingASectionTitleFoldsItIntoTheOneAbove() throws {
        let store = try makeStore()
        let first = store.addSection(titled: "One")
        let second = store.addSection(titled: "Two")
        _ = try added(store, "a", to: first)
        _ = try added(store, "b", to: second)

        store.renameSection(second, to: "")
        let titles = store.sections.map(\.title)
        let texts = store.sections.first?.notes.map(\.text)

        #expect(titles == ["One"])
        #expect(texts == ["a", "b"])
    }

    @Test func clearDoneRemovesOnlyDoneNotes() throws {
        let store = try makeStore()
        let done = try added(store, "done")
        _ = try added(store, "open")
        store.setDone([done], true)
        let hadDone = store.hasDoneNotes

        store.clearDone()
        let texts = store.allNotes.map(\.text)

        #expect(hadDone)
        #expect(texts == ["open"])
        #expect(store.hasDoneNotes == false)
    }

    @Test func reconcileKeepsIdsForUnchangedNotes() {
        let kept = Note(text: "unchanged")
        let old = [NoteSection(title: "Ideas", notes: [kept, Note(text: "edited")])]
        let new = NotesMarkdown.parse("## Ideas\n\n- [x] unchanged\n- [ ] edited elsewhere\n")

        let reconciled = NotesStore.reconcile(old: old, new: new)
        let notes = reconciled[0].notes

        #expect(reconciled[0].id == old[0].id)
        #expect(notes[0].id == kept.id)
        #expect(notes[0].isDone)
        #expect(notes[1].id != old[0].notes[1].id)
    }

    @Test func listsAreSortedMarkdownFiles() throws {
        let folder = try #require(TemporaryFolder.current)
        let files = NotesFileStore(folder: folder)
        try files.write("", list: "b list")
        try files.write("", list: "A list")
        try Data().write(to: folder.appending(path: "ignored.txt"))
        try files.rename(list: "b list", to: "C list")

        let names = files.listNames()
        #expect(names == ["A list", "C list"])
    }

    @Test func neverOverwritesAListItCannotRead() throws {
        let folder = try #require(TemporaryFolder.current)
        let files = NotesFileStore(folder: folder)
        try files.write("- [ ] precious\n", list: "Test")
        let url = files.fileURL(for: "Test")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path(percentEncoded: false))

        let store = NotesStore(folder: folder, listName: "Test")
        _ = store.addNote("new")
        let saved = store.saveNow()

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path(percentEncoded: false))
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        #expect(saved == false)
        #expect(onDisk == "- [ ] precious\n")
    }

    @Test func creatingAListNeverReplacesAnExistingFile() throws {
        let store = try makeStore()
        _ = try added(store, "keep me")
        store.saveNow()

        #expect(throws: (any Error).self) { try store.createList(named: "Test") }
        let fileURL = try #require(store.fileURL)
        let onDisk = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(onDisk.contains("keep me"))
    }

    @Test func savingOverAnOutsideEditKeepsAConflictCopy() throws {
        let store = try makeStore()
        _ = try added(store, "mine")
        store.saveNow()
        let fileURL = try #require(store.fileURL)
        try Data("- [ ] theirs\n".utf8).write(to: fileURL)

        _ = try added(store, "mine too")
        var copies: [String] = []
        store.onIssue = { if case .conflictCopySaved(let name) = $0 { copies.append(name) } }
        let saved = store.saveNow()

        let folder = try #require(TemporaryFolder.current)
        let copyName = try #require(copies.first)
        let copy = try String(contentsOf: folder.appending(path: "\(copyName).md"), encoding: .utf8)
        let onDisk = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(saved)
        #expect(copy == "- [ ] theirs\n")
        #expect(onDisk.contains("mine too"))
    }

    @Test func outsideEditsClearUndoSoTheyCantBeReverted() throws {
        let store = try makeStore()
        _ = try added(store, "before")
        store.saveNow()
        let fileURL = try #require(store.fileURL)
        try Data("- [ ] edited elsewhere\n".utf8).write(to: fileURL)

        store.filesDidChange()
        store.undo()
        let texts = store.allNotes.map(\.text)
        #expect(texts == ["edited elsewhere"])
    }

    @Test func windowsLineEndingsStayInsideOneNote() throws {
        let store = try makeStore()
        let section = store.addSection(titled: "A")
        _ = try added(store, "first\r\n# Not a heading\r\nthird", to: section)
        store.saveNow()

        let fileURL = try #require(store.fileURL)
        let reparsed = NotesMarkdown.parse(try String(contentsOf: fileURL, encoding: .utf8))
        #expect(reparsed.map(\.title) == ["A"])
        #expect(reparsed.first?.notes.map(\.text) == ["first\n# Not a heading\nthird"])
    }

    @Test func droppingInsideTheMovedBlockKeepsItInPlace() throws {
        let store = try makeStore()
        let section = store.addSection(titled: "S")
        let a = try added(store, "a", to: section)
        let b = try added(store, "b", to: section)
        _ = try added(store, "c", to: section)

        store.move([a, b], toSection: section, before: b)
        let texts = store.allNotes.map(\.text)
        #expect(texts == ["a", "b", "c"])
    }
}

@MainActor
@Suite(TemporaryFolder())
struct PanelModelTests {
    private struct Fixture {
        let store: NotesStore
        let model: PanelModel
    }

    /// Runs `body` with a model backed by throwaway defaults and pasteboard.
    private func withModel(_ body: (Fixture) throws -> Void) throws {
        let defaultsName = "CrumbsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        let store = NotesStore(folder: try #require(TemporaryFolder.current), listName: "Test")
        let model = PanelModel(store: store, settings: AppSettings(defaults: defaults))
        model.pasteboard = NSPasteboard(name: NSPasteboard.Name(defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            model.pasteboard.releaseGlobally()
        }
        try body(Fixture(store: store, model: model))
    }

    @Test func copyAsListNumbersNotesAndMarksThemDone() throws {
        try withModel { fixture in
            let a = try added(fixture.store, "How should configuration migrations work?")
            let b = try added(fixture.store, "Should plugins own their\nconfiguration schema?")

            fixture.model.copyAsList([a, b])
            let copied = fixture.model.pasteboard.string(forType: .string)
            let allDone = fixture.store.allNotes.allSatisfy { $0.isDone }

            #expect(copied == """
            1. How should configuration migrations work?
            2. Should plugins own their
               configuration schema?
            """)
            #expect(allDone)
        }
    }

    @Test func searchAndHideDoneFilterVisibleNotes() throws {
        try withModel { fixture in
            let done = try added(fixture.store, "Config done")
            _ = try added(fixture.store, "Config open")
            _ = try added(fixture.store, "Something else")
            fixture.store.setDone([done], true)

            fixture.model.searchText = "config"
            let searched = fixture.model.visibleSections.flatMap(\.notes).map(\.text)
            fixture.model.settings.hideDoneNotes = true
            let hidden = fixture.model.visibleSections.flatMap(\.notes).map(\.text)

            #expect(searched == ["Config done", "Config open"])
            #expect(hidden == ["Config open"])
        }
    }

    @Test func deleteSelectsTheNextNote() throws {
        try withModel { fixture in
            let a = try added(fixture.store, "a")
            let b = try added(fixture.store, "b")
            fixture.model.select(only: a)

            fixture.model.delete([a])
            let selection = fixture.model.selection

            #expect(selection == [b])
        }
    }

    @Test func selectionNeverIncludesNotesHiddenBySearch() throws {
        try withModel { fixture in
            _ = try added(fixture.store, "foo one")
            _ = try added(fixture.store, "bar")
            _ = try added(fixture.store, "foo two")
            fixture.model.selectAll()

            fixture.model.searchText = "foo"
            fixture.model.pruneState()
            fixture.model.delete(fixture.model.orderedSelection)
            let remaining = fixture.store.allNotes.map(\.text)

            #expect(remaining == ["bar"])
        }
    }

    @Test func clickingAnotherNoteSavesTheInlineEdit() throws {
        try withModel { fixture in
            let a = try added(fixture.store, "original")
            let b = try added(fixture.store, "other")
            fixture.model.beginEditing(a)
            fixture.model.editDraft = "changed"

            fixture.model.click(b, modifiers: [], clickCount: 1)
            let text = fixture.store.note(a)?.text

            #expect(text == "changed")
        }
    }

    @Test func escapeClearsSelectionThenReportsNothingLeft() throws {
        try withModel { fixture in
            let a = try added(fixture.store, "a")
            fixture.model.select(only: a)

            let first = fixture.model.handleEscape()
            let second = fixture.model.handleEscape()
            let selection = fixture.model.selection

            #expect(first)
            #expect(selection.isEmpty)
            #expect(second == false)
        }
    }
}

@MainActor
struct DoubleTapMonitorTests {
    private func taps(_ events: [(NSEvent.EventType, NSEvent.ModifierFlags, TimeInterval)]) -> Int {
        let monitor = ModifierDoubleTapMonitor()
        var fired = 0
        monitor.onDoubleTap = { fired += 1 }
        for (type, flags, time) in events { monitor.handle(type: type, flags: flags, timestamp: time) }
        return fired
    }

    @Test func twoQuickShiftTapsFire() {
        let fired = taps([
            (.flagsChanged, .shift, 0.00), (.flagsChanged, [], 0.08),
            (.flagsChanged, .shift, 0.20), (.flagsChanged, [], 0.28),
        ])
        #expect(fired == 1)
    }

    @Test func typingBetweenTapsCancels() {
        let fired = taps([
            (.flagsChanged, .shift, 0.00), (.flagsChanged, [], 0.08),
            (.keyDown, [], 0.12),
            (.flagsChanged, .shift, 0.20), (.flagsChanged, [], 0.28),
        ])
        #expect(fired == 0)
    }

    @Test func chordsAndLongHoldsDontCount() {
        let chord = taps([
            (.flagsChanged, .shift, 0.00), (.flagsChanged, [.shift, .command], 0.05), (.flagsChanged, [], 0.10),
            (.flagsChanged, .shift, 0.20), (.flagsChanged, [], 0.28),
        ])
        let longHold = taps([
            (.flagsChanged, .shift, 0.00), (.flagsChanged, [], 0.90),
            (.flagsChanged, .shift, 1.00), (.flagsChanged, [], 1.08),
        ])
        #expect(chord == 0)
        #expect(longHold == 0)
    }
}
