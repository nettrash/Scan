//
//  RegionalPaymentPayloads.swift
//  Scan
//
//  Recognises payment formats outside the EMVCo / EPC / IPS family —
//  Indian UPI, Czech SPD, Slovak Pay by Square, plus the URI-scheme
//  regional players (Bezahlcode, Swish, Vipps, MobilePay, Bizum, iDEAL).
//

import Foundation

// MARK: - UPI (India)

/// Parsed `upi://pay?…` URI per the NPCI specification.
struct UPIPayload: Equatable {
    let payeeAddress: String        // pa — VPA, e.g. "merchant@upi"
    let payeeName: String?          // pn
    let amount: String?             // am
    let currency: String?           // cu (defaults INR)
    let note: String?               // tn — transaction note
    let referenceURL: String?       // url
    let merchantCode: String?       // mc
    let transactionID: String?      // tid / tr
    let raw: String

    var labelledFields: [LabelledField] {
        var rows: [LabelledField] = []
        rows.append(.init(label: "Payee VPA", value: payeeAddress))
        if let n = payeeName  { rows.append(.init(label: "Payee", value: n)) }
        if let a = amount {
            let c = currency ?? "INR"
            rows.append(.init(label: "Amount", value: "\(a) \(c)"))
        }
        if let n = note            { rows.append(.init(label: "Note", value: n)) }
        if let m = merchantCode    { rows.append(.init(label: "Merchant code", value: m)) }
        if let t = transactionID   { rows.append(.init(label: "Transaction ID", value: t)) }
        if let u = referenceURL    { rows.append(.init(label: "Reference URL", value: u)) }
        return rows
    }
}

// MARK: - Czech SPD (Spayd)

/// Czech "short payment descriptor" used on Czech invoices. Format is
/// asterisk-delimited `KEY:VALUE` pairs starting with `SPD*<version>*…`.
struct CzechSPDPayload: Equatable {
    let version: String
    let fields: [(key: String, value: String)]

    static func == (lhs: CzechSPDPayload, rhs: CzechSPDPayload) -> Bool {
        guard lhs.version == rhs.version, lhs.fields.count == rhs.fields.count else {
            return false
        }
        for (a, b) in zip(lhs.fields, rhs.fields) {
            if a.key != b.key || a.value != b.value { return false }
        }
        return true
    }

    func value(for key: String) -> String? {
        fields.first(where: { $0.key == key })?.value
    }
    var iban: String?         { value(for: "ACC") }
    var altIBANs: String?     { value(for: "ALT-ACC") }
    var amount: String?       { value(for: "AM") }
    var currency: String?     { value(for: "CC") }
    var message: String?      { value(for: "MSG") }
    var recipient: String?    { value(for: "RN") }
    var refID: String?        { value(for: "X-ID") }
    var dueDate: String?      { value(for: "DT") }
    var variableSymbol: String?  { value(for: "X-VS") }
    var constantSymbol: String?  { value(for: "X-KS") }
    var specificSymbol: String?  { value(for: "X-SS") }
    var paymentType: String?     { value(for: "PT") }

    private static let labels: [String: String] = [
        "ACC":      "Account (IBAN)",
        "ALT-ACC":  "Alternative accounts",
        "AM":       "Amount",
        "CC":       "Currency",
        "MSG":      "Message",
        "RN":       "Recipient name",
        "X-ID":     "Reference ID",
        "DT":       "Due date",
        "X-VS":     "Variable symbol",
        "X-KS":     "Constant symbol",
        "X-SS":     "Specific symbol",
        "PT":       "Payment type",
        "RF":       "Creditor reference",
        "NT":       "Notification type",
        "NTA":      "Notification address"
    ]

    var labelledFields: [LabelledField] {
        let amountAndCurrency: LabelledField? = {
            guard let a = amount else { return nil }
            return .init(label: "Amount", value: currency.map { "\(a) \($0)" } ?? "\(a) CZK")
        }()

        var rows: [LabelledField] = []
        if let r = recipient     { rows.append(.init(label: "Recipient", value: r)) }
        if let i = iban          { rows.append(.init(label: "IBAN", value: i)) }
        if let row = amountAndCurrency { rows.append(row) }
        if let m = message       { rows.append(.init(label: "Message", value: m)) }
        if let d = dueDate       { rows.append(.init(label: "Due date", value: d)) }
        if let vs = variableSymbol  { rows.append(.init(label: "Variable symbol", value: vs)) }
        if let ks = constantSymbol  { rows.append(.init(label: "Constant symbol", value: ks)) }
        if let ss = specificSymbol  { rows.append(.init(label: "Specific symbol", value: ss)) }
        // Anything else not surfaced above falls back to the raw label/value.
        let surfaced: Set<String> = ["ACC", "AM", "CC", "MSG", "RN", "DT",
                                     "X-VS", "X-KS", "X-SS"]
        for f in fields where !surfaced.contains(f.key) {
            let label = Self.labels[f.key] ?? f.key
            rows.append(.init(label: label, value: f.value))
        }
        return rows
    }
}

