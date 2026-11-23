//
//  NFCTagWriter.swift
//  Scan
//
//  NFC is the same product idea as a QR, one step closer: a physical thing
//  you tap instead of point at. Written from the Generate tab it covers the
//  cases people actually ask for — a guest Wi-Fi tap, a website tap, a
//  contact tap — and reading covers the reverse: an unknown tag becomes a
//  normal decoded payload, so every smart action and the safety inspector
//  apply to it too.
//
//  Core NFC, one `NFCNDEFReaderSession` per tap, no background tag reading:
//  a session runs only after the user presses the control, only while the
//  system NFC sheet is up, and only in the foreground. Nothing is read
//  without that deliberate gesture, and nothing read or written leaves the
//  device.
//
//  Two halves:
//   - `NDEFRecordCodec` is pure bytes in, bytes out, with no Core NFC types,
//     so it can be unit-tested on the simulator. It mirrors the Android
//     port's `NfcPayloadCodec`: a tag written by either app must read back
//     the same on both.
//   - `NFCTagWriter` is the session plumbing, which only ever runs on an
//     iPhone that has an NFC reader.
//
//  The records are built by hand rather than with Core NFC's convenience
//  constructors because those make worse tags: `wellKnownTypeTextPayload(
//  string:locale:)` writes UTF-16 with a byte-order mark — twice the bytes
//  of UTF-8 for a Wi-Fi string, which decides whether it fits a 144-byte
//  NTAG213 — and keeps only the locale's language, and the URI reader
//  percent-encodes non-ASCII paths, so a tag would read back different from
//  the QR it was written next to. The NFC Forum formats are small enough to
//  own outright, and owning them is what keeps the two ports byte-identical.
//

import Foundation
import CoreNFC
import UIKit

// MARK: - What can go on a tag

enum NFCTagPayloadKind: String, CaseIterable, Identifiable {
    case text, url, wifi, contact
    var id: String { rawValue }
    var label: String {
        switch self {
        case .text:    return "Text"
        case .url:     return "URL"
        case .wifi:    return "Wi-Fi"
        case .contact: return "Contact"
        }
    }
    var symbol: String {
        switch self {
        case .text:    return "text.alignleft"
        case .url:     return "link"
        case .wifi:    return "wifi"
        case .contact: return "person.crop.square"
        }
    }

    /// What content starts with, in any case, to go on a tag as an RTD URI
    /// record: the links `ScanPayloadParser` reads — web, phone, email, SMS
    /// and map — so a tap can open, dial, compose or show the place on a
    /// phone that acts on that kind of link (an iPhone's background tag
    /// reading takes web, `tel:`, `mailto:` and `sms:` ones, not `smsto:` or
    /// `geo:`). Only `tel:` and `mailto:` have an NFC Forum prefix code
    /// besides the web ones; the rest are written whole. The Android port's
    /// `LINK_PREFIXES`.
    static let linkPrefixes = ["http://", "https://", "tel:", "mailto:", "sms:", "smsto:", "geo:"]

    /// The kind a code's content implies. The generator hands over the same
    /// string the QR encodes, and `CodeComposer` output announces itself
    /// (`WIFI:` / `BEGIN:VCARD`), so the content alone picks the record —
    /// which also means a Wi-Fi string pasted into the Text form becomes a
    /// Wi-Fi tag, exactly as its QR would be a Wi-Fi code, and a `tel:` one
    /// a link tag.
    static func inferred(from value: String) -> NFCTagPayloadKind {
        let lower = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.hasBytePrefix("wifi:") { return .wifi }
        if lower.hasBytePrefix("begin:vcard") { return .contact }
        if linkPrefixes.contains(where: lower.hasBytePrefix) { return .url }
        return .text
    }
}

private extension String {
    /// Whether the string's bytes start with `prefix`'s — what Kotlin's
    /// `startsWith` and the URI prefix table compare. `hasPrefix` compares
    /// whole characters instead, so a combining mark straight after a prefix
    /// (`tel:` + U+0301) would hide it here and not on Android.
    func hasBytePrefix(_ prefix: String) -> Bool {
        utf8.starts(with: prefix.utf8)
    }
}

/// The content to write: the same string the generated code carries. The
/// reader side parses whatever comes back with the same `ScanPayloadParser`
/// as a camera scan.
struct NFCTagWriteRequest {
    var kind: NFCTagPayloadKind
    var value: String
    /// RTD Text language. "en" on both ports: the generator has no idea
    /// what language a free-form string is in, and readers ignore it.
    var languageTag: String = "en"

    /// Non-empty after trimming, and a URL must carry its scheme
    /// (`example.com` is text, not a link) — the Android port's rule.
    var isValid: Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if kind == .url { return NDEFRecordCodec.hasScheme(trimmed) }
        return true
    }
}

// MARK: - NDEF records (pure)

