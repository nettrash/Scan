//
//  ShareViewController.swift
//  ScanShareExtension
//
//  Entry point for the share extension. iOS instantiates this class
//  when the user picks "Scan" from the iOS share sheet (after the
//  activation rule in Info.plist matches against the shared
//  content). We're a UIViewController subclass that hosts a SwiftUI
//  view so the actual UI lives in `ShareView.swift` — this file is
//  just the bridge.
//
//  Lifecycle:
//   1. iOS allocates ShareViewController and sets `extensionContext`.
//   2. `viewDidLoad` reads `extensionContext.inputItems`, extracts
//      every NSItemProvider that's an image or PDF, and hands them
//      to `ShareView`.
//   3. ShareView decodes and renders.
//   4. The "Done" button in ShareView calls
//      `extensionContext.completeRequest(...)` which dismisses the
//      sheet and (on iOS 8.2+) returns control to the source app.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let items = extractItems()

        let host = UIHostingController(rootView: ShareView(
            items: items,
            onDone: { [weak self] in
                // Returning empty items + nil error tells iOS the
                // user finished without sending anything back to the
                // host app — closes the sheet cleanly.
                self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            },
            onOpenInApp: { [weak self] code in
                self?.openInHostApp(code: code)
            }
        ))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    // MARK: - Item extraction

    /// Walk every NSExtensionItem in the input and pull out
    /// providers we can handle. The system already filtered against
    /// our activation rule before invoking us, so most providers
    /// here will load successfully — but we still re-check the
    /// type identifier per provider to guard against the
    /// occasional malformed share.
    private func extractItems() -> [ShareView.Item] {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem]
        else { return [] }
        var out: [ShareView.Item] = []
        for extItem in extensionItems {
            guard let providers = extItem.attachments else { continue }
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                    out.append(.init(provider: provider, kind: .pdf))
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    out.append(.init(provider: provider, kind: .image))
                }
            }
        }
        return out
    }

    // MARK: - "Open in Scan" hand-off

    /// Open the main Scan app via its custom-scheme route, carrying
    /// the decoded value AND the symbology hint. The extension is a
    /// separate process — it can't reach into the main app's Core
    /// Data — so passing the payload through the link is the
    /// simplest hand-off. The custom scheme is required (vs. the
    /// Universal Link) because iOS bypasses UL handlers when a URL
    /// is opened from inside the same app's process group, and the
    /// Share Extension counts as that.
    private func openInHostApp(code: ScannedCode) {
        guard let url = encodeDeepLink(payload: code.value, symbology: code.symbology) else { return }
        // Walk the responder chain looking for a parent we can ask
        // to open URLs. Apple's recommended idiom — share extensions
        // can't call UIApplication.shared.open directly.
        var responder: UIResponder? = self
        while responder != nil {
            if let app = responder as? UIApplication {
                app.open(url, options: [:], completionHandler: nil)
                break
            }
            responder = responder?.next
        }
        // Whichever way it went, dismiss the sheet.
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    /// Mints the URL we hand off to the host app. Custom-scheme is
    /// required (vs. the Universal Link `https://nettrash.me/scan/...`)
    /// because iOS bypasses the UL handler when a URL is opened
    /// from a process that belongs to the same app's process group
    /// — including share extensions — and falls back to Safari. The
    /// scheme registered in `Scan/Info.plist`'s `CFBundleURLTypes`
    /// has no such self-app restriction.
    ///
    /// Format: `me.nettrash.scan://scan/<base64url-payload>?t=<symbology>`.
    /// The `?t=` query is the symbology hint (`Symbology.rawValue`,
    /// percent-encoded for the spaces in "Data Matrix" / "Code 128").
    /// Without it the parser would lose the symbology context that
    /// distinguishes a 13-digit EAN-13 product code from a generic
    /// 13-digit numeric string. `DeepLink.decode(_:)` in the main
    /// app handles both encoded forms.
    private func encodeDeepLink(payload: String, symbology: Symbology) -> URL? {
        guard let data = payload.data(using: .utf8) else { return nil }
        let b64 = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let base = "me.nettrash.scan://scan/\(b64)"
        guard symbology != .unknown,
              let typeQuery = symbology.rawValue
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else {
            return URL(string: base)
        }
        return URL(string: "\(base)?t=\(typeQuery)")
    }
}
