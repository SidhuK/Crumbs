//
//  CrumbsApp.swift
//  Crumbs
//
//  Created by Karat Sidhu on 12/10/26.
//

import SwiftUI

@main
struct CrumbsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Crumbs", systemImage: "square.stack.3d.down.forward") {
            if let controller = appDelegate.controller {
                MenuBarMenu(controller: controller)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Nil while hosting unit tests, so tests never read, create or watch the user's notes.
    let controller: AppController? = AppDelegate.isRunningTests ? nil : AppController()

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.willTerminate()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.showPanel()
        return false
    }
}

private struct MenuBarMenu: View {
    let controller: AppController

    var body: some View {
        Button("Show Panel") { controller.showPanel() }
        Button("Settings…") { controller.showSettings() }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Crumbs") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