/// NDEF record payloads, byte for byte, per the NFC Forum NDEF 1.0, RTD
/// Text 1.0, RTD URI 1.0 and Smart Poster RTD 1.0 specifications, plus the
/// two MIME media records Scan writes: `application/vnd.wfa.wsc` (Wi-Fi
/// Simple Configuration) for a network and `text/vcard` (RFC 6350) for a
/// contact.
enum NDEFRecordCodec {

    /// One record as it sits on the tag, minus the header flags Core NFC
    /// adds when it frames the message.
    struct Record: Equatable {
        /// The 3-bit type name format (TNF).
        var format: UInt8
        var type: Data
        var payload: Data
    }

    /// NDEF 1.0 TNF values (`NFCTypeNameFormat` has the same raw values).
    enum TypeNameFormat {
        static let empty: UInt8 = 0x00
        static let wellKnown: UInt8 = 0x01
        static let media: UInt8 = 0x02
        static let absoluteURI: UInt8 = 0x03
        static let unknown: UInt8 = 0x05
        /// Only in the middle and last chunks of a chunked payload.
        static let unchanged: UInt8 = 0x06
        static let reserved: UInt8 = 0x07
    }

    /// Well-known record types: RTD Text, RTD URI and the Smart Poster.
    static let textType = Data("T".utf8)
    static let uriType = Data("U".utf8)
    static let smartPosterType = Data("Sp".utf8)

    /// The most records `records(inMessage:)` reads from one message. A
    /// Smart Poster is one URI plus a little metadata — a title per
    /// language, an action, a size, a type, an icon — so a poster with more
    /// is rejected rather than read on, which bounds what a hostile tag can
    /// make the parser allocate. The NDEF spec lets a parser refuse
    /// messages beyond its design limits (NDEF 1.0 §4.3).
    static let maxMessageRecords = 255

    static let wifiMediaType = "application/vnd.wfa.wsc"
    static let vCardMediaType = "text/vcard"
    /// Older name for the same thing; still what some writers emit.
    static let legacyVCardMediaType = "text/x-vcard"

    /// RTD URI identifier codes 0x00...0x23; the index is the code. 0x00
    /// means "no abbreviation", and 0x24...0xFF are reserved.
    static let uriPrefixes = [
        "", "http://www.", "https://www.", "http://", "https://", "tel:",
        "mailto:", "ftp://anonymous:anonymous@", "ftp://ftp.", "ftps://",
        "sftp://", "smb://", "nfs://", "ftp://", "dav://", "news:",
        "telnet://", "imap:", "rtsp://", "urn:", "pop:", "sip:", "sips:",
        "tftp:", "btspp://", "btl2cap://", "btgoep://", "tcpobex://",
        "irdaobex://", "file://", "urn:epc:id:", "urn:epc:tag:",
        "urn:epc:pat:", "urn:epc:raw:", "urn:epc:", "urn:nfc:",
    ]

    /// The language tag lives in a 6-bit length field.
    private static let maxLanguageTagBytes = 63

    // MARK: Write side

    /// The records to put on a tag for `request`, or nil when it can't be
    /// encoded. One record per tag: the first record sets the meaning of an
    /// NDEF message, and a second one would only eat into a small tag.
    static func records(for request: NFCTagWriteRequest) -> [Record]? {
        guard request.isValid else { return nil }
        let value = request.value
        switch request.kind {
        case .url:
            return [uriRecord(normalizedURL(value))]
        case .text:
            return [textRecord(value, languageTag: request.languageTag)]
        case .wifi:
            // A Wi-Fi Simple Configuration token is what makes an Android
            // phone offer to join the network on tap. Networks WSC can't
            // describe faithfully keep the QR's own `WIFI:` string, which
            // Scan reads back as Wi-Fi on either platform.
            if let token = WiFiSimpleConfig.token(forWiFiString: value) {
                return [mediaRecord(wifiMediaType, payload: token)]
            }
            return [textRecord(value, languageTag: request.languageTag)]
        case .contact:
            // A vCard as `text/vcard` is the contact card phones import on
            // tap; anything else rides as text, like its QR would.
            if looksLikeVCard(value) {
                return [mediaRecord(vCardMediaType, payload: Data(value.utf8))]
            }
            return [textRecord(value, languageTag: request.languageTag)]
        }
    }

    /// RTD Text: a status byte (bit 7 clear = UTF-8, bit 6 reserved, bits
    /// 5...0 the language tag's length), the ASCII language tag, the text.
    static func textRecord(_ text: String, languageTag: String) -> Record {
        let language = Data(normalizedLanguageTag(languageTag).utf8)
        var payload = Data([UInt8(language.count)])
        payload.append(language)
        payload.append(Data(text.utf8))
        return Record(format: TypeNameFormat.wellKnown, type: textType, payload: payload)
    }

