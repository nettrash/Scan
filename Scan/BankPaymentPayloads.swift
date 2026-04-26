//
//  BankPaymentPayloads.swift
//  Scan
//
//  Recognises four widely-used "scan-to-pay" / receipt QR payloads and
//  exposes their fields as labelled rows the UI can render uniformly:
//
//   * EPC QR (SEPA Credit Transfer / GiroCode) — EU
//   * ST00012 — Russian unified payment (utilities, taxes, transfers)
//   * FNS receipt — Russian retail cash-receipt verification QR
//   * EMVCo Merchant QR — international (PayNow, PromptPay, Pix, UPI…)
//

import Foundation

// MARK: - Labelled field

/// One row displayed in the result sheet. The UI shows `label` on the left,
/// `value` on the right, and a tap-to-copy button.
struct LabelledField: Identifiable, Hashable {
    let label: String
    let value: String
    /// Stable identifier so SwiftUI can diff field lists across re-renders.
    var id: String { "\(label)|\(value)" }
}

// MARK: - EPC SEPA Payment

struct EPCPaymentPayload: Equatable {
    let version: String                   // "001" or "002"
    let bic: String?
    let beneficiaryName: String?
    let iban: String?
    let currency: String?
    let amount: String?                   // e.g. "12.34"
    let purposeCode: String?
    let structuredReference: String?
    let unstructuredRemittance: String?
    let beneficiaryInfo: String?

    var labelledFields: [LabelledField] {
        var rows: [LabelledField] = []
        if let n = beneficiaryName { rows.append(.init(label: "Beneficiary", value: n)) }
        if let i = iban            { rows.append(.init(label: "IBAN", value: i)) }
        if let b = bic             { rows.append(.init(label: "BIC", value: b)) }
        if let a = amount, let c = currency {
            rows.append(.init(label: "Amount", value: "\(a) \(c)"))
        }
        if let p = purposeCode      { rows.append(.init(label: "Purpose code", value: p)) }
        if let s = structuredReference { rows.append(.init(label: "Reference", value: s)) }
        if let r = unstructuredRemittance { rows.append(.init(label: "Remittance info", value: r)) }
        if let bi = beneficiaryInfo { rows.append(.init(label: "Beneficiary info", value: bi)) }
        return rows
    }
}

// MARK: - Russian Unified Payment (ST00012)

struct RussianPaymentField: Equatable {
    let key: String
    let value: String
}

struct RussianPaymentPayload: Equatable {
    let version: String                    // "ST00012", "ST00011"
    let fields: [RussianPaymentField]

    /// Friendly English label for each well-known key, in the order they
    /// typically matter to a payer. Unknown keys fall back to the raw key.
    private static let labels: [String: String] = [
        "Name":          "Recipient",
        "PersonalAcc":   "Account",
        "BankName":      "Bank",
        "BIC":           "BIC",
        "CorrespAcc":    "Correspondent account",
        "PayeeINN":      "Recipient INN",
        "KPP":           "KPP",
        "KBK":           "Budget code (KBK)",
        "OKTMO":         "Territorial code (OKTMO)",
        "Sum":           "Amount",
        "Purpose":       "Purpose",
        "LastName":      "Payer last name",
        "FirstName":     "Payer first name",
        "MiddleName":    "Payer middle name",
        "PayerINN":      "Payer INN",
        "PayerAddress":  "Payer address",
        "PaytReason":    "Tax basis",
        "TaxPeriod":     "Tax period",
        "DocNo":         "Document number",
        "DocDate":       "Document date",
        "TaxPaytKind":   "Payment kind",
        "BirthDate":     "Birth date",
        "Phone":         "Phone",
        "ChildFio":      "Child"
    ]

    var labelledFields: [LabelledField] {
        fields.map { f in
            let label = Self.labels[f.key] ?? f.key
            let value: String
            if f.key == "Sum", let kopecks = Int(f.value) {
                // Sum is encoded in kopecks per STO BR FAPF.4-2018.
                let rubles = Double(kopecks) / 100.0
                value = String(format: "%.2f ₽", rubles)
            } else {
                value = f.value
            }
            return LabelledField(label: label, value: value)
        }
    }
}

