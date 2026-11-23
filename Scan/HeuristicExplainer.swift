//
//  HeuristicExplainer.swift
//  Scan
//
//  The assistant's offline floor. When Apple Intelligence is not on the
//  device (older iPhone, feature switched off, region not enabled) the
//  Explain button still has to answer, so every recognised payload kind
//  carries its own plain-language write-up here. It is also the safety net
//  when the model returns something unusable, and — because it is pure and
//  deterministic — the half of the assistant we can actually unit-test.
//

import Foundation

enum HeuristicExplainer {

    static func explain(raw: String, payload: ScanPayload?) -> AssistantExplanation {
        let kind = payload ?? ScanPayloadParser.parse(raw)
        var points: [String] = []
        var cautions: [String] = []

        switch kind {
        case .url(let url):
            points.append("Opens \(openedHost(raw: raw, url: url)) in your browser.")
            if url.scheme?.lowercased() == "http" { points.append("The site is served without encryption.") }
            cautions.append("Check the spelling of the domain before you sign in or pay.")

        case .email(let address, let subject, _):
            points.append("Starts a new message to \(address).")
            if let subject, !subject.isEmpty { points.append("Pre-filled subject: \(subject).") }

        case .phone(let number):
            points.append("Places a call to \(number).")
            cautions.append("A QR is not a caller-ID — the number is whatever the code says.")

        case .sms(let number, let body):
            points.append("Opens a message to \(number).")
            if let body, !body.isEmpty { points.append("Pre-filled text: \(body.prefix(80)).") }
            cautions.append("Some codes auto-send a premium-rate SMS — read the text before you confirm.")

        case .wifi(let ssid, let password, let security, let hidden):
            // The safety check's own rule, so the two cannot disagree.
            let isOpen = QrRiskAssessor.isOpenNetwork(password: password, security: security)
            points.append("Joins the Wi-Fi network “\(ssid)”.")
            // A code with no `T:` field and no password is an open network,
            // not a WPA one.
            points.append("Security: \(friendlyWifiSecurity(security ?? (isOpen ? "nopass" : "WPA"))).")
            if hidden { points.append("The network hides its name.") }
            if isOpen { points.append("No password is needed — the network is open.") }
            cautions.append("Only join networks whose name you can see printed by the venue.")

        case .geo(let lat, let lon, let query):
            points.append("Opens a map at \(String(format: "%.5f", lat)), \(String(format: "%.5f", lon)).")
            if let query, !query.isEmpty { points.append("Search text: \(query).") }

        case .contact(let c):
            if let name = c.fullName, !name.isEmpty {
                points.append("Adds “\(name)” to your contacts.")
            } else {
                points.append("Adds a contact card to your contacts.")
            }
            if let phone = c.phones.first { points.append("Phone \(phone).") }
            if let org = c.organization, !org.isEmpty { points.append("Organisation \(org).") }
            points.append("Nothing is saved until you press Add in the system form.")

        case .calendar(let event):
            points.append("Proposes a calendar entry: \(event.summary ?? "untitled").")
            if let location = event.location, !location.isEmpty { points.append("Location \(location).") }
            points.append("Nothing is saved until you press Add in the system form.")

        case .otp:
            points.append("Enrols this device in two-factor sign-in for an account.")
            cautions.append("Never show or forward this code — anyone holding it can sign in as you.")

        case .otpMigration:
            points.append("Bulk-imports several two-factor accounts at once.")
            cautions.append("Only scan a 2FA export you started yourself.")

        case .productCode(let code, let system):
            points.append("Retail item identifier — a \(system) code.")
            points.append("Barcode number \(code).")
            points.append("Scan does not look prices up; that would need a server.")

        case .crypto(let p):
            points.append("Requests a \(p.chain.rawValue) payment to address \(prefix(p.address)).")
            if let amount = p.amount { points.append("Asks for \(amount).") }
            cautions.append("Verify the address in your wallet before sending — crypto transfers cannot be undone.")

        case .epcPayment(let p):
            points.append("A SEPA bank transfer request.")
            if let name = p.beneficiaryName { points.append("Payee \(name).") }
            if let amount = p.amount, let currency = p.currency { points.append("Amount \(amount) \(currency).") }
            cautions.append("Compare the IBAN with the printed invoice before you approve.")

        case .emvPayment(let p):
            points.append("A merchant payment QR (EMVCo).")
            if let name = p.merchantName { points.append("Merchant \(name).") }
            if p.value(for: "01") == "11" { points.append("It is a static code, reusable for any number of payments.") }
            cautions.append("Confirm the merchant name and amount in your bank app.")

        case .swissQRBill, .ipsPayment, .upiPayment, .czechSPD, .regionalPayment,
             .ruPayment, .paBySquare:
            points.append("A payment request in a regional standard.")
            points.append("Scan shows the individual fields so you can check each one.")
            cautions.append("Confirm the recipient and amount in your own banking app.")

        case .sufReceipt, .fnsReceipt:
            points.append("A fiscal receipt verification code.")
            points.append("Opens the tax authority's verification page for this receipt.")

        case .walletConnect(let p):
            points.append("Pairs a crypto wallet with a decentralised app.")
            points.append("WalletConnect v\(p.version).")
            cautions.append("Approving a pairing lets that app see your addresses and ask you to sign.")

        case .nostr(let p):
            if p.entity == .privateKey {
                // Not even a prefix of the key: an explanation is not the
                // place to repeat a secret.
                points.append("A Nostr \(p.entity.rawValue.lowercased()).")
                cautions.append("This is a private key. Anyone holding it can post and spend as you.")
            } else {
                points.append("A Nostr \(p.entity.rawValue.lowercased()) — \(prefix(p.id)).")
            }

        case .passkey:
            points.append("Cross-device sign-in: it asks your phone to act as the passkey authenticator.")
            cautions.append("Only approve a passkey code you started yourself.")

        case .mobileDrivingLicense(let p):
            points += p.keyPoints
            cautions += p.cautions

        case .verifiableCredential(let p):
            points += p.explanationPoints
            cautions += p.cautions

        case .eInvoice(let p):
            points.append("An electronic-invoice summary in \(p.standard).")
            if let total = p.totalAmount { points.append("Total \(total).") }
            cautions.append("Reconcile the IBAN and amount against the document before paying.")

        case .boardingPass(let p):
            if let leg = p.legs.first {
                points.append("Flight \(leg.carrier)\(leg.flightNumber), \(leg.from) → \(leg.to).")
            }
            cautions.append("A boarding pass is a bearer document — do not post it.")

        case .drivingLicense:
            points.append("The machine-readable data from a driving licence.")
            cautions.append("Never photograph or share this — it is enough to impersonate you.")

        case .gs1(let p):
            points.append("Product data in GS1 format.")
            if let gtin = p.gtin { points.append("GTIN \(gtin).") }

        case .digitalProductPassport(let p):
            points.append("A Digital Product Passport record.")
            points.append("Product \(prefix(p.gtin ?? "unknown")).")

        case .magnet:
            points.append("A torrent download link.")
            cautions.append("Content is whatever the swarm serves, not what the label said.")

        case .richURL(let r):
            points.append("Opens \(r.kind.rawValue) content.")

        case .plusCode, .what3words:
            points.append("A compact way to write down a location.")

        case .iban(let p):
            points.append("A bank account number in IBAN form (\(p.countryCode)).")
            cautions.append("Check it against the invoice — a changed digit sends money elsewhere.")

        case .text(let t):
            points.append("Plain text, \(t.count) character\(t.count == 1 ? "" : "s").")
        }

        let report = QrRiskAssessor.assess(raw: raw, payload: kind)
        cautions.append(contentsOf: report.findings
            .filter { $0.severity != .note }
            .map(\.detail)
            .prefix(3))

        return AssistantExplanation(
            headline: headline(for: kind),
            summary: summary(for: kind, points: points),
            keyPoints: Array(points.prefix(6)),
            cautions: Array(Set(cautions)).sorted(),
            source: .builtIn)
    }

