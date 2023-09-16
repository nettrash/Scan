//
//  ScanApp.swift
//  Scan
//
//  Created by nettrash on 16/09/2023.
//

import SwiftUI

@main
struct ScanApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
