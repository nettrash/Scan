//
//  GS1Payload.swift
//  Scan
//
//  Recognises GS1 Application Identifier payloads — both the legacy
//  parens-delimited element string (`(01)09506000134352(17)201225(10)ABC123`)
//  and the modern GS1 Digital Link form
//  (`https://example.com/01/09506000134352/10/ABC123`).
//
//  The AI registry below is a curated subset of the most common AIs, sized
//  for a scanner app rather than a full traceability system. AIs not in
//  the registry are still surfaced under their numeric tag.
//

import Foundation

struct GS1Payload: Equatable {
    /// One AI → value pair, in source order.
    struct Element: Equatable {
        let ai: String          // e.g. "01", "17", "310"
        let value: String
    }

    let form: Form
    let elements: [Element]
    let raw: String

    enum Form: String, Equatable {
        case parens          = "Element string (parens)"
        case digitalLink     = "GS1 Digital Link"
        case unbracketed     = "Element string (FNC1)"
    }

    /// Convenience accessors for the most common AIs.
    func value(forAI ai: String) -> String? {
        elements.first(where: { $0.ai == ai })?.value
    }
    var gtin:      String? { value(forAI: "01") }
    var batchLot:  String? { value(forAI: "10") }
    var serial:    String? { value(forAI: "21") }
    var expiry:    String? { value(forAI: "17") }
    var bestBefore: String? { value(forAI: "15") }
    var production: String? { value(forAI: "11") }

    var labelledFields: [LabelledField] {
        elements.map { e in
            let name = GS1Registry.name(for: e.ai) ?? "AI \(e.ai)"
            let display = GS1Registry.formatValue(ai: e.ai, value: e.value)
            return LabelledField(label: "\(name) (\(e.ai))", value: display)
        }
    }
}

// MARK: - AI registry

enum GS1Registry {

    /// AI metadata: human-readable name + length category.
    private struct AIInfo {
        let name: String
        /// Fixed length, or `nil` for variable (terminator-driven).
        let length: Int?
        /// Whether the value is a date in YYMMDD form (so we can format it).
        let isDate: Bool
    }

    /// A focused set of AIs. The common product-level ones are first; the
    /// full GS1 General Spec has well over 200 AIs but most consumers
    /// never see them.
    private static let registry: [String: AIInfo] = [
        // Identification
        "00":  .init(name: "SSCC",                     length: 18, isDate: false),
        "01":  .init(name: "GTIN",                     length: 14, isDate: false),
        "02":  .init(name: "GTIN of contained items",  length: 14, isDate: false),

        // Batch / serial / variant
        "10":  .init(name: "Batch / lot",              length: nil, isDate: false),
        "20":  .init(name: "Variant",                  length: 2,  isDate: false),
        "21":  .init(name: "Serial number",            length: nil, isDate: false),
        "22":  .init(name: "Secondary data",           length: nil, isDate: false),
        "240": .init(name: "Additional product ID",    length: nil, isDate: false),
        "241": .init(name: "Customer part number",     length: nil, isDate: false),
        "242": .init(name: "Made-to-order variation",  length: nil, isDate: false),
        "243": .init(name: "Component / part",         length: nil, isDate: false),
        "250": .init(name: "Secondary serial number",  length: nil, isDate: false),
        "251": .init(name: "Reference to source entity", length: nil, isDate: false),
        "253": .init(name: "GDTI",                     length: nil, isDate: false),
        "254": .init(name: "GLN extension component",  length: nil, isDate: false),

        // Dates
        "11":  .init(name: "Production date",          length: 6,  isDate: true),
        "12":  .init(name: "Due date",                 length: 6,  isDate: true),
        "13":  .init(name: "Packaging date",           length: 6,  isDate: true),
        "15":  .init(name: "Best before",              length: 6,  isDate: true),
        "16":  .init(name: "Sell by",                  length: 6,  isDate: true),
        "17":  .init(name: "Expiry",                   length: 6,  isDate: true),

        // Quantity / measurement (only the simple ones — the 31xy / 32xy
        // family with embedded decimal indicators is intentionally skipped
        // here; we surface them as raw under their numeric tag).
        "30":  .init(name: "Variable count",           length: nil, isDate: false),
        "37":  .init(name: "Item count",               length: nil, isDate: false),

        // Pricing
        "390": .init(name: "Amount payable",           length: nil, isDate: false),
        "391": .init(name: "Amount payable + currency", length: nil, isDate: false),
        "392": .init(name: "Amount payable single item", length: nil, isDate: false),
        "393": .init(name: "Amount + currency single",  length: nil, isDate: false),

        // Logistics
        "400": .init(name: "Customer order number",    length: nil, isDate: false),
        "401": .init(name: "Consignment number",       length: nil, isDate: false),
        "402": .init(name: "Shipment ID number",       length: 17, isDate: false),
        "403": .init(name: "Routing code",             length: nil, isDate: false),
        "410": .init(name: "Ship to / deliver to GLN", length: 13, isDate: false),
        "411": .init(name: "Bill to GLN",              length: 13, isDate: false),
        "412": .init(name: "Purchased from GLN",       length: 13, isDate: false),
        "413": .init(name: "Ship for / deliver for GLN", length: 13, isDate: false),
        "414": .init(name: "Identification of physical location (GLN)", length: 13, isDate: false),
        "420": .init(name: "Ship to / deliver to postal code", length: nil, isDate: false),
        "421": .init(name: "Ship to + ISO country", length: nil, isDate: false),
        "422": .init(name: "Country of origin",        length: 3,  isDate: false),

        // URL
        "8200": .init(name: "Extended packaging URL",  length: nil, isDate: false),

        // Identifiers
        "8003": .init(name: "GRAI",                    length: nil, isDate: false),
        "8004": .init(name: "GIAI",                    length: nil, isDate: false),
        "8017": .init(name: "GSRN provider",           length: 18, isDate: false),
        "8018": .init(name: "GSRN recipient",          length: 18, isDate: false),
        "8020": .init(name: "Payment slip ref",        length: nil, isDate: false),
    ]