// MARK: - Russian FNS retail receipt QR

struct FNSReceiptPayload: Equatable {
    let rawTimestamp: String         // "20231225T1530" or with seconds
    let sum: String?                 // raw, in rubles with `.` decimal
    let fiscalNumber: String?        // fn — fiscal accumulator
    let receiptNumber: String?       // i  — fiscal document (FD)
    let fiscalSign: String?          // fp — fiscal sign
    let receiptType: String?         // n  — 1 sale, 2 sale-refund, 3 expense, 4 expense-refund

    var date: Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Moscow")
        for fmt in ["yyyyMMdd'T'HHmmss", "yyyyMMdd'T'HHmm"] {
            f.dateFormat = fmt
            if let d = f.date(from: rawTimestamp) { return d }
        }
        return nil
    }

    var receiptTypeLabel: String? {
        switch receiptType {
        case "1": return "Sale"
        case "2": return "Sale refund"
        case "3": return "Expense"
        case "4": return "Expense refund"
        default:  return receiptType
        }
    }

    var labelledFields: [LabelledField] {
        var rows: [LabelledField] = []
        if let d = date {
            let df = DateFormatter()
            df.locale = .current
            df.dateStyle = .medium
            df.timeStyle = .short
            rows.append(.init(label: "Date", value: df.string(from: d)))
        } else {
            rows.append(.init(label: "Date", value: rawTimestamp))
        }
        if let s = sum  { rows.append(.init(label: "Amount", value: s)) }
        if let t = receiptTypeLabel { rows.append(.init(label: "Type", value: t)) }
        if let n = fiscalNumber  { rows.append(.init(label: "FN (fiscal accumulator)", value: n)) }
        if let i = receiptNumber { rows.append(.init(label: "FD (receipt number)", value: i)) }
        if let p = fiscalSign    { rows.append(.init(label: "FPD (fiscal sign)", value: p)) }
        return rows
    }
}

// MARK: - Swiss QR-bill (SPC)

/// Address block as it appears in a Swiss QR-bill. The spec uses two
/// "address types": **S** (structured — separate street/house number) and
/// **K** (combined — two free-form address lines).
struct SwissQRBillAddress: Equatable {
    let addressType: String?   // "S" or "K"
    let name: String?
    let streetOrLine1: String?
    let houseNoOrLine2: String?
    let postCode: String?
    let city: String?
    let country: String?

    var isEmpty: Bool {
        name == nil && streetOrLine1 == nil && houseNoOrLine2 == nil
        && postCode == nil && city == nil && country == nil
    }

    /// Single-line representation for "Recipient" / "Payer" rows.
    var formatted: String? {
        let pieces: [String?] = [
            name,
            joined(streetOrLine1, houseNoOrLine2, separator: " "),
            joined(postCode, city, separator: " "),
            country
        ]
        let parts = pieces.compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func joined(_ a: String?, _ b: String?, separator: String) -> String? {
        switch (a?.isEmpty == false ? a : nil, b?.isEmpty == false ? b : nil) {
        case (.some(let x), .some(let y)): return "\(x)\(separator)\(y)"
        case (.some(let x), .none):        return x
        case (.none,        .some(let y)): return y
        default:                            return nil
        }
    }
}

struct SwissQRBillPayload: Equatable {
    let version: String                  // "0200" etc.
    let iban: String?                    // creditor IBAN or QR-IBAN
    let creditor: SwissQRBillAddress?
    let ultimateCreditor: SwissQRBillAddress?
    let amount: String?
    let currency: String?                // "CHF" or "EUR"
    let ultimateDebtor: SwissQRBillAddress?
    let referenceType: String?           // "QRR", "SCOR", "NON"
    let reference: String?
    let unstructuredMessage: String?
    let billInformation: String?

    private static let referenceTypeLabel: [String: String] = [
        "QRR":  "QR-Reference",
        "SCOR": "Creditor Reference",
        "NON":  "No reference"
    ]

