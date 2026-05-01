//
//  ContentView.swift
//  Scan
//
//  Created by nettrash on 16/09/2023.
//

import SwiftUI

struct ContentView: View {
    /// Last marketing version string the user has acknowledged the
    /// "What's new" sheet for. We compare it to the running build's
    /// `CFBundleShortVersionString` on every launch — if they differ,
    /// we present the sheet and stamp the new value once dismissed.
    /// Empty default ⇒ first-ever launch shows the sheet.
    @AppStorage(ScanSettingsKey.lastSeenVersion) private var lastSeenVersion: String = ""

    @State private var showWhatsNew = false
    /// When non-nil, we just received a Universal Link payload
    /// (`https://nettrash.me/scan/<base64url>`) and want to present
    /// the result sheet for it. Fed by `DeepLinkDispatcher` and
    /// `ScannerScreen`'s already-existing `.sheet(item:)` plumbing.
    @State private var deepLinkScan: ScannedCode?
    @ObservedObject private var deepLinks = DeepLinkDispatcher.shared

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

            NavigationStack {
                SettingsScreen()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .onAppear {
            // Decide once per launch whether to show the What's-New
            // sheet. We schedule the state flip async so the first
            // frame of the TabView renders cleanly underneath.
            let current = Self.currentMarketingVersion
            if current != lastSeenVersion && current == WhatsNew.version {
                DispatchQueue.main.async {
                    showWhatsNew = true
                }
            } else if current != lastSeenVersion {
                // Build is *ahead* of the bundled WhatsNew copy (or behind
                // it, in the case of a downgrade for QA). Don't show a
                // mismatched sheet — silently catch the storage up so
                // that next time the WhatsNew copy *is* updated, it
                // shows for that release and not this one.
                lastSeenVersion = current
            }
        }
        .sheet(isPresented: $showWhatsNew, onDismiss: {
            lastSeenVersion = Self.currentMarketingVersion
        }) {
            WhatsNewSheet(onDismiss: {
                lastSeenVersion = Self.currentMarketingVersion
                showWhatsNew = false
            })
        }
        // Cold-start path — if the dispatcher already had a payload
        // waiting (because `.onOpenURL` fired before this view was
        // in the hierarchy), drain it on first appear.
        .onAppear { consumeDeepLinkIfPending() }
        // Warm-start path — `DeepLinkDispatcher.handle(url:)` flips
        // `pending` on every Universal Link arrival.
        .onValueChange(of: deepLinks.pending) { _ in
            consumeDeepLinkIfPending()
        }
        // Result sheet for the decoded payload. Re-uses the same
        // ScanResultSheet UI as live scans by routing through
        // `deepLinkScan: ScannedCode?` — the sheet doesn't care
        // whether the bytes came from the camera or a deep link.
        .sheet(item: $deepLinkScan) { scan in
            DeepLinkResultSheet(scan: scan, onDismiss: { deepLinkScan = nil })
        }
    }

    /// Drain `DeepLinkDispatcher.pending` and turn it into a
    /// `ScannedCode` we can drive the result sheet with. Called on
    /// `.onAppear` (cold start) and on every change to
    /// `deepLinks.pending` (warm start). Symbology comes through
    /// the URL's `?t=` query when present (post-1.6 mints from the
    /// Share Extension); falls back to `.unknown` for vanilla
    /// shareable Universal Links from outside the app, which lets
    /// the parser still do its best from prefix patterns alone.
    private func consumeDeepLinkIfPending() {
        guard let payload = deepLinks.consumePending(), !payload.value.isEmpty else { return }
        deepLinkScan = ScannedCode(
            value: payload.value,
            symbology: payload.symbology,
            avType: "",
            timestamp: Date(),
            previewRect: nil
        )
    }

    /// Marketing version (e.g. "1.2") read from the bundle's
    /// `CFBundleShortVersionString`. Falls back to an empty string in
    /// previews and unit tests where the key may be absent.
    static var currentMarketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
