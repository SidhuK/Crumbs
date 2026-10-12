//
//  ComposerView.swift
//  Crumbs
//

import SwiftUI

struct ComposerView: View {
    @FocusState.Binding var focus: PanelField?
    @Environment(PanelModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let isFocused = focus == .composer

        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "circle")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            TextField(text: $model.composerText, prompt: Text(model.composerPlaceholder), axis: .vertical) {
                Text(model.composerPlaceholder)
            }
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .lineLimit(1...6)
            .focused($focus, equals: .composer)
            .accessibilityIdentifier("composer")
            .onSubmit { model.submitComposer() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
        .background(PanelStyle.cardFill, in: PanelStyle.cardShape)
        .overlay {
            PanelStyle.cardShape
                .strokeBorder(.tint, lineWidth: 2)
                .opacity(isFocused ? 1 : 0)
        }
        .contentShape(PanelStyle.cardShape)
        .onTapGesture { model.focus(.composer) }
        .animation(.smooth(duration: 0.15), value: isFocused)
        .padding(.horizontal, PanelStyle.horizontalInset)
        .padding(.top, 4)
        .padding(.bottom, PanelStyle.horizontalInset)
    }
}