    var labelledFields: [LabelledField] {
        var rows: [LabelledField] = []
        if let c = creditor?.formatted { rows.append(.init(label: "Creditor", value: c)) }
        if let i = iban                { rows.append(.init(label: "IBAN", value: i)) }
        if let a = amount, let c = currency {
            rows.append(.init(label: "Amount", value: "\(a) \(c)"))
        } else if let a = amount {
            rows.append(.init(label: "Amount", value: a))
        }
        if let d = ultimateDebtor?.formatted { rows.append(.init(label: "Debtor", value: d)) }
        if let uc = ultimateCreditor?.formatted, !uc.isEmpty {
            rows.append(.init(label: "Ultimate creditor", value: uc))
        }
        if let t = referenceType {
            rows.append(.init(label: "Reference type",
                              value: Self.referenceTypeLabel[t] ?? t))
        }
        if let r = reference, !r.isEmpty {
            rows.append(.init(label: "Reference", value: r))
        }
        if let m = unstructuredMessage, !m.isEmpty {
            rows.append(.init(label: "Message", value: m))
        }
        if let bi = billInformation, !bi.isEmpty {
            rows.append(.init(label: "Bill info", value: bi))
        }
        return rows
    }
}

// MARK: - Serbian fiscal receipt (SUF)

/// QR printed on every Serbian fiscal receipt since May 2022.
/// The QR encodes a URL on `suf.purs.gov.rs/v/?vl=…`; the `vl` value is
/// opaque encoded data that only the Tax Administration's server can
/// decode, so we can't surface receipt fields client-side. Best we can do
/// is recognise the URL pattern and offer a one-tap "Verify" action that
/// opens the official verification page.
struct SerbianFiscalReceiptPayload: Equatable {
    let url: URL

    var labelledFields: [LabelledField] {
        [
            .init(label: "Verification URL", value: url.absoluteString),
            .init(label: "Issuer", value: "Tax Administration of Serbia (PURS)")
        ]
    }
}

// MARK: - Serbian NBS IPS QR (Prenesi)

struct SerbianIPSField: Equatable {
    let key: String
    let value: String
}

struct SerbianIPSPayload: Equatable {
    let fields: [SerbianIPSField]

    /// QR-content kind: PR = printed bill, PT = merchant-presented at POS,
    /// PK = customer-presented at POS. We use this for the badge on the
    /// result sheet.
    var kind: String? { value(for: "K") }
    var version: String? { value(for: "V") }
    var recipientAccount: String? { value(for: "R") }
    var recipientName: String? { value(for: "N") }
    var amountField: String? { value(for: "I") }
    var paymentCode: String? { value(for: "SF") }
    var purpose: String? { value(for: "S") }
    var reference: String? { value(for: "RO") }

    func value(for key: String) -> String? {
        fields.first(where: { $0.key == key })?.value
    }

    private static let labels: [String: String] = [
        "K":  "Code",
        "V":  "Version",
        "C":  "Charset",
        "R":  "Account",
        "N":  "Recipient",
        "I":  "Amount",
        "SF": "Payment code",
        "S":  "Purpose",
        "RO": "Reference",
        "P":  "Payer"
    ]

    private static let kindLabel: [String: String] = [
        "PR": "Bill payment (PR)",
        "PT": "POS — merchant QR (PT)",
        "PK": "POS — customer QR (PK)"
    ]

    var labelledFields: [LabelledField] {
        fields.map { f in
            let label = Self.labels[f.key] ?? f.key
            // Decode percent-encoded values (recipient names commonly are).
            let decoded = f.value.removingPercentEncoding ?? f.value
            // Pretty-print the kind code.
            let display: String
            if f.key == "K" {
                display = Self.kindLabel[decoded] ?? decoded
            } else {
                display = decoded
            }
            return LabelledField(label: label, value: display)
        }
    }
}

// MARK: - EMVCo Merchant QR

struct EMVField: Equatable {
    let tag: String
    let value: String
}

struct EMVPaymentPayload: Equatable {
    let fields: [EMVField]

    private static let topLevelLabels: [String: String] = [
        "00": "Payload format",
        "01": "Initiation method",
        "52": "Merchant category",
        "53": "Currency",
        "54": "Amount",
        "55": "Tip indicator",
        "56": "Tip value",
        "57": "Convenience fee",
        "58": "Country",
        "59": "Merchant name",
        "60": "Merchant city",
        "61": "Postal code",
        "62": "Additional data",
        "63": "CRC",
        "64": "Merchant info language"
    ]