    /// RTD URI: the identifier code of the longest prefix the URI starts
    /// with, then the rest of the URI as UTF-8.
    static func uriRecord(_ uri: String) -> Record {
        let bytes = Array(uri.utf8)
        var code = 0
        var prefixLength = 0
        for (index, prefix) in uriPrefixes.enumerated() {
            let prefixBytes = Array(prefix.utf8)
            if prefixBytes.count > prefixLength, bytes.starts(with: prefixBytes) {
                code = index
                prefixLength = prefixBytes.count
            }
        }
        var payload = Data([UInt8(code)])
        payload.append(contentsOf: bytes[prefixLength...])
        return Record(format: TypeNameFormat.wellKnown, type: uriType, payload: payload)
    }

    static func mediaRecord(_ mediaType: String, payload: Data) -> Record {
        Record(format: TypeNameFormat.media, type: Data(mediaType.utf8), payload: payload)
    }

    // MARK: Read side

    /// The string a camera scan of the same content would have produced:
    /// the first record Scan can read, in record order (NDEF's first record
    /// sets what a message means), or nil when there is none. One exception,
    /// from the Smart Poster spec (§3.4): a readable Smart Poster overrides
    /// any URI records beside it, so those are passed over.
    static func readableString(in records: [Record]) -> String? {
        let hasPoster = records.contains { smartPosterURI(in: $0) != nil }
        return records.lazy
            .filter { !(hasPoster && $0.format == TypeNameFormat.wellKnown && $0.type == uriType) }
            .compactMap { readableString(in: $0) }
            .first
    }

