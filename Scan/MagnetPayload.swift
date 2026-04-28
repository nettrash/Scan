//
//  MagnetPayload.swift
//  Scan
//
//  Recognises BitTorrent magnet URIs (`magnet:?xt=urn:btih:…`).
//  Surfaces the info-hash, display name and tracker list — enough to
//  let the user copy any single field or hand the whole URI to a
//  torrent client via Share / Open.
//

import Foundation

struct MagnetPayload: Equatable {
    let infoHash: String?
    let displayName: String?
    let trackers: [String]
    let exactLength: Int64?
    /// Original `magnet:?...` URI.
    let raw: String

    var labelledFields: [LabelledField] {
        var rows: [LabelledField] = []
        if let n = displayName, !n.isEmpty {
            rows.append(.init(label: "Name", value: n))
        }
        if let h = infoHash, !h.isEmpty {
            rows.append(.init(label: "Info hash", value: h))
        }
        if let len = exactLength {
            rows.append(.init(label: "Size", value: byteCount(len)))
        }
        if !trackers.isEmpty {
            rows.append(.init(
                label: trackers.count == 1 ? "Tracker" : "Trackers",
                value: trackers.joined(separator: "\n")
            ))
        }
        return rows
    }

    private func byteCount(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useAll]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}

enum MagnetURIParser {

    /// Quick prefix check — magnet links always start with `magnet:?`.
    static func looksLikeMagnet(_ s: String) -> Bool {
        s.lowercased().hasPrefix("magnet:?")
    }

    static func parse(_ raw: String) -> MagnetPayload? {
        guard looksLikeMagnet(raw) else { return nil }
        // Drop the `magnet:` scheme so URLComponents can parse the query.
        let body = String(raw.dropFirst("magnet:".count))
        guard var comps = URLComponents(string: "scheme:\(body)") else {
            return nil
        }
        comps.scheme = "scheme"   // the dummy stays; we only need queryItems
        let items = comps.queryItems ?? []

        var infoHash: String?
        var name: String?
        var trackers: [String] = []
        var exactLength: Int64?

        for item in items {
            guard let value = item.value else { continue }
            switch item.name.lowercased() {
            case "xt":
                // Format: `urn:btih:<40 hex chars or 32 base32 chars>`
                if let dotRange = value.range(of: "btih:") {
                    infoHash = String(value[dotRange.upperBound...])
                }
            case "dn":
                name = value.removingPercentEncoding ?? value
            case "tr":
                let decoded = value.removingPercentEncoding ?? value
                trackers.append(decoded)
            case "xl":
                exactLength = Int64(value)
            default:
                break
            }
        }

        // Reject if no info-hash AND no name — likely garbage.
        if infoHash == nil && (name?.isEmpty ?? true) { return nil }

        return MagnetPayload(
            infoHash: infoHash,
            displayName: name,
            trackers: trackers,
            exactLength: exactLength,
            raw: raw
        )
    }
}
