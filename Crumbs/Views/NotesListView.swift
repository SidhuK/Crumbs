//
//  NotesListView.swift
//  Crumbs
//

import SwiftUI

struct NotesListView: View {
    @FocusState.Binding var focus: PanelField?
    @Environment(PanelModel.self) private var model

    var body: some View {
        let sections = model.visibleSections
        let showsSectionHeaders = sections.count > 1 || sections.contains { !$0.section.title.isEmpty }
        let store = model.store
        let targetSectionID = store.sections.count > 1 ? store.resolvedTargetSectionID : nil

        ScrollViewReader { proxy in
            ScrollView {
                // Rows are direct children of the lazy stack, so `scrollTo` can reach any note,
                // even in a section that hasn't been built yet.
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(sections) { visible in
                        Section {
                            ForEach(visible.notes) { note in
                                NoteRow(
                                    note: note,
                                    isSelected: model.selection.contains(note.id),
                                    isExpanded: model.expanded.contains(note.id),
                                    isEditing: model.editingNoteID == note.id,
                                    isFlashing: model.flashedNoteID == note.id,
                                    focus: $focus
                                )
                            }
                            .reorderable(collectionID: visible.id)
                        } header: {
                            if showsSectionHeaders, !visible.section.title.isEmpty || model.renamingSectionID == visible.id {
                                SectionHeaderView(
                                    sectionID: visible.id,
                                    title: visible.section.title,
                                    isTarget: targetSectionID == visible.id,
                                    isRenaming: model.renamingSectionID == visible.id,
                                    focus: $focus
                                )
                            }
                        }
                    }
                }
                .reorderContainer(for: Note.self, in: NoteSection.ID.self) { difference in
                    let before: Note.ID? = switch difference.destination.position {
                    case .before(let id): id
                    case .end: nil
                    }
                    model.store.move(difference.sources, toSection: difference.destination.collectionID, before: before)
                }
                .padding(.horizontal, PanelStyle.horizontalInset)
                .padding(.vertical, 8)
            }
            .overlay {
                EmptyStateView(isSearching: !model.searchText.isEmpty, hasVisibleNotes: sections.contains { !$0.notes.isEmpty })
            }
            .contentShape(.rect)
            .onTapGesture {
                model.clearSelection()
                model.focusList()
            }
            .onChange(of: model.scrollRequest) {
                guard let request = model.scrollRequest else { return }
                withAnimation(.smooth(duration: 0.25)) {
                    proxy.scrollTo(request.noteID)
                }
            }
            .onChange(of: model.store.sections) {
                model.pruneState()
            }
            .onChange(of: model.searchText) {
                model.pruneState()
            }
            .onChange(of: model.settings.hideDoneNotes) {
                model.pruneState()
            }
        }
    }
}

private struct EmptyStateView: View {
    let isSearching: Bool
    let hasVisibleNotes: Bool
    @Environment(PanelModel.self) private var model

    var body: some View {
        if !hasVisibleNotes {
            VStack(spacing: 8) {
                Group {
                    if isSearching {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(.tertiary)
                    } else {
                        PixelAsterisk()
                            .fill(.tint)
                            .frame(width: 27, height: 27)
                            .padding(.bottom, 4)
                    }
                }
                .accessibilityHidden(true)
                Text(isSearching ? "No Matches" : "Nothing Saved Yet")
                    .font(isSearching ? .system(size: 13, weight: .semibold) : Brand.wordmarkFont(size: 15))
                    .foregroundStyle(.secondary)
                if !isSearching {
                    Text(emptyMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)
            .allowsHitTesting(false)
        }
    }

    private var emptyMessage: LocalizedStringResource {
        let trigger = model.settings.captureTrigger
        return trigger == .off
            ? "Type a note below, or paste with ⌘V."
            : "Select text in any app and press \(trigger.symbol) to keep it here."
    }
}

private struct SectionHeaderView: View {
    let sectionID: NoteSection.ID
    let title: String
    let isTarget: Bool
    let isRenaming: Bool
    @FocusState.Binding var focus: PanelField?
    @Environment(PanelModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            if isRenaming {
                SectionTitleField(initialTitle: title, focus: $focus)
            } else {
                // User-entered text, so the casing is applied at runtime in the user's locale.
                Text(title.localizedUppercase)
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
                    .accessibilityAddTraits(.isHeader)
                if isTarget {
                    // A single square "pixel", to match the wordmark.
                    Rectangle()
                        .fill(.tint)
                        .frame(width: 5, height: 5)
                        .help("New notes are added to this section")
                        .accessibilityLabel("Default section for new notes")
                }
            }
            Rectangle()
                .fill(.quaternary)
                .frame(height: 1)
        }
        .padding(.horizontal, 6)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .contentShape(.rect)
        .onTapGesture {
            if NSApp.currentEvent?.clickCount == 2 {
                model.beginRenaming(sectionID)
            } else {
                model.store.targetSectionID = sectionID
            }
        }
        .contextMenu {
            Button("Add New Notes Here") { model.store.targetSectionID = sectionID }
                .disabled(isTarget)
            Button("Rename Section") { model.beginRenaming(sectionID) }
            Divider()
            Button("New Section") { model.addSection() }
            Divider()
            Button("Delete Section", role: .destructive) { model.deleteSection(sectionID) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Add New Notes Here") { model.store.targetSectionID = sectionID }
        .accessibilityAction(named: "Rename Section") { model.beginRenaming(sectionID) }
    }
}

private struct SectionTitleField: View {
    @FocusState.Binding var focus: PanelField?
    @Environment(PanelModel.self) private var model
    @State private var draft: String

    /// `initialTitle` only seeds the field when renaming begins.
    init(initialTitle: String, focus: FocusState<PanelField?>.Binding) {
        self._focus = focus
        self.draft = initialTitle
    }

    var body: some View {
        TextField("Section Name", text: $draft)
            .textFieldStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .focused($focus, equals: .sectionTitle)
            .onSubmit { model.commitRename(draft) }
            .onChange(of: focus) { old, new in
                if old == .sectionTitle, new != .sectionTitle, model.renamingSectionID != nil {
                    model.commitRename(draft)
                }
            }
            .frame(maxWidth: 200)
    }
}
