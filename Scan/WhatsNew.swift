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
    static let version = "1.6"

    /// Headline shown above the items.
    static let headline = "What's new in 1.6"

    static let items: [WhatsNewItem] = [
        WhatsNewItem(
            systemImage: "square.and.arrow.up.on.square",
            title: "Share to Scan",
            detail: "Scan now shows up in the iOS share sheet for images and PDFs. Long-press a photo, tap Share → Scan, and the result sheet appears without leaving the source app — Photos, Mail, Messages, anywhere a picture can be shared."
        ),
        WhatsNewItem(
            systemImage: "doc.fill",
            title: "PDF support",
            detail: "Multi-page boarding passes and receipts that arrive as PDFs are now decoded page-by-page. Both the share sheet and the in-app Files importer route through the same PDFKit walker."
        ),
        WhatsNewItem(
            systemImage: "rectangle.stack",
            title: "Multi-image batches",
            detail: "Share up to 10 images or PDFs in one go. Scan aggregates the recognised codes into a single list and lets you act on each one individually."
        ),
        WhatsNewItem(
            systemImage: "arrow.triangle.2.circlepath",
            title: "Carried over from 1.2 — 1.5",
            detail: "Settings, History favourites + CSV export, custom QR colours / logos / SVG + PDF export, multi-code disambiguation, WPA3 + Passpoint, stablecoin tokens, identity-flow detection, loyalty cards, Universal Links, iCloud sync surface — all here."
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
