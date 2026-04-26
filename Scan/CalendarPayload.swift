//
//  CalendarPayload.swift
//  Scan
//
//  Parses iCalendar (VEVENT) payloads per RFC 5545 — enough to surface
//  summary, start/end, location, description, organizer, and url, plus
//  to feed an EKEvent for "Add to Calendar".
//

import Foundation

struct CalendarPayload: Equatable {
    let summary: String?
    let startDate: Date?
    let endDate: Date?
    let allDay: Bool
    let location: String?
    let description: String?
    let organizer: String?
    let url: URL?
    let raw: String

    var labelledFields: [LabelledField] {
        var rows: [LabelledField] = []
        if let s = summary, !s.isEmpty {
            rows.append(.init(label: "Title", value: s))
        }
        if let start = startDate {
            rows.append(.init(label: "Start", value: format(start, allDay: allDay)))
        }
        if let end = endDate {
            rows.append(.init(label: "End", value: format(end, allDay: allDay)))
        }
        if let l = location, !l.isEmpty {
            rows.append(.init(label: "Location", value: l))
        }
        if let o = organizer, !o.isEmpty {
            rows.append(.init(label: "Organizer", value: o))
        }
        if let u = url {
            rows.append(.init(label: "URL", value: u.absoluteString))
        }
        if let d = description, !d.isEmpty {
            rows.append(.init(label: "Description", value: d))
        }
        return rows
    }

    private func format(_ date: Date, allDay: Bool) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.dateStyle = .medium
        f.timeStyle = allDay ? .none : .short
        return f.string(from: date)
    }
}

// MARK: - Parser

enum CalendarPayloadParser {

    /// Quick check: does this look like an iCalendar payload?
    static func looksLikeICalendar(_ s: String) -> Bool {
        let lower = s.lowercased()
        return lower.hasPrefix("begin:vcalendar") || lower.hasPrefix("begin:vevent")
    }

    /// Parse a VEVENT (or full VCALENDAR) into a CalendarPayload. Returns
    /// nil only if the input doesn't contain a recognisable event block.
    static func parse(_ raw: String) -> CalendarPayload? {
        // Unfold continuation lines: any line that begins with whitespace is a
        // continuation of the previous one (RFC 5545 § 3.1).
        let unfolded = unfold(raw)
        let lines = unfolded.components(separatedBy: "\n")

        // Find the VEVENT block. A VCALENDAR can hold many; we take the first.
        var inEvent = false
        var props: [(name: String, params: [String: String], value: String)] = []
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.uppercased() == "BEGIN:VEVENT" {
                inEvent = true; continue
            }
            if trimmedLine.uppercased() == "END:VEVENT" {
                break
            }
            // If the payload IS only a VEVENT (no enclosing VCALENDAR) we
            // still want to read its properties.
            if !inEvent && trimmedLine.uppercased().hasPrefix("BEGIN:V") { continue }
            if !inEvent && !trimmedLine.uppercased().hasPrefix("END:") { continue }
            if !inEvent { continue }
            guard !trimmedLine.isEmpty else { continue }
            if let prop = parseLine(trimmedLine) { props.append(prop) }
        }
        // Fallback: if we never saw BEGIN:VEVENT but the raw text looks
        // like a single VEVENT body, parse every property line we can find.
        if props.isEmpty {
            for line in lines {
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty,
                      !t.uppercased().hasPrefix("BEGIN:"),
                      !t.uppercased().hasPrefix("END:") else { continue }
                if let prop = parseLine(t) { props.append(prop) }
            }
        }
        guard !props.isEmpty else { return nil }

        var summary: String?
        var dtStart: (date: Date, allDay: Bool)?
        var dtEnd: (date: Date, allDay: Bool)?
        var location: String?
        var description: String?
        var organizer: String?
        var url: URL?

