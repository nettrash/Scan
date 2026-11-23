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
    static let version = "1.10"

    /// Headline shown above the items.
    static let headline = "What's new in 1.10"

    static let items: [WhatsNewItem] = [
        WhatsNewItem(
            systemImage: "sparkles",
            title: "Ask what a code means",
            detail: "A \u{201C}What is this code?\u{201D} button explains an unfamiliar code in plain language \u{2014} with Apple Intelligence on devices that have it, and Scan\u{2019}s built-in explainer everywhere else. What you scanned is never uploaded, and passwords, keys and secrets are blanked out first. Switch the assistant off any time in Settings \u{2192} Insights."
        ),
        WhatsNewItem(
            systemImage: "shield.lefthalf.filled",
            title: "QR safety check",
            detail: "Every code is checked before you are offered an action. Look-alike and disguised addresses, address-bar tricks, risky links, preset payment amounts and two codes stuck on top of each other get a plain-language warning, and a dangerous link offers Copy instead of Open. An ordinary link stays quiet."
        ),
        WhatsNewItem(
            systemImage: "text.viewfinder",
            title: "Live Text and Bulk modes",
            detail: "The Scan tab has three modes now. Live Text reads printed text alongside codes: tap a highlighted block to copy, share or translate it, or freeze the frame to select words. Bulk keeps scanning, counts every distinct code, and saves the list to History or exports it as CSV."
        ),
        WhatsNewItem(
            systemImage: "person.text.rectangle",
            title: "Digital ID, passport and invoice codes",
            detail: "Scan decodes digital-ID codes \u{2014} mobile driving licence and EU wallet connection codes, OpenID4VP requests and credential offers \u{2014} showing who is asking and, when the code itself carries the request, which credential and details it names. Scan never answers a request. It also reads EU Digital Product Passports and EN 16931 e-invoices, so you can check the payee and total before you pay."
        ),
        WhatsNewItem(
            systemImage: "person.badge.key",
            title: "Passkey sign-in codes",
            detail: "The \u{201C}sign in with your phone\u{201D} QR a website shows for passkeys now says what it is for and when it was made, with a phishing caution. Its one-time secret is never shown."
        ),
        WhatsNewItem(
            systemImage: "paintpalette",
            title: "Styled codes, described in a sentence",
            detail: "Generated QR codes can use shaped modules and eyes, gradient inks, a logo and presets, and PNG, SVG and PDF keep the style. Or type what you want \u{2014} \u{201C}Wi-Fi for network BlueHouse, password hunter2\u{201D} \u{2014} and the form fills itself."
        ),
        WhatsNewItem(
            systemImage: "globe",
            title: "On-device translation",
            detail: "Text results and Live Text can be translated with Apple\u{2019}s on-device translation into the language you pick in Settings \u{2192} Insights. If a language needs downloading, iOS asks you first."
        ),
        WhatsNewItem(
            systemImage: "wave.3.right",
            title: "NFC tags",
            detail: "On iPhone, read an NFC tag from the Scan tab, or write a generated code to a writable tag \u{2014} links, phone numbers, Wi-Fi networks and contacts in their own NFC formats."
        ),
        WhatsNewItem(
            systemImage: "square.stack.3d.up",
            title: "Shortcuts and Siri",
            detail: "Scan a code, explain one, generate one or copy your last scan from Shortcuts, Siri or the Action button. Siri never reads out what a scanned code contains."
        ),
        WhatsNewItem(
            systemImage: "arrow.triangle.2.circlepath",
            title: "Carried over from 1.2 \u{2014} 1.9",
            detail: "Mac (Catalyst) and Vision Pro apps, iCloud-synced History, WalletConnect, Nostr, Google Authenticator export, Plus Codes, what3words, IBAN and payment handles, reliable \u{201C}Open in \u{2026}\u{201D} hand-offs, History favourites + CSV export, QR colours / logos / SVG + PDF export, multi-code disambiguation, WPA3 + Passpoint, Universal Links, Share to Scan + PDF \u{2014} all here."
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