    /// The readable string for one record, or nil when it's skipped:
    /// Android application records, external and unknown types, and smart
    /// posters that hold no readable URI.
    static func readableString(in record: Record) -> String? {
        let text: String?
        switch record.format {
        case TypeNameFormat.wellKnown where record.type == textType:
            text = textFromPayload(record.payload)
        case TypeNameFormat.wellKnown where record.type == uriType:
            text = uriFromPayload(record.payload)
        case TypeNameFormat.wellKnown where record.type == smartPosterType:
            text = smartPosterURI(in: record)
        case TypeNameFormat.absoluteURI:
            // NDEF 1.0 puts an absolute URI in the TYPE field; a few writers
            // put it in the payload instead.
            let field = record.type.isEmpty ? record.payload : record.type
            text = String(decoding: field, as: UTF8.self)
        case TypeNameFormat.media:
            switch mediaType(of: record) {
            case wifiMediaType:
                text = WiFiSimpleConfig.wifiString(fromToken: record.payload)
            case vCardMediaType, legacyVCardMediaType:
                text = String(decoding: record.payload, as: UTF8.self)
            default:
                text = nil
            }
        default:
            text = nil
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }

    /// Inverse of `textRecord`, accepting the UTF-16 form too; nil for a
    /// payload too short for the language length it claims.
    static func textFromPayload(_ payload: Data) -> String? {
        let bytes = [UInt8](payload)
        guard let status = bytes.first else { return nil }
        let languageLength = Int(status & 0x3F)
        guard bytes.count >= 1 + languageLength else { return nil }
        let body = bytes[(1 + languageLength)...]
        if status & 0x80 == 0 { return String(decoding: body, as: UTF8.self) }
        return utf16String(body)
    }

    /// Inverse of `uriRecord`; nil for a reserved identifier code.
    static func uriFromPayload(_ payload: Data) -> String? {
        guard let code = payload.first, Int(code) < uriPrefixes.count else { return nil }
        return uriPrefixes[Int(code)] + String(decoding: payload.dropFirst(), as: UTF8.self)
    }

    /// What a Smart Poster (well-known type `Sp`, NFC Forum Smart Poster RTD
    /// 1.0) stands for: its URI. The payload is a nested NDEF message of one
    /// URI record plus optional titles (`T`, one per language), an action
    /// (`act`), a size (`s`), a type (`t`) and icons; only the URI is the
    /// value, so a poster tag reads exactly like a plain link tag. A title
    /// is display text the tag's author chose — the spec itself warns it can
    /// dress one link up as another — so it never becomes the value. Only
    /// URI records count inside, which keeps nesting at one level: a poster
    /// inside a poster is not followed. Nil for anything but a poster, and
    /// for a poster whose payload isn't a well-formed message or holds no
    /// readable URI record.
    static func smartPosterURI(in record: Record) -> String? {
        guard record.format == TypeNameFormat.wellKnown, record.type == smartPosterType,
              let nested = records(inMessage: record.payload) else { return nil }
        return nested.lazy
            .filter { $0.format == TypeNameFormat.wellKnown && $0.type == uriType }
            .compactMap { readableString(in: $0) }
            .first
    }

    /// The records of one raw NDEF message, or nil unless `message` is
    /// exactly one well-formed message (NFC Forum NDEF 1.0 §2.3, §3.2): MB
    /// on the first record only and ME on the last, nothing after it, every
    /// length inside the buffer (a length is never trusted for an
    /// allocation), chunked payloads (§2.3.3) reassembled, and the TNF rules
    /// of §3.2.6 — the checks Android's `NdefMessage(byte[])` makes, so both
    /// ports accept and reject the same bytes. Core NFC splits the tag's own
    /// message; this reads the one nested in a Smart Poster. At most
    /// `maxMessageRecords` records, chunks included.
    static func records(inMessage message: Data) -> [Record]? {
        let bytes = [UInt8](message)
        var index = 0
        /// The next `count` bytes, or nil when fewer are left.
        func take(_ count: Int) -> [UInt8]? {
            guard bytes.count - index >= count else { return nil }
            defer { index += count }
            return Array(bytes[index ..< index + count])
        }

        var records: [Record] = []
        /// A chunked payload being reassembled: the initial chunk's TNF and
        /// TYPE, the payload so far, and whether that chunk carried an ID.
        var chunk: (record: Record, hasID: Bool)?
        var physicalRecords = 0
        var ended = false
        while !ended {
            physicalRecords += 1
            guard physicalRecords <= maxMessageRecords, let header = take(1)?.first else { return nil }
            let begins = header & 0x80 != 0
            ended = header & 0x40 != 0
            let chunked = header & 0x20 != 0
            let short = header & 0x10 != 0
            let hasIDLength = header & 0x08 != 0
            let format = header & 0x07
            let continuing = chunk != nil
            guard begins == (records.isEmpty && !continuing),
                  // A chunked payload ends inside the message (§2.3.3)...
                  !(chunked && ended),
                  // ...its later chunks, and only they, are "unchanged"...
                  continuing == (format == TypeNameFormat.unchanged),
                  // ...and they carry neither a TYPE nor an ID.
                  !(continuing && hasIDLength),
                  let typeLength = take(1)?.first,
                  let lengthBytes = take(short ? 1 : 4),
                  let idLength = hasIDLength ? take(1)?.first : 0,
                  !(continuing && typeLength != 0),
                  let type = take(Int(typeLength)),
                  let id = take(Int(idLength)),
                  // Big-endian; up to 2^32 - 1, which take(_:) checks
                  // against what is actually left.
                  let payload = take(lengthBytes.reduce(0) { $0 << 8 | Int($1) })
            else { return nil }

            var current = chunk ?? (Record(format: format, type: Data(type), payload: Data()), !id.isEmpty)
            // Let go of the stored copy first, so the append doesn't copy the buffer.
            chunk = nil
            current.record.payload.append(contentsOf: payload)
            if chunked {
                // The initial chunk names the type of the whole payload.
                guard continuing || typeLength != 0 || format == TypeNameFormat.unknown else { return nil }
                chunk = current
                continue
            }
            let record = current.record
            switch record.format {
            case TypeNameFormat.empty:
                guard record.type.isEmpty, !current.hasID, record.payload.isEmpty else { return nil }
            case TypeNameFormat.unknown, TypeNameFormat.reserved:
                guard record.type.isEmpty else { return nil }
            default:
                break
            }
            records.append(record)
        }
        guard index == bytes.count else { return nil }
        return records
    }

    // MARK: Helpers

    /// RFC 3986: a scheme is a letter, then letters, digits, `+`, `-`, `.`.
    /// So `"12:30"` is text, not a URL. Same rule as the Android port, read
    /// the same way, scalar by scalar: a combining mark on the colon
    /// (`tel:` + U+0301) makes it part of another character, which
    /// `firstIndex(of: ":")` would step over.
    static func hasScheme(_ value: String) -> Bool {
        let scalars = value.unicodeScalars
        guard let colon = scalars.firstIndex(of: ":") else { return false }
        let scheme = scalars[..<colon]
        func isLetter(_ scalar: Unicode.Scalar) -> Bool {
            ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
        }
        guard let first = scheme.first, isLetter(first) else { return false }
        return scheme.allSatisfy {
            isLetter($0) || ("0"..."9").contains($0) || $0 == "+" || $0 == "-" || $0 == "."
        }
    }

    /// Prepend `https://` when the content is a bare host.
    static func normalizedURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return hasScheme(trimmed) ? trimmed : "https://" + trimmed
    }

    /// Lowercased, ASCII-only, length-capped language tag; "en" when
    /// nothing usable is left.
    static func normalizedLanguageTag(_ languageTag: String) -> String {
        let cleaned = languageTag.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix { $0.isASCII && ($0.isLetter || $0 == "-") }
            .lowercased()
            .prefix(maxLanguageTagBytes)
        return cleaned.isEmpty ? "en" : String(cleaned)
    }

    private static func looksLikeVCard(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasBytePrefix("begin:vcard")
    }

