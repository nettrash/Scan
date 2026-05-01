//
//  RichURLPayload.swift
//  Scan
//
//  Recognises specific URL flavours — WhatsApp click-to-chat, Telegram
//  links, Apple Wallet passes, App Store / Play Store, YouTube, Spotify,
//  Apple Music, Google Maps share, Apple Maps share — and surfaces a
//  more useful smart action than "Open in Safari".
//
//  This file *parses*; the dispatch logic in `ScanPayloadParser.parse()`
//  decides whether to return `.richURL` or fall through to `.url`.
//

import Foundation

/// A URL we recognised as a known service / format.
struct RichURLPayload: Equatable {

    enum Kind: String, Equatable {
        case whatsApp     = "WhatsApp"
        case telegram     = "Telegram"
        case appleWallet  = "Apple Wallet"
        case appStore     = "App Store"
        case playStore    = "Google Play"
        case youtube      = "YouTube"
        case spotify      = "Spotify"
        case appleMusic   = "Apple Music"
        case googleMaps   = "Google Maps"
        case appleMaps    = "Apple Maps"
        /// New in 1.4. Identity-flow URLs — DigiD (NL government
        /// SSO), EUDI Wallet (EU Digital Identity), and the generic
        /// OpenID4VC verifier / issuer endpoints they're built on.
        /// Special-cased so the result sheet can show a security
        /// warning before the user taps "Continue in browser".
        case digitalIdentity = "Digital identity"
    }

    let kind: Kind
    let url: URL
    /// One or two key fields the UI surfaces above the smart action — e.g.
    /// `["Phone": "+12025551212", "Message": "Hello"]` for WhatsApp.
    let fields: [LabelledField]

    var labelledFields: [LabelledField] {
        var rows = [LabelledField(label: "Service", value: kind.rawValue)]
        rows.append(contentsOf: fields)
        rows.append(.init(label: "URL", value: url.absoluteString))
        return rows
    }
}

enum RichURLParser {

