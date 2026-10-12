//
//  NoteEditorWindow.swift
//  Crumbs
//

import SwiftUI

/// Opens longer notes in a regular, resizable window.
final class NoteWindowManager {
    private let store: NotesStore
    private var windows: [Note.ID: NSWindow] = [:]
    private var closeObservers: [Note.ID: NSObjectProtocol] = [:]

    init(store: NotesStore) {
        self.store = store
    }

    func open(_ noteID: Note.ID) {
        NSApp.activate()
        if let window = windows[noteID] {
            window.makeKeyAndOrderFront(nil)
            return
        }
        guard let note = store.note(noteID) else { return }

        // One undo step for the whole editing session.
        store.checkpoint()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(note.title.prefix(60))
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: NoteEditorView(noteID: noteID, initialText: note.text, store: store) { [weak window] in
                window?.close()
            }
        )
        window.setContentSize(NSSize(width: 480, height: 360))
        window.center()
        window.makeKeyAndOrderFront(nil)
        windows[noteID] = window

        closeObservers[noteID] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.windowWillClose(noteID)
            }
        }
    }

    private func windowWillClose(_ noteID: Note.ID) {
        windows[noteID] = nil
        if let observer = closeObservers.removeValue(forKey: noteID) {
            NotificationCenter.default.removeObserver(observer)
        }
        store.saveNow()
    }
}

private struct NoteEditorView: View {
    let noteID: Note.ID
    let store: NotesStore
    let onNoteRemoved: () -> Void
    @State private var text: String
    /// The note text as last written by this window or read from the store.
    @State private var syncedText: String

    /// `initialText` seeds the editor once; after that the window and the store sync both ways.
    init(noteID: Note.ID, initialText: String, store: NotesStore, onNoteRemoved: @escaping () -> Void) {
        self.noteID = noteID
        self.store = store
        self.onNoteRemoved = onNoteRemoved
        self.text = initialText
        self.syncedText = initialText
    }

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 14))
            .lineSpacing(3)
            .scrollContentBackground(.hidden)
            .padding(16)
            .frame(minWidth: 320, minHeight: 200)
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: text) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                // Keep the note while the text is momentarily empty.
                guard !trimmed.isEmpty, trimmed != syncedText else { return }
                syncedText = trimmed
                store.updateText(of: noteID, to: text, registerUndo: false)
            }
            .onChange(of: store.note(noteID)?.text) { _, storeText in
                guard let storeText else {
                    // Deleted in the panel, or replaced by an edit made in another app.
                    onNoteRemoved()
                    return
                }
                if storeText != syncedText {
                    syncedText = storeText
                    text = storeText
                }
            }
    }
}
