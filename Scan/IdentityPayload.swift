//
//  IdentityPayload.swift
//  Scan
//
//  The two digital-identity codes people actually meet now that wallets
//  ship: the ISO/IEC 18013-5 mdoc engagement QR (`mdoc:`, the one a
//  digital-ID wallet shows an ID reader; `mdoc://` is the ISO/IEC 18013-7
//  online form a website hands a wallet) and the eIDAS 2.0 / OpenID4VP
//  wallet flows (the one a verifier site shows so an EU Digital Identity
//  Wallet can hand it attributes).
//
//  Neither is a credential: one sets up a connection, the other tells a
//  wallet what to reveal. That makes them the same shape as the FIDO passkey
//  QR from 1.10 — a code that starts an exchange between two other parties —
//  so they get the same treatment: decode it, say plainly what it is for,
//  and never perform the exchange ourselves. Signature verification is
//  explicitly out of scope: we decode to inform, and say so, rather than
//  implying we vouched for it.
//

import Foundation

// MARK: - Base64URL helper

/// Shared lenient base64URL decoder. The existing private one in
/// `DeepLink.swift` returns a `String`; the identity payloads need raw
/// bytes (CBOR inside a query parameter), so this lives beside them.
enum PayloadCodec {

    static func base64URLData(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+")
                 .replacingOccurrences(of: "_", with: "/")
        // Strip any whitespace a camera decode may have introduced.
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.count % 4 != 0 { t.append("=") }
        return Data(base64Encoded: t, options: [])
    }

    static func base64URLString(_ s: String) -> String? {
        guard let d = base64URLData(s),
              let text = String(data: d, encoding: .utf8) else { return nil }
        return text
    }

    /// Loose JSON parse of a base64URL JWT segment. Returns nil for
    /// anything that is not a JSON object, which is the shape every claim
    /// set in these profiles uses.
    static func jsonObject(fromBase64URL segment: String) -> [String: Any]? {
        base64URLData(segment).flatMap(jsonObject(fromJSONData:))
    }

    /// Containers a JSON document may nest — the CBOR reader's cap. The
    /// Android reader stops at the same depth, so a document parses on
    /// both phones or on neither.
    static let maxJSONDepth = 64

    /// The one way a scanned JSON document reaches `JSONSerialization`: a
    /// JSON object in UTF-8, or nil. `JSONSerialization` would also take
    /// UTF-16 and UTF-32 — a NUL byte is how it spots them, and ASCII text
    /// in those encodings is otherwise valid UTF-8 — which the Android port
    /// never reads, so NUL bytes and invalid UTF-8 are turned away first.
    /// The depth check comes before the parse because `JSONSerialization`
    /// recurses once per container: about 400 of them, which fit in one QR
    /// code, overrun the 512 KB stack of the thread an App Intent runs on.
    static func jsonObject(fromJSONData data: Data) -> [String: Any]? {
        guard !data.contains(0), String(validating: data, as: UTF8.self) != nil,
              jsonNestingIsWithinLimit(data),
              let obj = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = obj as? [String: Any] else { return nil }
        return dict
    }

    /// False once `{` / `[` nest deeper than `maxJSONDepth` outside a
    /// string (escapes honoured). Only the brackets are counted: whether
    /// the rest is JSON is `JSONSerialization`'s question.
    static func jsonNestingIsWithinLimit(_ bytes: some Sequence<UInt8>) -> Bool {
        var depth = 0
        var inString = false
        var escaped = false
        for b in bytes {
            if inString {
                if escaped {
                    escaped = false
                } else if b == UInt8(ascii: "\\") {
                    escaped = true
                } else if b == UInt8(ascii: "\"") {
                    inString = false
                }
                continue
            }
            switch b {
            case UInt8(ascii: "\""):
                inString = true
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1
                if depth > maxJSONDepth { return false }
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth -= 1
            default:
                break
            }
        }
        return true
    }
}

// MARK: - Hosts on the credential and passport sheets