    /// Recognise the URL's flavour. Returns nil for everything that should
    /// stay a plain `.url`.
    static func parse(_ url: URL) -> RichURLPayload? {
        guard let host = url.host?.lowercased() else { return nil }
        let path = url.path
        let scheme = url.scheme?.lowercased() ?? ""
        // Only http/https URLs are handled here — wallet / app-scheme URIs
        // are recognised below as additional non-http fast paths.
        guard scheme == "http" || scheme == "https" else { return nil }

        // -- WhatsApp click-to-chat --------------------------------------
        // wa.me/<phone>?text=<msg>   or   api.whatsapp.com/send?phone=…&text=…
        if host == "wa.me" || host.hasSuffix(".wa.me") {
            let phone = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let text = url.queryItem("text")
            return RichURLPayload(
                kind: .whatsApp, url: url,
                fields: [
                    LabelledField(label: "Phone", value: phone),
                    text.map { LabelledField(label: "Message", value: $0) }
                ].compactMap { $0 }
            )
        }
        if host == "api.whatsapp.com" || host == "whatsapp.com" {
            let phone = url.queryItem("phone") ?? ""
            let text  = url.queryItem("text")
            return RichURLPayload(
                kind: .whatsApp, url: url,
                fields: [
                    LabelledField(label: "Phone", value: phone),
                    text.map { LabelledField(label: "Message", value: $0) }
                ].compactMap { $0 }
            )
        }

        // -- Telegram ----------------------------------------------------
        // t.me/<username>   t.me/<channel>   t.me/joinchat/<token>
        if host == "t.me" || host == "telegram.me" {
            let segs = path.split(separator: "/").map(String.init)
            let target = segs.joined(separator: "/")
            return RichURLPayload(
                kind: .telegram, url: url,
                fields: target.isEmpty ? [] : [
                    LabelledField(label: "Target", value: "@" + target)
                ]
            )
        }

        // -- Apple Wallet pass -------------------------------------------
        if path.lowercased().hasSuffix(".pkpass") {
            return RichURLPayload(
                kind: .appleWallet, url: url,
                fields: [LabelledField(label: "Pass file", value: url.lastPathComponent)]
            )
        }

        // -- App Store ---------------------------------------------------
        // apps.apple.com/<country>/app/<slug>/id<digits>[?…]
        if host == "apps.apple.com" || host == "itunes.apple.com" {
            // Pull the trailing /id<digits> path component.
            let segs = path.split(separator: "/").map(String.init)
            let appId = segs.first(where: { $0.hasPrefix("id") })?.dropFirst(2)
            return RichURLPayload(
                kind: .appStore, url: url,
                fields: appId.map { [LabelledField(label: "App ID", value: String($0))] } ?? []
            )
        }

        // -- Google Play -------------------------------------------------
        // play.google.com/store/apps/details?id=<package>
        if host == "play.google.com" {
            let pkg = url.queryItem("id")
            return RichURLPayload(
                kind: .playStore, url: url,
                fields: pkg.map { [LabelledField(label: "Package", value: $0)] } ?? []
            )
        }

        // -- YouTube -----------------------------------------------------
        // youtube.com/watch?v=<id>  |  youtu.be/<id>  |  youtube.com/shorts/<id>
        if host == "youtu.be" || host.hasSuffix("youtube.com") {
            let videoId: String?
            if host == "youtu.be" {
                videoId = path.split(separator: "/").map(String.init).first
            } else if path.hasPrefix("/shorts/") {
                videoId = String(path.dropFirst("/shorts/".count))
                    .split(separator: "/").map(String.init).first
            } else {
                videoId = url.queryItem("v")
            }
            return RichURLPayload(
                kind: .youtube, url: url,
                fields: videoId.map { [LabelledField(label: "Video", value: $0)] } ?? []
            )
        }

        // -- Spotify ----------------------------------------------------
        // open.spotify.com/<kind>/<id>     (track / album / playlist / artist)
        if host == "open.spotify.com" {
            let segs = path.split(separator: "/").map(String.init)
            if segs.count >= 2 {
                return RichURLPayload(
                    kind: .spotify, url: url,
                    fields: [
                        LabelledField(label: "Kind", value: segs[0].capitalized),
                        LabelledField(label: "ID",   value: segs[1]),
                    ]
                )
            }
            return RichURLPayload(kind: .spotify, url: url, fields: [])
        }

        // -- Apple Music ------------------------------------------------
        // music.apple.com/<country>/<kind>/<slug>/<id>
        if host == "music.apple.com" {
            let segs = path.split(separator: "/").map(String.init)
            return RichURLPayload(
                kind: .appleMusic, url: url,
                fields: segs.last.map { [LabelledField(label: "ID", value: $0)] } ?? []
            )
        }

        // -- Google Maps share -----------------------------------------
        // www.google.com/maps/place/<…>/@<lat>,<lon>,<zoom>z?…
        // maps.google.com / maps.app.goo.gl shortlinks (lat/lon hidden)
        if host == "maps.google.com" || host == "www.google.com" || host == "google.com" {
            if let coords = extractGoogleMapsCoords(from: url) {
                return RichURLPayload(
                    kind: .googleMaps, url: url,
                    fields: [
                        LabelledField(label: "Latitude",  value: String(coords.lat)),
                        LabelledField(label: "Longitude", value: String(coords.lon)),
                    ]
                )
            }
        }
        if host == "maps.app.goo.gl" {
            // Shortlink — no coordinates without a network round-trip.
            return RichURLPayload(kind: .googleMaps, url: url, fields: [])
        }

        // -- Digital identity flows ------------------------------------
        // DigiD (Netherlands SSO): digid.nl + login.digid.nl
        // EUDI Wallet (EU Digital Identity reference & national wallets):
        //   *.eudiw.dev, eudi-wallet.* preview hosts
        //   OpenID4VC verifier / issuer endpoints often served from
        //   government domains. We detect the well-known *brands*
        //   here; if a flow uses a generic openid-credential-offer
        //   URL, we'll still pick it up via the path-suffix check.
        if let identity = digitalIdentityPayload(url: url, host: host, path: path) {
            return identity
        }

        // -- Apple Maps share -----------------------------------------
        // maps.apple.com/?ll=<lat>,<lon>&q=<query>
        if host == "maps.apple.com" {
            if let ll = url.queryItem("ll"), let coords = parseLatLon(ll) {
                let query = url.queryItem("q")
                return RichURLPayload(
                    kind: .appleMaps, url: url,
                    fields: [
                        LabelledField(label: "Latitude",  value: String(coords.lat)),
                        LabelledField(label: "Longitude", value: String(coords.lon)),
                        query.map { LabelledField(label: "Query", value: $0) }
                    ].compactMap { $0 }
                )
            }
        }

        return nil
    }