    // MARK: Text builders

    private static func headline(for payload: ScanPayload) -> String {
        switch payload {
        case .url:                 return "A web link"
        case .email:               return "An email to compose"
        case .phone:               return "A phone number to dial"
        case .sms:                 return "A text message to send"
        case .wifi:                return "A Wi-Fi login"
        case .geo:                 return "A map location"
        case .contact:             return "A contact card"
        case .calendar:            return "A calendar invitation"
        case .otp:                 return "A two-factor enrolment"
        case .otpMigration:        return "A two-factor export"
        case .productCode:         return "A retail barcode"
        case .crypto:              return "A crypto payment request"
        case .epcPayment:          return "A SEPA payment request"
        case .emvPayment:          return "A merchant payment QR"
        case .swissQRBill:         return "A Swiss QR-bill"
        case .ipsPayment:          return "A Serbian IPS payment"
        case .upiPayment:          return "An Indian UPI payment"
        case .czechSPD:            return "A Czech payment QR"
        case .sufReceipt, .fnsReceipt: return "A fiscal receipt check"
        case .walletConnect:       return "A wallet pairing request"
        case .nostr:               return "A Nostr identity or note"
        case .passkey:             return "A cross-device sign-in request"
        case .mobileDrivingLicense(let p): return p.headline
        case .verifiableCredential(let p): return p.kind.rawValue
        case .eInvoice:            return "An electronic invoice"
        case .boardingPass:        return "A boarding pass"
        case .drivingLicense:      return "Driving licence data"
        case .gs1:                 return "GS1 product data"
        case .digitalProductPassport: return "A Digital Product Passport"
        case .magnet:              return "A torrent link"
        case .richURL(let r):      return "\(r.kind.rawValue) link"
        case .plusCode, .what3words: return "A location code"
        case .iban:                return "A bank account (IBAN)"
        case .regionalPayment(let r): return "\(r.scheme.rawValue) payment"
        case .ruPayment:           return "A Russian payment order"
        case .paBySquare:          return "A Slovak payment QR"
        case .text:                return "Plain text"
        }
    }