        for p in props {
            let value = unescapeText(p.value)
            switch p.name.uppercased() {
            case "SUMMARY":
                summary = value
            case "LOCATION":
                location = value
            case "DESCRIPTION":
                description = value
            case "ORGANIZER":
                // ORGANIZER values are typically `mailto:foo@bar` or
                // `CN=Name:mailto:...`. Strip the mailto: if present.
                let raw = value
                organizer = raw
                    .replacingOccurrences(of: "mailto:", with: "", options: .caseInsensitive)
            case "URL":
                url = URL(string: value)
            case "DTSTART":
                dtStart = parseDate(value: p.value, params: p.params)
            case "DTEND":
                dtEnd = parseDate(value: p.value, params: p.params)
            default:
                break
            }
        }

        return CalendarPayload(
            summary: summary,
            startDate: dtStart?.date,
            endDate: dtEnd?.date,
            allDay: (dtStart?.allDay ?? false) || (dtEnd?.allDay ?? false),
            location: location,
            description: description,
            organizer: organizer,
            url: url,
            raw: raw
        )
    }

    // MARK: - Line unfolding

    /// RFC 5545 line folding: a line starting with a space or tab is a
    /// continuation of the previous logical line.
    private static func unfold(_ s: String) -> String {
        let normalised = s.replacingOccurrences(of: "\r\n", with: "\n")
        var out = ""
        for line in normalised.split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = line.first, (first == " " || first == "\t") {
                out += String(line.dropFirst())
            } else {
                if !out.isEmpty { out += "\n" }
                out += String(line)
            }
        }
        return out
    }

    // MARK: - Property line

    private static func parseLine(
        _ line: String
    ) -> (name: String, params: [String: String], value: String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let head = String(line[..<colon])
        let value = String(line[line.index(after: colon)...])

        let pieces = head.split(separator: ";").map(String.init)
        guard let name = pieces.first else { return nil }
        var params: [String: String] = [:]
        for piece in pieces.dropFirst() {
            let kv = piece.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { params[kv[0].uppercased()] = kv[1] }
        }
        return (name, params, value)
    }

    // MARK: - Date parsing

    /// Parses an iCalendar date / date-time. Handles three common forms:
    ///   `DTSTART;VALUE=DATE:20260115`              (all-day)
    ///   `DTSTART:20260115T140000Z`                 (UTC)
    ///   `DTSTART;TZID=Europe/Berlin:20260115T140000` (timezone-aware)
    /// Floating-time (no TZ, no Z) is interpreted as the device's local TZ.
    private static func parseDate(
        value: String,
        params: [String: String]
    ) -> (date: Date, allDay: Bool)? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let isAllDay = (params["VALUE"]?.uppercased() == "DATE") || v.count == 8

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if isAllDay {
            formatter.dateFormat = "yyyyMMdd"
            formatter.timeZone = TimeZone.current
            return formatter.date(from: v).map { ($0, true) }
        }

        // Has a "Z" suffix → UTC.
        if v.hasSuffix("Z") {
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            formatter.timeZone = TimeZone(identifier: "UTC")
            return formatter.date(from: v).map { ($0, false) }
        }

        // TZID parameter, otherwise local time.
        let tz = params["TZID"].flatMap { TimeZone(identifier: $0) }
            ?? TimeZone.current
        formatter.timeZone = tz
        for fmt in ["yyyyMMdd'T'HHmmss", "yyyyMMdd'T'HHmm"] {
            formatter.dateFormat = fmt
            if let d = formatter.date(from: v) { return (d, false) }
        }
        return nil
    }

    /// Reverse the iCalendar TEXT escaping rules (RFC 5545 § 3.3.11):
    /// \\, \;, \, and \n / \N → newline.
    private static func unescapeText(_ s: String) -> String {
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "\\", let next = s.index(i, offsetBy: 1, limitedBy: s.endIndex), next < s.endIndex {
                let n = s[next]
                switch n {
                case "n", "N": out.append("\n")
                case "\\":     out.append("\\")
                case ";":      out.append(";")
                case ",":      out.append(",")
                default:       out.append(n)
                }
                i = s.index(after: next)
            } else {
                out.append(c)
                i = s.index(after: i)
            }
        }
        return out
    }
}