    /// A media record's type without parameters — everything before the
    /// first `;`, less the spaces and tabs RFC 9110 allows around it —
    /// lowercased. Cut at the byte, so the Android port cuts at exactly the
    /// same place.
    private static func mediaType(of record: Record) -> String {
        let essence = String(decoding: record.type.prefix { $0 != UInt8(ascii: ";") }, as: UTF8.self)
        return essence.trimmingCharacters(in: CharacterSet(charactersIn: " \t")).lowercased()
    }

    /// RTD Text allows a byte-order mark and means big-endian without one.
    private static func utf16String(_ bytes: ArraySlice<UInt8>) -> String {
        var body = bytes
        var bigEndian = true
        if body.starts(with: [0xFE, 0xFF]) {
            body = body.dropFirst(2)
        } else if body.starts(with: [0xFF, 0xFE]) {
            bigEndian = false
            body = body.dropFirst(2)
        }
        var units: [UInt16] = []
        units.reserveCapacity(body.count / 2)
        var index = body.startIndex
        while body.endIndex - index >= 2 {
            let first = UInt16(body[index])
            let second = UInt16(body[index + 1])
            units.append(bigEndian ? first << 8 | second : second << 8 | first)
            index += 2
        }
        return String(decoding: units, as: UTF16.self)
    }
}

// MARK: - Wi-Fi Simple Configuration

/// The Wi-Fi Simple Configuration (WSC 2.0) NFC configuration token: the
/// `application/vnd.wfa.wsc` payload Android's NFC service turns into a
/// "Connect to this network?" prompt. A run of big-endian type-length-value
/// attributes: Version, Credential { Network Index, SSID, Authentication
/// Type, Encryption Type, Network Key, MAC Address }, and the Wi-Fi
/// Alliance vendor extension that carries Version2.
enum WiFiSimpleConfig {

    // Attribute types.
    private static let versionAttribute: UInt16 = 0x104A
    private static let credentialAttribute: UInt16 = 0x100E
    private static let networkIndexAttribute: UInt16 = 0x1026
    private static let ssidAttribute: UInt16 = 0x1045
    private static let authenticationAttribute: UInt16 = 0x1003
    private static let encryptionAttribute: UInt16 = 0x100F
    private static let networkKeyAttribute: UInt16 = 0x1027
    private static let macAddressAttribute: UInt16 = 0x1020
    private static let vendorExtensionAttribute: UInt16 = 0x1049

    // Authentication type flags.
    private static let authenticationOpen: UInt16 = 0x0001
    private static let authenticationWPAPersonal: UInt16 = 0x0002
    private static let authenticationShared: UInt16 = 0x0004
    private static let authenticationWPAEnterprise: UInt16 = 0x0008
    private static let authenticationWPA2Enterprise: UInt16 = 0x0010
    private static let authenticationWPA2Personal: UInt16 = 0x0020

    // Encryption type flags.
    private static let encryptionNone: UInt16 = 0x0001
    private static let encryptionWEP: UInt16 = 0x0002
    private static let encryptionAES: UInt16 = 0x0008