/// The host a credential or Digital Product Passport row names for a URL in
/// the code: the host a browser would contact, written as the safety
/// check's findings write it (`HostName.normalized` — percent-decoded,
/// NFKC-folded, invisible characters dropped, lower-cased, Unicode kept), so
/// the sheet, the risk banner and the look-alike check all see one host.
/// The authority is split by `DecodedURL`'s rules — it ends at `\`, IPv6
/// brackets and the port are dropped — rather than by Foundation's
/// `URL.host`, which shows an internationalised host as punycode and reads
/// a `\` differently from a browser and from Android, so one code named two
/// verifiers. The split runs on bytes, as the Kotlin port's runs on chars:
/// `DecodedURL` steps by `Character`, and a combining mark after a
/// delimiter would hide it from Swift alone.
///
/// An address that hides its host is not named at all: user-info (`a@b` is
/// how a link disguises its real host), an empty authority, spaces or
/// control characters in it, or a host with characters no host name has.
/// The row then says `unusual`, and the sheet adds `hiddenHostCaution`.
enum ShownHost {
    /// What a row shows for such an address, and what a host field holds
    /// for one — the mdoc sheet's wording.
    static let unusual = "Unusual address — not shown"

    /// The caution that goes with it.
    static let hiddenHostCaution =
        "An address in this code is written in a way that can hide where it leads, so Scan does not show its host."

    /// `host` as it reads inside a sentence ("fetches it from …").
    static func inSentence(_ host: String) -> String {
        host == unusual ? "an unusual address (not shown)" : host
    }

    /// The host to name for `raw`; `unusual` when the address hides it; nil
    /// when `raw` is not a `scheme://` address at all.
    static func of(_ raw: String) -> String? {
        let bytes = Array(raw.utf8)
        guard let separator = firstIndex(of: Array("://".utf8), in: bytes) else { return nil }
        // The authority as RFC 3986 bounds it, which — unlike a browser —
        // does not stop at `\`: an `@` anywhere in it is user-info to one
        // parser or the other.
        let start = separator + 3
        let end = bytes[start...].firstIndex(where: { $0 == 0x2F || $0 == 0x3F || $0 == 0x23 }) ?? bytes.count
        let authority = bytes[start..<end]
        guard !authority.isEmpty,
              !authority.contains(where: { $0 == 0x40 || $0 <= 0x20 || $0 == 0x7F }),
              !String(decoding: authority, as: UTF8.self).unicodeScalars.contains(where: { (0x80...0x9F).contains($0.value) })
        else { return unusual }
        // A browser reads `\` as `/`, so the host ends there.
        let hostPort = authority.prefix { $0 != 0x5C }
        let host: ArraySlice<UInt8>
        let bracketed = hostPort.first == 0x5B
        if bracketed {
            guard let close = hostPort.firstIndex(of: 0x5D) else { return unusual }
            let after = hostPort[(close + 1)...]
            guard after.isEmpty || (after.first == 0x3A && after.dropFirst().allSatisfy(isDigit)) else { return unusual }
            host = hostPort[(hostPort.startIndex + 1)..<close]
        } else if let colon = hostPort.lastIndex(of: 0x3A), hostPort[(colon + 1)...].allSatisfy(isDigit) {
            host = hostPort[..<colon]
        } else {
            host = hostPort
        }
        let name = HostName(String(decoding: host, as: UTF8.self)).normalized
        return isPlainHost(name, bracketed: bracketed) ? name : unusual
    }

    private static func isDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }

    private static func firstIndex(of needle: [UInt8], in bytes: [UInt8]) -> Int? {
        guard bytes.count >= needle.count else { return nil }
        return (0...(bytes.count - needle.count)).first { bytes[$0..<($0 + needle.count)].elementsEqual(needle) }
    }

    /// Something to show, and no character a host name cannot hold: the
    /// WHATWG forbidden domain code points, C1 controls, spaces that
    /// survive NFKC, bidi and other format controls, U+FFFD (a decoding
    /// failure), and — outside an IPv6 literal — `:`. Code-point ranges, so
    /// both ports agree whatever Unicode version their OS ships.
    private static func isPlainHost(_ host: String, bracketed: Bool) -> Bool {
        let scalars = host.unicodeScalars
        guard !scalars.isEmpty, scalars.count <= 253 else { return false }
        if bracketed {
            return scalars.allSatisfy { s in
                ("0"..."9").contains(s) || ("a"..."f").contains(s) || s == ":" || s == "."
            }
        }
        return !scalars.contains { s in
            switch s.value {
            case 0x00...0x20, 0x7F...0x9F, 0x061C, 0x1680, 0x180E, 0x200E, 0x200F, 0x2028...0x202E,
                 0x2061...0x2064, 0x2066...0x2069, 0xFFF9...0xFFFB, 0xFFFD:
                return true
            default:
                return "#%/:<>?@[\\]^|".unicodeScalars.contains(s)
            }
        }
    }
}

