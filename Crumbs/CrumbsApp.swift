//
//  CrumbsApp.swift
//  Crumbs
//
//  Created by Karat Sidhu on 12/10/26.
//

import SwiftUI
import CoreData

@main
struct CrumbsApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