    private static let initiationMethodLabel: [String: String] = [
        "11": "Static QR (multiple uses)",
        "12": "Dynamic QR (single use)"
    ]

    /// ISO 4217 numeric → 3-letter alpha lookup for the most common currencies.
    private static let currencyCodes: [String: String] = [
        "036": "AUD", "124": "CAD", "156": "CNY", "344": "HKD",
        "356": "INR", "392": "JPY", "410": "KRW", "458": "MYR",
        "554": "NZD", "643": "RUB", "702": "SGD", "752": "SEK",
        "756": "CHF", "764": "THB", "784": "AED", "826": "GBP",
        "840": "USD", "858": "UYU", "894": "ZMW", "971": "AFN",
        "972": "TJS", "974": "BYN", "975": "BGN", "978": "EUR",
        "980": "UAH", "981": "GEL", "985": "PLN", "986": "BRL"
    ]

    func value(for tag: String) -> String? {
        fields.first(where: { $0.tag == tag })?.value
    }
    var merchantName: String? { value(for: "59") }
    var merchantCity: String? { value(for: "60") }
    var amount: String?       { value(for: "54") }
    var country: String?      { value(for: "58") }
    var currency: String?     { value(for: "53") }

    /// Sub-tag labels inside the "Additional Data Field Template" (tag 62).
    private static let additionalDataLabels: [String: String] = [
        "01": "Bill number",
        "02": "Mobile number",
        "03": "Store label",
        "04": "Loyalty number",
        "05": "Reference label",
        "06": "Customer label",
        "07": "Terminal label",
        "08": "Purpose of transaction",
        "09": "Additional consumer data request"
    ]

    /// Known scheme-identifier strings that turn up at sub-tag 00 (or
    /// equivalent) inside Merchant Account Information templates (tags
    /// 02–51). Used to label the template by scheme so the user sees
    /// "Pix", "PayNow", "PromptPay", etc. instead of opaque tag numbers.
    private static let knownGUIDs: [String: String] = [
        "BR.GOV.BCB.PIX":            "Pix",
        "BR.GOV.BCB.SPI":            "Pix (SPI)",
        "SG.PAYNOW":                 "PayNow",
        "SG.COM.NETS":               "NETS",
        "TH.COM.SAMSUNG.SPAY":       "Samsung Pay (TH)",
        "MX.COM.BANXICO.CODI":       "CoDi",
        "INT.COM.UPI":               "UPI",
        "UPI":                       "UPI",
        "HK.COM.HKICL":              "FPS (Hong Kong)",
        "MY.COM.PAYNET":             "DuitNow",
        "PH.COM.BANCNETPAY":         "BancNet Pay",
        "ID.QRIS":                   "QRIS",
        "ID.CO.QRIS.WWW":            "QRIS",
        "VN.NAPAS":                  "NAPAS"
    ]