// MARK: - ISO/IEC 18013-5 / 18013-7 mdoc engagement

/// A decoded `mdoc:` or `mdoc://` code: the *engagement* that opens an
/// ISO/IEC 18013-5 (in person) or ISO/IEC 18013-7 (online) presentation of
/// a mobile document — a mobile driving licence, an EU PID or any other
/// mdoc. "mdoc" is an IANA-registered (provisional) URI scheme.
///
/// An engagement is neither the document nor a request for it. It carries a
/// version, a fresh one-time public key and the ways the other side may
/// connect; the request, the holder's approval and the data itself only
/// travel over that connection, between a wallet and a reader. Scan is
/// neither, so it describes the code and stops there. It never keeps what
/// works as a secret (a server-retrieval token, a Wi-Fi Aware passphrase),
/// the key bytes, or the radio identifiers (BLE UUIDs, device address).
struct MobileDrivingLicensePayload: Equatable {

    /// Who shows the code, and so who is meant to scan it.
    enum Kind: Equatable {
        /// `mdoc:` + `DeviceEngagement`: a holder's wallet shows it to an
        /// ID reader (ISO/IEC 18013-5:2021 §8.2.2.3).
        case deviceEngagement
        /// `mdoc:` + `ReaderEngagement`: an ID reader shows it to a wallet
        /// (the Reader QR of the 18013-5 second edition).
        case readerEngagement
        /// `mdoc://` + `ReaderEngagement`: a website asks a wallet for an
        /// mdoc over the internet (ISO/IEC 18013-7 Annex A).
        case onlineRequest
    }

    /// One `DeviceRetrievalMethod`: a way the two sides can connect.
    enum Channel: Equatable {
        case nfc
        /// The mdoc BLE modes (`BleOptions` keys 0 and 1).
        case bluetooth(peripheralServer: Bool, centralClient: Bool)
        case wifiAware
        /// The 18013-7 HTTP method (type 4); only its URL's host is kept.
        case website(host: String?)
        case other(type: UInt64)
    }

    /// One `ServerRetrievalMethods` entry, without its token.
    struct ServerRetrieval: Equatable {
        /// "WebAPI" or "OIDC".
        let method: String
        /// The issuer URL's host; nil when it is not a plain web address.
        let host: String?
    }

    /// The one-time key's COSE type: `kty` (label 1) and `crv` (label -1).
    struct KeyType: Equatable {
        var kty: UInt64?
        var crv: UInt64?
    }

    var raw: String
    var kind: Kind
    /// False when the code has the `mdoc` scheme but did not decode.
    var decoded: Bool
    /// Key 0 as written — "1.0" or "1.1" today.
    var version: String?
    /// The first element of `Security`; 1 is the only suite 18013-5 defines.
    var cipherSuite: UInt64?
    /// `EDeviceKey` (or `EReaderKey`); nil when the code carries none.
    var key: KeyType?
    var channels: [Channel]
    var serverRetrieval: [ServerRetrieval]

    // MARK: Display

    var kindLabel: String {
        switch kind {
        case .deviceEngagement: return "Digital ID"
        case .readerEngagement: return "ID Reader"
        case .onlineRequest:    return "ID Request"
        }
    }

    var headline: String {
        switch kind {
        case .deviceEngagement: return "A digital-ID engagement code"
        case .readerEngagement: return "An ID reader's engagement code"
        case .onlineRequest:    return "An online ID request"
        }
    }

    private static let walletDocuments = "A digital-ID wallet (mDL, EU PID or other mdoc)"

