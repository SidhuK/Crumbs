//
//  PanelHeader.swift
//  Crumbs
//

import SwiftUI

struct PanelHeader: View {
    @FocusState.Binding var focus: PanelField?
    @Environment(PanelModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 10) {
            Wordmark(size: 20)
                .padding(.leading, 6)
            searchRow
        }
        .padding(.horizontal, PanelStyle.horizontalInset)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .background(WindowDragArea())
    }

    private var searchRow: some View {
        @Bindable var model = model

        return HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .focused($focus, equals: .search)
                if !model.searchText.isEmpty {
                    Button("Clear Search", systemImage: "xmark.circle.fill") {
                        model.searchText = ""
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(PanelStyle.cardFill, in: .capsule)

            PanelMenu()
                .background(PanelStyle.cardFill, in: .circle)
        }
    }
}

private struct PanelMenu: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        @Bindable var model = model
        @Bindable var settings = model.settings
        let store = model.store

        Menu {
            Section("Lists") {
                Picker("List", selection: $model.activeListName) {
                    ForEach(store.listNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Button("New List…") { model.host?.promptForNewList() }
                Button("Rename List…") { model.host?.promptToRenameList() }
                Button("Move List to Trash…") { model.host?.confirmTrashList() }
            }

            Divider()

            Button("New Section") { model.addSection() }
            Toggle("Hide Done Notes", isOn: $settings.hideDoneNotes)
            Button("Clear Done Notes") { model.store.clearDone() }
                .disabled(!store.hasDoneNotes)

            Divider()

            Button("Show in Finder") { model.host?.revealListInFinder() }
            Button("Settings…") { model.host?.showSettings() }
            Button("Hide Panel") { model.host?.hidePanel() }

            Divider()

            Button("Quit Crumbs") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .contentShape(.circle)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("More")
    }
}
