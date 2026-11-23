//
//  DigitalProductPassport.swift
//  Scan
//
//  The EU Digital Product Passport is arriving on a data carrier most people
//  already own a reader for: a GS1 DataMatrix or QR carrying GS1 Digital Link
//  AIs. Textiles, batteries, steel and electronics are scheduled to need one
//  first, and the consumer-facing question is always the same short list —
//  what is it, which batch, when does it expire, where is it from.
//
//  Scan reads the *carrier*: everything encoded in the code itself. The
//  passport record proper lives behind the resolver URL, and fetching it
//  would mean sending the serial number of the thing in your hand to a
//  server, so we show what the code says and where it would resolve, and no
//  further.
//
//  "Where is it from" is GS1's country family (General Specifications,
//  AIs 422–426): 422 the country of origin, 423 initial processing, 424
//  processing, 425 disassembly, 426 the country covering the full process
//  chain. AI 421 is not one of them — it is a *ship-to* postal code
//  prefixed with the destination's country code.
//

import Foundation

struct DigitalProductPassportPayload: Equatable {
    let gtin: String?
    let batchLot: String?
    let serial: String?
    let expiry: String?
    let production: String?
    /// ISO 3166-1 numeric country of origin — AI 422.
    let originNumeric: String?
    var originDescription: String? {
        guard let numeric = originNumeric else { return nil }
        return ISOCountry.name(numeric: numeric)
    }
    /// AI 423 — up to five countries of initial processing, three digits each.
    let initialProcessingNumeric: String?
    /// AI 424 — the country of processing.
    let processingNumeric: String?
    /// AI 425 — up to five countries of disassembly, three digits each.
    let disassemblyNumeric: String?
    /// AI 426 — the one country covering the full process chain.
    let fullProcessNumeric: String?
    /// Host the Digital Link resolver would be contacted at — shown, never
    /// contacted. `ShownHost.unusual` when the link hides its host.
    let resolverHost: String?
    /// The raw carrier, for copy / share.
    let raw: String
    /// Every element the carrier holds, in source order — the passport
    /// rows show some of them, and the rest must not vanish.
    let elements: [GS1Payload.Element]

    /// The AIs the passport rows already show.
    private static let passportAIs: Set<String> = ["01", "10", "21", "17", "11", "422", "423", "424", "425", "426"]

    var labelledFields: [LabelledField] {
        var rows: [LabelledField] = [
            .init(label: "Format", value: "GS1 Digital Product Passport carrier"),
        ]
        if let g = gtin        { rows.append(.init(label: "Product (GTIN)", value: g)) }
        if let b = batchLot    { rows.append(.init(label: "Batch / lot", value: b)) }
        if let s = serial      { rows.append(.init(label: "Serial", value: s)) }
        if let e = expiry      { rows.append(.init(label: "Expiry", value: e)) }
        if let p = production  { rows.append(.init(label: "Produced", value: p)) }
        if let o = originDescription {
            rows.append(.init(label: "Country of origin", value: o))
        }
        if let c = initialProcessingNumeric.flatMap(ISOCountry.names(numericList:)) {
            rows.append(.init(label: "Country of initial processing", value: c))
        }
        if let c = processingNumeric.flatMap({ ISOCountry.name(numeric: $0) }) {
            rows.append(.init(label: "Country of processing", value: c))
        }
        if let c = disassemblyNumeric.flatMap(ISOCountry.names(numericList:)) {
            rows.append(.init(label: "Country of disassembly", value: c))
        }
        if let c = fullProcessNumeric.flatMap({ ISOCountry.name(numeric: $0) }) {
            rows.append(.init(label: "Country covering full process chain", value: c))
        }
        if let h = resolverHost {
            rows.append(.init(label: "Passport hosted at", value: h))
        }
        // Everything else the carrier holds — best before, net weight, an
        // approval number — as the plain GS1 sheet shows it.
        rows += GS1Payload(form: .parens, elements: elements.filter { !Self.passportAIs.contains($0.ai) }, raw: raw)
            .labelledFields
        rows.append(.init(label: "Read from", value: "the code itself — nothing was fetched"))
        return rows
    }
}

enum DigitalProductPassportParser {