    var labelledFields: [LabelledField] {
        var rows: [LabelledField]
        switch kind {
        case .deviceEngagement:
            rows = [.init(label: "Format", value: "ISO/IEC 18013-5 device engagement"),
                    .init(label: "Shown by", value: Self.walletDocuments),
                    .init(label: "Meant for", value: "An ID reader")]
        case .readerEngagement:
            rows = [.init(label: "Format", value: "ISO/IEC 18013-5 reader engagement"),
                    .init(label: "Shown by", value: "An ID reader"),
                    .init(label: "Meant for", value: Self.walletDocuments)]
        case .onlineRequest:
            rows = [.init(label: "Format", value: "ISO/IEC 18013-7 online request"),
                    .init(label: "Shown by", value: "A website"),
                    .init(label: "Meant for", value: Self.walletDocuments)]
        }
        guard decoded else {
            rows.append(.init(label: "Contents", value: "Not decodable — damaged or a newer version"))
            return rows
        }
        rows.append(.init(label: "ID data", value: "None — only how to connect"))
        rows.append(.init(label: "Version", value: versionText))
        let names = channelNames
        rows.append(.init(label: "Channels",
                          value: names.isEmpty ? "None stated" : names.joined(separator: ", ")))
        if let modes = bluetoothModes {
            rows.append(.init(label: "Bluetooth LE", value: modes))
        }
        if let site = websiteText {
            rows.append(.init(label: "Website", value: site))
        }
        if !serverRetrieval.isEmpty {
            rows.append(.init(label: "Server retrieval", value: serverRetrieval
                .map { "\($0.method) at \($0.host ?? "an unusual address (not shown)")" }
                .joined(separator: ", ")))
        }
        rows.append(.init(label: "Cipher suite", value: cipherSuiteText))
        rows.append(.init(label: kind == .deviceEngagement ? "Device key" : "Reader key",
                          value: keyText))
        return rows
    }

    /// The explainer's points: what the code is, how the other side would
    /// connect, and that it holds a key rather than the ID.
    var keyPoints: [String] {
        var points: [String]
        let spoken = Self.spokenList(channels.compactMap(Self.knownChannelName))
        switch kind {
        case .deviceEngagement:
            points = ["A digital-ID wallet's code for an ID reader (ISO/IEC 18013-5), for a mobile driving licence, an EU PID or another mdoc."]
            if decoded, !spoken.isEmpty { points.append("A reader can connect over \(spoken).") }
            if decoded { points.append("It carries a fresh one-time key, not the ID itself.") }
        case .readerEngagement:
            points = ["An ID reader's code for a digital-ID wallet (ISO/IEC 18013-5): it invites a wallet to connect so the reader can ask for an ID."]
            if decoded, !spoken.isEmpty { points.append("A wallet would connect over \(spoken).") }
            if decoded { points.append("It carries the reader's one-time key, not anyone's ID.") }
        case .onlineRequest:
            points = ["A website's request for a digital ID (ISO/IEC 18013-7): it asks a wallet to share a mobile driving licence, an EU PID or another mdoc online."]
            if decoded, !websiteHosts.isEmpty {
                points.append("A wallet would connect to \(websiteHosts.joined(separator: ", ")).")
            }
            if decoded { points.append("It carries the site's one-time key, not anyone's ID.") }
        }
        if !decoded {
            points.append("Its contents could not be decoded — it may be damaged or a newer version.")
        }
        return points
    }

    /// The explainer's cautions.
    var cautions: [String] {
        switch kind {
        case .deviceEngagement:
            return ["Scan is not an ID reader: it cannot request or read the document.",
                    "A nearby reader can use this code to start a request, which the wallet still asks its holder to approve."]
                + warnings
        case .readerEngagement:
            return ["Scan is not a wallet: it cannot answer the reader or share a document.",
                    "Scanned with a wallet, it lets the reader ask for data, and the wallet asks you to approve what is shared."]
                + warnings
        case .onlineRequest:
            return ["Scan is not a wallet: it cannot answer this request or share a document.",
                    "Opened in a wallet, it lets the site ask for data, and the wallet asks you to approve what is shared."]
                + warnings
        }
    }

    /// The result sheet's highlighted warnings — the subset of `cautions`
    /// that asks the user to do something.
    var warnings: [String] {
        switch kind {
        case .deviceEngagement:
            var out = ["Only show your own code to the reader you mean to share with."]
            if decoded, !serverRetrieval.isEmpty {
                out.append("It also carries a server-retrieval token: whoever scans it can ask the issuer for the holder's data directly.")
            }
            return out
        case .readerEngagement:
            return ["Only scan a reader's code with your wallet where you meant to show your ID."]
        case .onlineRequest:
            return ["Only continue in your wallet for a site you opened yourself, and check its address."]
        }
    }

