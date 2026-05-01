//
//  PayloadActionsView.swift
//  Scan
//
//  Smart-action buttons for a parsed ScanPayload, plus copy & share.
//

import SwiftUI
import UIKit
import Contacts
import ContactsUI
import EventKit
import EventKitUI

struct PayloadActionsView: View {
    let payload: ScanPayload
    let raw: String

    @Environment(\.managedObjectContext) private var viewContext

    @State private var showShare = false
    @State private var showAddContact = false
    @State private var showAddCalendar = false
    @State private var calendarStore: EKEventStore?
    @State private var calendarError: String?
    @State private var copied = false
    /// Loyalty-card "save with merchant" alert. The text field is
    /// stored locally; `showLoyaltyAlert` toggles the alert and
    /// `loyaltySaved` flips a confirmation tick once the row is in
    /// Core Data.
    @State private var showLoyaltyAlert = false
    @State private var loyaltyMerchant = ""
    @State private var loyaltySaved = false

    var body: some View {
        Section("Actions") {
            smartActions

            Button {
                UIPasteboard.general.string = raw
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Label(copied ? "Copied!" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
            }

            Button {
                showShare = true
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [raw])
        }
        .sheet(isPresented: $showAddContact) {
            if case .contact(let c) = payload {
                AddContactSheet(
                    contact: c,
                    onComplete: { _ in showAddContact = false }
                )
            }
        }
        .sheet(isPresented: $showAddCalendar) {
            if case .calendar(let cal) = payload, let store = calendarStore {
                AddCalendarEventSheet(
                    event: cal,
                    store: store,
                    onComplete: { _ in showAddCalendar = false }
                )
            }
        }
        .alert("Calendar access denied",
               isPresented: Binding(
                   get: { calendarError != nil },
                   set: { if !$0 { calendarError = nil } }
               ),
               presenting: calendarError) { _ in
            Button("OK", role: .cancel) {}
        } message: { msg in
            Text(msg)
        }
        .alert("Save as loyalty card", isPresented: $showLoyaltyAlert) {
            TextField("Merchant (e.g. Tesco, IKEA)", text: $loyaltyMerchant)
                .autocorrectionDisabled()
            Button("Save") { saveAsLoyaltyCard() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved scans tagged \"Loyalty: …\" are favourited so they pin to the top of History.")
        }
    }

    /// Persist the current `raw` payload as a favourited History row
    /// with `notes = "Loyalty: <merchant>"`. The History screen's
    /// search field matches the notes, and the `isFavorite` flag
    /// keeps the row pinned. Empty merchant input is allowed —
    /// "Loyalty: " alone is still a valid filter target.
    private func saveAsLoyaltyCard() {
        let trimmed = loyaltyMerchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = ScanRecord(context: viewContext)
        record.id = UUID()
        record.value = raw
        // Try to surface the symbology if we have one.
        if case .productCode(_, let system) = payload {
            record.symbology = system
        } else {
            record.symbology = "Loyalty"
        }
        record.timestamp = Date()
        record.notes = trimmed.isEmpty ? "Loyalty" : "Loyalty: \(trimmed)"
        record.isFavorite = true
        do {
            try viewContext.save()
            loyaltySaved = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            // Surface the failure via the existing copied/saved
            // flicker — a dedicated alert would be heavy for what's
            // typically a transient Core Data issue.
            loyaltySaved = false
        }
    }

    @ViewBuilder
    private var smartActions: some View {
        switch payload {
        case .url(let url):
            Button {
                UIApplication.shared.open(url)
            } label: {
                Label("Open in Safari", systemImage: "safari")
            }
            Text(url.absoluteString)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

        case .email(let address, let subject, let body):
            Button {
                openMail(to: address, subject: subject, body: body)
            } label: {
                Label("Compose email to \(address)", systemImage: "envelope")
            }

        case .phone(let number):
            Button {
                openTel(number)
            } label: {
                Label("Call \(number)", systemImage: "phone")
            }

        case .sms(let number, let body):
            Button {
                openSMS(to: number, body: body)
            } label: {
                Label("Send SMS to \(number)", systemImage: "message")
            }

        case .wifi(let ssid, let password, let security, let hidden):
            VStack(alignment: .leading, spacing: 6) {
                Label("Wi-Fi network: \(ssid)", systemImage: "wifi")
                if let security, !security.isEmpty {
                    Text("Security: \(friendlyWifiSecurity(security))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if security.uppercased() == "HS20" {
                        // iOS doesn't have a public API for
                        // programmatically installing a Passpoint
                        // profile, and dropping the user into a
                        // generic Wi-Fi settings doesn't help much
                        // either. Be explicit about the limitation.
                        Text("Passpoint profiles must be installed manually — pass this QR's contents to your IT team or the venue's portal.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                if hidden {
                    Text("Hidden network").font(.caption).foregroundStyle(.secondary)
                }
                if let password, !password.isEmpty {
                    HStack {
                        Text("Password:")
                        Text(password).font(.body.monospaced()).textSelection(.enabled)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = password
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                    }
                    .font(.caption)
                }
            }
            Button {
                openSettings()
            } label: {
                Label("Open Wi-Fi Settings", systemImage: "gear")
            }

        case .geo(let lat, let lon, let query):
            Button {
                openMaps(lat: lat, lon: lon, query: query)
            } label: {
                Label("Open in Maps", systemImage: "map")
            }
            Text(String(format: "%.5f, %.5f", lat, lon))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            if let query, !query.isEmpty {
                Text(query).font(.caption).foregroundStyle(.secondary)
            }

        case .contact(let c):
            if let name = c.fullName, !name.isEmpty {
                Text(name).font(.headline)
            }
            ForEach(c.phones, id: \.self) { p in
                Button {
                    openTel(p)
                } label: {
                    Label(p, systemImage: "phone")
                }
            }
            ForEach(c.emails, id: \.self) { e in
                Button {
                    openMail(to: e, subject: nil, body: nil)
                } label: {
                    Label(e, systemImage: "envelope")
                }
            }
            ForEach(c.urls, id: \.self) { s in
                if let u = URL(string: s) {
                    Button {
                        UIApplication.shared.open(u)
                    } label: {
                        Label(s, systemImage: "link")
                    }
                }
            }
            Button {
                showAddContact = true
            } label: {
                Label("Add to Contacts", systemImage: "person.crop.circle.badge.plus")
            }

        case .calendar(let cal):
            LabelledFieldsList(fields: cal.labelledFields)
            Button {
                requestCalendarAccess { store in
                    if let store {
                        calendarStore = store
                        showAddCalendar = true
                    } else {
                        calendarError = "Allow Calendar access in Settings to add events from a scanned QR."
                    }
                }
            } label: {
                Label("Add to Calendar", systemImage: "calendar.badge.plus")
            }

        case .otp:
            Text("One-time password URI")
            Text("Open with your authenticator app of choice via Share.")
                .font(.caption).foregroundStyle(.secondary)

        case .productCode(let code, let system):
            Label("\(system): \(code)", systemImage: "barcode")
            if let url = URL(string: "https://www.google.com/search?q=\(code)") {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    Label("Look up product", systemImage: "magnifyingglass")
                }
            }
            // Loyalty-card affordance — surfacing it here is the
            // pragmatic answer to "let me Add to Wallet this loyalty
            // barcode": iOS PassKit needs a server-signed `.pkpass`
            // we can't mint client-side, so instead we save a
            // favourited History row tagged with the merchant name.
            // The user re-finds the code via History → Favourites
            // (and the merchant tag makes search trivial).
            Button {
                loyaltyMerchant = ""
                showLoyaltyAlert = true
            } label: {
                Label(loyaltySaved ? "Saved as loyalty card" : "Save as loyalty card",
                      systemImage: loyaltySaved ? "checkmark" : "creditcard.and.123")
            }
            .disabled(loyaltySaved)

        case .crypto(let p):
            LabelledFieldsList(fields: p.labelledFields)
            if let url = URL(string: p.raw) {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    Label("Open in Wallet", systemImage: "wallet.pass")
                }
            }

        case .epcPayment(let p):
            LabelledFieldsList(fields: p.labelledFields)

        case .swissQRBill(let p):
            LabelledFieldsList(fields: p.labelledFields)

        case .ruPayment(let p):
            LabelledFieldsList(fields: p.labelledFields)

        case .fnsReceipt(let p):
            LabelledFieldsList(fields: p.labelledFields)

        case .emvPayment(let p):
            LabelledFieldsList(fields: p.labelledFields)

        case .sufReceipt(let p):
            LabelledFieldsList(fields: p.labelledFields)
            Button {
                UIApplication.shared.open(p.url)
            } label: {
                Label("Verify Receipt", systemImage: "checkmark.seal")
            }

        case .ipsPayment(let p):
            LabelledFieldsList(fields: p.labelledFields)

        case .upiPayment(let p):
            LabelledFieldsList(fields: p.labelledFields)
            if let url = URL(string: p.raw) {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    Label("Open in UPI app", systemImage: "indianrupeesign.circle")
                }
            }

        case .czechSPD(let p):
            LabelledFieldsList(fields: p.labelledFields)

        case .paBySquare(let p):
            LabelledFieldsList(fields: p.labelledFields)

        case .regionalPayment(let p):
            LabelledFieldsList(fields: p.labelledFields)
            if let url = URL(string: p.raw) {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    Label("Open in \(p.scheme.rawValue)", systemImage: "arrow.up.forward.app")
                }
            }

        case .magnet(let m):
            LabelledFieldsList(fields: m.labelledFields)
            if let url = URL(string: m.raw) {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    Label("Open in torrent client", systemImage: "link.badge.plus")
                }
            }

