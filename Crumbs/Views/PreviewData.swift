//
//  PreviewData.swift
//  Crumbs
//

#if DEBUG
import Foundation

extension AppSettings {
    /// Settings backed by a throwaway defaults suite, so previews never share state.
    static func preview() -> AppSettings {
        AppSettings(defaults: UserDefaults(suiteName: "CrumbsPreviews-\(UUID().uuidString)") ?? .standard)
    }
}

extension NotesStore {
    /// An in-memory list, for previews.
    static func preview(_ sections: [NoteSection] = .sample) -> NotesStore {
        NotesStore(inMemory: sections, listName: "development")
    }
}

extension PanelModel {
    /// A panel model over an in-memory list, for previews.
    static func preview(_ sections: [NoteSection] = .sample) -> PanelModel {
        PanelModel(store: .preview(sections), settings: .preview())
    }
}

extension [NoteSection] {
    static var sample: [NoteSection] {
        [
            NoteSection(title: "Research", notes: [
                Note(text: "**Negation in inherited configs.** The moment a config can extend a base or preset, someone needs to *remove* an extension the base added."),
            ]),
            NoteSection(title: "Configuration Formats", notes: [
                Note(text: "Use **TOML as the default declarative format**, backed by a published schema"),
                Note(text: "Three things worth locking down before it ships:\n1. A `version` field on the format.\n2. An effective-config command.\n3. Whether extensions may contribute top-level fields."),
                Note(text: "How should configuration migrations work?"),
                Note(text: "Should plugins own their configuration schema?", isDone: true),
            ]),
        ]
    }
}
#endif