    /// The result sheet's explanation under the fields.
    var notice: String {
        switch kind {
        case .deviceEngagement:
            return "Scan is not an ID reader and cannot request or read the document. A nearby reader can use this code to start a request, which the wallet still asks its holder to approve. The code carries a fresh one-time key, so it is not the ID itself."
        case .readerEngagement:
            return "Scan is not a wallet and cannot answer the reader. Scanned with a wallet, the code lets the reader ask for data, and the wallet asks you to approve what is shared. It carries the reader's one-time key, not anyone's ID."
        case .onlineRequest:
            return "Scan is not a wallet and cannot answer this request. Opened in a wallet, the code lets the site ask for data, and the wallet asks you to approve what is shared. It carries the site's one-time key, not anyone's ID."
        }
    }

    // MARK: Field text

    /// The version as written when it has the `major.minor` shape the
    /// standard uses; anything else is not echoed back.
    private var versionText: String {
        guard let version else { return "Not stated" }
        return MobileDrivingLicenseParser.versionNumbers(version) == nil ? "Unrecognised" : version
    }

    private var channelNames: [String] {
        var names: [String] = []
        for name in channels.map(Self.channelName) where !names.contains(name) {
            names.append(name)
        }
        return names
    }

    private static func channelName(_ channel: Channel) -> String {
        switch channel {
        case .nfc:              return "NFC"
        case .bluetooth:        return "Bluetooth LE"
        case .wifiAware:        return "Wi-Fi Aware"
        case .website:          return "Website"
        case .other(let type):  return "Type \(type)"
        }
    }

    /// The name, for the methods a sentence can mention.
    private static func knownChannelName(_ channel: Channel) -> String? {
        if case .other = channel { return nil }
        return channelName(channel)
    }

    /// Every Bluetooth method's modes, together.
    private var bluetoothModes: String? {
        var any = false, peripheral = false, central = false
        for case let .bluetooth(peripheralServer, centralClient) in channels {
            any = true
            peripheral = peripheral || peripheralServer
            central = central || centralClient
        }
        guard any else { return nil }
        switch (peripheral, central) {
        case (true, true):  return "Peripheral server and central client modes"
        case (true, false): return "Peripheral server mode"
        case (false, true): return "Central client mode"
        default:            return "No mode stated"
        }
    }

    private var websiteHosts: [String] {
        var hosts: [String] = []
        for case let .website(host?) in channels where !hosts.contains(host) {
            hosts.append(host)
        }
        return Array(hosts.prefix(3))
    }

    private var websiteText: String? {
        guard channels.contains(where: { if case .website = $0 { return true }; return false }) else {
            return nil
        }
        let hosts = websiteHosts
        return hosts.isEmpty ? "Unusual address — not shown" : hosts.joined(separator: ", ")
    }

    private var cipherSuiteText: String {
        switch cipherSuite {
        case 1?:            return "1 (ECDH, AES-256-GCM)"
        case let suite?:    return "\(suite) (unknown)"
        case nil:           return "Not stated"
        }
    }

    private var keyText: String {
        guard let key else { return "Missing" }
        let curve = key.crv.map { MobileDrivingLicenseParser.curveName($0) ?? "Curve \($0)" }
        let type = key.kty.map { MobileDrivingLicenseParser.keyTypeName($0) ?? "Key type \($0)" }
        switch (curve, type) {
        case let (curve?, type?): return "\(curve) (\(type)), one-time key"
        case let (curve?, nil):   return "\(curve), one-time key"
        case let (nil, type?):    return "\(type), one-time key"
        case (nil, nil):          return "Present, type not readable"
        }
    }

    /// "a", "a or b", "a, b or c".
    private static func spokenList(_ items: [String]) -> String {
        var unique: [String] = []
        for item in items where !unique.contains(item) { unique.append(item) }
        guard let last = unique.last else { return "" }
        return unique.count == 1 ? last : unique.dropLast().joined(separator: ", ") + " or " + last
    }
}

enum MobileDrivingLicenseParser {

    /// The longest encoded engagement decoded. A real one is a few hundred
    /// characters; the cap bounds what a hostile code can make us do.
    static let maxEncodedLength = 4096
    /// Retrieval methods kept; a real engagement lists one to three.
    static let maxChannels = 8

    // MARK: Recognition

    /// `mdoc:` + an encoded engagement, or `mdoc://` + one in the
    /// authority. `mdoc-openid4vp://` (ISO/IEC 18013-7 Annex B) is a
    /// different scheme — an OpenID4VP request — and is left to the
    /// verifiable-credential parser.
    static func looksLikeMdocURI(_ raw: String) -> Bool {
        split(raw) != nil
    }