    var labelledFields: [LabelledField] {
        var rows: [LabelledField] = []
        for f in fields {
            // Determine label.
            let label: String
            if let known = Self.topLevelLabels[f.tag] {
                label = known
            } else if let tagInt = Int(f.tag), (2...51).contains(tagInt) {
                // Try to recognise the scheme from the embedded GUID.
                let nested = parseNestedTLV(f.value)
                if let guidValue = nested.first(where: { $0.tag == "00" })?.value,
                   let scheme = Self.knownGUIDs.first(where: {
                       guidValue.uppercased().contains($0.key)
                   })?.value {
                    label = "\(scheme) account (\(f.tag))"
                } else {
                    label = "Merchant account (\(f.tag))"
                }
            } else {
                label = "Tag \(f.tag)"
            }

            // Determine display value.
            let displayValue: String
            switch f.tag {
            case "53":
                displayValue = Self.currencyCodes[f.value]
                    .map { "\($0) (\(f.value))" } ?? f.value
            case "01":
                displayValue = Self.initiationMethodLabel[f.value] ?? f.value
            default:
                displayValue = f.value
            }

            rows.append(LabelledField(label: label, value: displayValue))

            // Drill into known nested-template containers so the user can
            // copy individual fields rather than the whole opaque value.
            if let tagInt = Int(f.tag), (2...51).contains(tagInt) || f.tag == "62" {
                let nested = parseNestedTLV(f.value)
                let isAdditionalData = (f.tag == "62")
                for sub in nested {
                    let subLabel: String
                    if isAdditionalData {
                        subLabel = "  ↳ \(Self.additionalDataLabels[sub.tag] ?? "Sub-tag \(sub.tag)")"
                    } else {
                        // Inside merchant account info templates, sub-tag 00
                        // is the scheme GUID and 01+ are scheme-specific.
                        switch sub.tag {
                        case "00": subLabel = "  ↳ Scheme GUID"
                        case "01": subLabel = "  ↳ Identifier"
                        case "02": subLabel = "  ↳ Account info"
                        default:   subLabel = "  ↳ Sub-tag \(sub.tag)"
                        }
                    }
                    rows.append(LabelledField(label: subLabel, value: sub.value))
                }
            }
        }
        return rows
    }

    /// Walk a value as a series of TLVs. Returns an empty array if the
    /// content doesn't decode as well-formed TLV — protects against
    /// false-positive drilling into plain strings that happen to start
    /// with two digits.
    private func parseNestedTLV(_ value: String) -> [EMVField] {
        var out: [EMVField] = []
        var idx = value.startIndex
        while idx < value.endIndex {
            guard value.distance(from: idx, to: value.endIndex) >= 4 else {
                return []   // malformed — give up rather than partial-parse
            }
            let tagEnd = value.index(idx, offsetBy: 2)
            let lenEnd = value.index(tagEnd, offsetBy: 2)
            let tag = String(value[idx..<tagEnd])
            let lenStr = String(value[tagEnd..<lenEnd])
            // Both tag and length must be ASCII digits.
            guard tag.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let len = Int(lenStr), len >= 0 else { return [] }
            guard let valEnd = value.index(lenEnd, offsetBy: len, limitedBy: value.endIndex) else {
                return []
            }
            let v = String(value[lenEnd..<valEnd])
            out.append(EMVField(tag: tag, value: v))
            idx = valEnd
        }
        return out
    }
}

// MARK: - Parsers

enum BankPaymentParser {

    // MARK: EPC QR

    static func parseEPC(_ raw: String) -> EPCPaymentPayload? {
        let lines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        guard lines.count >= 6, lines[0] == "BCD" else { return nil }

        func line(_ i: Int) -> String? {
            guard lines.indices.contains(i) else { return nil }
            let s = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : s
        }

        let version    = line(1) ?? "001"
        // Lines 2 (charset) and 3 (identification "SCT") aren't surfaced.
        let bic        = line(4)
        let name       = line(5)
        let iban       = line(6)
        let amountRaw  = line(7)
        let purpose    = line(8)
        let structRef  = line(9)
        let unstruct   = line(10)
        let beneInfo   = line(11)

        // Amount field is "<CCY><AMOUNT>" e.g. "EUR12.34". Currency is always
        // 3 letters, amount is the rest.
        var currency: String?
        var amount: String?
        if let a = amountRaw, a.count >= 4 {
            currency = String(a.prefix(3))
            amount   = String(a.dropFirst(3))
        }

        // Treat as valid only if at least name *or* IBAN was provided.
        guard name != nil || iban != nil else { return nil }

        return EPCPaymentPayload(
            version: version,
            bic: bic,
            beneficiaryName: name,
            iban: iban,
            currency: currency,
            amount: amount,
            purposeCode: purpose,
            structuredReference: structRef,
            unstructuredRemittance: unstruct,
            beneficiaryInfo: beneInfo
        )
    }

    // MARK: Swiss QR-bill (SPC)

