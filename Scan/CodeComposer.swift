//
//  CodeComposer.swift
//  Scan
//
//  Builds well-formed payload strings from structured user input — vCard
//  3.0 contacts, WIFI: blobs, etc. The output of these composers is what
//  feeds CodeGenerator.image(for:symbology:scale:).
//

import Foundation

enum CodeComposer {

    // MARK: - vCard 3.0

    /// Build a minimal vCard 3.0 string. Only non-empty fields are emitted.
    /// The line separator is CRLF, per RFC 2425/2426 — Vision and most
    /// scanners accept LF too, but CRLF is the canonical choice.
    static func vCard(
        fullName: String,
        phone: String? = nil,
        email: String? = nil,
        organization: String? = nil,
        url: String? = nil
    ) -> String {
        var lines = ["BEGIN:VCARD", "VERSION:3.0"]

        let fn = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fn.isEmpty {
            lines.append("FN:\(escapeVCard(fn))")
            // Best-effort N: split — first space separates given/family.
            if let space = fn.firstIndex(of: " ") {
                let given = String(fn[..<space])
                let family = String(fn[fn.index(after: space)...])
                lines.append("N:\(escapeVCard(family));\(escapeVCard(given));;;")
            } else {
                lines.append("N:;\(escapeVCard(fn));;;")
            }
        }

        if let p = phone?.trimmed, !p.isEmpty {
            lines.append("TEL;TYPE=CELL:\(p)")
        }
        if let e = email?.trimmed, !e.isEmpty {
            lines.append("EMAIL:\(e)")
        }
        if let o = organization?.trimmed, !o.isEmpty {
            lines.append("ORG:\(escapeVCard(o))")
        }
        if let u = url?.trimmed, !u.isEmpty {
            lines.append("URL:\(u)")
        }

        lines.append("END:VCARD")
        return lines.joined(separator: "\r\n")
    }

    /// vCard text values must escape `\`, `,`, `;`, and newlines. Most simple
    /// inputs won't contain these, but be defensive.
    private static func escapeVCard(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "\\": out.append("\\\\")
            case ",":  out.append("\\,")
            case ";":  out.append("\\;")
            case "\n": out.append("\\n")
            default:   out.append(ch)
            }
        }
        return out
    }

    // MARK: - Wi-Fi

    enum WifiSecurity: String, CaseIterable, Identifiable {
        case wpa  = "WPA"
        case wep  = "WEP"
        /// WPA3 — uses the SAE handshake. Many devices that emit a
        /// WPA3-personal QR use this exact tag in the `T:` field;
        /// some still emit `WPA` with a SAE-only network and let the
        /// client fall back. We recognise both.
        case wpa3 = "SAE"
        /// Hotspot 2.0 / Passpoint. Not formally part of the original
        /// `WIFI:` spec but increasingly used in the wild — some
        /// vendors encode `T:HS20` for cafes / airport networks that
        /// support 802.11u/Passpoint provisioning. We recognise it
        /// for display only; iOS doesn't expose a programmatic API
        /// to install the matching profile.
        case passpoint = "HS20"
        case open = "nopass"
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .open:      return "None"
            case .wpa:       return "WPA / WPA2"
            case .wep:       return "WEP"
            case .wpa3:      return "WPA3 (SAE)"
            case .passpoint: return "Passpoint (HS20)"
            }
        }
    }

    /// Build a WIFI: payload per the de facto standard documented at
    /// https://en.wikipedia.org/wiki/QR_code#Wi-Fi_network_login
    /// Special characters in SSID/password are backslash-escaped.
    static func wifi(
        ssid: String,
        password: String? = nil,
        security: WifiSecurity = .wpa,
        hidden: Bool = false
    ) -> String {
        var fields: [String] = []
        fields.append("T:\(security.rawValue)")
        fields.append("S:\(escapeWifi(ssid))")
        if security != .open, let p = password, !p.isEmpty {
            fields.append("P:\(escapeWifi(p))")
        }
        if hidden {
            fields.append("H:true")
        }
        // Trailing empty field gives the canonical ";;" terminator.
        return "WIFI:" + fields.joined(separator: ";") + ";;"
    }

    /// Wi-Fi values escape `\`, `;`, `,`, `:`, and `"`.
    private static func escapeWifi(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            if "\\;,:\"".contains(ch) {
                out.append("\\")
            }
            out.append(ch)
        }
        return out
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
