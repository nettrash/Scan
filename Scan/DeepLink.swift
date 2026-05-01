//
//  DeepLink.swift
//  Scan
//
//  Universal Links handler. Apple's `swcd` opens the app when the
//  user follows an `https://nettrash.me/scan/<base64url-payload>`
//  URL anywhere on iOS — Mail, Messages, Safari, AirDrop, …
//
//  We decode the path tail back into the original payload string,
//  parse it through `ScanPayloadParser`, and surface it via
//  `DeepLinkDispatcher` so `ContentView` can present the result
//  sheet directly. No actual scanning happens — the link *is* the
//  scan.
//
//  URL shape:
//
//      https://nettrash.me/scan/<base64url-payload>
//
//  The payload is the raw bytes the QR / barcode would have contained,
//  encoded with the URL-safe base64 variant (`-_`, no `=` padding).
//  This keeps the path round-trippable for arbitrary binary payloads
//  (vCards with newlines, EMVCo merchant blobs with `&` and `=`, …)
//  while staying short enough for the URL to remain shareable.
//

import Foundation
import Combine
import SwiftUI

enum DeepLink {

    /// Custom URL scheme registered in `Scan/Info.plist`. Used by
    /// the Share Extension to hand off to the main app — Universal
    /// Links (https://) bypass the app handler when opened from a
    /// process belonging to the same app group, falling back to
    /// Safari and navigating to nettrash.me. The custom scheme has
    /// no such self-app restriction.
    static let customScheme = "me.nettrash.scan"

    /// What we hand back from `decode(_:)`. Carries both the
    /// payload bytes and the optional symbology hint that lets the
    /// parser pick the right branch (e.g. an EAN-13 symbology
    /// classifies a 13-digit string as `.productCode`; without it
    /// the same string could fall to `.text`). `symbology` is
    /// `.unknown` for URLs minted before 1.6 or by callers that
    /// don't know — the parser still does its best.
    struct Payload: Equatable {
        let value: String
        let symbology: Symbology
    }

    /// Top-level URL → decoded `Payload`. Returns nil for URLs that
    /// aren't ours, paths we don't claim, or payloads we can't decode.
    /// Accepts two URL shapes:
    ///
    ///  - Universal Link: `https://nettrash.me/scan/<base64url>[?t=<symbology>]`
    ///    — what links from outside the app (Mail, Messages,
    ///    Safari, …) take.
    ///  - Custom scheme: `me.nettrash.scan://scan/<base64url>[?t=<symbology>]`
    ///    — what the Share Extension uses to bring the host app
    ///    forward.
    ///
    /// Both shapes share the same path layout, base64-url payload
    /// encoding, and the optional `?t=<symbology-rawValue>` query
    /// (`t` for "type"; the value is one of `Symbology.allCases.rawValue`,
    /// percent-encoded since some raw values contain spaces — e.g.
    /// "Data Matrix", "Code 128").
    static func decode(_ url: URL) -> Payload? {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "https" {
            guard let host = url.host?.lowercased(), host == "nettrash.me" else { return nil }
        } else if scheme == customScheme {
            // No host check — the host part is empty in
            // `me.nettrash.scan://scan/...` and meaningful in
            // `me.nettrash.scan:scan/...` (no `//`); we only care
            // about the trailing `/scan/<base64url>` path.
        } else {
            return nil
        }
        let comps = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let rawPayload: String?
        if comps.count == 2 && comps[0].lowercased() == "scan" {
            rawPayload = base64URLDecode(comps[1])
        } else if scheme == customScheme,
                  url.host?.lowercased() == "scan",
                  comps.count == 1 {
            // `me.nettrash.scan://scan/<payload>` form (host = "scan",
            // path = "/<payload>").
            rawPayload = base64URLDecode(comps[0])
        } else {
            rawPayload = nil
        }
        guard let value = rawPayload else { return nil }

        // Parse `?t=<symbology>` (if present). URLComponents handles
        // the percent decoding for us — `t=Data%20Matrix` lands as
        // `Data Matrix` here, which matches `Symbology.dataMatrix`'s
        // rawValue. Unknown / missing values fall back to `.unknown`,
        // which keeps every pre-1.6 URL working.
        let comps_ = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let typeRaw = comps_?.queryItems?.first(where: { $0.name == "t" })?.value
        let symbology = typeRaw.flatMap { Symbology(rawValue: $0) } ?? .unknown
        return Payload(value: value, symbology: symbology)
    }

