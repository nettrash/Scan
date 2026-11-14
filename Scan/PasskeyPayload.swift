//
//  PasskeyPayload.swift
//  Scan
//
//  FIDO cross-device sign-in QR (CTAP 2.2 "hybrid transport", the code a
//  website shows so a phone can serve as the passkey authenticator).
//
//  The payload is `FIDO:/` followed by a digit-encoded CBOR map: every
//  7 bytes become 17 zero-padded decimal digits (little-endian), and a
//  trailing partial chunk uses a fixed smaller digit count. We decode it
//  to show *what the code is for* — sign-in vs. create-a-passkey, when it
//  was generated, tunnel-server count — but, like the 2FA-export payload,
//  deliberately never display the embedded one-time secret. Scan cannot
//  complete the handshake itself (that flow is reserved for the system
//  camera), so the result sheet is informational.
//

import Foundation

/// A decoded FIDO hybrid-transport (cross-device passkey) QR.
struct PasskeyPayload: Equatable {
    /// False when the `FIDO:/` prefix matched but the digit blob didn't
    /// decode to the expected CBOR map (truncated scan, future format).
    var decoded: Bool
    /// CTAP operation hint — "ga" (sign in) / "mc" (create a passkey).
    /// Other values are possible (the spec allows unknown hints).
    var operationHint: String?
    /// Number of assigned tunnel-server domains (CBOR key 2).
    var tunnelDomains: Int?
    /// When the displaying device generated the code (CBOR key 3, its
    /// own clock — informational only).
    var generatedAt: Date?
    /// Whether the displaying device offers "remember this phone" state-
    /// assisted transactions (CBOR key 4).
    var linkable: Bool?
    var raw: String

    var purposeDescription: String {
        switch operationHint {
        case "ga":   return "Sign in with a passkey"
        case "mc":   return "Create a passkey"
        case let h?: return "Cross-device passkey (\(h))"
        case nil:    return "Cross-device passkey"
        }
    }

    var labelledFields: [LabelledField] {
        var rows: [LabelledField] = [
            .init(label: "Format", value: "FIDO cross-device sign-in"),
            .init(label: "Purpose", value: purposeDescription),
        ]
        if let d = generatedAt {
            let f = DateFormatter()
            f.locale = .current
            f.dateStyle = .medium
            f.timeStyle = .short
            rows.append(.init(label: "Generated", value: f.string(from: d)))
        }
        if let n = tunnelDomains {
            rows.append(.init(label: "Tunnel servers", value: "\(n)"))
        }
        if let l = linkable {
            rows.append(.init(label: "Device linking", value: l ? "Offered" : "Not offered"))
        }
        if !decoded {
            rows.append(.init(label: "Payload", value: "Not decodable — possibly a newer format"))
        }
        return rows
    }
}

enum PasskeyParser {

    /// `FIDO:/` + at least one character. The QR alphanumeric mode the
    /// spec mandates is uppercase, but be liberal in what we accept.
    static func looksLikePasskey(_ s: String) -> Bool {
        s.count > 6 && s.prefix(6).uppercased() == "FIDO:/"
    }

    static func parse(_ raw: String) -> PasskeyPayload? {
        guard looksLikePasskey(raw) else { return nil }
        let digits = String(raw.dropFirst(6))
        // A real hybrid QR is strictly decimal digits after the prefix;
        // anything else is some other (unknown) FIDO: form → plain text.
        guard digits.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }

        guard let bytes = digitDecode(digits),
              let fields = decodeCBORMap(bytes) else {
            // Recognised but undecodable — still better than raw "text".
            return PasskeyPayload(decoded: false, operationHint: nil,
                                  tunnelDomains: nil, generatedAt: nil,
                                  linkable: nil, raw: raw)
        }

