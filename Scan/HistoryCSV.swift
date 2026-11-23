//
//  HistoryCSV.swift
//  Scan
//
//  Convert a list of `ScanRecord`s into a CSV file written to a
//  temporary URL. The URL is then handed to a `ShareLink` (system
//  share sheet) so the user can drop it into Files, AirDrop it,
//  e-mail it, etc.
//
//  We re-export to a fresh URL on every share — small (history is
//  rarely huge) and avoids stale-content woes if the user exports
//  twice without leaving the screen.
//

import Foundation

enum HistoryCSV {
    /// Header row written verbatim. Keep field order stable — at least
    /// one of our power users will be importing this into a spreadsheet
    /// with positional column references.
    private static let header = "timestamp,symbology,value,notes,favourite"

    /// ISO 8601 with calendar date + time + offset. Spreadsheet-friendly
    /// and unambiguous across DST / timezones.
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Writes the CSV to a temporary file and returns the URL. The
    /// file is created with a stable filename (`Scan-history.csv`) so
    /// the share-sheet target sees a friendly name; we delete any
    /// pre-existing file at that path first to avoid mixing old and
    /// new content.
    static func write(_ records: [ScanRecord]) throws -> URL {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("Scan-history.csv")
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }

        var lines: [String] = [header]
        lines.reserveCapacity(records.count + 1)
        for r in records {
            let timestamp = r.timestamp.map(isoFormatter.string(from:)) ?? ""
            let symbology = r.symbology ?? ""
            let value     = r.value ?? ""
            let notes     = r.notes ?? ""
            let favourite = r.isFavorite ? "1" : "0"
            lines.append([
                csvEscape(timestamp),
                csvEscape(symbology),
                csvEscape(value),
                csvEscape(notes),
                favourite,
            ].joined(separator: ","))
        }
        // RFC 4180 says CRLF line breaks; Excel (especially older
        // Windows builds) really, really wants those.
        let body = lines.joined(separator: "\r\n") + "\r\n"
        try body.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    /// RFC 4180 escape (with formula neutralisation) exposed for the
    /// bulk-capture export in `BulkScanSession`, so both exports quote
    /// identically.
    static func csvField(_ s: String) -> String { csvEscape(s) }

    /// Shared timestamp rendering (ISO 8601 with offset).
    static func timestampString(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    /// Writes a bulk-capture session to a temporary CSV for the share
    /// sheet. Same escaping and line-ending rules as the history export.
    static func writeBulk(lines: [String]) throws -> URL {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("Scan-bulk-capture.csv")
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        let body = lines.joined(separator: "\r\n") + "\r\n"
        try body.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    /// RFC 4180-style escape, after `neutralisingFormula(_:)`: wrap in
    /// double quotes if the field contains a quote, comma, CR, or LF;
    /// double-up any embedded quotes. Always quoting would be safer but
    /// would bloat the output and trip up a few naïve consumers, so we
    /// only quote where we must.
    ///
    /// The tests look at Unicode scalars, not `Character`s, and the quotes
    /// are doubled with a literal replace. "\r\n" is a single grapheme
    /// cluster that equals neither "\r" nor "\n", and a comma or quote
    /// followed by a combining mark is one cluster too, so a `Character`
    /// test left a CRLF vCard unquoted and split its row, and the default
    /// (non-literal) replace skips such a quote. Scalars are also what the
    /// Android port's per-`Char` check sees for these ASCII characters, so
    /// both write the same bytes.
    private static func csvEscape(_ s: String) -> String {
        let field = neutralisingFormula(s)
        let needsQuoting = field.unicodeScalars.contains { scalar in
            scalar == "\"" || scalar == "," || scalar == "\r" || scalar == "\n"
        }
        if !needsQuoting { return field }
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"", options: .literal)
        return "\"\(escaped)\""
    }

    /// CSV formula injection: a spreadsheet opening the file evaluates a
    /// cell that starts with = + - or @, and a scanned code is text an
    /// attacker chose. A cell starting with one of those, or with a tab or
    /// CR, gets a leading apostrophe, which keeps it plain text. Applied to
    /// every escaped cell of both exports, before the quoting above — so
    /// `=1+2";=1+2` is written `"'=1+2"";=1+2"`, as in OWASP's example. The
    /// Android port's `HistoryCsv` applies the same rule to the same set.
    private static func neutralisingFormula(_ s: String) -> String {
        guard let first = s.unicodeScalars.first,
              ["=", "+", "-", "@", "\t", "\r"].contains(first) else { return s }
        return "'" + s
    }
}