    private static func summary(for payload: ScanPayload, points: [String]) -> String {
        let lead = points.first ?? "Scan recognised the contents and listed the fields."
        let rest = points.dropFirst().prefix(2).joined(separator: " ")
        return rest.isEmpty ? lead : "\(lead) \(rest)"
    }

    private static func prefix(_ s: String, _ count: Int = 10) -> String {
        s.count <= count * 2 ? s : "\(s.prefix(count))…\(s.suffix(4))"
    }

    /// The host the Open button reaches. It is opened from Foundation's
    /// reading of the link, so that decides; the code's own spelling, split
    /// the way the safety check and the Android port split it, is what is
    /// shown when the two agree — Foundation would show an internationalised
    /// host as punycode.
    private static func openedHost(raw: String, url: URL) -> String {
        let opened = DecodedURL.parse(url.absoluteString)?.host ?? ""
        let written = DecodedURL.parse(raw)?.host ?? ""
        func labels(_ host: String) -> [String] { HostName(host).unicodeLabels.map { $0.lowercased() } }
        if !written.isEmpty, opened.isEmpty || labels(written) == labels(opened) { return written }
        if !opened.isEmpty { return opened }
        return url.host ?? url.absoluteString
    }

    // MARK: Compose fallback

    /// Rule-based version of the Generate tab's "describe the code" box.
    /// Deliberately narrow: it only claims a result when the request names
    /// the thing explicitly ("wifi", "contact", a link, "text …"), otherwise
    /// the user gets the normal form. The rules run in that order and the
    /// first one that understands the request wins.
    ///
    /// The Android port runs the same patterns. They are written without
    /// `\b`, `\s`, `\w` and `\d`, which ICU (iOS, and Android devices) reads
    /// as Unicode classes but the JVM that runs Android's unit tests reads as
    /// ASCII: `sp` is ICU's `\s`, `start`/`end` are its word boundary on
    /// either side of a word, and `\p{Nd}` is its `\d`.
    static func compose(request: String) -> ComposeResult? {
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return composeWifi(trimmed)
            ?? composeContact(trimmed)
            ?? composeURL(trimmed)
            ?? composeText(trimmed)
    }

    /// One whitespace character, and the same inside a bracket expression.
    private static let sp = #"[\t\n\f\r\p{Z}]"#
    private static let spChars = #"\t\n\f\r\p{Z}"#
    /// A word starts / ends here (ICU's `\b` next to a letter or digit).
    private static let start = #"(?<![\p{L}\p{M}\p{Nd}\p{Pc}])"#
    private static let end = #"(?![\p{L}\p{M}\p{Nd}\p{Pc}])"#

    // MARK: Wi-Fi

    /// Words that end a network name: whatever comes next describes the
    /// network rather than naming it.
    private static let wifiKeywords =
        "password|passphrase|passcode|pass|pwd|pw|key|hidden|security|encryption|wpa3|wpa2|wpa|wep|sae|nopass|open|no"
        + sp + "+password"