        var p = PasskeyPayload(decoded: true, operationHint: nil,
                               tunnelDomains: nil, generatedAt: nil,
                               linkable: nil, raw: raw)
        for (key, value) in fields {
            switch (key, value) {
            case (2, .uint(let n)) where n <= UInt64(Int.max):
                p.tunnelDomains = Int(n)
            case (3, .uint(let t)) where t < 1 << 40:
                p.generatedAt = Date(timeIntervalSince1970: TimeInterval(t))
            case (4, .bool(let b)):
                p.linkable = b
            case (5, .text(let s)):
                p.operationHint = s
            default:
                break   // keys 0 (public key) / 1 (QR secret) / unknown
            }
        }
        return p
    }

    // MARK: - CTAP digit encoding

    /// Digit count of a trailing partial chunk → its byte count.
    private static let partialChunkBytes: [Int: Int] = [3: 1, 5: 2, 8: 3, 10: 4, 13: 5, 15: 6]

    /// Reverses CTAP 2.2 `digitEncode`: each 17-decimal-digit chunk is a
    /// 7-byte little-endian integer; the final partial chunk must have one
    /// of the fixed digit counts above.
    private static func digitDecode(_ digits: String) -> [UInt8]? {
        guard !digits.isEmpty else { return nil }
        var out: [UInt8] = []
        var s = Substring(digits)
        while !s.isEmpty {
            let take: Int, byteCount: Int
            if s.count >= 17 {
                take = 17; byteCount = 7
            } else {
                guard let b = partialChunkBytes[s.count] else { return nil }
                take = s.count; byteCount = b
            }
            guard let v = UInt64(s.prefix(take)),
                  v < (UInt64(1) << (8 * byteCount)) else { return nil }
            var x = v
            for _ in 0..<byteCount {
                out.append(UInt8(x & 0xFF))
                x >>= 8
            }
            s = s.dropFirst(take)
        }
        return out
    }

    // MARK: - CBOR

    private static func decodeCBORMap(_ bytes: [UInt8]) -> [(UInt64, CBORReader.Value)]? {
        var reader = CBORReader(bytes)
        guard let header = reader.readHeader(), header.major == 5 else { return nil }
        var pairs: [(UInt64, CBORReader.Value)] = []
        for _ in 0..<header.arg {
            guard let key = reader.readValue(), let value = reader.readValue() else { return nil }
            if case .uint(let k) = key {
                pairs.append((k, value))
            }
        }
        return pairs
    }
}

/// Minimal CBOR reader — just enough to walk the CTAP2 canonical-CBOR map
/// inside a hybrid-transport QR. Understands unsigned ints, byte / text
/// strings and bools; skips everything else structurally. Indefinite
/// lengths (banned in CTAP2 CBOR) abort the parse.
private struct CBORReader {
    private let bytes: [UInt8]
    private var i = 0
    init(_ data: [UInt8]) { bytes = data }

    enum Value: Equatable {
        case uint(UInt64)
        case bytes([UInt8])
        case text(String)
        case bool(Bool)
        case other
    }

    mutating func readHeader() -> (major: UInt8, arg: UInt64)? {
        guard i < bytes.count else { return nil }
        let b = bytes[i]; i += 1
        let major = b >> 5
        let info = b & 0x1F
        switch info {
        case 0...23:
            return (major, UInt64(info))
        case 24...27:
            let n = 1 << Int(info - 24)
            guard i + n <= bytes.count else { return nil }
            var v: UInt64 = 0
            for _ in 0..<n { v = (v << 8) | UInt64(bytes[i]); i += 1 }
            return (major, v)
        default:
            return nil
        }
    }

    mutating func readValue() -> Value? {
        guard let h = readHeader() else { return nil }
        switch h.major {
        case 0:
            return .uint(h.arg)
        case 1:
            return .other                       // negative int — arg consumed
        case 2, 3:
            guard h.arg <= UInt64(bytes.count), i + Int(h.arg) <= bytes.count else { return nil }
            defer { i += Int(h.arg) }
            let d = Array(bytes[i ..< i + Int(h.arg)])
            if h.major == 2 { return .bytes(d) }
            return String(bytes: d, encoding: .utf8).map { .text($0) } ?? .other
        case 4, 5:
            // Nested array / map — skip elementwise. A count can't exceed
            // the remaining bytes (each element is ≥ 1 byte), so a huge
            // declared length is malformed rather than a long loop.
            guard h.arg <= UInt64(bytes.count) else { return nil }
            let elements = h.major == 5 ? 2 * h.arg : h.arg
            for _ in 0..<elements {
                guard readValue() != nil else { return nil }
            }
            return .other
        case 6:
            return readValue() == nil ? nil : .other
        case 7:
            if h.arg == 20 { return .bool(false) }
            if h.arg == 21 { return .bool(true) }
            return .other                       // null / float — bytes consumed
        default:
            return nil
        }
    }
}