    /// Parse a Swiss QR-bill payload. Layout per Swiss Implementation Guidelines
    /// for Payments (`SPC` Swiss Payments Code, version `0200` and `0210`):
    ///
    /// ```
    ///  0  QRType            "SPC"
    ///  1  Version           "0200" / "0210"
    ///  2  Coding type       "1" (UTF-8)
    ///  3  IBAN              creditor IBAN or QR-IBAN
    ///  4  Creditor address type   "S" or "K"
    ///  5  Creditor name
    ///  6  Creditor street / addr line 1
    ///  7  Creditor house no / addr line 2
    ///  8  Creditor postcode
    ///  9  Creditor city
    /// 10  Creditor country
    /// 11..17  Ultimate creditor (same shape, all empty in current spec)
    /// 18  Amount
    /// 19  Currency          "CHF" / "EUR"
    /// 20..26  Ultimate debtor (same shape as creditor)
    /// 27  Reference type    "QRR" / "SCOR" / "NON"
    /// 28  Reference
    /// 29  Unstructured message
    /// 30  Trailer           "EPD"
    /// 31  Bill information (optional)
    /// 32..  Alternative procedure parameters (optional)
    /// ```
    static func parseSwissQRBill(_ raw: String) -> SwissQRBillPayload? {
        let lines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        guard lines.count >= 28, lines[0] == "SPC" else { return nil }

        func line(_ i: Int) -> String? {
            guard lines.indices.contains(i) else { return nil }
            let s = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : s
        }

        func address(at base: Int) -> SwissQRBillAddress? {
            let addressType = line(base)
            let name        = line(base + 1)
            let line1       = line(base + 2)
            let line2       = line(base + 3)
            let postCode    = line(base + 4)
            let city        = line(base + 5)
            let country     = line(base + 6)
            let address = SwissQRBillAddress(
                addressType: addressType,
                name: name,
                streetOrLine1: line1,
                houseNoOrLine2: line2,
                postCode: postCode,
                city: city,
                country: country
            )
            return address.isEmpty ? nil : address
        }

        let version    = line(1) ?? "0200"
        let iban       = line(3)
        let creditor   = address(at: 4)
        let ultCred    = address(at: 11)
        let amount     = line(18)
        let currency   = line(19)
        let debtor     = address(at: 20)
        let refType    = line(27)
        let reference  = line(28)
        let message    = line(29)
        // line(30) is the "EPD" trailer; we don't surface it.
        let billInfo   = line(31)

        // Need at minimum an IBAN or a creditor name to be useful.
        guard iban != nil || creditor?.name != nil else { return nil }

        return SwissQRBillPayload(
            version: version,
            iban: iban,
            creditor: creditor,
            ultimateCreditor: ultCred,
            amount: amount,
            currency: currency,
            ultimateDebtor: debtor,
            referenceType: refType,
            reference: reference,
            unstructuredMessage: message,
            billInformation: billInfo
        )
    }

    // MARK: Serbian SUF fiscal receipt

    /// Recognises the Serbian Tax Administration's fiscal-receipt
    /// verification URL. Both the live host (`suf.purs.gov.rs`) and the
    /// sandbox (`tap.sandbox.suf.purs.gov.rs`) are accepted.
    static func parseSerbianSUFReceipt(_ raw: String) -> SerbianFiscalReceiptPayload? {
        guard let url = URL(string: raw),
              let host = url.host?.lowercased(),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return nil
        }
        // Match the exact PURS host or a proper subdomain (sandbox/test envs).
        // hasSuffix alone would let `notsuf.purs.gov.rs` slip through, which
        // is why we check for a leading dot on the suffix variant.
        let isExact = host == "suf.purs.gov.rs"
        let isSubdomain = host.hasSuffix(".suf.purs.gov.rs")
        guard isExact || isSubdomain else { return nil }
        return SerbianFiscalReceiptPayload(url: url)
    }

    // MARK: Serbian NBS IPS QR

    static func parseSerbianIPS(_ raw: String) -> SerbianIPSPayload? {
        // Pipe-separated `K:value` pairs. Required: K, V, C, R, N, I.
        let pieces = raw.components(separatedBy: "|")
        var fields: [SerbianIPSField] = []
        for piece in pieces {
            guard let colon = piece.firstIndex(of: ":") else { continue }
            let key = String(piece[..<colon])
            let value = String(piece[piece.index(after: colon)...])
            guard !key.isEmpty else { continue }
            fields.append(SerbianIPSField(key: key, value: value))
        }
        // Sanity check on the required fields. Without K + R it's not a
        // valid IPS QR.
        let keys = Set(fields.map { $0.key })
        guard keys.contains("K"), keys.contains("R"), keys.contains("V") else {
            return nil
        }
        return SerbianIPSPayload(fields: fields)
    }