    static func parse(_ raw: String) -> MobileDrivingLicensePayload? {
        guard let (online, body) = split(raw) else { return nil }
        var p = MobileDrivingLicensePayload(
            raw: raw, kind: online ? .onlineRequest : .deviceEngagement, decoded: false,
            version: nil, cipherSuite: nil, key: nil, channels: [], serverRetrieval: [])
        guard body.count <= maxEncodedLength,
              let bytes = decodeBase64URL(body),
              let e = decodeEngagement(bytes) else { return p }
        p.decoded = true
        p.version = e.version
        p.cipherSuite = e.cipherSuite
        p.key = e.key
        p.channels = e.channels
        p.serverRetrieval = e.serverRetrieval
        if !online, isReaderEngagement(e) { p.kind = .readerEngagement }
        return p
    }

    /// (online, encoded engagement), or nil when `raw` is not an mdoc URI.
    /// Byte-wise and ASCII-only, so both ports split identically.
    private static func split(_ raw: String) -> (Bool, String)? {
        let utf8 = Array(raw.utf8)
        let scheme = Array("mdoc:".utf8)
        guard utf8.count > scheme.count else { return nil }
        for (i, expected) in scheme.enumerated() {
            let b = utf8[i]
            guard (b >= 0x41 && b <= 0x5A ? b + 0x20 : b) == expected else { return nil }
        }
        var rest = utf8[scheme.count...]
        let online = rest.starts(with: Array("//".utf8))
        if online {
            // ISO/IEC 18013-7: the engagement is the authority; whatever
            // follows it is not part of the engagement.
            rest = rest.dropFirst(2).prefix { $0 != 0x2F && $0 != 0x3F && $0 != 0x23 }
        }
        guard !rest.isEmpty, rest.allSatisfy({ isEncodedByte($0, online: online) }) else { return nil }
        return (online, String(decoding: rest, as: UTF8.self))
    }