// MARK: - Slovak Pay by Square (BySquare) — recognition only

/// Slovak invoice QR. The actual contents are LZMA-compressed binary
/// encoded with base32hex; iOS doesn't ship LZMA in any framework we can
/// reach, so we recognise the format and let the user pass the raw token
/// to their banking app via Share or Copy.
struct PayBySquarePayload: Equatable {
    let raw: String

    var labelledFields: [LabelledField] {
        [
            .init(label: "Format", value: "Pay by Square (Slovakia)"),
            .init(label: "Note",
                  value: "Decoding requires LZMA, which iOS doesn't ship. Open this in your bank's app or use Share / Copy."),
            .init(label: "Token", value: raw)
        ]
    }
}

// MARK: - Regional URI-scheme schemes (Bezahlcode, Swish, Vipps, MobilePay, Bizum, iDEAL)

struct RegionalPaymentPayload: Equatable {
    enum Scheme: String, Equatable {
        case bezahlcode  = "Bezahlcode"
        case swish       = "Swish"
        case vipps       = "Vipps"
        case mobilePay   = "MobilePay"
        case bizum       = "Bizum"
        case ideal       = "iDEAL"
    }

    let scheme: Scheme
    let raw: String
    let parsed: [LabelledField]

    var labelledFields: [LabelledField] {
        var rows: [LabelledField] = [.init(label: "Scheme", value: scheme.rawValue)]
        rows.append(contentsOf: parsed)
        return rows
    }
}

// MARK: - Parsers

enum RegionalPaymentParser {

    /// Lowercased URI schemes the detector should treat as "potentially a
    /// regional payment URI". Matches `(scheme): (host, path, ...)`.
    static let knownURISchemes: [String: RegionalPaymentPayload.Scheme] = [
        "bank":         .bezahlcode,
        "bezahlcode":   .bezahlcode,
        "swish":        .swish,
        "vipps":        .vipps,
        "mobilepay":    .mobilePay,
        "bizum":        .bizum,
        "ideal":        .ideal
    ]

    // MARK: UPI

    static func parseUPI(_ raw: String) -> UPIPayload? {
        guard raw.lowercased().hasPrefix("upi:") else { return nil }
        let body = String(raw.dropFirst(4))
        // UPI is `upi:CMD?key=val&…`. The CMD is "pay" or "mandate"; we only
        // care about pay for now but tolerate either.
        guard let q = body.firstIndex(of: "?") else { return nil }
        let cmd = String(body[..<q]).lowercased().replacingOccurrences(of: "//", with: "")
        guard cmd == "pay" || cmd == "mandate" else { return nil }
        let query = String(body[body.index(after: q)...])

        var pairs: [String: String] = [:]
        for kv in query.split(separator: "&") {
            let parts = kv.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, let value = parts[1].removingPercentEncoding else { continue }
            pairs[parts[0].lowercased()] = value
        }

        guard let pa = pairs["pa"], !pa.isEmpty else { return nil }
        return UPIPayload(
            payeeAddress: pa,
            payeeName: pairs["pn"],
            amount: pairs["am"],
            currency: pairs["cu"] ?? "INR",
            note: pairs["tn"],
            referenceURL: pairs["url"],
            merchantCode: pairs["mc"],
            transactionID: pairs["tr"] ?? pairs["tid"],
            raw: raw
        )
    }

    // MARK: Czech SPD