    /// Quick prefix probe — IPS payloads always start with `K:` followed by
    /// one of the three valid kind codes.
    static func looksLikeSerbianIPS(_ raw: String) -> Bool {
        guard raw.hasPrefix("K:") else { return false }
        let head = raw.prefix(while: { $0 != "|" })
        guard let colon = head.firstIndex(of: ":") else { return false }
        let value = head[head.index(after: colon)...]
        return ["PR", "PT", "PK"].contains(String(value))
    }

    // MARK: Russian Unified Payment

    static func parseRussianPayment(_ raw: String) -> RussianPaymentPayload? {
        guard let firstPipe = raw.firstIndex(of: "|") else { return nil }
        let header = String(raw[..<firstPipe])
        // Both ST00011 and ST00012 are seen in the wild; both follow the
        // same key=value field layout.
        guard header.hasPrefix("ST0001") else { return nil }

        let body = String(raw[raw.index(after: firstPipe)...])
        let pairs: [RussianPaymentField] = body
            .components(separatedBy: "|")
            .compactMap { field in
                guard let eq = field.firstIndex(of: "=") else { return nil }
                let key = String(field[..<eq])
                let value = String(field[field.index(after: eq)...])
                guard !key.isEmpty else { return nil }
                return RussianPaymentField(key: key, value: value)
            }
        guard !pairs.isEmpty else { return nil }
        return RussianPaymentPayload(version: header, fields: pairs)
    }

    // MARK: FNS Receipt

    static func parseFNSReceipt(_ raw: String) -> FNSReceiptPayload? {
        let pairs = raw
            .components(separatedBy: "&")
            .compactMap { f -> (String, String)? in
                guard let eq = f.firstIndex(of: "=") else { return nil }
                return (String(f[..<eq]), String(f[f.index(after: eq)...]))
            }
        let dict = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        guard let t = dict["t"], dict["fn"] != nil, dict["fp"] != nil else {
            return nil
        }
        return FNSReceiptPayload(
            rawTimestamp: t,
            sum: dict["s"],
            fiscalNumber: dict["fn"],
            receiptNumber: dict["i"],
            fiscalSign: dict["fp"],
            receiptType: dict["n"]
        )
    }

    static func looksLikeFNSReceipt(_ raw: String) -> Bool {
        raw.hasPrefix("t=") && raw.contains("&fn=") && raw.contains("&fp=")
    }

    // MARK: EMVCo Merchant QR

    /// Top-level TLV decoder. Each field is `TT LL VV…` where TT is a 2-digit
    /// tag, LL is a 2-digit decimal length, and VV… is the value of that length.
    static func parseEMV(_ raw: String) -> EMVPaymentPayload? {
        guard raw.hasPrefix("000201") else { return nil }

        var fields: [EMVField] = []
        var idx = raw.startIndex
        while idx < raw.endIndex {
            guard raw.distance(from: idx, to: raw.endIndex) >= 4 else { return nil }
            let tagEnd = raw.index(idx, offsetBy: 2)
            let lenEnd = raw.index(tagEnd, offsetBy: 2)
            let tag = String(raw[idx..<tagEnd])
            let lenStr = String(raw[tagEnd..<lenEnd])
            guard let len = Int(lenStr), len >= 0 else { return nil }
            guard let valEnd = raw.index(lenEnd, offsetBy: len, limitedBy: raw.endIndex) else { return nil }
            let value = String(raw[lenEnd..<valEnd])
            fields.append(EMVField(tag: tag, value: value))
            idx = valEnd
        }

        // Must lead with the Payload Format Indicator (tag 00 / value "01").
        guard fields.first?.tag == "00", fields.first?.value == "01" else { return nil }
        return EMVPaymentPayload(fields: fields)
    }
}