    /// Variable-length AIs — ordered by prefix length, longest first.
    /// Used by the unbracketed parser to pick the correct prefix length.
    private static let knownPrefixes: [String] = {
        registry.keys.sorted { a, b in a.count > b.count }
    }()

    static func name(for ai: String) -> String? {
        registry[ai]?.name
    }

    static func length(for ai: String) -> Int? {
        registry[ai]?.length
    }

    static func isDate(_ ai: String) -> Bool {
        registry[ai]?.isDate ?? false
    }

    /// Human-friendly value rendering — dates as YYYY-MM-DD, everything else verbatim.
    static func formatValue(ai: String, value: String) -> String {
        guard isDate(ai), value.count == 6 else { return value }
        let yy = String(value.prefix(2))
        let mm = String(value.dropFirst(2).prefix(2))
        let dd = String(value.suffix(2))
        // GS1 date convention: YY interpretation per AI spec (most use the
        // 51-year-window rule). Pragmatic compromise: pivot on YY=70.
        let year = (Int(yy) ?? 0) >= 70 ? "19\(yy)" : "20\(yy)"
        // DD == "00" means "month only".
        let dayPart = dd == "00" ? "" : "-\(dd)"
        return "\(year)-\(mm)\(dayPart)"
    }

    /// Pick the longest prefix from the variable-length AI registry that
    /// matches the start of `s`. Returns the prefix length on success.
    static func resolveVariablePrefix(_ s: Substring) -> Int? {
        for prefix in knownPrefixes where s.hasPrefix(prefix) {
            return prefix.count
        }
        // Unknown AIs default to 2-digit prefixes — better than failing.
        return s.count >= 2 ? 2 : nil
    }
}

// MARK: - Parsers

enum GS1Parser {

    private static let fnc1: Character = "\u{001D}"

    /// Quick probe — does this look like a GS1 element string?
    static func looksLikeGS1(_ raw: String) -> Bool {
        // Parens form starts with "(NN" or "(NNN".
        if raw.hasPrefix("(") {
            let after = raw.dropFirst()
            return after.prefix(4).allSatisfy { $0.isNumber || $0 == ")" }
        }
        // Digital Link — has /01/<14 digits> in the path.
        if let url = URL(string: raw),
           let host = url.host,
           !host.isEmpty,
           url.path.range(of: #"/0\d/\d{8,14}"#, options: .regularExpression) != nil {
            return true
        }
        // FNC1 form — starts with two digits and contains a GS or starts
        // with the FNC1 character.
        if raw.first == fnc1 { return true }
        if raw.count >= 4,
           raw.prefix(2).allSatisfy({ $0.isNumber }),
           GS1Registry.length(for: String(raw.prefix(2))) != nil ||
           GS1Registry.length(for: String(raw.prefix(3))) != nil ||
           GS1Registry.length(for: String(raw.prefix(4))) != nil {
            return true
        }
        return false
    }

