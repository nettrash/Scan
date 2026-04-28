//
//  DrivingLicensePayload.swift
//  Scan
//
//  Recognises AAMVA-format driver's licence PDF417 codes — the bar code
//  on the back of every US and Canadian driving licence.
//
//  Spec: AAMVA Card Design Standard 2020 (and earlier revisions). The
//  payload is a complex envelope of subfile records keyed by 3-letter
//  element IDs (DCS, DAQ, DBA, …). We surface the most common identity
//  + expiry fields without making any claims about jurisdiction-
//  specific extras.
//

import Foundation

struct DrivingLicensePayload: Equatable {

    let issuerIIN: String?              // 6-digit AAMVA Issuer ID Number
    let issuerName: String?             // resolved jurisdiction name when known
    let licenseNumber: String?
    let firstName: String?
    let middleName: String?
    let lastName: String?
    let dateOfBirth: Date?
    let expiry: Date?
    let issueDate: Date?
    let sex: String?                    // "Male" / "Female" / "Not specified"
    let address: String?
    let city: String?
    let state: String?
    let postalCode: String?
    /// Original raw payload — useful for forwarding to a verification service.
    let raw: String

    var labelledFields: [LabelledField] {
        var rows: [LabelledField] = []
        if let n = issuerName { rows.append(.init(label: "Issuer", value: n)) }
        else if let iin = issuerIIN { rows.append(.init(label: "Issuer IIN", value: iin)) }

        let fullName = [firstName, middleName, lastName]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " ")
        if !fullName.isEmpty { rows.append(.init(label: "Name", value: fullName)) }

        if let l = licenseNumber  { rows.append(.init(label: "License #", value: l)) }
        if let dob = dateOfBirth  { rows.append(.init(label: "Date of birth", value: DrivingLicensePayload.formatDate(dob))) }
        if let exp = expiry       { rows.append(.init(label: "Expires", value: DrivingLicensePayload.formatDate(exp))) }
        if let iss = issueDate    { rows.append(.init(label: "Issued", value: DrivingLicensePayload.formatDate(iss))) }
        if let s = sex            { rows.append(.init(label: "Sex", value: s)) }

        let addressLine = [address, city, state, postalCode]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: ", ")
        if !addressLine.isEmpty { rows.append(.init(label: "Address", value: addressLine)) }

        return rows
    }

    private static func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.locale = .current
        return f.string(from: d)
    }
}

// MARK: - Parser

enum DrivingLicenseParser {

    /// AAMVA payloads start with the compliance indicator `@`, then a
    /// line feed, then either `ANSI ` or `AAMVA ` followed by the IIN.
    static func looksLikeAAMVA(_ raw: String) -> Bool {
        guard raw.first == "@" else { return false }
        let lower = raw.lowercased()
        return lower.contains("\nansi ")
            || lower.contains("\naamva ")
            || lower.contains("\u{1E}ansi ")
            || lower.contains("\u{1E}aamva ")
    }

    static func parse(_ raw: String) -> DrivingLicensePayload? {
        guard looksLikeAAMVA(raw) else { return nil }

        // Step 1: extract the IIN. The header is on the second line:
        //   ANSI <IIN><version><jurisdiction-version><N subfiles>...
        // The IIN is 6 digits starting after "ANSI " or "AAMVA ".
        let iin: String? = {
            let lower = raw.lowercased()
            for marker in ["ansi ", "aamva "] {
                if let r = lower.range(of: marker) {
                    let after = raw.index(r.lowerBound, offsetBy: marker.count)
                    let tail = raw[after...]
                    let digits = tail.prefix(while: { $0.isNumber })
                    if digits.count >= 6 { return String(digits.prefix(6)) }
                }
            }
            return nil
        }()

        // Step 2: data elements appear after the subfile-designator
        // "DL" header (for driver licence). Each element is a 3-character
        // code followed by its value, terminated by a line break (\n) or
        // an ASCII record separator (0x1E or 0x1F).
        let body = raw

        // Common AAMVA element IDs — see spec appendix D.
        let elements: [String: String] = parseElements(body)

        // Date format in AAMVA is MMDDYYYY (US) or YYYYMMDD (CA).
        let isCanada: Bool = {
            // Canadian provinces use 9-digit IINs starting with 6 (e.g. 636023 for SK).
            // US issuers use 6-digit IINs starting with 6 too. Practical
            // heuristic: if DBA looks like YYYYMMDD (year > 1900), use CA layout.
            guard let dba = elements["DBA"] else { return false }
            return dba.count == 8 && Int(dba.prefix(4)).map { $0 > 1900 } ?? false
        }()

        let parseDate: (String?) -> Date? = { s in
            guard let s, s.count == 8 else { return nil }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = isCanada ? "yyyyMMdd" : "MMddyyyy"
            return f.date(from: s)
        }

        let sex: String? = {
            switch elements["DBC"] {
            case "1": return "Male"
            case "2": return "Female"
            case "9": return "Not specified"
            default: return elements["DBC"]
            }
        }()

        return DrivingLicensePayload(
            issuerIIN: iin,
            issuerName: iin.flatMap { jurisdictionName(forIIN: $0) },
            licenseNumber: elements["DAQ"],
            firstName: elements["DAC"] ?? elements["DCT"],
            middleName: elements["DAD"],
            lastName: elements["DCS"] ?? elements["DAB"],
            dateOfBirth: parseDate(elements["DBB"]),
            expiry: parseDate(elements["DBA"]),
            issueDate: parseDate(elements["DBD"]),
            sex: sex,
            address: elements["DAG"],
            city: elements["DAI"],
            state: elements["DAJ"],
            postalCode: elements["DAK"],
            raw: raw
        )
    }

