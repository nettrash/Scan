//
//  ContentView.swift
//  Scan
//
//  Created by nettrash on 16/09/2023.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                ScannerScreen()
            }
            .tabItem {
                Label("Scan", systemImage: "qrcode.viewfinder")
            }

            NavigationStack {
                GeneratorScreen()
            }
            .tabItem {
                Label("Generate", systemImage: "qrcode")
            }

            NavigationStack {
                HistoryScreen()
            }
            .tabItem {
                Label("History", systemImage: "clock")
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
