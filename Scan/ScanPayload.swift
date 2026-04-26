//
//  ScanPayload.swift
//  Scan
//
//  Recognises common payload shapes encoded in QR / barcodes and turns
//  them into a structured value the UI can offer smart actions for.
//

import Foundation

/// A parsed barcode/QR payload.
enum ScanPayload: Equatable {
    case url(URL)
    case email(address: String, subject: String?, body: String?)
    case phone(String)
    case sms(number: String, body: String?)
    case wifi(ssid: String, password: String?, security: String?, hidden: Bool)
    case geo(latitude: Double, longitude: Double, query: String?)
    case contact(ContactPayload)
    case calendar(CalendarPayload)
    case otp(String)
    case productCode(String, system: String) // e.g. EAN-13, UPC-E
    case crypto(CryptoPayload)
    // Bank / receipt formats — see BankPaymentPayloads.swift.
    case epcPayment(EPCPaymentPayload)
    case swissQRBill(SwissQRBillPayload)
    case ruPayment(RussianPaymentPayload)
    case fnsReceipt(FNSReceiptPayload)
    case emvPayment(EMVPaymentPayload)
    case sufReceipt(SerbianFiscalReceiptPayload)
    case ipsPayment(SerbianIPSPayload)
    case upiPayment(UPIPayload)
    case czechSPD(CzechSPDPayload)
    case paBySquare(PayBySquarePayload)
    case regionalPayment(RegionalPaymentPayload)
    case text(String)

    struct ContactPayload: Equatable {
        var fullName: String?
        var phones: [String]
        var emails: [String]
        var urls: [String]
        var organization: String?
        var note: String?
    }

    /// Short label describing the payload kind, for UI badges.
    var kindLabel: String {
        switch self {
        case .url:          return "URL"
        case .email:        return "Email"
        case .phone:        return "Phone"
        case .sms:          return "SMS"
        case .wifi:         return "Wi-Fi"
        case .geo:          return "Location"
        case .contact:      return "Contact"
        case .calendar:     return "Calendar"
        case .otp:          return "OTP"
        case .productCode:  return "Product"
        case .crypto:       return "Crypto"
        case .epcPayment:   return "SEPA Payment"
        case .swissQRBill:  return "QR-bill (Swiss)"
        case .ruPayment:    return "Payment"
        case .fnsReceipt:   return "Receipt"
        case .emvPayment:   return "Merchant QR"
        case .sufReceipt:   return "Receipt (RS)"
        case .ipsPayment:   return "IPS Payment (RS)"
        case .upiPayment:   return "UPI"
        case .czechSPD:     return "SPD (CZ)"
        case .paBySquare:   return "Pay by Square (SK)"
        case .regionalPayment(let r): return r.scheme.rawValue
        case .text:         return "Text"
        }
    }
}

enum ScanPayloadParser {

