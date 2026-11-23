//
//  InvoicePayload.swift
//  Scan
//
//  Electronic-invoice QR codes in the EN 16931 CII syntax (UN/CEFACT Cross
//  Industry Invoice) and the profiles built on it: ZUGFeRD / Factur-X and
//  XRechnung. UBL documents — Peppol BIS among them — are not read: the
//  gate below only admits CII. Where a payment code tells your bank what
//  to pay, an e-invoice QR carries the invoice *summary* itself, so a buyer
//  can check the payee and the total before approving a transfer — which
//  is exactly the mismatch a swapped QR exploits.
//
//  Two carrier shapes are seen in the wild: the QR holds the XML document
//  (small invoices, or the "embedded QR" variant of ZUGFeRD), or it holds
//  that XML base64-encoded. Both are handled.
//
//  Parsing is deliberately shallow: we pull the handful of elements a human
//  needs in order to say "yes, this is the invoice I am holding" and stop.
//  No XML validity check, no schema, no Schematron rules — that is what the
//  accounting software on the other end is for, and doing it here would
//  imply we certified the document.
//
//  The lookups follow the EN 16931 CII syntax binding, and the ones that
//  are easy to get wrong name the business term (BT-n) they read. The
//  Android port's `InvoicePayload.kt` reads the same elements in the same
//  order.
//

import Foundation

struct InvoicePayload: Equatable {
    /// The profile / guideline family the document declares.
    let standard: String
    /// `GuidelineSpecifiedDocumentContextParameter/ID`, verbatim — the
    /// assertion we are quoting rather than classifying ourselves.
    var guideline: String?
    var invoiceNumber: String?
    var sellerName: String?
    var sellerVAT: String?
    var buyerName: String?
    /// German `Leitweg-ID` and the generic buyer reference.
    var buyerReference: String?
    var currency: String?
    var totalAmount: String?
    var taxAmount: String?
    var issueDate: String?
    var dueDate: String?
    var iban: String?
    /// True when the QR held base64 rather than raw XML.
    let wasEncoded: Bool
    let raw: String

    var labelledFields: [LabelledField] {
        var rows: [LabelledField] = [
            .init(label: "Format", value: standard),
        ]
        if let n = invoiceNumber { rows.append(.init(label: "Invoice no.", value: n)) }
        if let s = sellerName     { rows.append(.init(label: "Seller", value: s)) }
        if let v = sellerVAT      { rows.append(.init(label: "Seller VAT", value: v)) }
        if let b = buyerName      { rows.append(.init(label: "Buyer", value: b)) }
        if let r = buyerReference { rows.append(.init(label: "Buyer ref / Leitweg-ID", value: r)) }
        if let a = totalAmount {
            rows.append(.init(label: "Total", value: currency.map { "\(a) \($0)" } ?? a))
        }
        if let t = taxAmount { rows.append(.init(label: "Tax", value: t)) }
        if let d = issueDate { rows.append(.init(label: "Issued", value: d)) }
        if let d = dueDate   { rows.append(.init(label: "Due", value: d)) }
        if let i = iban      { rows.append(.init(label: "IBAN", value: i)) }
        if let g = guideline { rows.append(.init(label: "Guideline", value: g)) }
        if wasEncoded        { rows.append(.init(label: "Carrier", value: "base64-encoded XML")) }
        return rows
    }
}

enum InvoiceParser {

    private static let markers = [
        "CrossIndustryInvoice",
        "urn:un:unece:uncefact:data:standard:CrossIndustryInvoice",
        "ram:CrossIndustryInvoice",
        "<rsm:",
    ]

    /// Cheap pre-check used by the master parser before we attempt any
    /// base64 decoding — a QR of arbitrary text must not pay that cost.
    static func looksLikeEInvoice(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if markers.contains(where: { trimmed.contains($0) }) { return true }
        // Base64 carrier: only worth a decode attempt when it is long,
        // single-line and base64-shaped.
        guard trimmed.count > 160,
              trimmed.count % 4 == 0 || trimmed.hasSuffix("="),
              trimmed.allSatisfy({ $0.isLetter || $0.isNumber || "+/=_-".contains($0) })
        else { return false }
        guard let data = Data(base64Encoded: trimmed, options: [.ignoreUnknownCharacters]),
              let text = String(data: data, encoding: .utf8) else { return false }
        return markers.contains(where: { text.contains($0) })
    }

    static func parse(_ raw: String) -> InvoicePayload? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var xml = trimmed
        var encoded = false
        if !markers.contains(where: { trimmed.contains($0) }) {
            guard let data = Data(base64Encoded: trimmed, options: [.ignoreUnknownCharacters]),
                  let text = String(data: data, encoding: .utf8),
                  markers.contains(where: { text.contains($0) }) else { return nil }
            xml = text
            encoded = true
        }
        guard markers.contains(where: { xml.contains($0) }) else { return nil }