    static func parseCzechSPD(_ raw: String) -> CzechSPDPayload? {
        guard raw.hasPrefix("SPD*") else { return nil }
        let parts = raw.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
        // parts[0] = "SPD", parts[1] = version, parts[2..] = key:value
        guard parts.count >= 3, parts[0] == "SPD" else { return nil }
        let version = parts[1]
        var fields: [(String, String)] = []
        for part in parts.dropFirst(2) where !part.isEmpty {
            guard let colon = part.firstIndex(of: ":") else { continue }
            let key = String(part[..<colon])
            let value = String(part[part.index(after: colon)...])
                .replacingOccurrences(of: "+", with: " ")
                .removingPercentEncoding ?? String(part[part.index(after: colon)...])
            guard !key.isEmpty else { continue }
            fields.append((key, value))
        }
        guard !fields.isEmpty else { return nil }
        return CzechSPDPayload(version: version, fields: fields)
    }

    // MARK: Slovak Pay by Square — heuristic recognition only

    /// BySquare QRs are base32hex-encoded (RFC 4648 alphabet
    /// `0123456789ABCDEFGHIJKLMNOPQRSTUV`). The first ~5 characters carry a
    /// fixed-shape header — version 0 of the "Pay" type yields strings that
    /// always begin with one of `0000`, `0008`, `00018`, etc. and are
    /// followed by a long run of base32hex-only characters (no lowercase).
    /// We probe with a fairly conservative test to avoid false positives.
    static func looksLikePayBySquare(_ raw: String) -> Bool {
        let s = raw
        // Must be reasonably long.
        guard s.count >= 32 else { return false }
        // Header range is small; any of these covers v0 across BySquare doc
        // types (Pay, PayBills, Invoice, Order, Inquiry).
        let validHeaders = ["0000A", "0000B", "0000C", "0000D", "0000E",
                            "0008A", "0008B", "0008C",
                            "00010", "00018", "00020"]
        guard validHeaders.contains(where: { s.hasPrefix($0) }) else { return false }
        // The whole string must be base32hex (digits + A-V uppercase).
        let allowed: Set<Character> = Set("0123456789ABCDEFGHIJKLMNOPQRSTUV")
        return s.allSatisfy { allowed.contains($0) }
    }

    static func parsePayBySquare(_ raw: String) -> PayBySquarePayload? {
        guard looksLikePayBySquare(raw) else { return nil }
        return PayBySquarePayload(raw: raw)
    }

    // MARK: Bezahlcode / Swish / Vipps / MobilePay / Bizum / iDEAL

    /// Parse a regional URI-scheme payment payload by dispatching on the
    /// scheme. Each scheme is given its own per-scheme decoder below.
    static func parseRegional(_ raw: String) -> RegionalPaymentPayload? {
        guard let colon = raw.firstIndex(of: ":") else { return nil }
        let scheme = String(raw[..<colon]).lowercased()
        guard let kind = knownURISchemes[scheme] else { return nil }

        switch kind {
        case .bezahlcode: return parseBezahlcode(raw)
        case .swish:      return parseSwish(raw)
        case .vipps:      return parseVipps(raw)
        case .mobilePay:  return parseMobilePay(raw)
        case .bizum:      return parseBizum(raw)
        case .ideal:      return parseIDEAL(raw)
        }
    }

    /// Bezahlcode: legacy German `bank://singlepaymentsepa?…` style URI
    /// (also `bezahlcode://`). Field names follow the BezahlCode spec —
    /// `name`, `iban`, `bic`, `amount`, `currency`, `reason`, etc.
    private static func parseBezahlcode(_ raw: String) -> RegionalPaymentPayload? {
        let pairs = queryPairs(raw)
        let labels: [String: String] = [
            "name":         "Beneficiary",
            "iban":         "IBAN",
            "bic":          "BIC",
            "amount":       "Amount",
            "currency":     "Currency",
            "reason":       "Purpose",
            "executiondate":"Execution date",
            "creditorid":   "Creditor ID",
            "mandateid":    "Mandate ID",
            "dateofsignature": "Mandate date",
            "reference":    "Reference"
        ]
        let parsed: [LabelledField] = pairs.compactMap { k, v in
            let label = labels[k.lowercased()] ?? k
            return LabelledField(label: label, value: v)
        }
        guard !parsed.isEmpty else { return nil }
        return RegionalPaymentPayload(scheme: .bezahlcode, raw: raw, parsed: parsed)
    }