    static func parse(_ raw: String) -> GS1Payload? {
        if raw.hasPrefix("(") {
            return parseParens(raw)
        }
        if let url = URL(string: raw), url.scheme?.hasPrefix("http") == true {
            return parseDigitalLink(url, raw: raw)
        }
        return parseFNC1(raw)
    }

    // MARK: Parens form — (01)09506000134352(17)201225(10)ABC123

    private static func parseParens(_ raw: String) -> GS1Payload? {
        var elements: [GS1Payload.Element] = []
        var i = raw.startIndex
        while i < raw.endIndex {
            guard raw[i] == "(",
                  let close = raw[i...].firstIndex(of: ")") else {
                return nil
            }
            let ai = String(raw[raw.index(after: i)..<close])
            // Find next "(" to delimit the value.
            let valStart = raw.index(after: close)
            let valEnd = raw[valStart...].firstIndex(of: "(") ?? raw.endIndex
            let value = String(raw[valStart..<valEnd])
            elements.append(.init(ai: ai, value: value))
            i = valEnd
        }
        guard !elements.isEmpty else { return nil }
        return GS1Payload(form: .parens, elements: elements, raw: raw)
    }

    // MARK: GS1 Digital Link — https://example.com/01/<gtin>/10/<batch>?…

    private static func parseDigitalLink(_ url: URL, raw: String) -> GS1Payload? {
        // Walk the path components in pairs: <ai>/<value>.
        let segments = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        var elements: [GS1Payload.Element] = []
        var idx = 0
        while idx + 1 < segments.count {
            let ai = segments[idx]
            // Only treat as AI if it's pure digits and the registry knows it.
            guard ai.allSatisfy({ $0.isNumber }),
                  GS1Registry.name(for: ai) != nil else {
                idx += 1
                continue
            }
            let value = segments[idx + 1]
            elements.append(.init(ai: ai, value: value))
            idx += 2
        }
        // Query params can also carry AIs.
        if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let items = comps.queryItems {
            for q in items where q.name.allSatisfy({ $0.isNumber }) {
                if GS1Registry.name(for: q.name) != nil, let v = q.value {
                    elements.append(.init(ai: q.name, value: v))
                }
            }
        }
        guard !elements.isEmpty else { return nil }
        return GS1Payload(form: .digitalLink, elements: elements, raw: raw)
    }

    // MARK: FNC1 / unbracketed form

    private static func parseFNC1(_ raw: String) -> GS1Payload? {
        // Strip a leading FNC1 if present.
        var s = Substring(raw)
        if s.first == fnc1 { s = s.dropFirst() }

        var elements: [GS1Payload.Element] = []
        while !s.isEmpty {
            guard let prefixLen = GS1Registry.resolveVariablePrefix(s) else { return nil }
            let aiEnd = s.index(s.startIndex, offsetBy: prefixLen)
            let ai = String(s[..<aiEnd])
            s = s[aiEnd...]

            if let fixed = GS1Registry.length(for: ai) {
                guard s.count >= fixed else { return nil }
                let valueEnd = s.index(s.startIndex, offsetBy: fixed)
                elements.append(.init(ai: ai, value: String(s[..<valueEnd])))
                s = s[valueEnd...]
            } else {
                // Variable — read up to next FNC1 or end.
                if let fnc = s.firstIndex(of: fnc1) {
                    elements.append(.init(ai: ai, value: String(s[..<fnc])))
                    s = s[s.index(after: fnc)...]
                } else {
                    elements.append(.init(ai: ai, value: String(s)))
                    s = Substring()
                }
            }
        }
        guard !elements.isEmpty else { return nil }
        return GS1Payload(form: .unbracketed, elements: elements, raw: raw)
    }
}