    /// Version 1.0, kept for older readers; WSC 2.0 moved the real
    /// version into the vendor extension below.
    private static let legacyVersion: [UInt8] = [0x10]
    /// Wi-Fi Alliance vendor id 00:37:2A, then sub-element Version2
    /// (id 0x00, length 1) = 2.0.
    private static let version2Extension: [UInt8] = [0x00, 0x37, 0x2A, 0x00, 0x01, 0x20]
    /// A tag doesn't know the access point's BSSID; the broadcast address
    /// is the conventional "any".
    private static let anyMACAddress: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]

    /// The token for a `WIFI:` string, or nil when WSC can't say it
    /// faithfully: WEP and WPA3 (SAE) networks, Passpoint, a hidden SSID
    /// (there is no attribute for it), an SSID over 32 bytes or a key over
    /// 64. Those keep the plain-text form.
    static func token(forWiFiString value: String) -> Data? {
        guard case let .wifi(ssid, password, security, hidden) = ScanPayloadParser.parse(value),
              !hidden else { return nil }
        let key = password ?? ""
        let authentication: UInt16
        let encryption: UInt16
        switch security?.uppercased() {
        case "WPA", "WPA2":
            guard !key.isEmpty else { return nil }
            authentication = authenticationWPA2Personal
            encryption = encryptionAES
        case "NOPASS":
            authentication = authenticationOpen
            encryption = encryptionNone
        case nil, "":
            // No type and no password is an open network; no type with a
            // password is ambiguous, so it stays text.
            guard key.isEmpty else { return nil }
            authentication = authenticationOpen
            encryption = encryptionNone
        default:
            return nil
        }
        let ssidBytes = Array(ssid.utf8)
        let keyBytes = authentication == authenticationOpen ? [] : Array(key.utf8)
        guard (1...32).contains(ssidBytes.count), keyBytes.count <= 64 else { return nil }

        var credential = [UInt8]()
        append(networkIndexAttribute, [0x01], to: &credential)
        append(ssidAttribute, ssidBytes, to: &credential)
        append(authenticationAttribute, bigEndian(authentication), to: &credential)
        append(encryptionAttribute, bigEndian(encryption), to: &credential)
        append(networkKeyAttribute, keyBytes, to: &credential)
        append(macAddressAttribute, anyMACAddress, to: &credential)

        var token = [UInt8]()
        append(versionAttribute, legacyVersion, to: &token)
        append(credentialAttribute, credential, to: &token)
        append(vendorExtensionAttribute, version2Extension, to: &token)
        return Data(token)
    }

    /// The `WIFI:` string for a token's first credential, or nil when the
    /// token is malformed or holds an enterprise (EAP) network, whose
    /// sign-in a `WIFI:` string can't carry.
    static func wifiString(fromToken token: Data) -> String? {
        let bytes = [UInt8](token)
        guard let top = attributes(in: bytes[...]),
              let credential = top.first(where: { $0.type == credentialAttribute }),
              let fields = attributes(in: credential.value) else { return nil }

        var ssid = ""
        var key = ""
        var authentication: UInt16 = 0
        var encryption: UInt16 = 0
        for field in fields {
            switch field.type {
            case ssidAttribute:
                ssid = String(decoding: field.value, as: UTF8.self)
            case networkKeyAttribute:
                key = String(decoding: field.value, as: UTF8.self)
            case authenticationAttribute where field.value.count == 2:
                authentication = uint16(field.value)
            case encryptionAttribute where field.value.count == 2:
                encryption = uint16(field.value)
            default:
                break
            }
        }
        guard !ssid.isEmpty else { return nil }

        let security: CodeComposer.WifiSecurity
        if authentication & (authenticationWPAPersonal | authenticationWPA2Personal) != 0 {
            security = .wpa
        } else if authentication & (authenticationWPAEnterprise | authenticationWPA2Enterprise) != 0 {
            return nil
        } else if authentication & authenticationShared != 0 || encryption == encryptionWEP {
            security = .wep
        } else if authentication & authenticationOpen != 0 {
            security = .open
        } else {
            security = key.isEmpty ? .open : .wpa
        }
        return CodeComposer.wifi(ssid: ssid, password: key, security: security, hidden: false)
    }

    // MARK: TLV

    private static func append(_ type: UInt16, _ value: [UInt8], to buffer: inout [UInt8]) {
        buffer += bigEndian(type)
        buffer += bigEndian(UInt16(value.count))
        buffer += value
    }

    private static func bigEndian(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0xFF)]
    }

    private static func uint16(_ bytes: ArraySlice<UInt8>) -> UInt16 {
        UInt16(bytes[bytes.startIndex]) << 8 | UInt16(bytes[bytes.startIndex + 1])
    }

    /// The attributes in `bytes`, or nil when one overruns the buffer.
    private static func attributes(
        in bytes: ArraySlice<UInt8>
    ) -> [(type: UInt16, value: ArraySlice<UInt8>)]? {
        var result: [(type: UInt16, value: ArraySlice<UInt8>)] = []
        var index = bytes.startIndex
        while index < bytes.endIndex {
            guard bytes.endIndex - index >= 4 else { return nil }
            let type = uint16(bytes[index ..< index + 2])
            let length = Int(uint16(bytes[index + 2 ..< index + 4]))
            let start = index + 4
            guard bytes.endIndex - start >= length else { return nil }
            result.append((type, bytes[start ..< start + length]))
            index = start + length
        }
        return result
    }
}

// MARK: - Core NFC bridging

private extension NDEFRecordCodec.Record {
    init(_ record: NFCNDEFPayload) {
        self.init(format: record.typeNameFormat.rawValue, type: record.type, payload: record.payload)
    }

    var ndefPayload: NFCNDEFPayload {
        NFCNDEFPayload(format: NFCTypeNameFormat(rawValue: format) ?? .unknown,
                       type: type,
                       identifier: Data(),
                       payload: payload)
    }
}

// MARK: - Session

/// One-shot NFC read or write session.
///
/// Both directions use a read-write session — this class implements
/// `readerSession(_:didDetect:)` — because only that delivers the tag
/// itself, so a read can tell an empty tag from a foreign one and a write
/// can check the tag before touching it: `queryNDEFStatus` answers
/// "writable, and big enough?" before a single byte is written, so a
/// read-only tag (most of the cheap stickers sold as "NFC business cards")
/// fails with a clear message instead of a half-written tag.
///
/// Threading: the session is created on the main queue, and Core NFC
/// delivers every delegate callback and every tag completion handler on the
/// session's queue. So all of it runs on the main actor, and the tag — which
/// is not Sendable — never leaves it.
@MainActor
final class NFCTagWriter: NSObject, ObservableObject {

    enum Status: Equatable {
        case idle
        /// The NFC sheet is up, waiting for a tag.
        case scanning
        /// A writable tag is connected and the write is in flight.
        case writing
        /// Done: a tag was written or read; the message says which.
        case wrote(String)
        case failed(String)
    }