    /// Parse a decoded barcode string into a structured payload.
    /// `symbology` is used to recognise pure 1D product codes (EAN/UPC).
    static func parse(_ raw: String, symbology: Symbology = .unknown) -> ScanPayload {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Pure-numeric retail codes
        switch symbology {
        case .ean8, .ean13, .upce, .itf14:
            return .productCode(trimmed, system: symbology.displayName)
        default:
            break
        }

        let lower = trimmed.lowercased()

        // ---- Bank / receipt payloads. Matched first because they have very
        // specific prefixes / shapes that mustn't be misclassified as URLs. ----

        // EPC SEPA Payment QR (a.k.a. GiroCode) — line 1 is "BCD".
        if trimmed.hasPrefix("BCD\n") || trimmed.hasPrefix("BCD\r\n") {
            if let p = BankPaymentParser.parseEPC(trimmed) {
                return .epcPayment(p)
            }
        }

        // Swiss QR-bill — line 1 is "SPC".
        if trimmed.hasPrefix("SPC\n") || trimmed.hasPrefix("SPC\r\n") {
            if let p = BankPaymentParser.parseSwissQRBill(trimmed) {
                return .swissQRBill(p)
            }
        }

        // Russian unified payment (utilities, taxes, transfers).
        if trimmed.hasPrefix("ST00012|") || trimmed.hasPrefix("ST00011|") {
            if let p = BankPaymentParser.parseRussianPayment(trimmed) {
                return .ruPayment(p)
            }
        }

        // EMVCo Merchant QR — Payload Format Indicator is "00 02 01".
        if trimmed.hasPrefix("000201") {
            if let p = BankPaymentParser.parseEMV(trimmed) {
                return .emvPayment(p)
            }
        }

        // FNS retail receipt verification QR.
        if BankPaymentParser.looksLikeFNSReceipt(trimmed) {
            if let p = BankPaymentParser.parseFNSReceipt(trimmed) {
                return .fnsReceipt(p)
            }
        }

        // Serbian NBS IPS QR (Prenesi / printed bills / POS).
        if BankPaymentParser.looksLikeSerbianIPS(trimmed) {
            if let p = BankPaymentParser.parseSerbianIPS(trimmed) {
                return .ipsPayment(p)
            }
        }

        // Serbian fiscal receipt verification URL — must be checked before
        // the generic URL fallback so we get the dedicated "Verify Receipt"
        // smart action.
        if lower.contains("suf.purs.gov.rs") {
            if let p = BankPaymentParser.parseSerbianSUFReceipt(trimmed) {
                return .sufReceipt(p)
            }
        }

        // Cryptocurrency wallet URIs (BIP-21 / EIP-681 / BOLT-11). Detected
        // by scheme so we don't confuse them with regular https URLs.
        if let schemeEnd = trimmed.firstIndex(of: ":"),
           CryptoURIParser.knownSchemes.contains(String(trimmed[..<schemeEnd]).lowercased()) {
            if let p = CryptoURIParser.parse(trimmed) {
                return .crypto(p)
            }
        }

        // UPI (India) — `upi://pay?…`.
        if lower.hasPrefix("upi:") {
            if let p = RegionalPaymentParser.parseUPI(trimmed) {
                return .upiPayment(p)
            }
        }

        // Regional payment URI schemes — Bezahlcode, Swish, Vipps,
        // MobilePay, Bizum, iDEAL.
        if let schemeEnd = trimmed.firstIndex(of: ":"),
           RegionalPaymentParser.knownURISchemes[String(trimmed[..<schemeEnd]).lowercased()] != nil {
            if let p = RegionalPaymentParser.parseRegional(trimmed) {
                return .regionalPayment(p)
            }
        }

        // Czech SPD (Spayd) — invoice payment QR.
        if trimmed.hasPrefix("SPD*") {
            if let p = RegionalPaymentParser.parseCzechSPD(trimmed) {
                return .czechSPD(p)
            }
        }

        // Slovak Pay by Square — recognised heuristically.
        if RegionalPaymentParser.looksLikePayBySquare(trimmed) {
            if let p = RegionalPaymentParser.parsePayBySquare(trimmed) {
                return .paBySquare(p)
            }
        }

        // Wi-Fi: WIFI:T:WPA;S:My_Network;P:my_password;H:false;;
        if lower.hasPrefix("wifi:") {
            return parseWifi(trimmed) ?? .text(trimmed)
        }

        // mailto:
        if lower.hasPrefix("mailto:") {
            return parseMailto(trimmed) ?? .text(trimmed)
        }

        // tel:
        if lower.hasPrefix("tel:") {
            let n = String(trimmed.dropFirst(4))
            return .phone(n)
        }

        // sms: / smsto:
        if lower.hasPrefix("smsto:") || lower.hasPrefix("sms:") {
            return parseSMS(trimmed) ?? .text(trimmed)
        }

        // geo:
        if lower.hasPrefix("geo:") {
            return parseGeo(trimmed) ?? .text(trimmed)
        }

        // otpauth://
        if lower.hasPrefix("otpauth://") {
            return .otp(trimmed)
        }

        // BEGIN:VCARD ...
        if lower.hasPrefix("begin:vcard") {
            return parseVCard(trimmed)
        }

        // MECARD:
        if lower.hasPrefix("mecard:") {
            return parseMECard(trimmed)
        }

        // BEGIN:VEVENT / VCALENDAR
        if CalendarPayloadParser.looksLikeICalendar(trimmed) {
            if let p = CalendarPayloadParser.parse(trimmed) {
                return .calendar(p)
            }
            // Fall through to .text if parsing failed somehow.
        }

        // URL-ish
        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme) {
            return .url(url)
        }