        let p = InvoicePayload(
            standard: standard(for: xml),
            // BT-24, the specification identifier. Named in full: the suffix
            // `DocumentContextParameter` also matches BT-23's
            // `BusinessProcessSpecifiedDocumentContextParameter`, which CII
            // puts first, so an XRechnung document would quote its
            // business-process id as the guideline.
            guideline: firstValue("ID", in: xml, after: "GuidelineSpecifiedDocumentContextParameter"),
            invoiceNumber: firstValue("ID", in: xml, after: "ExchangedDocument")
                ?? firstValue("ID", in: xml, after: "DocumentReference")
                ?? firstValue("DocumentNumber", in: xml, after: nil)
                ?? firstValue("InvoiceNumber", in: xml, after: nil),
            sellerName: firstValue("Name", in: xml, after: "SellerTradeParty"),
            sellerVAT: vatNumber(in: xml),
            buyerName: firstValue("Name", in: xml, after: "BuyerTradeParty"),
            buyerReference: firstValue("BuyerReference", in: xml, after: nil)
                ?? firstValue("LeaderID", in: xml, after: nil),
            // BT-5, the currency the invoice's amounts are in: CII calls it
            // `InvoiceCurrencyCode`; a carrier that borrows the
            // `DocumentCurrencyCode` spelling is read too. Never
            // `TaxCurrencyCode` — that is BT-6, the VAT *accounting*
            // currency, which may differ, and pinning it to the total would
            // misstate the one figure the buyer is checking.
            currency: firstValue("InvoiceCurrencyCode", in: xml, after: nil)
                ?? firstValue("DocumentCurrencyCode", in: xml, after: nil),
            totalAmount: firstValue("GrandTotalAmount", in: xml, after: nil),
            taxAmount: firstValue("TaxTotalAmount", in: xml, after: nil)
                ?? firstValue("CalculatedAmount", in: xml, after: "ApplicableTradeTax"),
            issueDate: dateValue("IssueDateTime", in: xml),
            // BT-9: CII's `SpecifiedTradePaymentTerms/DueDateDateTime`, or
            // the `PaymentDueDate` spelling minimal summary carriers use.
            dueDate: dateValue("DueDateDateTime", in: xml) ?? dateValue("PaymentDueDate", in: xml),
            iban: firstValue("IBANID", in: xml, after: nil)
                ?? firstValue("IBAN", in: xml, after: nil)
                ?? firstValue("ID", in: xml, after: "CreditorFinancialAccount")
                ?? firstValue("ID", in: xml, after: "PayeeFinancialAccount"),
            wasEncoded: encoded,
            raw: raw
        )
        // Nothing a human could reconcile against the paper invoice: better
        // to leave it as text than to badge an unreadable blob "e-invoice".
        if p.invoiceNumber == nil, p.sellerName == nil, p.totalAmount == nil,
           p.buyerReference == nil {
            return nil
        }
        return p
    }

    // MARK: Profile naming

    private static func standard(for xml: String) -> String {
        let lower = xml.lowercased()
        if lower.contains("xrechnung") || lower.contains("leitweg") || lower.contains("br-de-1") {
            return "XRechnung (EN 16931, Germany)"
        }
        if lower.contains("zugferd") { return "ZUGFeRD (EN 16931, Germany)" }
        if lower.contains("factur-x") || lower.contains("facturx") { return "Factur-X (EN 16931, France)" }
        if lower.contains("en16931") { return "EN 16931 e-invoice" }
        return "Electronic invoice (UN/CEFACT)"
    }

    // MARK: Element scraping
    //
    // Namespaced XML (`<ram:Name>`), so a match is on the local name. The
    // `after` anchor keeps us out of trouble when the same element name
    // appears under several parents — `Name` exists for seller, buyer,
    // tax representative and payee alike.

    private static func firstValue(_ tag: String, in xml: String, after anchor: String?) -> String? {
        guard let search = searchArea(of: xml, after: anchor) else { return nil }
        let pattern = "<(?:[A-Za-z0-9_]+:)?" + NSRegularExpression.escapedPattern(for: tag)
            + "(?:\\s[^>]*)?>([^<]+)</(?:[A-Za-z0-9_]+:)?" + NSRegularExpression.escapedPattern(for: tag) + ">"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: String(search), options: [],
                                           range: NSRange(search.startIndex..., in: search)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: search) else { return nil }
        let value = String(search[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// The slice to look in. An anchor is an element *name*: we start just
    /// after its opening tag and read forward. A missing anchor means "no
    /// match", not "ignore the anchor" — `Name` from the tax representative
    /// reported as the seller is the one mistake an invoice summary must not
    /// make, and a substring match would also let `ExchangedDocumentContext`
    /// stand in for `ExchangedDocument`.
    private static func searchArea(of xml: String, after anchor: String?) -> Substring? {
        guard let anchor else { return Substring(xml) }
        // A leading `[A-Za-z0-9_]*` lets a suffix anchor work, because CII
        // qualifies the names it reuses: the guideline parameter is really
        // `GuidelineSpecifiedDocumentContextParameter`. The closing boundary
        // is what keeps `ExchangedDocument` from matching
        // `ExchangedDocumentContext`.
        let pattern = "<(?:[A-Za-z0-9_]+:)?[A-Za-z0-9_]*"
            + NSRegularExpression.escapedPattern(for: anchor)
            + "(?:\\s[^>]*)?>"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: xml, options: [],
                                           range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range, in: xml) else { return nil }
        return xml[range.upperBound...]
    }

    /// EN 16931 dates arrive as `DateTimeString` inside a
    /// `…DateTime/DateTimeString` block, usually `20260514`.
    private static func dateValue(_ tag: String, in xml: String) -> String? {
        let raw = firstValue("DateTimeString", in: xml, after: tag)
            ?? firstValue("DateString", in: xml, after: tag)
            ?? firstValue(tag, in: xml, after: nil)
        guard let raw else { return nil }
        let digits = raw.filter(\.isNumber)
        if digits.count >= 8 {
            let y = digits.prefix(4), m = digits.dropFirst(4).prefix(2), d = digits.dropFirst(6).prefix(2)
            return "\(y)-\(m)-\(d)"
        }
        return raw
    }

    /// Seller VAT id, EN 16931 BT-31. In CII that is the seller's
    /// `SpecifiedTaxRegistration/ID` with `schemeID="VA"` — the scheme is
    /// what tells it apart from the tax number (`FC`, BT-32) kept in the
    /// same element. A DE/FR/GB…-shaped id without a scheme still counts, as
    /// minimal summary carriers put it under the legal organisation.
    ///
    /// Both are looked for inside the seller's own element and nowhere else.
    /// The first VAT-shaped id in the document can be the invoice number
    /// (`INV20260001` fits the shape and comes first) or the buyer's VAT id,
    /// and calling either the seller's is the misattribution this summary
    /// exists to prevent.
    private static func vatNumber(in xml: String) -> String? {
        guard let seller = elementBody(named: "SellerTradeParty", in: xml) else { return nil }
        if let registered = firstCapture(vatRegistration, in: seller)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !registered.isEmpty {
            return registered
        }
        return firstCapture(vatShapedID, in: seller)
    }

    private static let vatRegistration =
        #"<(?:[A-Za-z0-9_]+:)?ID\s[^>]*\bschemeID\s*=\s*["']VA["'][^>]*>([^<]+)<"#

    private static let vatShapedID =
        #"<(?:[A-Za-z0-9_]+:)?(?:ID|GlobalID)\s*>\s*([A-Z]{2}[0-9A-Z]{8,12})\s*<"#

    /// The content of the first `<name>` element up to its own closing tag —
    /// unlike `searchArea`, which reads on to the end of the document. Nil
    /// when the element is missing or never closed: an unbounded search is
    /// exactly how another party's id would leak in.
    private static func elementBody(named name: String, in xml: String) -> String? {
        let open = "<((?:[A-Za-z0-9_]+:)?" + NSRegularExpression.escapedPattern(for: name) + ")(?:\\s[^>]*)?>"
        guard let openRegex = try? NSRegularExpression(pattern: open),
              let openMatch = openRegex.firstMatch(in: xml, options: [],
                                                   range: NSRange(xml.startIndex..., in: xml)),
              let openRange = Range(openMatch.range, in: xml),
              let qualified = Range(openMatch.range(at: 1), in: xml) else { return nil }
        let close = "</" + NSRegularExpression.escapedPattern(for: String(xml[qualified])) + "\\s*>"
        guard let closeRegex = try? NSRegularExpression(pattern: close),
              let closeMatch = closeRegex.firstMatch(in: xml, options: [],
                                                     range: NSRange(openRange.upperBound..., in: xml)),
              let closeRange = Range(closeMatch.range, in: xml) else { return nil }
        return String(xml[openRange.upperBound..<closeRange.lowerBound])
    }

    /// The first capture group of `pattern` in `text`.
    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, options: [],
                                           range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