    @Published private(set) var status: Status = .idle

    /// Whether this device has an NFC reader. Gates the UI, so a device
    /// without one never shows a control that can only fail: false on Mac
    /// Catalyst, the simulator and Apple Vision Pro. `readingAvailable`
    /// reports the hardware only; a build without the entitlement doesn't
    /// get `false` here, it fails to sign.
    static var isSupported: Bool {
        #if targetEnvironment(macCatalyst) || targetEnvironment(simulator)
        return false
        #else
        if Platform.isVisionOS || Platform.isMac { return false }
        return NFCNDEFReaderSession.readingAvailable
        #endif
    }

    /// What the running session is for.
    private enum Job {
        case read((ScanPayload, String) -> Void)
        case write(NFCNDEFMessage)
    }

    private var session: NFCNDEFReaderSession?
    /// Bumped for every session. Completion handlers capture it (an Int is
    /// Sendable, and unlike an object identity it is never reused), so a
    /// late callback from a replaced or cancelled session is dropped.
    private var generation = 0
    private var job: Job?
    /// The tag the session is talking to. Kept here rather than captured by
    /// the completion handlers, which are `@Sendable`.
    private var tag: (any NFCNDEFTag)?
    /// Set once the session reached its own outcome, so the invalidation
    /// that follows (the sheet going away) doesn't overwrite the status.
    private var concluded = false

    // MARK: Write

    /// Write `request` to the next writable tag held to the phone.
    func write(_ request: NFCTagWriteRequest) {
        guard request.isValid else {
            status = .failed("Nothing to write yet — fill in the content first.")
            return
        }
        guard Self.isSupported else {
            status = .failed("This device can't write NFC tags.")
            return
        }
        guard let records = NDEFRecordCodec.records(for: request) else {
            status = .failed("Could not encode the tag content.")
            return
        }
        let message = NFCNDEFMessage(records: records.map(\.ndefPayload))
        start(.write(message), prompt: "Hold near a writable NFC tag")
    }

    // MARK: Read

    /// Read the next tag and hand back the decoded payload and the raw
    /// string — the same pair a camera scan produces, so callers reuse
    /// every existing affordance.
    func read(onResult: @escaping (ScanPayload, String) -> Void) {
        guard Self.isSupported else {
            status = .failed("This device can't read NFC tags.")
            return
        }
        start(.read(onResult), prompt: "Hold near an NFC tag")
    }

    func cancel() {
        let running = session
        session = nil
        job = nil
        tag = nil
        running?.invalidate()
        status = .idle
    }

    /// The content the control writes changed. An outcome reported for the
    /// old content — "Tag written", or why it wasn't — says nothing about
    /// what a tap writes now, so it goes, and a session still waiting for a
    /// tag is stopped rather than left to write the old content. Android's
    /// `contentChanged()`.
    func contentDidChange() {
        guard status != .idle else { return }
        cancel()
    }

