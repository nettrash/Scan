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
    /// The visible tab. Only moved in code by the Start Scanning App Intent
    /// (via `ScanIntentRouter`), which has to land on the camera even when
    /// the app was left on another tab — and with nothing of ours over it:
    /// this view takes down whatever is presented over the window, from any
    /// tab, and drops its deep-link and What's New sheets; `ScannerScreen`
    /// clears its own state.
    @State private var selectedTab: RootTab = .scan
    @ObservedObject private var intentRouter = ScanIntentRouter.shared

    private enum RootTab: Hashable {
        case scan, generate, history, settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ScannerScreen()
            }
            .tabItem {
                Label("Scan", systemImage: "qrcode.viewfinder")
            }
            .tag(RootTab.scan)

            NavigationStack {
                GeneratorScreen()
            }
            .tabItem {
                Label("Generate", systemImage: "qrcode")
            }
            .tag(RootTab.generate)

            NavigationStack {
                HistoryScreen()
            }
            .tabItem {
                Label("History", systemImage: "clock")
            }
            .tag(RootTab.history)

            NavigationStack {
                SettingsScreen()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(RootTab.settings)
        }
        // Start Scanning App Intent — see `ScanIntentRouter`. Whatever is
        // over the window goes first: a sheet, picker or alert from any tab
        // (a History share sheet, the Generate tab's photo picker, …) or the
        // Files picker. A What's New sheet already up counts as seen once it
        // goes (its `onDismiss` stamps the version); a deep-link result is
        // simply closed.
        .onValueChange(of: intentRouter.scannerRequests) { _ in
            Self.dismissPresentedControllers()
            selectedTab = .scan
            deepLinkScan = nil
            showWhatsNew = false
        }
        .onAppear {
            // Decide once per launch whether to show the What's-New
            // sheet. We schedule the state flip async so the first
            // frame of the TabView renders cleanly underneath.
            let current = Self.currentMarketingVersion
            if current != lastSeenVersion && current == WhatsNew.version {
                DispatchQueue.main.async {
                    // A launch that came from Start Scanning is for the
                    // camera. The version stays unstamped, so the sheet
                    // shows on the next ordinary launch instead.
                    guard intentRouter.scannerRequests == 0 else { return }
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

    /// Takes down everything presented over each window's root view
    /// controller, without animation: dismissing the root's presented
    /// controller dismisses the whole stack above it. SwiftUI sees its own
    /// sheets go and resets their bindings, as after a swipe-down.
    @MainActor
    private static func dismissPresentedControllers() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.rootViewController?.presentedViewController?.dismiss(animated: false)
            }
        }
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