    /// "wifi BlueHouse password hunter2 hidden", "Wi-Fi QR for guest network
    /// BlueHouse, password hunter2", "guest wifi called Cafe Lumen with
    /// password espresso42", `network "Home 5G" wpa3`.
    private static func composeWifi(_ request: String) -> ComposeResult? {
        guard matches(start + "(?:wi-?fi|wi" + sp + "+fi|wlan|ssid)" + end, in: request) else { return nil }
        var values: [String: String] = [:]
        var rest = request

        // The password first, and then out of the way: what is left can be
        // searched for the network name without a password that happens to
        // contain "network" or "hidden" getting in the way. "password" beats
        // the looser "key" / "pass", so "wifi Key West password x" reads x;
        // a quoted password may contain spaces. "no password" is not one.
        let connector = "(?:[" + spChars + ",;]*" + start + "(?:with|and|using)" + sp + "+(?:the" + sp + "+|a" + sp + "+)?)?"
        let notNegated = "(?<!no" + sp + ")(?<!without" + sp + ")(?<!without" + sp + "a" + sp + ")"
        let introducer = sp + "*(?:(?:is|was)" + sp + "+|[=:]" + sp + "*)?"
        passwordSearch: for keywords in ["password|passphrase|passcode|pwd|pw", "pass|key"] {
            for value in [#"["“]([^"”\n]{1,63})["”]"#, "[\"“'‘]?([^" + spChars + "\"”'’,;]{3,63})[\"”'’]?"] {
                let pattern = connector + notNegated + start + "(?:" + keywords + ")" + end + introducer + value
                guard let match = captureWithRange(pattern, in: rest) else { continue }
                // A full stop that ends the sentence is not part of the password.
                let endsRequest = match.range.upperBound == rest.endIndex
                values["password"] = endsRequest && match.value.hasSuffix(".")
                    ? String(match.value.dropLast()) : match.value
                rest.replaceSubrange(match.range, with: " , ")
                break passwordSearch
            }
        }

        let lower = rest.lowercased()
        if let security = capture(start + "(wpa3|wpa2|wpa|wep|sae)" + end, in: lower) {
            values["security"] = security.uppercased()
        } else if matches(start + "(?:nopass|no" + sp + "+password|without" + sp + "+(?:a" + sp + "+)?password|open"
                          + sp + "+(?:wi-?fi|network))" + end, in: lower) {
            values["security"] = "NOPASS"
        }
        if matches(start + "hidden" + end, in: lower) { values["hidden"] = "true" }

        // The network name: a quoted name wins, then the most specific
        // keyword ("ssid", "name", "network", "named"/"called") before the
        // bare "wifi <name>" form, so "Wi-Fi QR for guest network X" reads X
        // and not "QR for guest network X".
        let name = "[\"“'‘]?([^" + spChars + "\"”'’,;][^\"”,;\\n]{0,31}?)[\"”'’]?"
        let stop = "(?=" + sp + "*(?:[,;]|\\.(?:" + sp + "|$)|$)|" + sp + "+(?:(?:with|and|using)" + sp + "+)*(?:"
            + wifiKeywords + ")" + end + ")"
        let introduced = sp + "*(?:is" + sp + "+|[=:]" + sp + "*)?"
        let ssidPatterns = [
            #"["“]([^"”\n]{1,32})["”]"#,
            start + "ssid" + end + introduced + name + stop,
            start + "(?:network" + sp + "+)?name" + end + introduced + name + stop,
            start + "network" + sp + "+(?:(?:is|named|called)" + sp + "+|[=:]" + sp + "*)?" + name + stop,
            start + "(?:named|called)" + sp + "+" + name + stop,
            start + "(?:wi-?fi|wi" + sp + "+fi|wlan)" + sp + "+(?:(?:qr" + sp + "+code|qr|code)" + sp + "+)?(?:(?:network|for)"
                + sp + "+)*" + name + stop,
        ]
        for pattern in ssidPatterns {
            if let ssid = capture(pattern, in: rest), !ssid.isEmpty,
               !matches("^(?:" + wifiKeywords + "|network|qr|code|for)$", in: ssid) {
                values["ssid"] = ssid
                break
            }
        }
        guard values["ssid"] != nil else { return nil }
        return ComposeResult(kind: .wifi, values: values, text: "", source: .builtIn)
    }

    // MARK: Contact

