//
//  WhatsNew.swift
//  Scan
//
//  "What's new in this version" sheet, presented automatically on the
//  first launch after the user upgrades from a previous build. The
//  trigger lives in `ContentView`; this file owns the bundled release
//  notes and the sheet UI.
//
//  Notes are stored as a literal Swift array so we don't depend on a
//  bundled markdown resource — keeps the repo simple and lets the
//  notes survive any reshuffling of `Info.plist` keys.
//

import SwiftUI

struct WhatsNewItem: Identifiable {
    /// Stable ID = SF Symbol name (each entry uses a distinct icon
    /// anyway, so this never collides — no need for a UUID).
    var id: String { systemImage }
    let systemImage: String
    let title: String
    let detail: String
}

enum WhatsNew {
    /// Marketing version this card describes. Used as the value we
    /// stash into `@AppStorage(ScanSettingsKey.lastSeenVersion)` once
    /// the user dismisses the sheet, so we don't re-show it on the
    /// next launch. Keep this in sync with `MARKETING_VERSION` in
    /// `Scan.xcodeproj/project.pbxproj`.
    static let version = "1.8"

    /// Headline shown above the items.
    static let headline = "What's new in 1.8"

    static let items: [WhatsNewItem] = [
        WhatsNewItem(
            systemImage: "laptopcomputer",
            title: "Now on Mac",
            detail: "Scan runs natively on macOS via Mac Catalyst. The live scanner uses your Mac's built-in webcam or any Continuity Camera; the Generator and History tabs work exactly as on iPhone."
        ),
        WhatsNewItem(
            systemImage: "visionpro",
            title: "On Vision Pro: library + image import",
            detail: "Apple doesn't expose Vision Pro's world cameras to third-party apps, so live scanning isn't possible there. What you do get is the Generate tab, your full iCloud-synced History, and on-device decoding of any image or PDF you import from Photos or Files."
        ),
        WhatsNewItem(
            systemImage: "shareplay",
            title: "Same library, every device",
            detail: "iCloud sync was already wired up, so your scan history follows you across iPhone, iPad, Mac, and Vision Pro. Scan a Wi-Fi QR on your phone, copy the password from your Mac an hour later."
        ),
        WhatsNewItem(
            systemImage: "arrow.triangle.2.circlepath",
            title: "Carried over from 1.2 — 1.7",
            detail: "Settings tab, History favourites + CSV export, QR colours / logos / SVG + PDF export, multi-code disambiguation, WPA3 + Passpoint, stablecoin tokens, identity-flow detection, loyalty cards, Universal Links, iCloud sync surface, Share to Scan + PDF, pinch-to-zoom + centred-frame scanning — all here."
        ),
    ]
}

// MARK: - Sheet view

struct WhatsNewSheet: View {
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(WhatsNew.headline)
                        .font(.largeTitle.bold())
                        .padding(.top, 8)

                    ForEach(WhatsNew.items) { item in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: item.systemImage)
                                .font(.title2)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 32)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.headline)
                                Text(item.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue", action: onDismiss).bold()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#if DEBUG
struct WhatsNewSheet_Previews: PreviewProvider {
    static var previews: some View {
        WhatsNewSheet(onDismiss: {})
    }
}
#endif
