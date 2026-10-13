//
//  PanelRootView.swift
//  Crumbs
//

import SwiftUI

struct PanelRootView: View {
    @Environment(PanelModel.self) private var model
    @Environment(AccessibilityPermission.self) private var permission
    @FocusState private var focus: PanelField?

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(focus: $focus)

            if !permission.isTrusted {
                PermissionBanner()
                    .padding(.horizontal, PanelStyle.horizontalInset)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            NotesListView(focus: $focus)

            ComposerView(focus: $focus)
        }
        .overlay(alignment: .bottom) {
            ToastOverlay()
                .padding(.bottom, 92)
        }
        .tint(Brand.accent)
        .animation(.smooth(duration: 0.25), value: permission.isTrusted)
        .onChange(of: model.focusRequest) {
            focus = model.focusRequest.field
        }
        .onChange(of: focus) {
            model.focusedField = focus
        }
    }
}

private struct ToastOverlay: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        ZStack {
            if let toast = model.toast {
                Label {
                    Text(toast.message)
                } icon: {
                    Image(systemName: toast.systemImage)
                        .foregroundStyle(.tint)
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                // An opaque pill: the panel is already glass, and glass can't sample glass.
                .background(.regularMaterial, in: .capsule)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                .id(toast.id)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: model.toast)
        .allowsHitTesting(false)
    }
}

struct PermissionBanner: View {
    @Environment(AccessibilityPermission.self) private var permission
    @Environment(PanelModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Allow Accessibility access", systemImage: "hand.raised.fill")
                .font(.system(size: 12, weight: .semibold))
            Text("Crumbs needs it to notice \(model.settings.captureTrigger.symbol) and copy your selection from other apps.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open System Settings") {
                permission.request()
                permission.openSystemSettings()
            }
            .controlSize(.small)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(PanelStyle.cardFill, in: PanelStyle.cardShape)
    }
}

#if DEBUG
#Preview("Notes") {
    PanelRootView()
        .environment(PanelModel.preview())
        .environment(AccessibilityPermission(previewTrusted: true))
        .frame(width: 340, height: 640)
}

#Preview("Empty") {
    PanelRootView()
        .environment(PanelModel.preview([]))
        .environment(AccessibilityPermission(previewTrusted: false))
        .frame(width: 340, height: 640)
}
#endif