    // MARK: - Digital identity (1.4)

    /// Recognise URLs that look like DigiD / EUDI Wallet / generic
    /// OpenID4VC identity flows. Returns nil if nothing matches —
    /// the caller falls back to plain `.url` in that case.
    ///
    /// Keep this conservative: we only flag well-known brands plus a
    /// path-level signal (`openid-credential-offer`, `openid4vp`,
    /// `oidvp`) so that an arbitrary `https://example.com/login`
    /// doesn't get mis-classified and trigger the security warning.
    private static func digitalIdentityPayload(
        url: URL,
        host: String,
        path: String
    ) -> RichURLPayload? {
        let lowerPath = path.lowercased()
        let isDigiD = host.hasSuffix("digid.nl") || host == "mijn.digid.nl"
        let isEUDI  = host.hasSuffix("eudiw.dev")
            || host.hasSuffix("eu-digital-identity-wallet.eu")
            || host.hasSuffix("ec.europa.eu") && lowerPath.contains("eudi")
        // OpenID for Verifiable Credentials path markers — these
        // aren't tied to a specific brand but reliably identify an
        // identity flow over plain HTTPS.
        let isOpenID4VC = lowerPath.contains("openid-credential-offer")
            || lowerPath.contains("openid4vp")
            || lowerPath.contains("/oidvp/")
            || lowerPath.contains("authorize")
                && (url.queryItem("response_type") == "vp_token"
                    || url.queryItem("client_id_scheme") != nil)

        guard isDigiD || isEUDI || isOpenID4VC else { return nil }

        var fields: [LabelledField] = []
        if isDigiD {
            fields.append(.init(label: "Provider", value: "DigiD (Netherlands)"))
        } else if isEUDI {
            fields.append(.init(label: "Provider", value: "EU Digital Identity Wallet"))
        } else {
            fields.append(.init(label: "Protocol", value: "OpenID for Verifiable Credentials"))
        }
        fields.append(.init(label: "Host", value: host))
        // Surface a high-signal subset of the query so the user can
        // see *what* the flow is asking for (presentation_definition,
        // request_uri, …) without dumping the full URL into the sheet.
        for key in ["client_id", "response_type", "scope", "request_uri", "presentation_definition_uri"] {
            if let v = url.queryItem(key) {
                fields.append(.init(label: key, value: v))
            }
        }
        return RichURLPayload(kind: .digitalIdentity, url: url, fields: fields)
    }

    // MARK: - Helpers

    /// Parse `lat,lon` into a tuple. Returns nil if either side isn't numeric.
    private static func parseLatLon(_ s: String) -> (lat: Double, lon: Double)? {
        let parts = s.split(separator: ",").map(String.init)
        guard parts.count >= 2,
              let lat = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let lon = Double(parts[1].trimmingCharacters(in: .whitespaces))
        else { return nil }
        return (lat, lon)
    }

    /// Pull lat/lon out of a Google-Maps URL. The canonical place is the
    /// `@<lat>,<lon>,<zoom>z` segment in the path; some shorter share URLs
    /// use a `?ll=` query param.
    private static func extractGoogleMapsCoords(from url: URL) -> (lat: Double, lon: Double)? {
        if let ll = url.queryItem("ll"), let parsed = parseLatLon(ll) {
            return parsed
        }
        // Look for `@…,…` in the path.
        if let atRange = url.path.range(of: "@") {
            let tail = String(url.path[atRange.upperBound...])
            // <lat>,<lon>,<zoom>z…
            let chunk = tail.split(separator: ",")
            if chunk.count >= 2,
               let lat = Double(chunk[0]),
               let lon = Double(chunk[1].split(separator: "z").first ?? chunk[1]) {
                return (lat, lon)
            }
        }
        return nil
    }
}

// MARK: - URL convenience

private extension URL {
    /// Lookup a query parameter case-insensitively.
    func queryItem(_ name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name.lowercased() == name.lowercased() })?
            .value
    }
}