    /// Walk the raw payload extracting `XYZ<value>` elements.
    /// Element IDs are 3 ASCII letters; values run until the next line
    /// terminator or record separator.
    private static func parseElements(_ raw: String) -> [String: String] {
        let terminators = Set<Character>(["\n", "\r", "\u{1E}", "\u{1F}"])
        var result: [String: String] = [:]
        let chars = Array(raw)
        var i = 0
        while i < chars.count {
            // A real AAMVA data element ID is 3 uppercase letters starting
            // with `D` (DCS, DAQ, DBA, …), and follows a record terminator
            // (newline / 0x1E). The `DL` and `ID` subfile *designators* are
            // 2 chars + 4-digit offset + 4-digit length; they cannot match
            // the three-uppercase-letter check below, so they're skipped
            // for free.
            if i + 3 < chars.count,
               chars[i] == "D",
               chars[i + 1].isLetter, chars[i + 1].isUppercase,
               chars[i + 2].isLetter, chars[i + 2].isUppercase {
                // Require the previous character to be a terminator (or the
                // element to be at the very start) so we don't false-match
                // letter triples that happen to appear inside another
                // element's value.
                let atStart = i == 0
                let afterTerminator = i > 0 && terminators.contains(chars[i - 1])
                guard atStart || afterTerminator else {
                    i += 1
                    continue
                }
                let id = String(chars[i..<i + 3])
                var j = i + 3
                while j < chars.count, !terminators.contains(chars[j]) {
                    j += 1
                }
                let value = String(chars[i + 3..<j])
                    .trimmingCharacters(in: .whitespaces)
                if !value.isEmpty, result[id] == nil {
                    result[id] = value
                }
                i = j + 1
            } else {
                i += 1
            }
        }
        return result
    }

    /// Map a few well-known IINs to a friendly issuer name. The full table
    /// has ~70 entries (every US state + DC + Canadian provinces); we ship
    /// just the busiest jurisdictions and surface the raw IIN for the rest.
    private static func jurisdictionName(forIIN iin: String) -> String? {
        switch iin {
        case "636014": return "California"
        case "636015": return "Texas"
        case "636001": return "Alabama"
        case "636025": return "Indiana"
        case "636026": return "South Carolina"
        case "636017": return "Wisconsin"
        case "636018": return "Wyoming"
        case "636020": return "Iowa"
        case "636021": return "Massachusetts"
        case "636030": return "Tennessee"
        case "636032": return "New Mexico"
        case "636034": return "Oregon"
        case "636035": return "South Dakota"
        case "636036": return "Pennsylvania"
        case "636038": return "Mississippi"
        case "636039": return "Vermont"
        case "636042": return "Rhode Island"
        case "636043": return "Hawaii"
        case "636045": return "New Hampshire"
        case "636046": return "Maine"
        case "636049": return "Idaho"
        case "636050": return "Montana"
        case "636051": return "Nebraska"
        case "636052": return "Nevada"
        case "636053": return "Arizona"
        case "636054": return "Connecticut"
        case "636055": return "Florida"
        case "636056": return "Illinois"
        case "636057": return "Washington"
        case "636058": return "Oklahoma"
        case "636059": return "Maryland"
        case "636060": return "Kentucky"
        case "636062": return "Virginia"
        case "636067": return "Kansas"
        case "636068": return "Minnesota"
        case "636069": return "Michigan"
        case "636070": return "New Jersey"
        case "636071": return "New York"
        case "636072": return "North Carolina"
        case "636074": return "North Dakota"
        case "636075": return "Ohio"
        // Canada
        case "636016": return "Ontario"
        case "636028": return "British Columbia"
        case "636023": return "Saskatchewan"
        case "636040": return "Alberta"
        case "636044": return "Quebec"
        case "636047": return "Manitoba"
        case "636048": return "New Brunswick"
        case "636066": return "Nova Scotia"
        case "636019": return "Prince Edward Island"
        case "636037": return "Newfoundland and Labrador"
        default: return nil
        }
    }
}