        case .gs1(let g):
            LabelledFieldsList(fields: g.labelledFields)
            if let gtin = g.gtin,
               let lookupURL = URL(string: "https://www.google.com/search?q=GTIN+\(gtin)") {
                Button {
                    UIApplication.shared.open(lookupURL)
                } label: {
                    Label("Look up GTIN \(gtin)", systemImage: "magnifyingglass")
                }
            }

        case .boardingPass(let bp):
            LabelledFieldsList(fields: bp.labelledFields)
            // No "open in" action — boarding passes don't have a universal
            // handler scheme. Copy / Share are the standard affordances.

        case .drivingLicense(let dl):
            LabelledFieldsList(fields: dl.labelledFields)
            // Same as boarding pass — Copy / Share are the actions.

        case .richURL(let r):
            LabelledFieldsList(fields: r.labelledFields)
            // Digital identity flows can be coerced into impersonation:
            // a stranger's QR will *try* to log you in to their flow as
            // *you*. Always make the user confirm they initiated it.
            if r.kind == .digitalIdentity {
                Label(
                    "Identity flow — only continue if you started this login yourself.",
                    systemImage: "exclamationmark.shield"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }
            Button {
                UIApplication.shared.open(r.url)
            } label: {
                Label(Self.richURLActionLabel(r.kind),
                      systemImage: Self.richURLActionSymbol(r.kind))
            }

        case .text:
            EmptyView()
        }
    }

    private static func richURLActionLabel(_ kind: RichURLPayload.Kind) -> String {
        switch kind {
        case .whatsApp:    return "Open in WhatsApp"
        case .telegram:    return "Open in Telegram"
        case .appleWallet: return "Add to Wallet"
        case .appStore:    return "Open in App Store"
        case .playStore:   return "Open Play Store listing"
        case .youtube:     return "Watch on YouTube"
        case .spotify:     return "Open in Spotify"
        case .appleMusic:  return "Open in Apple Music"
        case .googleMaps, .appleMaps: return "Open in Maps"
        case .digitalIdentity:        return "Continue in browser"
        }
    }

    private static func richURLActionSymbol(_ kind: RichURLPayload.Kind) -> String {
        switch kind {
        case .whatsApp, .telegram:    return "message"
        case .appleWallet:            return "wallet.pass"
        case .appStore, .playStore:   return "arrow.down.app"
        case .youtube:                return "play.rectangle"
        case .spotify, .appleMusic:   return "music.note"
        case .googleMaps, .appleMaps: return "map"
        case .digitalIdentity:        return "person.text.rectangle"
        }
    }

    // MARK: - URL helpers

    private func openTel(_ number: String) {
        let cleaned = number.filter { "0123456789+*#".contains($0) }
        if let url = URL(string: "tel:\(cleaned)") { UIApplication.shared.open(url) }
    }
    private func openSMS(to number: String, body: String?) {
        var s = "sms:\(number)"
        if let body, var c = URLComponents(string: s) {
            c.queryItems = [URLQueryItem(name: "body", value: body)]
            s = c.string ?? s
        }
        if let url = URL(string: s) { UIApplication.shared.open(url) }
    }
    private func openMail(to address: String, subject: String?, body: String?) {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = address
        var items: [URLQueryItem] = []
        if let subject { items.append(URLQueryItem(name: "subject", value: subject)) }
        if let body    { items.append(URLQueryItem(name: "body", value: body)) }
        if !items.isEmpty { c.queryItems = items }
        if let url = c.url { UIApplication.shared.open(url) }
    }
    private func openMaps(lat: Double, lon: Double, query: String?) {
        var s = "http://maps.apple.com/?ll=\(lat),\(lon)"
        if let query, let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            s += "&q=\(encoded)"
        }
        if let url = URL(string: s) { UIApplication.shared.open(url) }
    }
    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Labelled fields list (used for bank / receipt payloads)