    /// A Core NFC session is single-use, so every attempt builds a new one.
    private func start(_ job: Job, prompt: String) {
        cancel()
        // `invalidateAfterFirstRead` must be false for a read-write session;
        // this class ends each session itself once it has an outcome.
        let session = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: false)
        session.alertMessage = prompt
        self.session = session
        self.job = job
        generation += 1
        concluded = false
        status = .scanning
        session.begin()
    }

    // MARK: Steps

    /// Whether `generation` is still the running session, which has no
    /// outcome yet.
    private func isCurrent(_ generation: Int) -> Bool {
        session != nil && !concluded && generation == self.generation
    }

    private func didConnect(_ generation: Int, error: (any Error)?) {
        guard isCurrent(generation), let tag else { return }
        if let error {
            conclude(failure: Self.message(for: error))
            return
        }
        tag.queryNDEFStatus { [weak self] ndefStatus, capacity, error in
            MainActor.assumeIsolated {
                self?.didQuery(generation, ndefStatus, capacity: capacity, error: error)
            }
        }
    }

    private func didQuery(_ generation: Int, _ ndefStatus: NFCNDEFStatus, capacity: Int, error: (any Error)?) {
        guard isCurrent(generation), let session, let tag, let job else { return }
        if let error {
            conclude(failure: Self.message(for: error))
            return
        }
        switch ndefStatus {
        case .readWrite, .readOnly:
            break
        case .notSupported:
            conclude(failure: "That tag doesn't speak NDEF.")
            return
        @unknown default:
            conclude(failure: "That tag doesn't speak NDEF.")
            return
        }

        switch job {
        case .read:
            tag.readNDEF { [weak self] message, error in
                // Flatten to a String here, so only Sendable values cross
                // into the main actor.
                let text = message.flatMap { message in
                    NDEFRecordCodec.readableString(in: message.records.map { NDEFRecordCodec.Record($0) })
                }
                MainActor.assumeIsolated {
                    self?.didRead(generation, text: text, error: error)
                }
            }
        case .write(let message):
            guard ndefStatus == .readWrite else {
                conclude(failure: "That tag is read-only. Writable NDEF tags are sold as such.")
                return
            }
            // A tag that reports no capacity is left to `writeNDEF`, which
            // has its own too-small error.
            guard capacity == 0 || message.length <= capacity else {
                conclude(failure: "That tag holds \(capacity) bytes; this content needs \(message.length).")
                return
            }
            status = .writing
            session.alertMessage = "Writing…"
            tag.writeNDEF(message) { [weak self] error in
                MainActor.assumeIsolated {
                    self?.didWrite(generation, error: error)
                }
            }
        }
    }

    private func didRead(_ generation: Int, text: String?, error: (any Error)?) {
        guard isCurrent(generation), case .read(let deliver)? = job else { return }
        if let error {
            conclude(failure: Self.message(for: error))
            return
        }
        guard let text else {
            conclude(failure: "That tag holds no readable text record.")
            return
        }
        let payload = ScanPayloadParser.parse(text)
        conclude(success: "Read “\(payload.kindLabel)” from the tag")
        deliver(payload, text)
    }

    private func didWrite(_ generation: Int, error: (any Error)?) {
        guard isCurrent(generation) else { return }
        if let error {
            conclude(failure: Self.message(for: error))
            return
        }
        conclude(success: "Tag written")
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// End the session with a checkmark and `message` on the NFC sheet.
    private func conclude(success message: String) {
        guard let session else { return }
        concluded = true
        status = .wrote(message)
        session.alertMessage = message
        session.invalidate()
    }

    /// End the session with an error symbol and `message` on the NFC sheet.
    private func conclude(failure message: String) {
        guard let session else { return }
        concluded = true
        status = .failed(message)
        session.invalidate(errorMessage: message)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// Two tags at once can't be told apart; ask for one and poll again.
    /// Restarting invalidates the tags already reported, hence the reset.
    private func retryWithOneTag(_ session: NFCNDEFReaderSession) {
        session.alertMessage = "More than one tag found. Remove all tags and try again."
        tag = nil
        let generation = self.generation
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, self.isCurrent(generation), let session = self.session else { return }
            session.restartPolling()
        }
    }

    private static func message(for error: any Error) -> String {
        guard let nfcError = error as? NFCReaderError else { return error.localizedDescription }
        switch nfcError.code {
        case .readerSessionInvalidationErrorSessionTimeout:
            return "No tag was found in time."
        case .readerSessionInvalidationErrorSystemIsBusy:
            return "NFC is busy right now. Try again in a moment."
        case .readerErrorUnsupportedFeature, .readerErrorSecurityViolation:
            return "NFC isn't available to Scan on this device."
        case .readerErrorRadioDisabled:
            return "NFC is turned off."
        case .readerTransceiveErrorTagConnectionLost:
            return "The tag moved away. Hold it still and try again."
        case .ndefReaderSessionErrorTagNotWritable:
            return "That tag is read-only. Writable NDEF tags are sold as such."
        case .ndefReaderSessionErrorTagSizeTooSmall:
            return "That tag is too small for this content."
        case .ndefReaderSessionErrorTagUpdateFailure:
            return "The tag refused the write."
        case .ndefReaderSessionErrorZeroLengthMessage:
            return "That tag is empty."
        default:
            return nfcError.localizedDescription
        }
    }
}

// MARK: - Delegate

// `@preconcurrency`: Core NFC predates Swift concurrency, and these callbacks
// arrive on the session's queue, which `start` makes the main queue.
extension NFCTagWriter: @preconcurrency NFCNDEFReaderSessionDelegate {

    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [any NFCNDEFTag]) {
        guard session === self.session, !concluded else { return }
        guard tags.count == 1, let tag = tags.first else {
            retryWithOneTag(session)
            return
        }
        self.tag = tag
        let generation = self.generation
        session.connect(to: tag) { [weak self] error in
            MainActor.assumeIsolated {
                self?.didConnect(generation, error: error)
            }
        }
    }

    /// Required by the protocol, never called: implementing
    /// `readerSession(_:didDetect:)` turns this into a read-write session,
    /// which reports tags instead of messages.
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {}

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: any Error) {
        guard session === self.session else { return }
        self.session = nil
        job = nil
        tag = nil
        // An outcome this class reached itself already set the status.
        guard !concluded else { return }
        switch (error as? NFCReaderError)?.code {
        case .readerSessionInvalidationErrorUserCanceled?,
             .readerSessionInvalidationErrorSessionTerminatedUnexpectedly?,
             .readerSessionInvalidationErrorFirstNDEFTagRead?:
            // Cancelled, or the app went to the background: nothing to report.
            status = .idle
        default:
            status = .failed(Self.message(for: error))
        }
    }
}