    /// Decode URL-safe base64 (`-_`, no padding) back into a UTF-8
    /// string. Pads with `=` to a multiple of 4 first because
    /// `Data(base64Encoded:)` is strict about that. Returns nil
    /// when the input isn't valid base64 or the bytes aren't UTF-8.
    private static func base64URLDecode(_ s: String) -> String? {
        var b64 = s
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // RFC 4648 padding.
        let pad = (4 - b64.count % 4) % 4
        if pad > 0 { b64.append(String(repeating: "=", count: pad)) }
        guard let data = Data(base64Encoded: b64) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Companion encoder — used by the website's `Generate` flow if
    /// it ever wants to mint a deep link. Kept here so the encode
    /// and decode rules stay in lockstep. Set `symbology` to a
    /// non-`.unknown` value to round-trip the type hint to the
    /// parser via the `?t=` query.
    static func encode(payload: String,
                       symbology: Symbology = .unknown,
                       useCustomScheme: Bool = false) -> URL? {
        guard let data = payload.data(using: .utf8) else { return nil }
        let b64 = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let base = useCustomScheme
            ? "\(customScheme)://scan/\(b64)"
            : "https://nettrash.me/scan/\(b64)"
        guard symbology != .unknown,
              let queryEncoded = symbology.rawValue
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else {
            return URL(string: base)
        }
        return URL(string: "\(base)?t=\(queryEncoded)")
    }
}

// MARK: - Dispatcher

/// Singleton bridge between the `onContinueUserActivity` callback
/// (called by `ScanApp`) and the SwiftUI views that want to present
/// the result sheet (`ContentView`). Plumbing the activity via
/// `@EnvironmentObject` would be cleaner but introduces a lifecycle
/// race — `ContentView` may not be in the hierarchy yet when the
/// link fires from a cold start. The singleton holds the pending
/// scan in a Combine `@Published` slot, and `ContentView` flushes
/// it on `onAppear` plus subscribes to `objectWillChange` for
/// warm-start arrivals.
final class DeepLinkDispatcher: ObservableObject {
    static let shared = DeepLinkDispatcher()
    private init() {}

    /// Most recently decoded payload — value + symbology. Read once,
    /// then cleared by `consumePending()` to avoid re-presenting on
    /// every render.
    @Published private(set) var pending: DeepLink.Payload?

    func handle(url: URL) {
        if let payload = DeepLink.decode(url) {
            pending = payload
        }
    }

    /// Called by `ContentView` when it has presented the payload —
    /// nil-out the slot so a re-render of the same view doesn't
    /// re-trigger the sheet.
    func consumePending() -> DeepLink.Payload? {
        let p = pending
        pending = nil
        return p
    }
}

// MARK: - Result sheet for Universal-Link arrivals

/// Presented when the user opens an `https://nettrash.me/scan/<…>`
/// link. Re-uses the parser + `PayloadActionsView` so the displayed
/// fields and smart actions match exactly what a freshly-scanned
/// code would surface — the only difference is that "Save to history"
/// is offered via a single Save button rather than a free-form notes
/// flow, since deep-link arrivals are usually one-offs the user wants
/// to act on, not log.
struct DeepLinkResultSheet: View {
    @Environment(\.managedObjectContext) private var viewContext

    let scan: ScannedCode
    let onDismiss: () -> Void

    @State private var saved = false

    private var payload: ScanPayload {
        ScanPayloadParser.parse(scan.value, symbology: scan.symbology)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(payload.kindLabel)
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                        Spacer()
                        Text("Universal Link")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(scan.value)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }

                PayloadActionsView(payload: payload, raw: scan.value)

                Section {
                    Button {
                        save()
                    } label: {
                        Label(saved ? "Saved to History" : "Save to History",
                              systemImage: saved ? "checkmark" : "tray.and.arrow.down")
                    }
                    .disabled(saved)
                }
            }
            .navigationTitle("Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let record = ScanRecord(context: viewContext)
        record.id = UUID()
        record.value = scan.value
        record.symbology = scan.symbology.displayName
        record.timestamp = Date()
        try? viewContext.save()
        saved = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
