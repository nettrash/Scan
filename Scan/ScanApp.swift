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
                // Universal Link arrival — Apple's `swcd` opens the
                // app and hands the URL via NSUserActivity-browsing-web.
                // We hand it to the dispatcher; ContentView reads and
                // consumes the payload on its `onAppear` / publisher
                // subscription so a sheet pops up immediately.
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL {
                        DeepLinkDispatcher.shared.handle(url: url)
                    }
                }
                // Cold-start path — `swcd` opens the app *and* sets
                // the launch URL; SwiftUI surfaces it via `.onOpenURL`
                // in addition to the user-activity callback above.
                .onOpenURL { url in
                    DeepLinkDispatcher.shared.handle(url: url)
                }
        }
    }
}