    /// DPP markers on a GS1 payload: a Digital Link with a `dpp` path
    /// segment or query parameter (ASCII, any case), or a passport-shaped
    /// bundle of AIs (origin + date + batch/serial alongside a GTIN). The
    /// origin is AI 422, or AI 426 — which GS1 uses *instead of* 422 when
    /// one country covers the whole process chain.
    static func looksLikePassport(_ payload: GS1Payload) -> Bool {
        if hasDPPMarker(payload) { return true }
        guard payload.gtin != nil else { return false }
        let hasOrigin = payload.value(forAI: "422") != nil || payload.value(forAI: "426") != nil
        let hasDate = payload.expiry != nil || payload.production != nil
        let hasUnit = payload.batchLot != nil || payload.serial != nil
        return hasOrigin && hasDate && hasUnit
    }

    static func parse(_ payload: GS1Payload) -> DigitalProductPassportPayload {
        let resolver = digitalLinkHost(payload.raw)
        return DigitalProductPassportPayload(
            gtin: payload.gtin,
            batchLot: payload.batchLot,
            serial: payload.serial,
            expiry: payload.expiry.map { GS1Registry.formatValue(ai: "17", value: $0) },
            production: payload.production.map { GS1Registry.formatValue(ai: "11", value: $0) },
            originNumeric: countryCodes(payload.value(forAI: "422"), max: 1),
            initialProcessingNumeric: countryCodes(payload.value(forAI: "423"), max: 5),
            processingNumeric: countryCodes(payload.value(forAI: "424"), max: 1),
            disassemblyNumeric: countryCodes(payload.value(forAI: "425"), max: 5),
            fullProcessNumeric: countryCodes(payload.value(forAI: "426"), max: 1),
            resolverHost: resolver,
            raw: payload.raw,
            elements: payload.elements
        )
    }

    /// A `dpp` path segment that is not an AI's value, or a `dpp` query
    /// parameter, in a Digital Link — read off the same split
    /// `GS1Parser.parseDigitalLink` walks. Never a substring of the raw
    /// text: a lot `ADPPX`, a serial or a host name `dppnews.example`
    /// would turn an ordinary product code into a passport.
    private static func hasDPPMarker(_ payload: GS1Payload) -> Bool {
        guard payload.form == .digitalLink, let url = URL(string: payload.raw) else { return false }
        let segments = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var idx = 0
        while idx < segments.count {
            let segment = segments[idx]
            if idx + 1 < segments.count, segment.allSatisfy({ $0.isNumber }), GS1Registry.name(for: segment) != nil {
                idx += 2                        // an AI and its value
                continue
            }
            if isDPP(segment) { return true }
            idx += 1
        }
        let names = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.map(\.name) ?? []
        return names.contains(where: isDPP)
    }

    private static func isDPP(_ s: String) -> Bool {
        s.utf8.count == 3 && s.utf8.map { $0 >= 0x41 && $0 <= 0x5A ? $0 + 0x20 : $0 }.elementsEqual("dpp".utf8)
    }

    /// An AI 422–426 value: one (N3) or up to five (N3+N..12) ISO 3166-1
    /// numeric codes, back to back. Anything else is not a country code.
    private static func countryCodes(_ value: String?, max: Int) -> String? {
        guard let value, !value.isEmpty, value.utf8.count % 3 == 0, value.utf8.count <= 3 * max,
              value.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
        return value
    }

    /// The resolver's host, by the rule the credential sheet uses
    /// (`ShownHost`), for an `http(s)` link in any letter case.
    private static func digitalLinkHost(_ raw: String) -> String? {
        let scheme = raw.prefix(8).lowercased()
        guard scheme.hasPrefix("http://") || scheme.hasPrefix("https://") else { return nil }
        return ShownHost.of(raw)
    }
}

/// ISO 3166-1 numeric → display name. GS1 carries the numeric form, and a
/// product can come from anywhere, so this is the whole current list: all
/// 249 codes, one row each, in numeric order.
///
/// Every row is the ISO assignment for its code: a wrong row is worse than a
/// missing one, because it prints a confident, false origin. The rows were
/// generated, not typed: codes and alpha-3 from ICU's region data
/// (`uloc_getISOCountries`, `uregion_getNumericCode`, `uloc_getISO3Country`),
/// checked against the UN M49 list (which leaves out 158, Taiwan) and the
/// JDK's; names are CLDR's English ones, where Apple's ICU swaps in its own
/// for five territories. The Android port's table is identical.
enum ISOCountry {