    /// "vcard for Ana Ivić +381641234567 ana@example.com", "contact card for
    /// Marko Petrović, phone 064 123 4567, company Acme".
    private static func composeContact(_ request: String) -> ComposeResult? {
        guard matches("^" + sp + "*(?:vcard|v-card|contact)" + end + "|" + start + "(?:business|contact)" + sp + "+card"
                      + end + "|" + start + "vcard" + end, in: request) else { return nil }
        var values: [String: String] = [:]
        if let email = capture(#"([A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,})"#, in: request) {
            values["email"] = email
        }
        if let phone = capture(#"(?<![\p{L}\p{M}\p{Nd}\p{Pc}@.])(\+?\p{Nd}[\p{Nd} \-().]{5,20}\p{Nd})(?![\p{L}\p{M}\p{Nd}\p{Pc}@])"#,
                               in: request),
           phone.unicodeScalars.filter({ $0.properties.generalCategory == .decimalNumber }).count >= 7 {
            values["phone"] = phone
        }
        let stop = "(?=" + sp + #"*(?:[,;]|$|\+|\p{Nd}|\(|[A-Za-z0-9._%+\-]+@)|"# + sp
            + "+(?:phone|tel|mobile|cell|email|e-mail|mail|company|org|organi[sz]ation|works)" + end + ")"
        if let name = capture(start + "(?:for|name|named|called)" + end + sp + "*:?" + sp + #"+(\p{L}[\p{L}\p{M}'’ .\-]{1,59}?)"#
                              + stop, in: request) {
            values["name"] = name
        }
        if let org = capture(start + "(?:company|org|organi[sz]ation|works" + sp + "+at)" + end + sp + "*:?" + sp
                             + #"+(\p{L}[\p{L}\p{M}0-9&'’ .\-]{1,59}?)"# + stop, in: request) {
            values["org"] = org
        }
        if values["name"] == nil, values["phone"] == nil, values["email"] == nil { return nil }
        return ComposeResult(kind: .contact, values: values, text: "", source: .builtIn)
    }

    // MARK: URL

    /// "url https://example.com/x", or a bare domain when the request says
    /// it is a link: "a QR for our website example.com/menu" (or münchen.de).
    /// A domain behind another scheme (`ftp://…`) is not quietly made https.
    private static func composeURL(_ request: String) -> ComposeResult? {
        if let url = capture("(https?://[^" + spChars + "]+)", in: request) {
            return ComposeResult(kind: .url, values: [:], text: trimmingLinkPunctuation(url),
                                 source: .builtIn)
        }
        let label = #"[\p{L}\p{Nd}](?:[\p{L}\p{M}\p{Nd}\-]*[\p{L}\p{M}\p{Nd}])?"#
        guard matches(start + "(?:url|link|website|web" + sp + "+site|site|web" + sp + "+page|webpage|homepage)" + end,
                      in: request),
              let domain = capture(#"(?<![@\p{L}\p{M}\p{Nd}\p{Pc}./\-])((?:www\.)?"# + label + #"(?:\."# + label
                                   + #")*\.\p{L}{2,}(?:/[^"# + spChars + "]*)?)", in: request) else { return nil }
        return ComposeResult(kind: .url, values: [:],
                             text: "https://" + trimmingLinkPunctuation(domain), source: .builtIn)
    }

    // MARK: Text

    /// "text anything at all", "note: back in 5 minutes".
    private static func composeText(_ request: String) -> ComposeResult? {
        guard let text = capture("(?s)^(?:text|note|message)" + end + sp + "*[:\\-]?" + sp + "+(.+)$", in: request) else {
            return nil
        }
        return ComposeResult(kind: .text, values: [:], text: text, source: .builtIn)
    }

    // MARK: Regex helpers

    /// A sentence's closing punctuation is not part of the link.
    private static func trimmingLinkPunctuation(_ link: String) -> String {
        var s = link
        while let last = s.last, ".,;:!?)\"”'’".contains(last) { s.removeLast() }
        return s
    }

    private static func matches(_ pattern: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        return regex.firstMatch(in: text, options: [],
                                range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        captureWithRange(pattern, in: text)?.value
    }

    /// The first capture group, trimmed, and the range of the whole match.
    private static func captureWithRange(_ pattern: String,
                                         in text: String) -> (value: String, range: Range<String.Index>)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, options: [],
                                           range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let group = Range(match.range(at: 1), in: text),
              let whole = Range(match.range, in: text) else { return nil }
        let value = String(text[group]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (value, whole)
    }
}
