//
//  CBORReader.swift
//  Scan
//
//  Minimal RFC 8949 (CBOR) reader — just enough to walk the small,
//  definite-length maps that ride inside the codes this app understands.
//  Shared by the CTAP hybrid-transport passkey QR and the ISO/IEC 18013-5
//  mobile-driving-licence request (both new in 1.10); it used to live
//  privately inside `PasskeyPayload.swift` until the mDL parser needed it.
//
//  Deliberately incomplete: indefinite-length items are banned in both
//  CTAP2 canonical CBOR and the mdoc profiles, so encountering one aborts
//  the parse rather than guessing. Floats, tags and negative integers are
//  consumed structurally and reported as `.other` — no caller needs them.
//
//  Containers and tags nest at most `maxDepth` deep. The input is a scanned
//  code — whoever printed it chose every byte — and an array-of-array-of-…
//  payload recurses once per byte: a QR's worth is a few thousand frames,
//  enough to overflow a thread's stack and take the app (or the share
//  extension) down. No structure we decode nests more than half a dozen
//  levels, so the cap costs nothing real. Same cap as the Android port.
//

import Foundation

struct CBORReader {
    private let bytes: [UInt8]
    private var i = 0

    init(_ data: [UInt8]) { bytes = data }

    /// Deepest container / tag nesting accepted — see the file header.
    static let maxDepth = 64

    /// True while unread input remains — lets a caller distinguish
    /// "parsed to the end" from "stopped early".
    var hasMore: Bool { i < bytes.count }

    enum Value {
        case uint(UInt64)
        case bytes([UInt8])
        case text(String)
        case bool(Bool)
        case array([Value])
        case map([CBORPair])
        case other
    }

    struct Header {
        let major: UInt8
        let arg: UInt64
    }

    mutating func readHeader() -> Header? {
        guard i < bytes.count else { return nil }
        let b = bytes[i]; i += 1
        let major = b >> 5
        let info = b & 0x1F
        switch info {
        case 0...23:
            return Header(major: major, arg: UInt64(info))
        case 24...27:
            let n = 1 << Int(info - 24)
            guard i + n <= bytes.count else { return nil }
            var v: UInt64 = 0
            for _ in 0..<n { v = (v << 8) | UInt64(bytes[i]); i += 1 }
            return Header(major: major, arg: v)
        default:                            // 28–31: indefinite / simple — unsupported
            return nil
        }
    }

    mutating func readValue() -> Value? {
        readValue(depth: 0)
    }

    private mutating func readValue(depth: Int) -> Value? {
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
            guard depth < Self.maxDepth else { return nil }
            // Nested array / map — walk elementwise. An element is ≥ 1 byte,
            // so a declared count larger than the remaining input is
            // malformed rather than a long loop.
            guard h.arg <= UInt64(bytes.count) else { return nil }
            if h.major == 4 {
                var items: [Value] = []
                for _ in 0..<h.arg {
                    guard let v = readValue(depth: depth + 1) else { return nil }
                    items.append(v)
                }
                return .array(items)
            }
            var pairs: [CBORPair] = []
            for _ in 0..<h.arg {
                guard let k = readValue(depth: depth + 1),
                      let v = readValue(depth: depth + 1) else { return nil }
                pairs.append(CBORPair(key: k, value: v))
            }
            return .map(pairs)
        case 6:
            // Tag: the tag number was consumed with the header; now the item.
            // Tags can wrap tags, so they count towards the depth too.
            guard depth < Self.maxDepth else { return nil }
            return readValue(depth: depth + 1) == nil ? nil : .other
        case 7:
            if h.arg == 20 { return .bool(false) }
            if h.arg == 21 { return .bool(true) }
            return .other                       // null / undefined / float
        default:
            return nil
        }
    }
}

/// One key/value entry of a decoded CBOR map. A struct (rather than a
/// labelled tuple) so `Value` can be `Equatable` without recursive-tuple
/// gymnastics and so the lookups below read cleanly.
struct CBORPair: Equatable {
    let key: CBORReader.Value
    let value: CBORReader.Value
}

extension Array where Element == CBORPair {
    /// Value for a text key, if present.
    func value(forKey key: String) -> CBORReader.Value? {
        first { $0.key == .text(key) }?.value
    }

    /// Value for an unsigned-integer key, if present.
    func value(forKey key: UInt64) -> CBORReader.Value? {
        first { $0.key == .uint(key) }?.value
    }

    /// Every value stored under a text key. CBOR permits duplicate keys and
    /// the mdoc structures key by integer *or* name depending on profile,
    /// so callers that want completeness use this instead of `value(forKey:)`.
    func values(forKey key: String) -> [CBORReader.Value] {
        filter { $0.key == .text(key) }.map(\.value)
    }
}

// Explicit rather than synthesised: `Value` reaches `CBORPair` and
// `CBORPair` reaches back to `Value`, and a synthesised `==` across that
// cycle is something the compiler will not generate for us.
extension CBORReader.Value: Equatable {
    static func == (lhs: CBORReader.Value, rhs: CBORReader.Value) -> Bool {
        switch (lhs, rhs) {
        case let (.uint(a), .uint(b)):           return a == b
        case let (.bytes(a), .bytes(b)):         return a == b
        case let (.text(a), .text(b)):           return a == b
        case let (.bool(a), .bool(b)):           return a == b
        case let (.array(a), .array(b)):         return a == b
        case let (.map(a), .map(b)):             return a == b
        case (.other, .other):                   return true
        default:                                 return false
        }
    }
}
