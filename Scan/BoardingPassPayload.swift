//
//  BoardingPassPayload.swift
//  Scan
//
//  Recognises the IATA Bar Coded Boarding Pass format (RP 1740c, version
//  M1). Found on virtually every airline boarding pass — the PDF417 / QR
//  / Aztec strip you see at the bottom of an electronic boarding pass.
//
//  Reference: IATA RP 1740c "Bar Coded Boarding Pass — Implementation
//  Guide". The mandatory leg layout is fixed-position; everything beyond
//  that is conditional, gated by a length field. We surface the
//  mandatory fields plus the per-leg fields we know how to parse.
//

import Foundation

struct BoardingPassPayload: Equatable {

    struct Leg: Equatable {
        let pnr: String
        let from: String                 // 3-letter IATA airport code
        let to: String                   // 3-letter IATA airport code
        let carrier: String              // 2-3 letter operating carrier code
        let flightNumber: String
        let dateJulian: Int?             // Day of year (1..366)
        let compartment: String          // single-letter cabin code (Y, J, F)
        let seat: String
        let sequenceNumber: String
        let passengerStatus: String
    }

    let passengerName: String
    let electronicTicket: Bool
    let formatCode: Character            // "M" for current spec
    let numberOfLegs: Int
    let legs: [Leg]
    /// Original raw payload — useful for re-encoding or sharing.
    let raw: String

    var labelledFields: [LabelledField] {
        var rows: [LabelledField] = []
        rows.append(.init(label: "Passenger", value: passengerName))
        rows.append(.init(label: "E-ticket",  value: electronicTicket ? "Yes" : "No"))
        rows.append(.init(label: "Legs",      value: String(numberOfLegs)))
        for (i, leg) in legs.enumerated() {
            let prefix = legs.count > 1 ? "Leg \(i + 1) — " : ""
            rows.append(.init(label: "\(prefix)PNR",      value: leg.pnr))
            rows.append(.init(label: "\(prefix)From",     value: leg.from))
            rows.append(.init(label: "\(prefix)To",       value: leg.to))
            rows.append(.init(label: "\(prefix)Flight",   value: "\(leg.carrier) \(leg.flightNumber.trimmingCharacters(in: .whitespaces))"))
            if let dj = leg.dateJulian {
                rows.append(.init(label: "\(prefix)Date", value: BoardingPassPayload.formatJulian(dj)))
            }
            rows.append(.init(label: "\(prefix)Cabin",    value: leg.compartment))
            rows.append(.init(label: "\(prefix)Seat",     value: leg.seat.trimmingCharacters(in: .whitespaces)))
            rows.append(.init(label: "\(prefix)Sequence", value: leg.sequenceNumber.trimmingCharacters(in: .whitespaces)))
        }
        return rows
    }

    /// Format a Julian day-of-year (1..366) as "DD MMM" using the current
    /// year as the assumed reference. Doesn't matter much — boarding
    /// passes are scanned within a few days of issue, so the year context
    /// is implicit.
    private static func formatJulian(_ day: Int) -> String {
        var comps = DateComponents()
        let year = Calendar.current.component(.year, from: Date())
        comps.year = year
        comps.day = day
        guard let date = Calendar.current.date(from: comps) else {
            return "Day \(day)"
        }
        let f = DateFormatter()
        f.dateFormat = "dd MMM"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}

// MARK: - Parser

enum BoardingPassParser {

    /// Quick prefix probe — BCBP starts with a format code (typically `M`)
    /// followed by a digit (number of legs).
    static func looksLikeBoardingPass(_ raw: String) -> Bool {
        guard raw.count >= 60 else { return false }
        let first = raw.first
        guard first == "M" else { return false }
        guard let second = raw.dropFirst().first, second.isNumber else { return false }
        // 'E' (electronic ticket indicator) at index 22 is a strong fingerprint.
        let idx22 = raw.index(raw.startIndex, offsetBy: 22)
        return raw[idx22] == "E"
    }

    static func parse(_ raw: String) -> BoardingPassPayload? {
        guard raw.count >= 60, raw.first == "M" else { return nil }

        // Mandatory fields (fixed positions per RP 1740c §3.1):
        //  0       Format Code               1 char
        //  1       Number of legs encoded    1 char
        //  2..21   Passenger name            20 chars
        //  22      Electronic ticket ind.    1 char
        //  23..29  Operating PNR             7 chars
        //  30..32  From IATA airport         3 chars
        //  33..35  To IATA airport           3 chars
        //  36..38  Operating carrier         3 chars
        //  39..43  Flight number             5 chars
        //  44..46  Date of flight (Julian)   3 chars
        //  47      Compartment code          1 char
        //  48..51  Seat                      4 chars
        //  52..56  Check-in sequence number  5 chars
        //  57      Passenger status          1 char
        //  58..59  Field size of variable    2 chars hex
        let chars = Array(raw)
        func slice(_ start: Int, _ length: Int) -> String {
            let end = min(start + length, chars.count)
            return String(chars[start..<end])
        }

        let formatCode = chars[0]
        guard let legCount = Int(String(chars[1])) else { return nil }
        let passengerName = slice(2, 20).trimmingCharacters(in: .whitespaces)
        let etktChar = chars[22]
        let pnr = slice(23, 7).trimmingCharacters(in: .whitespaces)
        let from = slice(30, 3)
        let to = slice(33, 3)
        let carrier = slice(36, 3).trimmingCharacters(in: .whitespaces)
        let flightNumber = slice(39, 5)
        let dateJulian = Int(slice(44, 3).trimmingCharacters(in: .whitespaces))
        let compartment = slice(47, 1)
        let seat = slice(48, 4)
        let sequence = slice(52, 5)
        let status = slice(57, 1)

        // Sanity-check airport codes — three uppercase A-Z each.
        let isAirport: (String) -> Bool = { s in
            s.count == 3 && s.allSatisfy { $0.isLetter && $0.isUppercase }
        }
        guard isAirport(from), isAirport(to) else { return nil }

        let firstLeg = BoardingPassPayload.Leg(
            pnr: pnr,
            from: from,
            to: to,
            carrier: carrier,
            flightNumber: flightNumber,
            dateJulian: dateJulian,
            compartment: compartment,
            seat: seat,
            sequenceNumber: sequence,
            passengerStatus: status
        )

        // Subsequent legs (if numberOfLegs > 1) follow the conditional
        // section and have a similar fixed layout, but parsing them
        // robustly across airlines is non-trivial — different carriers
        // emit varying conditional sections. For now, we surface only
        // the first leg in detail and let `numberOfLegs` reflect the total.
        // The conditional / security data is not parsed.

        return BoardingPassPayload(
            passengerName: passengerName,
            electronicTicket: etktChar == "E",
            formatCode: formatCode,
            numberOfLegs: legCount,
            legs: [firstLeg],
            raw: raw
        )
    }
}