    /// Swish: `swish://payment?data=<base64-encoded JSON>`. The JSON
    /// commonly contains `payee`, `amount`, `message`, `currency`.
    private static func parseSwish(_ raw: String) -> RegionalPaymentPayload? {
        let pairs = queryPairs(raw)
        var parsed: [LabelledField] = []
        if let data = pairs.first(where: { $0.0.lowercased() == "data" })?.1 {
            // Try to decode as base64 → UTF-8 → JSON.
            if let decoded = decodeBase64URL(data),
               let str = String(data: decoded, encoding: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: Data(str.utf8)),
               let dict = obj as? [String: Any] {
                let labelMap: [String: String] = [
                    "payee":   "Payee",
                    "amount":  "Amount",
                    "message": "Message",
                    "currency":"Currency",
                    "reference":"Reference"
                ]
                for (k, v) in dict.sorted(by: { $0.key < $1.key }) {
                    let label = labelMap[k.lowercased()] ?? k
                    parsed.append(.init(label: label, value: "\(v)"))
                }
            } else {
                // Couldn't parse — surface the raw blob.
                parsed.append(.init(label: "Data", value: data))
            }
        }
        return RegionalPaymentPayload(scheme: .swish, raw: raw, parsed: parsed)
    }

    /// Vipps: `vipps://...` deep links. Format varies by use case (P2P vs.
    /// merchant); we surface what we can.
    private static func parseVipps(_ raw: String) -> RegionalPaymentPayload? {
        let pairs = queryPairs(raw)
        let labels: [String: String] = [
            "phonenumber": "Phone number",
            "amount":      "Amount",
            "message":     "Message",
            "merchantserialnumber": "Merchant ID",
            "ordertext":   "Order text"
        ]
        let parsed = pairs.map { (k, v) in
            LabelledField(label: labels[k.lowercased()] ?? k, value: v)
        }
        return RegionalPaymentPayload(scheme: .vipps, raw: raw, parsed: parsed)
    }

    /// MobilePay (Denmark / Finland): `mobilepay://...`.
    private static func parseMobilePay(_ raw: String) -> RegionalPaymentPayload? {
        let pairs = queryPairs(raw)
        let labels: [String: String] = [
            "phone":   "Phone number",
            "amount":  "Amount",
            "comment": "Comment",
            "lock":    "Locked amount"
        ]
        let parsed = pairs.map { (k, v) in
            LabelledField(label: labels[k.lowercased()] ?? k, value: v)
        }
        return RegionalPaymentPayload(scheme: .mobilePay, raw: raw, parsed: parsed)
    }

    /// Bizum (Spain): `bizum://...` P2P.
    private static func parseBizum(_ raw: String) -> RegionalPaymentPayload? {
        let pairs = queryPairs(raw)
        let labels: [String: String] = [
            "amount":   "Amount",
            "concept":  "Concept",
            "phone":    "Phone number"
        ]
        let parsed = pairs.map { (k, v) in
            LabelledField(label: labels[k.lowercased()] ?? k, value: v)
        }
        return RegionalPaymentPayload(scheme: .bizum, raw: raw, parsed: parsed)
    }

    /// iDEAL (Netherlands): `ideal://...`.
    private static func parseIDEAL(_ raw: String) -> RegionalPaymentPayload? {
        let pairs = queryPairs(raw)
        let labels: [String: String] = [
            "amount":      "Amount",
            "description": "Description",
            "iban":        "IBAN",
            "name":        "Beneficiary",
            "reference":   "Reference"
        ]
        let parsed = pairs.map { (k, v) in
            LabelledField(label: labels[k.lowercased()] ?? k, value: v)
        }
        return RegionalPaymentPayload(scheme: .ideal, raw: raw, parsed: parsed)
    }

    // MARK: - Helpers

    /// Extract the query-string `key=value` pairs from a URI, percent-decoded.
    /// Works on opaque schemes where URLComponents would otherwise parse the
    /// host/path inconsistently.
    private static func queryPairs(_ raw: String) -> [(String, String)] {
        guard let q = raw.firstIndex(of: "?") else { return [] }
        let query = String(raw[raw.index(after: q)...])
        var out: [(String, String)] = []
        for kv in query.split(separator: "&") {
            let parts = kv.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let value = parts[1].removingPercentEncoding else { continue }
            out.append((parts[0], value))
        }
        return out
    }

    /// Tolerant base64 decoder that accepts both standard and URL-safe
    /// alphabets and pads the input on demand.
    private static func decodeBase64URL(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+")
                 .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - t.count % 4) % 4
        t.append(String(repeating: "=", count: pad))
        return Data(base64Encoded: t)
    }
}