    static func name(numeric: String) -> String? {
        guard let (alpha, name) = table[numeric] else { return nil }
        return "\(name) (\(alpha))"
    }

    /// Back-to-back three-digit codes (AIs 423 and 425), every one named,
    /// or nil: a list with a country left out would be a false answer.
    static func names(numericList: String) -> String? {
        guard !numericList.isEmpty, numericList.utf8.count % 3 == 0 else { return nil }
        var names: [String] = []
        var rest = Substring(numericList)
        while !rest.isEmpty {
            guard let name = name(numeric: String(rest.prefix(3))) else { return nil }
            names.append(name)
            rest = rest.dropFirst(3)
        }
        return names.joined(separator: ", ")
    }

    private static let table: [String: (String, String)] = [
        "004": ("AFG", "Afghanistan"),
        "008": ("ALB", "Albania"),
        "010": ("ATA", "Antarctica"),
        "012": ("DZA", "Algeria"),
        "016": ("ASM", "American Samoa"),
        "020": ("AND", "Andorra"),
        "024": ("AGO", "Angola"),
        "028": ("ATG", "Antigua & Barbuda"),
        "031": ("AZE", "Azerbaijan"),
        "032": ("ARG", "Argentina"),
        "036": ("AUS", "Australia"),
        "040": ("AUT", "Austria"),
        "044": ("BHS", "Bahamas"),
        "048": ("BHR", "Bahrain"),
        "050": ("BGD", "Bangladesh"),
        "051": ("ARM", "Armenia"),
        "052": ("BRB", "Barbados"),
        "056": ("BEL", "Belgium"),
        "060": ("BMU", "Bermuda"),
        "064": ("BTN", "Bhutan"),
        "068": ("BOL", "Bolivia"),
        "070": ("BIH", "Bosnia & Herzegovina"),
        "072": ("BWA", "Botswana"),
        "074": ("BVT", "Bouvet Island"),
        "076": ("BRA", "Brazil"),
        "084": ("BLZ", "Belize"),
        "086": ("IOT", "British Indian Ocean Territory"),
        "090": ("SLB", "Solomon Islands"),
        "092": ("VGB", "British Virgin Islands"),
        "096": ("BRN", "Brunei"),
        "100": ("BGR", "Bulgaria"),
        "104": ("MMR", "Myanmar (Burma)"),
        "108": ("BDI", "Burundi"),
        "112": ("BLR", "Belarus"),
        "116": ("KHM", "Cambodia"),
        "120": ("CMR", "Cameroon"),
        "124": ("CAN", "Canada"),
        "132": ("CPV", "Cape Verde"),
        "136": ("CYM", "Cayman Islands"),
        "140": ("CAF", "Central African Republic"),
        "144": ("LKA", "Sri Lanka"),
        "148": ("TCD", "Chad"),
        "152": ("CHL", "Chile"),
        "156": ("CHN", "China"),
        "158": ("TWN", "Taiwan"),
        "162": ("CXR", "Christmas Island"),
        "166": ("CCK", "Cocos (Keeling) Islands"),
        "170": ("COL", "Colombia"),
        "174": ("COM", "Comoros"),
        "175": ("MYT", "Mayotte"),
        "178": ("COG", "Congo - Brazzaville"),
        "180": ("COD", "Congo - Kinshasa"),
        "184": ("COK", "Cook Islands"),
        "188": ("CRI", "Costa Rica"),
        "191": ("HRV", "Croatia"),
        "192": ("CUB", "Cuba"),
        "196": ("CYP", "Cyprus"),
        "203": ("CZE", "Czechia"),
        "204": ("BEN", "Benin"),
        "208": ("DNK", "Denmark"),
        "212": ("DMA", "Dominica"),
        "214": ("DOM", "Dominican Republic"),
        "218": ("ECU", "Ecuador"),
        "222": ("SLV", "El Salvador"),
        "226": ("GNQ", "Equatorial Guinea"),
        "231": ("ETH", "Ethiopia"),
        "232": ("ERI", "Eritrea"),
        "233": ("EST", "Estonia"),
        "234": ("FRO", "Faroe Islands"),
        "238": ("FLK", "Falkland Islands"),
        "239": ("SGS", "South Georgia & South Sandwich Islands"),
        "242": ("FJI", "Fiji"),
        "246": ("FIN", "Finland"),
        "248": ("ALA", "Åland Islands"),
        "250": ("FRA", "France"),
        "254": ("GUF", "French Guiana"),
        "258": ("PYF", "French Polynesia"),
        "260": ("ATF", "French Southern Territories"),
        "262": ("DJI", "Djibouti"),
        "266": ("GAB", "Gabon"),
        "268": ("GEO", "Georgia"),
        "270": ("GMB", "Gambia"),
        "275": ("PSE", "Palestinian Territories"),
        "276": ("DEU", "Germany"),
        "288": ("GHA", "Ghana"),
        "292": ("GIB", "Gibraltar"),
        "296": ("KIR", "Kiribati"),
        "300": ("GRC", "Greece"),
        "304": ("GRL", "Greenland"),
        "308": ("GRD", "Grenada"),
        "312": ("GLP", "Guadeloupe"),
        "316": ("GUM", "Guam"),
        "320": ("GTM", "Guatemala"),
        "324": ("GIN", "Guinea"),
        "328": ("GUY", "Guyana"),
        "332": ("HTI", "Haiti"),
        "334": ("HMD", "Heard & McDonald Islands"),
        "336": ("VAT", "Vatican City"),
        "340": ("HND", "Honduras"),
        "344": ("HKG", "Hong Kong SAR China"),
        "348": ("HUN", "Hungary"),
        "352": ("ISL", "Iceland"),
        "356": ("IND", "India"),
        "360": ("IDN", "Indonesia"),
        "364": ("IRN", "Iran"),
        "368": ("IRQ", "Iraq"),
        "372": ("IRL", "Ireland"),
        "376": ("ISR", "Israel"),
        "380": ("ITA", "Italy"),
        "384": ("CIV", "Côte d’Ivoire"),
        "388": ("JAM", "Jamaica"),
        "392": ("JPN", "Japan"),
        "398": ("KAZ", "Kazakhstan"),
        "400": ("JOR", "Jordan"),
        "404": ("KEN", "Kenya"),
        "408": ("PRK", "North Korea"),
        "410": ("KOR", "South Korea"),
        "414": ("KWT", "Kuwait"),
        "417": ("KGZ", "Kyrgyzstan"),
        "418": ("LAO", "Laos"),
        "422": ("LBN", "Lebanon"),
        "426": ("LSO", "Lesotho"),
        "428": ("LVA", "Latvia"),
        "430": ("LBR", "Liberia"),
        "434": ("LBY", "Libya"),
        "438": ("LIE", "Liechtenstein"),
        "440": ("LTU", "Lithuania"),
        "442": ("LUX", "Luxembourg"),
        "446": ("MAC", "Macao SAR China"),
        "450": ("MDG", "Madagascar"),
        "454": ("MWI", "Malawi"),
        "458": ("MYS", "Malaysia"),
        "462": ("MDV", "Maldives"),
        "466": ("MLI", "Mali"),
        "470": ("MLT", "Malta"),
        "474": ("MTQ", "Martinique"),
        "478": ("MRT", "Mauritania"),
        "480": ("MUS", "Mauritius"),
        "484": ("MEX", "Mexico"),
        "492": ("MCO", "Monaco"),
        "496": ("MNG", "Mongolia"),
        "498": ("MDA", "Moldova"),
        "499": ("MNE", "Montenegro"),
        "500": ("MSR", "Montserrat"),
        "504": ("MAR", "Morocco"),
        "508": ("MOZ", "Mozambique"),
        "512": ("OMN", "Oman"),
        "516": ("NAM", "Namibia"),
        "520": ("NRU", "Nauru"),
        "524": ("NPL", "Nepal"),
        "528": ("NLD", "Netherlands"),
        "531": ("CUW", "Curaçao"),
        "533": ("ABW", "Aruba"),
        "534": ("SXM", "Sint Maarten"),
        "535": ("BES", "Caribbean Netherlands"),
        "540": ("NCL", "New Caledonia"),
        "548": ("VUT", "Vanuatu"),
        "554": ("NZL", "New Zealand"),
        "558": ("NIC", "Nicaragua"),
        "562": ("NER", "Niger"),
        "566": ("NGA", "Nigeria"),
        "570": ("NIU", "Niue"),
        "574": ("NFK", "Norfolk Island"),
        "578": ("NOR", "Norway"),
        "580": ("MNP", "Northern Mariana Islands"),
        "581": ("UMI", "U.S. Outlying Islands"),
        "583": ("FSM", "Micronesia"),
        "584": ("MHL", "Marshall Islands"),
        "585": ("PLW", "Palau"),
        "586": ("PAK", "Pakistan"),
        "591": ("PAN", "Panama"),
        "598": ("PNG", "Papua New Guinea"),
        "600": ("PRY", "Paraguay"),
        "604": ("PER", "Peru"),
        "608": ("PHL", "Philippines"),
        "612": ("PCN", "Pitcairn Islands"),
        "616": ("POL", "Poland"),
        "620": ("PRT", "Portugal"),
        "624": ("GNB", "Guinea-Bissau"),
        "626": ("TLS", "Timor-Leste"),
        "630": ("PRI", "Puerto Rico"),
        "634": ("QAT", "Qatar"),
        "638": ("REU", "Réunion"),
        "642": ("ROU", "Romania"),
        "643": ("RUS", "Russia"),
        "646": ("RWA", "Rwanda"),
        "652": ("BLM", "St. Barthélemy"),
        "654": ("SHN", "St. Helena"),
        "659": ("KNA", "St. Kitts & Nevis"),
        "660": ("AIA", "Anguilla"),
        "662": ("LCA", "St. Lucia"),
        "663": ("MAF", "St. Martin"),
        "666": ("SPM", "St. Pierre & Miquelon"),
        "670": ("VCT", "St. Vincent & Grenadines"),
        "674": ("SMR", "San Marino"),
        "678": ("STP", "São Tomé & Príncipe"),
        "682": ("SAU", "Saudi Arabia"),
        "686": ("SEN", "Senegal"),
        "688": ("SRB", "Serbia"),
        "690": ("SYC", "Seychelles"),
        "694": ("SLE", "Sierra Leone"),
        "702": ("SGP", "Singapore"),
        "703": ("SVK", "Slovakia"),
        "704": ("VNM", "Vietnam"),
        "705": ("SVN", "Slovenia"),
        "706": ("SOM", "Somalia"),
        "710": ("ZAF", "South Africa"),
        "716": ("ZWE", "Zimbabwe"),
        "724": ("ESP", "Spain"),
        "728": ("SSD", "South Sudan"),
        "729": ("SDN", "Sudan"),
        "732": ("ESH", "Western Sahara"),
        "740": ("SUR", "Suriname"),
        "744": ("SJM", "Svalbard & Jan Mayen"),
        "748": ("SWZ", "Eswatini"),
        "752": ("SWE", "Sweden"),
        "756": ("CHE", "Switzerland"),
        "760": ("SYR", "Syria"),
        "762": ("TJK", "Tajikistan"),
        "764": ("THA", "Thailand"),
        "768": ("TGO", "Togo"),
        "772": ("TKL", "Tokelau"),
        "776": ("TON", "Tonga"),
        "780": ("TTO", "Trinidad & Tobago"),
        "784": ("ARE", "United Arab Emirates"),
        "788": ("TUN", "Tunisia"),
        "792": ("TUR", "Türkiye"),
        "795": ("TKM", "Turkmenistan"),
        "796": ("TCA", "Turks & Caicos Islands"),
        "798": ("TUV", "Tuvalu"),
        "800": ("UGA", "Uganda"),
        "804": ("UKR", "Ukraine"),
        "807": ("MKD", "North Macedonia"),
        "818": ("EGY", "Egypt"),
        "826": ("GBR", "United Kingdom"),
        "831": ("GGY", "Guernsey"),
        "832": ("JEY", "Jersey"),
        "833": ("IMN", "Isle of Man"),
        "834": ("TZA", "Tanzania"),
        "840": ("USA", "United States"),
        "850": ("VIR", "U.S. Virgin Islands"),
        "854": ("BFA", "Burkina Faso"),
        "858": ("URY", "Uruguay"),
        "860": ("UZB", "Uzbekistan"),
        "862": ("VEN", "Venezuela"),
        "876": ("WLF", "Wallis & Futuna"),
        "882": ("WSM", "Samoa"),
        "887": ("YEM", "Yemen"),
        "894": ("ZMB", "Zambia"),
    ]
}