        return .text(trimmed)
    }

    // MARK: - Wi-Fi

    /// Splits a body of `key:value` pairs separated by `;`, where literal
    /// `\;`, `\:` and `\\` are escaped characters per the Wi-Fi MECARD-like format.
    private static func splitSemicolonFields(_ body: String) -> [(key: String, value: String)] {
        var pairs: [(String, String)] = []
        var current = ""
        var fields: [String] = []
        var i = body.startIndex
        while i < body.endIndex {
            let c = body[i]
            if c == "\\", body.index(after: i) < body.endIndex {
                current.append(body[body.index(after: i)])
                i = body.index(i, offsetBy: 2)
                continue
            }
            if c == ";" {
                fields.append(current)
                current = ""
            } else {
                current.append(c)
            }
            i = body.index(after: i)
        }
        if !current.isEmpty { fields.append(current) }

        for field in fields where !field.isEmpty {
            if let sep = field.firstIndex(of: ":") {
                let k = String(field[..<sep])
                let v = String(field[field.index(after: sep)...])
                pairs.append((k, v))
            }
        }
        return pairs
    }

    private static func parseWifi(_ raw: String) -> ScanPayload? {
        // Strip the WIFI: prefix (case-insensitive)
        guard let colon = raw.firstIndex(of: ":") else { return nil }
        let body = String(raw[raw.index(after: colon)...])
        let pairs = splitSemicolonFields(body)
        var ssid: String?
        var password: String?
        var security: String?
        var hidden = false
        for (k, v) in pairs {
            switch k.uppercased() {
            case "S": ssid = v
            case "P": password = v
            case "T": security = v
            case "H": hidden = (v.lowercased() == "true")
            default: break
            }
        }
        guard let s = ssid else { return nil }
        return .wifi(ssid: s, password: password, security: security, hidden: hidden)
    }

    // MARK: - mailto

    private static func parseMailto(_ raw: String) -> ScanPayload? {
        guard let comps = URLComponents(string: raw) else { return nil }
        let address = comps.path
        let q = comps.queryItems ?? []
        let subject = q.first(where: { $0.name.lowercased() == "subject" })?.value
        let body = q.first(where: { $0.name.lowercased() == "body" })?.value
        return .email(address: address, subject: subject, body: body)
    }

    // MARK: - sms

    private static func parseSMS(_ raw: String) -> ScanPayload? {
        // Forms: sms:NUMBER , sms:NUMBER?body=... , smsto:NUMBER:BODY
        let lower = raw.lowercased()
        if lower.hasPrefix("smsto:") {
            let rest = String(raw.dropFirst(6))
            let parts = rest.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            let num = parts.first ?? ""
            let body = parts.count > 1 ? parts[1] : nil
            return .sms(number: num, body: body)
        }
        guard let comps = URLComponents(string: raw) else { return nil }
        let num = comps.path
        let body = comps.queryItems?.first(where: { $0.name.lowercased() == "body" })?.value
        return .sms(number: num, body: body)
    }

    // MARK: - geo

    private static func parseGeo(_ raw: String) -> ScanPayload? {
        // geo:LAT,LON  or  geo:LAT,LON?q=Place
        let body = String(raw.dropFirst(4))
        let parts = body.split(separator: "?", maxSplits: 1).map(String.init)
        let coords = parts[0].split(separator: ",").map(String.init)
        guard coords.count >= 2,
              let lat = Double(coords[0]),
              let lon = Double(coords[1]) else { return nil }
        var query: String?
        if parts.count > 1 {
            let q = parts[1].split(separator: "&")
                .compactMap { kv -> String? in
                    let kvParts = kv.split(separator: "=", maxSplits: 1)
                    guard kvParts.count == 2, kvParts[0] == "q" else { return nil }
                    return String(kvParts[1]).removingPercentEncoding
                        ?? String(kvParts[1])
                }
            query = q.first
        }
        return .geo(latitude: lat, longitude: lon, query: query)
    }

    // MARK: - vCard

    private static func parseVCard(_ raw: String) -> ScanPayload {
        var contact = ScanPayload.ContactPayload(
            fullName: nil, phones: [], emails: [], urls: [], organization: nil, note: nil
        )
        let lines = raw.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n")
        for line in lines {
            let l = String(line)
            guard let colon = l.firstIndex(of: ":") else { continue }
            let head = String(l[..<colon]).uppercased()
            let value = String(l[l.index(after: colon)...])
            // strip parameters: e.g. TEL;TYPE=CELL
            let key = head.split(separator: ";").first.map(String.init) ?? head
            switch key {
            case "FN":   contact.fullName = value
            case "N" where contact.fullName == nil:
                // N:Last;First;Middle;Prefix;Suffix
                let parts = value.split(separator: ";").map(String.init)
                let composed = ([parts.dropFirst().first, parts.first]).compactMap { $0 }.joined(separator: " ")
                contact.fullName = composed.isEmpty ? value : composed
            case "TEL":  contact.phones.append(value)
            case "EMAIL": contact.emails.append(value)
            case "URL":  contact.urls.append(value)
            case "ORG":  contact.organization = value
            case "NOTE": contact.note = value
            default: break
            }
        }
        return .contact(contact)
    }

    // MARK: - MECARD

    private static func parseMECard(_ raw: String) -> ScanPayload {
        // MECARD:N:Doe,Jane;TEL:+1234;EMAIL:a@b.com;;
        guard let colon = raw.firstIndex(of: ":") else { return .text(raw) }
        let body = String(raw[raw.index(after: colon)...])
        let pairs = splitSemicolonFields(body)
        var contact = ScanPayload.ContactPayload(
            fullName: nil, phones: [], emails: [], urls: [], organization: nil, note: nil
        )
        for (k, v) in pairs {
            switch k.uppercased() {
            case "N":
                // "Last,First"
                let parts = v.split(separator: ",").map(String.init)
                if parts.count >= 2 {
                    contact.fullName = "\(parts[1]) \(parts[0])"
                } else {
                    contact.fullName = v
                }
            case "TEL":   contact.phones.append(v)
            case "EMAIL": contact.emails.append(v)
            case "URL":   contact.urls.append(v)
            case "ORG":   contact.organization = v
            case "NOTE":  contact.note = v
            default: break
            }
        }
        return .contact(contact)
    }
}