    /// base64url, plus `=` padding — and, for the QR form, the standard
    /// alphabet's `+` and `/`, which some encoders emit.
    private static func isEncodedByte(_ b: UInt8, online: Bool) -> Bool {
        (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || (b >= 0x30 && b <= 0x39)
            || b == 0x2D || b == 0x5F || b == 0x3D
            || (!online && (b == 0x2B || b == 0x2F))
    }

    // MARK: Decoding

    /// Canonical base64(url) only: padding at the end and only as much as
    /// the length needs, no impossible lengths, and zero spare bits. Lenient
    /// decoders disagree on everything else, and the two ports must not.
    static func decodeBase64URL(_ text: String) -> [UInt8]? {
        let chars = Array(text.utf8)
        let data = chars.prefix { $0 != 0x3D }
        let padding = chars.count - data.count
        guard padding <= 2, chars[data.count...].allSatisfy({ $0 == 0x3D }),
              data.count % 4 != 1,
              padding == 0 || (data.count + padding) % 4 == 0,
              let last = data.last.flatMap(sextet) else { return nil }
        switch data.count % 4 {
        case 2: guard last & 0x0F == 0 else { return nil }
        case 3: guard last & 0x03 == 0 else { return nil }
        default: break
        }
        return PayloadCodec.base64URLData(String(decoding: data, as: UTF8.self)).map { Array($0) }
    }

    private static func sextet(_ b: UInt8) -> UInt8? {
        switch b {
        case 0x41...0x5A: return b - 0x41
        case 0x61...0x7A: return b - 0x61 + 26
        case 0x30...0x39: return b - 0x30 + 52
        case 0x2B, 0x2D:  return 62
        case 0x2F, 0x5F:  return 63
        default:          return nil
        }
    }

    /// What the parser keeps of one engagement.
    struct Engagement: Equatable {
        var version: String?
        var cipherSuite: UInt64?
        var key: MobileDrivingLicensePayload.KeyType?
        var channels: [MobileDrivingLicensePayload.Channel] = []
        var serverRetrieval: [MobileDrivingLicensePayload.ServerRetrieval] = []
        /// OriginInfos (5) or Capabilities (6): only a DeviceEngagement
        /// 1.1 carries them.
        var hasDeviceOnlyKeys = false
    }

    /// `DeviceEngagement` / `ReaderEngagement` (ISO/IEC 18013-5 §8.2.1.1):
    /// `{0: version, 1: Security, ?2: DeviceRetrievalMethods,
    /// ?3: ServerRetrievalMethods, ?4: ProtocolInfo, ?5: OriginInfos,
    /// ?6: Capabilities, …}`. Nil unless it is one whole, well-formed map
    /// with a text version.
    static func decodeEngagement(_ bytes: [UInt8]) -> Engagement? {
        var reader = CBORReader(bytes)
        guard let head = reader.readHeader(), head.major == 5,
              head.arg <= UInt64(bytes.count) else { return nil }
        var e = Engagement()
        for _ in 0..<head.arg {
            guard let key = reader.readValue() else { return nil }
            if key == .uint(1) {
                guard readSecurity(&reader, into: &e) else { return nil }
                continue
            }
            guard let value = reader.readValue() else { return nil }
            switch key {
            case .uint(0):
                if case .text(let version) = value { e.version = version }
            case .uint(2):
                if case .array(let methods) = value {
                    e.channels = methods.prefix(maxChannels).compactMap(channel)
                }
            case .uint(3):
                if case .map(let pairs) = value { e.serverRetrieval = serverRetrieval(pairs) }
            case .uint(5), .uint(6):
                e.hasDeviceOnlyKeys = true
            default:
                break                           // ProtocolInfo, RFU, extensions
            }
        }
        guard !reader.hasMore, e.version != nil else { return nil }
        return e
    }

    /// `Security = [cipher suite, #6.24(bstr .cbor COSE_Key)]`, walked by
    /// hand: the shared reader reports a tag as `.other` and drops what it
    /// wraps, and the key's type is inside the wrapper. A Security of any
    /// other shape ends the parse, as it would in a real reader.
    private static func readSecurity(_ reader: inout CBORReader, into e: inout Engagement) -> Bool {
        guard let head = reader.readHeader(), head.major == 4,
              head.arg >= 2, head.arg <= 16,
              let suite = reader.readValue() else { return false }
        if case .uint(let n) = suite { e.cipherSuite = n }
        guard let tag = reader.readHeader(), tag.major == 6,
              let wrapped = reader.readValue() else { return false }
        if tag.arg == 24, case .bytes(let coseKey) = wrapped {
            e.key = keyType(coseKey)
        } else {
            e.key = .init(kty: nil, crv: nil)
        }
        for _ in 2..<head.arg {
            guard reader.readValue() != nil else { return false }
        }
        return true
    }

    /// `kty` and `crv` of a COSE_Key. Labels are small integers in every
    /// key we read; a text label cannot be stepped over with a bare
    /// header, so it ends the walk with whatever was found before it.
    private static func keyType(_ bytes: [UInt8]) -> MobileDrivingLicensePayload.KeyType {
        var key = MobileDrivingLicensePayload.KeyType(kty: nil, crv: nil)
        var reader = CBORReader(bytes)
        guard let head = reader.readHeader(), head.major == 5, head.arg <= 32 else { return key }
        for _ in 0..<head.arg {
            guard let label = reader.readHeader(), label.major <= 1, label.arg < 256,
                  let value = reader.readValue() else { break }
            guard case .uint(let v) = value else { continue }
            if label.major == 0, label.arg == 1 { key.kty = v }    // kty
            if label.major == 1, label.arg == 0 { key.crv = v }    // crv, label -1
        }
        return key
    }

    /// `[type, version, options]` — ISO/IEC 18013-5 Table 7, plus the
    /// ISO/IEC 18013-7 HTTP method.
    private static func channel(_ method: CBORReader.Value) -> MobileDrivingLicensePayload.Channel? {
        guard case .array(let items) = method, items.count >= 2,
              case .uint(let type) = items[0] else { return nil }
        var options: [CBORPair] = []
        if items.count >= 3, case .map(let pairs) = items[2] { options = pairs }
        switch type {
        case 1:
            return .nfc
        case 2:
            return .bluetooth(peripheralServer: options.value(forKey: 0) == .bool(true),
                              centralClient: options.value(forKey: 1) == .bool(true))
        case 3:
            return .wifiAware
        case 4:
            if case .text(let uri)? = options.value(forKey: 0) { return .website(host: host(ofURL: uri)) }
            return .website(host: nil)
        default:
            return .other(type: type)
        }
    }

    /// `{? "webApi": [version, issuer URL, token], ? "oidc": […]}` — the
    /// host is kept, the token never is.
    private static func serverRetrieval(_ pairs: [CBORPair]) -> [MobileDrivingLicensePayload.ServerRetrieval] {
        var out: [MobileDrivingLicensePayload.ServerRetrieval] = []
        for (name, method) in [("webApi", "WebAPI"), ("oidc", "OIDC")] {
            guard case .array(let fields)? = pairs.value(forKey: name), fields.count >= 2 else { continue }
            var host: String?
            if case .text(let url) = fields[1] { host = Self.host(ofURL: url) }
            out.append(.init(method: method, host: host))
        }
        return out
    }

    /// A Reader QR (18013-5 second edition) is a `ReaderEngagement` behind
    /// the same `mdoc:` prefix. It is version 1.1 or later with a key and
    /// Bluetooth only, and has neither OriginInfos nor Capabilities — which
    /// a `DeviceEngagement` 1.1 always carries at least one of.
    private static func isReaderEngagement(_ e: Engagement) -> Bool {
        guard let numbers = versionNumbers(e.version ?? ""), numbers.major == 1, numbers.minor >= 1,
              !e.hasDeviceOnlyKeys, e.key != nil, !e.channels.isEmpty else { return false }
        return e.channels.allSatisfy { if case .bluetooth = $0 { return true }; return false }
    }

    /// `major.minor`, one to four ASCII digits each.
    static func versionNumbers(_ version: String) -> (major: Int, minor: Int)? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts.allSatisfy({ (1...4).contains($0.utf8.count) && $0.utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 } }),
              let major = Int(parts[0]), let minor = Int(parts[1]) else { return nil }
        return (major, minor)
    }

    /// The host of an `http(s)` URL, lower-cased — or nil for anything
    /// that is not a plain web address. Hand-rolled and strict so both
    /// ports agree byte for byte: ASCII only (no look-alike letters, and
    /// nothing a case mapping could fold into ASCII), no user-info (`a@b`
    /// is how a link hides its real host), DNS labels or an IPv4 address.
    static func host(ofURL url: String) -> String? {
        let bytes = Array(url.utf8)
        guard bytes.allSatisfy({ $0 > 0x20 && $0 < 0x7F }) else { return nil }
        let lower = bytes.map { $0 >= 0x41 && $0 <= 0x5A ? $0 + 0x20 : $0 }
        let afterScheme: ArraySlice<UInt8>
        if lower.starts(with: Array("https://".utf8)) {
            afterScheme = lower[8...]
        } else if lower.starts(with: Array("http://".utf8)) {
            afterScheme = lower[7...]
        } else {
            return nil
        }
        var host = afterScheme.prefix { $0 != 0x2F && $0 != 0x3F && $0 != 0x23 }
        guard !host.contains(0x40) else { return nil }                        // '@'
        if let colon = host.lastIndex(of: 0x3A) {                             // ':port'
            let port = host[host.index(after: colon)...]
            guard (1...5).contains(port.count), port.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }),
                  let number = Int(String(decoding: port, as: UTF8.self)), number <= 65_535 else { return nil }
            host = host[..<colon]
        }
        guard (1...253).contains(host.count),
              host.allSatisfy({ ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2D || $0 == 0x2E }),
              !host.split(separator: 0x2E, omittingEmptySubsequences: false).contains(where: \.isEmpty)
        else { return nil }
        return String(decoding: host, as: UTF8.self)
    }

    // MARK: Naming tables

    /// IANA "COSE Elliptic Curves" — the ISO/IEC 18013-5 Table 22 curves
    /// and secp256k1.
    static func curveName(_ crv: UInt64) -> String? {
        switch crv {
        case 1:   return "P-256"
        case 2:   return "P-384"
        case 3:   return "P-521"
        case 4:   return "X25519"
        case 5:   return "X448"
        case 6:   return "Ed25519"
        case 7:   return "Ed448"
        case 8:   return "secp256k1"
        case 256: return "brainpoolP256r1"
        case 257: return "brainpoolP320r1"
        case 258: return "brainpoolP384r1"
        case 259: return "brainpoolP512r1"
        default:  return nil
        }
    }

    /// IANA "COSE Key Types" that can hold an ECDH key.
    static func keyTypeName(_ kty: UInt64) -> String? {
        switch kty {
        case 1:  return "OKP"
        case 2:  return "EC2"
        default: return nil
        }
    }
}