/// A vertical stack of `LabelledFieldRow` items, each tappable to copy its
/// value to the pasteboard. Designed to be embedded inside a Form Section.
struct LabelledFieldsList: View {
    let fields: [LabelledField]
    var body: some View {
        ForEach(fields) { f in
            LabelledFieldRow(field: f)
        }
    }
}

private struct LabelledFieldRow: View {
    let field: LabelledField
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(field.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(field.value)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(4)
            }
            Spacer(minLength: 8)
            Button {
                UIPasteboard.general.string = field.value
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .imageScale(.medium)
                    .foregroundStyle(copied ? Color.green : Color.accentColor)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Copy \(field.label)")
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Add contact sheet

/// Hosts the system "New Contact" UI. The user explicitly taps Done to save
/// (or Cancel to discard); we forward that decision back to SwiftUI so we can
/// dismiss the sheet.
struct AddContactSheet: UIViewControllerRepresentable {
    let contact: ScanPayload.ContactPayload
    /// Called with `true` if the user saved a contact, `false` if they cancelled.
    let onComplete: (Bool) -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let cn = Self.makeCNContact(from: contact)
        let vc = CNContactViewController(forNewContact: cn)
        vc.allowsActions = true
        vc.delegate = context.coordinator

        let nav = UINavigationController(rootViewController: vc)
        // CNContactViewController provides its own bar buttons; hide the
        // wrapping UINavigationController's bar so we don't double up.
        nav.setNavigationBarHidden(false, animated: false)
        return nav
    }

    func updateUIViewController(_ vc: UINavigationController, context: Context) {
        // Keep the coordinator in sync if SwiftUI rebuilds the wrapper.
        context.coordinator.onComplete = onComplete
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    final class Coordinator: NSObject, CNContactViewControllerDelegate {
        var onComplete: (Bool) -> Void
        init(onComplete: @escaping (Bool) -> Void) { self.onComplete = onComplete }

        func contactViewController(_ viewController: CNContactViewController,
                                   didCompleteWith contact: CNContact?) {
            // Per Apple docs: contact is non-nil if the user saved, nil if cancelled.
            let saved = (contact != nil)
            onComplete(saved)
        }
    }

    // MARK: - Build a CNMutableContact from our parsed payload

    private static func makeCNContact(from payload: ScanPayload.ContactPayload) -> CNMutableContact {
        let cn = CNMutableContact()

        if let full = payload.fullName, !full.isEmpty {
            // vCard "FN" can be a single string; split into given/family on
            // the first space so the system editor pre-populates both fields.
            let parts = full.split(separator: " ", maxSplits: 1).map(String.init)
            cn.givenName = parts.first ?? ""
            cn.familyName = parts.dropFirst().first ?? ""
        }

        cn.phoneNumbers = payload.phones.map {
            CNLabeledValue(label: CNLabelPhoneNumberMobile,
                           value: CNPhoneNumber(stringValue: $0))
        }
        cn.emailAddresses = payload.emails.map {
            CNLabeledValue(label: CNLabelHome, value: $0 as NSString)
        }
        cn.urlAddresses = payload.urls.map {
            CNLabeledValue(label: CNLabelHome, value: $0 as NSString)
        }
        if let org = payload.organization, !org.isEmpty {
            cn.organizationName = org
        }
        // Note: setting `cn.note` requires the
        // `com.apple.developer.contacts.notes` entitlement on iOS 13+. We omit
        // it deliberately so the build stays entitlement-free; if the scanned
        // payload had a note, the user can paste it manually.
        return cn
    }
}

// MARK: - Add calendar event sheet

/// Hosts EKEventEditViewController as the sheet content. The caller is
/// responsible for requesting write-access first and passing in an authorised
/// EKEventStore — see `requestCalendarAccess(_:)` below.
struct AddCalendarEventSheet: UIViewControllerRepresentable {
    let event: CalendarPayload
    let store: EKEventStore
    /// `true` if the user saved (action `.saved`) — anything else is treated
    /// as a cancel/dismiss.
    let onComplete: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let ek = EKEvent(eventStore: store)
        ek.title    = event.summary
        ek.startDate = event.startDate ?? Date()
        ek.endDate   = event.endDate
            ?? (event.startDate ?? Date()).addingTimeInterval(3600)
        ek.isAllDay = event.allDay
        ek.location = event.location
        ek.notes    = event.description
        if let url = event.url { ek.url = url }

        // EKEventEditViewController IS itself a UINavigationController, so we
        // can hand it to SwiftUI directly.
        let vc = EKEventEditViewController()
        vc.event = ek
        vc.eventStore = store
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: EKEventEditViewController, context: Context) {
        context.coordinator.onComplete = onComplete
    }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        var onComplete: (Bool) -> Void
        init(onComplete: @escaping (Bool) -> Void) { self.onComplete = onComplete }

        func eventEditViewController(
            _ controller: EKEventEditViewController,
            didCompleteWith action: EKEventEditViewAction
        ) {
            // EKEventEditViewController dismisses itself — we just forward
            // the result so the SwiftUI binding can flip back to false.
            onComplete(action == .saved)
        }
    }
}

/// Requests write-only access to the user's calendars and hands back the
/// authorised `EKEventStore` on success (nil on denial). Uses the iOS 17+
/// least-privilege API exclusively — the deployment target requires iOS 17.
func requestCalendarAccess(completion: @escaping (EKEventStore?) -> Void) {
    let store = EKEventStore()
    store.requestWriteOnlyAccessToEvents { granted, _ in
        DispatchQueue.main.async { completion(granted ? store : nil) }
    }
}

// MARK: - Wi-Fi security friendly label (1.4: WPA3 + Passpoint)

/// Map the raw `T:` field of a `WIFI:` payload to a user-friendly
/// label. Anything we don't recognise is passed through verbatim so a
/// future security tag still surfaces *something* in the result sheet
/// instead of being silently dropped.
internal func friendlyWifiSecurity(_ raw: String) -> String {
    switch raw.uppercased() {
    case "WPA", "WPA2": return "WPA / WPA2"
    case "WEP":         return "WEP"
    case "SAE", "WPA3": return "WPA3 (SAE)"
    case "HS20", "PASSPOINT", "OSU": return "Passpoint (HS20)"
    case "NOPASS", "NONE", "":       return "None"
    default:                         return raw
    }
}
