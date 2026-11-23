//
//  QrRisk.swift
//  Scan
//
//  On-device QR safety assessment — the "should I tap this?" answer.
//
//  A scanned code is an instruction the user cannot read: a parking-meter
//  sticker, a donation box, a restaurant table tent, an emailed invoice. The
//  abuse pattern in all of them is the same — swap the printed code for
//  yours, or shorten a link so the destination is invisible. This file scores
//  those patterns from the payload alone.
//
//  There is deliberately **no** URL-reputation or "safe browsing" service
//  call: sending the user's scanned URLs to somebody's API to be graded
//  breaks the on-device invariant the app is built on. Everything here is
//  string analysis over data already in memory.
//

import CryptoKit
import Foundation

// MARK: - Model

enum QrRiskLevel: Int, Comparable {
    case safe = 0
    case caution = 1
    case danger = 2

    static func < (lhs: QrRiskLevel, rhs: QrRiskLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .safe:    return "Looks fine"
        case .caution: return "Check before you open"
        case .danger:  return "Suspicious"
        }
    }

    var symbol: String {
        switch self {
        case .safe:    return "checkmark.shield"
        case .caution: return "exclamationmark.shield"
        case .danger:  return "xmark.shield"
        }
    }
}

struct QrRiskFinding: Equatable, Identifiable {
    enum Severity: Int {
        case note = 0         // informational, does not raise the level
        case caution = 1
        case danger = 2
    }

    /// Stable identifier so a finding can be tested, localised, or muted
    /// later without matching on display text.
    let code: String
    let title: String
    let detail: String
    let severity: Severity

    var id: String { code }
}

struct QrRiskReport: Equatable {
    let level: QrRiskLevel
    let findings: [QrRiskFinding]

    var isBlocking: Bool { level == .danger }
    var isEmpty: Bool { findings.isEmpty }

    var headline: String {
        switch level {
        case .safe:
            return findings.first?.title ?? "Nothing unusual detected"
        case .caution:
            return findings.filter { $0.severity.rawValue >= QrRiskFinding.Severity.caution.rawValue }
                .first?.title ?? "Check before you open"
        case .danger:
            return findings.first(where: { $0.severity == .danger })?.title ?? "Suspicious"
        }
    }
}


// MARK: - Assessor

enum QrRiskAssessor {

    /// Assess one decoded code. `codesInFrame` is the number of distinct
    /// codes the camera saw in the same frame — more than one is the classic
    /// sticker-over-sticker tamper, so the caller passes it in when known.
    static func assess(raw: String,
                       payload: ScanPayload? = nil,
                       codesInFrame: Int = 1) -> QrRiskReport {

        var found: [QrRiskFinding] = []
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if codesInFrame > 1 {
            found.append(QrRiskFinding(
                code: "multi-code-frame",
                title: "\(codesInFrame) codes in this frame",
                detail: "More than one code is visible at once. That is how a tamper sticker is placed over a real one — make sure you are scanning the code the venue printed, not something stuck on top.",
                severity: .caution))
        }

        // URL-shaped payloads get the full host treatment.
        let written = webURL(in: trimmed)
        if let written {
            found += analyse(url: written)
        } else if isWebLink(payload) {
            // The parser and the Open button took it for a web link, but it
            // does not split into a domain: a browser would repair it and go
            // somewhere nobody checked.
            found.append(QrRiskFinding(
                code: "unreadable-address",
                title: "Scan can't tell where this link goes",
                detail: "The address is written in a way Scan cannot read a domain from, but a browser may still open it — somewhere you cannot check first.",
                severity: .danger))
        } else if let scheme = scheme(of: trimmed) {
            if dangerousSchemes.contains(scheme) {
                found.append(QrRiskFinding(
                    code: "dangerous-scheme",
                    title: "\(scheme) code",
                    detail: "This payload asks the system to run a \(scheme) action rather than show something. Nothing safe should need it.",
                    severity: .danger))
            } else if scheme == "market" {
                found.append(QrRiskFinding(
                    code: "store-link",
                    title: "A Google Play store link",
                    detail: "This code points at an app's page in Google Play (market:) rather than showing something. That is harmless in itself — install apps only from a developer you recognise.",
                    severity: .note))
            }
        }
        // The Open button hands the system Foundation's re-encoding of the
        // link, not the scanned text, so that string is graded too: a link
        // only has to look bad one way to be stopped.
        if let opened = openedURL(of: payload), opened.absoluteString != written?.absoluteString {
            found = union(found, analyse(url: opened))
        }

        // Secrets and keys that should never be sitting in a scannable code.
        if let secret = exposedSecretKind(trimmed) {
            found.append(QrRiskFinding(
                code: "secret-exposed",
                title: "Secret material in the code",
                detail: "It contains a \(secret). Anyone who can photograph this code can use it — treat it as a credential, not a link.",
                severity: secret == "private key" || secret == "seed phrase" ? .danger : .caution))
        }

        found += analyse(payload: payload, raw: trimmed)

        let level: QrRiskLevel
        if found.contains(where: { $0.severity == .danger }) { level = .danger }
        else if found.contains(where: { $0.severity == .caution }) { level = .caution }
        else { level = .safe }

        return QrRiskReport(level: level, findings: found)
    }

    // MARK: URL analysis

    /// The web link to analyse: the code's own text, split the way a
    /// browser splits it. Only http/https qualify — a rich URL can also be an
    /// app scheme (`matrix:u/alice:example.org`, `weixin://…`), and grading
    /// one of those as a web address reports "no domain" on a perfectly
    /// ordinary code. Those fall through to the scheme check instead.
    ///
    /// Split by hand (`DecodedURL`) rather than read back from Foundation's
    /// `URL`: that punycodes an internationalised host and decodes escapes,
    /// erasing the very characters the homoglyph checks exist to notice —
    /// and the Android port has to see exactly the same host. Foundation's
    /// own spelling is graded separately (`openedURL(of:)`).
    private static func webURL(in raw: String) -> DecodedURL? {
        guard let url = DecodedURL.parse(raw), url.scheme == "http" || url.scheme == "https" else { return nil }
        return url
    }

    /// The parser read the code as a web link, so the result sheet offers to
    /// open it.
    private static func isWebLink(_ payload: ScanPayload?) -> Bool {
        let scheme: String?
        switch payload {
        case .url(let u):     scheme = u.scheme
        case .richURL(let r): scheme = r.url.scheme
        default:              scheme = nil
        }
        return ["http", "https"].contains(scheme?.lowercased() ?? "")
    }

    /// The string the Open button passes to `UIApplication.open` — Foundation
    /// re-encodes what it was given (`paypal.com\@evil.example` becomes
    /// `paypal.com%5C@evil.example`, which goes to evil.example).
    private static func openedURL(of payload: ScanPayload?) -> DecodedURL? {
        switch payload {
        case .url(let u):     return webURL(in: u.absoluteString)
        case .richURL(let r): return webURL(in: r.url.absoluteString)
        default:              return nil
        }
    }

    /// Both lists' findings, one per code, keeping the more severe of two.
    private static func union(_ a: [QrRiskFinding], _ b: [QrRiskFinding]) -> [QrRiskFinding] {
        var out = a
        for finding in b {
            if let index = out.firstIndex(where: { $0.code == finding.code }) {
                if finding.severity.rawValue > out[index].severity.rawValue { out[index] = finding }
            } else {
                out.append(finding)
            }
        }
        return out
    }

    private static func analyse(url: DecodedURL) -> [QrRiskFinding] {
        var found: [QrRiskFinding] = []
        let name = HostName(url.host)
        let host = name.normalized

        if host.isEmpty {
            found.append(QrRiskFinding(code: "no-host", title: "Address has no domain",
                                       detail: "There is no readable domain name in this link.", severity: .caution))
            // A login with nothing after it is still the login trick.
            guard url.userInfo != nil else { return found }
        }

        // An internationalised name is not suspicious in itself — münchen.de
        // and президент.рф are what their owners are called. These two are.
        if name.hasMalformedPunycode {
            found.append(QrRiskFinding(
                code: "punycode-host",
                title: "Internationalised domain",
                detail: "The domain \(host) carries an encoded (punycode) label that does not decode to valid text. Browsers reject names like this, and nothing legitimate needs one.",
                severity: .danger))
        } else if name.isWholeScriptLookalike {
            found.append(QrRiskFinding(
                code: "punycode-host",
                title: "Internationalised domain",
                detail: "The domain \(host) is spelled in another alphabet with letters that pass for Latin ones, so it can read as a familiar address without being one. Compare it letter by letter with the site you meant to visit.",
                severity: .danger))
        }

        if name.mixesAlphabets {
            found.append(QrRiskFinding(
                code: "mixed-script-host",
                title: "Mixed-alphabet domain",
                detail: "\(host) mixes characters from more than one alphabet. That is the signature of a homoglyph attack: it looks like a real brand but resolves somewhere else.",
                severity: .danger))
        }

        if let brand = lookalikeBrand(name) {
            let display = brandDisplay(brand)
            found.append(QrRiskFinding(
                code: "lookalike-domain",
                title: "Impersonates \(display)",
                detail: "\(host) imitates \(display), but \(display) does not operate on this domain.",
                severity: .danger))
        } else if let front = brandInFront(name) {
            let display = brandDisplay(front.brand)
            found.append(QrRiskFinding(
                code: "lookalike-domain",
                title: "Impersonates \(display)",
                detail: "\(host) puts \(display)'s address in front of \(front.domain), which is where the link really goes — and \(display) does not operate on it.",
                severity: .danger))
        }

        if host.contains(":") {                                     // IPv6
            found.append(QrRiskFinding(
                code: "ip-literal-host",
                title: "Points at a raw IP address",
                detail: "The link goes straight to \(host) with no domain, so there is no certificate identity to check and no brand to compare against.",
                severity: .caution))
        } else if let address = ipv4Address(host) {
            let written = address == host ? address : "\(address) (written as \(host))"
            found.append(QrRiskFinding(
                code: "ip-literal-host",
                title: "Points at a raw IP address",
                detail: "The link goes straight to \(written) with no domain, so there is no certificate identity to check and no brand to compare against.",
                severity: isPrivateIP(address) ? .note : .caution))
        }

        // `https://paypal.com@evil.test/` renders as paypal.com in most
        // address bars but resolves to evil.test — the classic QR trick.
        if url.userInfo != nil {
            found.append(QrRiskFinding(
                code: "credentials-in-url",
                title: "Login embedded in the link",
                detail: "The address carries a username (and possibly a password) before the domain. Everything after the @ is the real destination — and it is not who it appears to be.",
                severity: .danger))
        }

        if let port = url.port.flatMap({ Int($0) }), ![80, 443, 8080, 8443].contains(port) {
            found.append(QrRiskFinding(
                code: "odd-port",
                title: "Unusual port :\(port)",
                detail: "Shops and banks do not serve pages from port \(port). Legitimate uses exist, but it is common on throwaway phishing hosts.",
                severity: .caution))
        }

        if url.scheme == "http" {
            found.append(QrRiskFinding(
                code: "plain-http",
                title: "Unencrypted (http)",
                detail: "The page is served without TLS, so anything you type on it travels in the clear.",
                severity: .caution))
        }

        let labels = host.split(separator: ".").map(String.init)
        // Levels in front of the registrable domain, so www.tax.service.gov.uk
        // (two, under gov.uk) is not counted like a.b.c.example.com (three).
        let subdomains = registrableStart(labels)
        if subdomains > 2 {
            found.append(QrRiskFinding(
                code: "deep-subdomain",
                title: "Deeply nested subdomain",
                detail: "\(host) stacks \(subdomains) subdomain levels. Attackers bury the brand they are faking in the middle of a long host.",
                severity: .caution))
        }

        if let tld = labels.last, abuseTLDs.contains(tld) {
            found.append(QrRiskFinding(
                code: "abuse-tld",
                title: "High-abuse domain ending (.\(tld))",
                detail: "Domains ending .\(tld) are registered by the thousand for phishing and are cheap to throw away.",
                severity: .caution))
        }

        if !shortenerExceptions.contains(host),
           shorteners.contains(host) || shorteners.contains(labels.suffix(2).joined(separator: ".")) {
            found.append(QrRiskFinding(
                code: "url-shortener",
                title: "Shortened link",
                detail: "The destination is hidden behind a redirect service. Scan does not follow links, so the real address stays unknown until your browser does.",
                severity: .caution))
        }

        if let redirect = redirectTarget(of: url, host: host) {
            found.append(QrRiskFinding(
                code: "open-redirect",
                title: "Link bounces through a redirect parameter",
                detail: "The trusted-looking domain \(host) is only carrying you onward — \(redirect.via) sends you to \(redirect.host).",
                severity: .caution))
        }

        if let query = url.query?.lowercased() {
            if query.contains("data=") && looksLikeBase64(query) {
                found.append(QrRiskFinding(
                    code: "base64-payload",
                    title: "Encoded blob in the link",
                    detail: "The address carries a base64 payload, which usually means the real instruction is deliberately unreadable.",
                    severity: .caution))
            }
        }

        // UTF-16 units, like the Kotlin port's `length`.
        if url.absoluteString.utf16.count > 900 {
            found.append(QrRiskFinding(
                code: "oversized-url",
                title: "Very long link",
                detail: "Over 900 characters. Long URLs like this typically smuggle a token or a second URL inside the path.",
                severity: .note))
        }

        // Amazon's own parcel pages and PayPal's own invoices use these words
        // too; on the brand's own domain they are the site, not a lure.
        let pathish = (url.path + "?" + (url.query ?? "")).lowercased()
        if !isBrandOwned(labels),
           let bait = phishingKeywords.first(where: { containsWord($0, in: pathish) }) {
            found.append(QrRiskFinding(
                code: "bait-keyword",
                title: "Urgent wording (\(bait))",
                detail: "Payment, refund and account-verification language in a link you did not ask for is the most common QR lure.",
                severity: .caution))
        }

        return found
    }

    // MARK: Payload-shaped findings

    private static func analyse(payload: ScanPayload?, raw: String) -> [QrRiskFinding] {
        var found: [QrRiskFinding] = []
        switch payload {
        case .emvPayment(let p):
            if p.merchantName?.trimmingCharacters(in: .whitespaces).isEmpty != false {
                found.append(QrRiskFinding(
                    code: "payment-no-merchant",
                    title: "Payment code with no merchant name",
                    detail: "Nothing in this code identifies who gets the money. Confirm the name in your bank app before you approve.",
                    severity: .caution))
            }
            // A dynamic code (`01` = 12) is drawn on a screen for one payment,
            // so its amount is expected; the sticker trick needs a printed one.
            if p.value(for: "54") != nil, p.value(for: "01") != "12" {
                found.append(QrRiskFinding(
                    code: "static-amount-poster",
                    title: "Fixed amount baked into the code",
                    detail: "The amount is set by the code, not by you. A sticker pasted over a genuine one quietly changes what you pay.",
                    severity: .caution))
            }
            if p.value(for: "01") == "11" {
                found.append(QrRiskFinding(
                    code: "static-payment-code",
                    title: "Static payment code",
                    detail: "This QR works for unlimited payments and never changes, which is precisely why tampering with it pays. Check it is the venue's own.",
                    severity: .caution))
            }
        case .epcPayment(let p):
            if p.beneficiaryName?.trimmingCharacters(in: .whitespaces).isEmpty != false {
                found.append(QrRiskFinding(
                    code: "payment-no-payee",
                    title: "Payment code with no payee name",
                    detail: "Only an IBAN is present. Check it against the invoice before paying — that is exactly what a swapped QR targets.",
                    severity: .caution))
            }
        case .ipsPayment(let p):
            if p.recipientName?.trimmingCharacters(in: .whitespaces).isEmpty != false {
                found.append(QrRiskFinding(
                    code: "payment-no-payee",
                    title: "Payment code with no recipient name",
                    detail: "Confirm the recipient and the amount inside your bank app before you approve.",
                    severity: .caution))
            }
        case .crypto(let p):
            if p.amount != nil {
                found.append(QrRiskFinding(
                    code: "crypto-amount-preset",
                    title: "Address and amount both preset",
                    detail: "Verify the address characters in your wallet — a lookalike address sends funds somewhere unrecoverable.",
                    severity: .caution))
            }
        case .wifi(_, let password, let security, _):
            if isOpenNetwork(password: password, security: security) {
                found.append(QrRiskFinding(
                    code: "open-wifi",
                    title: "Open network",
                    detail: "This joins an unencrypted Wi-Fi network. Anything you send on it can be read by whoever named it.",
                    severity: .caution))
            }
        case .text(let t):
            if lureInText(t) {
                found.append(QrRiskFinding(
                    code: "lure-text",
                    title: "Payment instruction in free text",
                    detail: "Text like this is normally printed by a venue, not typed into a code by a stranger. Check the physical source before acting.",
                    severity: .caution))
            }
        case .otp, .otpMigration:
            found.append(QrRiskFinding(
                code: "otp-share-warning",
                title: "Two-factor enrolment code",
                detail: "Anyone holding this code can sign in as you. Nobody legitimate will ask you to scan one for them.",
                severity: .caution))
        default:
            break
        }
        return found
    }

    // MARK: Helpers used elsewhere

    /// Public so the identity sheets can ask the same question without
    /// duplicating the brand table.
    static func looksLookalike(_ host: String) -> Bool {
        let name = HostName(host)
        return lookalikeBrand(name) != nil || brandInFront(name) != nil
    }

    /// What the "This link looks suspicious" alert says about a link inside
    /// another code: the verdict, then the reason. The reason names the host
    /// lower-cased (`paypai.com`) — never the link as written, whose capital
    /// I passes for an l in the system font.
    static func gatedLinkMessage(for link: String) -> String {
        let report = assess(raw: link)
        guard let reason = report.findings.first(where: { $0.severity == .danger })?.detail else {
            return report.headline
        }
        return "\(report.headline)\n\n\(reason)"
    }

    /// A `WIFI:` code with no password and no security (absent, empty,
    /// `nopass` or `none`) joins an unencrypted network. The explainer asks
    /// the same question, so the two cannot disagree.
    static func isOpenNetwork(password: String?, security: String?) -> Bool {
        guard password?.isEmpty != false else { return false }
        let tag = security?.trimmingCharacters(in: .whitespaces).uppercased() ?? ""
        return tag.isEmpty || tag == "NOPASS" || tag == "NONE"
    }

    private static func scheme(of raw: String) -> String? {
        guard let end = raw.firstIndex(of: ":") else { return nil }
        let s = String(raw[..<end]).lowercased()
        return s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." } ? s : nil
    }

    /// `market:` is not here: it only opens a Google Play listing, and gets
    /// a note instead.
    private static let dangerousSchemes: Set<String> = [
        "javascript", "vbscript", "data", "file", "jar", "intent",
    ]

    /// Brands are stored lowercased; this puts the capitalisation back for
    /// display.
    private static func brandDisplay(_ brand: String) -> String {
        if let named = brandNames[brand] { return named }
        guard let first = brand.first else { return brand }
        return first.uppercased() + brand.dropFirst()
    }

    /// An IPv4 address in any spelling a browser accepts (`ipv4Address`), or
    /// anything with a colon, which in a host is IPv6.
    static func isIpLiteral(_ host: String) -> Bool {
        host.contains(":") || ipv4Address(host) != nil
    }

    /// The host read the way a browser reads an IPv4 address (the WHATWG
    /// URL Standard's IPv4 parser): one to four dot-separated numbers, each
    /// decimal, octal (a leading 0) or hex (0x), the last one filling the
    /// bytes that are left — so 3627732046, 0xd83ad60e and 0330.072.0326.016
    /// are all 216.58.204.78. The dotted-quad form, or nil when the host is
    /// not IPv4.
    static func ipv4Address(_ host: String) -> String? {
        var parts = host.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count > 1, parts.last?.isEmpty == true { parts.removeLast() }
        guard (1...4).contains(parts.count) else { return nil }
        var numbers: [UInt64] = []
        for part in parts {
            guard let number = ipv4Number(part) else { return nil }
            numbers.append(number)
        }
        guard numbers.dropLast().allSatisfy({ $0 <= 255 }),
              numbers[numbers.count - 1] < UInt64(1) << (8 * (5 - numbers.count)) else { return nil }
        var address = numbers[numbers.count - 1]
        for (index, number) in numbers.dropLast().enumerated() {
            address += number << (8 * (3 - index))
        }
        return [24, 16, 8, 0].map { String((address >> UInt64($0)) & 0xFF) }.joined(separator: ".")
    }

    /// One part of an IPv4 host as a number, or nil when it is not one. A
    /// value too large for any address comes back as 2^33, which every caller
    /// rejects.
    private static func ipv4Number(_ part: Substring) -> UInt64? {
        guard !part.isEmpty else { return nil }
        var digits = Array(part.unicodeScalars)
        var radix: UInt64 = 10
        if digits.count >= 2, digits[0] == "0", digits[1] == "x" || digits[1] == "X" {
            digits.removeFirst(2)
            radix = 16
        } else if digits.count >= 2, digits[0] == "0" {
            digits.removeFirst()
            radix = 8
        }
        var value: UInt64 = 0
        for scalar in digits {
            let digit: UInt64
            switch scalar.value {
            case 0x30...0x39: digit = UInt64(scalar.value - 0x30)
            case 0x61...0x66: digit = UInt64(scalar.value - 0x61 + 10)
            case 0x41...0x46: digit = UInt64(scalar.value - 0x41 + 10)
            default: return nil
            }
            guard digit < radix else { return nil }
            value = min(value * radix + digit, UInt64(1) << 33)
        }
        return value
    }

    private static func isPrivateIP(_ host: String) -> Bool {
        if host.hasPrefix("10.") || host.hasPrefix("192.168.")
            || host.hasPrefix("127.") || host.hasPrefix("169.254.") { return true }
        if host.hasPrefix("172.") {
            let parts = host.split(separator: ".")
            if let second = parts[safe: 1], let n = Int(second) { return (16...31).contains(n) }
        }
        return false
    }

    /// Registrable-domain shorthand: the label in front of the longest public
    /// suffix the table knows (`example.co.uk`, not `co.uk`), else the last
    /// two labels.
    static func registrableDomain(_ host: String) -> String {
        let labels = host.split(separator: ".").map(String.init)
        return labels.suffix(labels.count - registrableStart(labels)).joined(separator: ".")
    }

    /// Index of the registrable domain's first label in `labels` — which is
    /// also how many subdomain labels stand in front of it.
    private static func registrableStart(_ labels: [String]) -> Int {
        guard labels.count > 2 else { return 0 }
        let lower = labels.map { $0.lowercased() }
        var suffix = 1
        for entry in multiPartSuffixes where entry.count > suffix && entry.count < lower.count {
            if zip(entry, lower.suffix(entry.count)).allSatisfy({ $0 == "*" || $0 == $1 }) { suffix = entry.count }
        }
        return lower.count - suffix - 1
    }

    /// The registrable domain is the brand's own name under `.com` or a
    /// country ending (amazon.co.uk, paypal.de) — not a brand under some
    /// other ending, which is a domain anybody could have bought.
    private static func isBrandOwned(_ labels: [String]) -> Bool {
        let lower = labels.map { $0.lowercased() }
        guard !lower.isEmpty else { return false }
        let start = registrableStart(lower)
        guard brands.contains(lower[start]) else { return false }
        let suffix = lower[(start + 1)...]
        guard let tld = suffix.last else { return false }
        return tld == "com" || (tld.count == 2 && tld.unicodeScalars.allSatisfy { ("a"..."z").contains($0) })
    }

    /// The brand the domain is imitating, if any. Looked for in the first
    /// label of the registrable domain only, because that is the part nobody
    /// else can register:
    /// - the brand as a hyphen-separated word of a longer label
    ///   (`paypal-secure-login`, `revolut-pay`) — the brand run together with
    ///   other letters is not enough, or `ubereats`, `appleinsider` and
    ///   `startups` (UPS!) would all be "impersonations". A brand that is
    ///   also an everyday word (`big-apple-pizza`, `wise-owl-books`) counts
    ///   only when another word is about accounts, payments or parcels
    ///   (`apple-support-login`, `ups-delivery`);
    /// - a label that reads as the brand once look-alike characters are
    ///   folded (`paypa1`, `paypaI`, `аpple`, `rnicrosoft`, `páypal`);
    /// - for brands of six letters or more, one doubled letter or one swapped
    ///   pair (`gooogle`, `paypla`) — not an arbitrary edit, which would make
    ///   `telegraph` a Telegram fake and `wish` a Wise one.
    /// A label that *is* the brand in another case (`Google.com`) is the
    /// brand: DNS ignores case.
    private static func lookalikeBrand(_ name: HostName) -> String? {
        let labels = name.unicodeLabels
        guard !labels.isEmpty else { return nil }
        let lower = labels.map { $0.lowercased() }
        let start = registrableStart(lower)
        if brandOwnedDomains.contains(lower[start...].joined(separator: ".")) { return nil }
        let label = labels[start]
        guard label.unicodeScalars.count >= 4 else { return nil }
        if brands.contains(label.lowercased()) { return nil }
        let words = label.split(separator: "-").map(String.init)
        let lowerWords = words.map { $0.lowercased() }
        let wordSkeletons = words.map { $0.unicodeScalars.count >= 4 ? confusableSkeleton($0) : nil }
        let inPhishingContext = lowerWords.contains { phishingContextWords.contains($0) }
        let folded = confusableSkeleton(label)
        for brand in brands {
            let target = brandSkeletons[brand] ?? brand
            if words.count > 1 {
                // A look-alike spelling of the brand as a word is never innocent.
                let disguised = zip(lowerWords, wordSkeletons).contains { $0 != brand && $1 == target }
                let named = lowerWords.contains(brand) && (inPhishingContext || !commonWordBrands.contains(brand))
                if disguised || named { return brand }
            }
            if folded == target { return brand }
            if brand.count >= 6, isSlip(Array(folded.unicodeScalars), of: Array(target.unicodeScalars)) {
                return brand
            }
        }
        return nil
    }

    /// A brand's own address written in front of somebody else's domain —
    /// `paypal.com.secure-login.info`, `apple.com-support.help` — the most
    /// common phishing host there is: a brand label (or a look-alike of it)
    /// followed by a label that reads as a domain ending, still in front of
    /// the registrable domain, or followed by a registrable domain that
    /// starts `com-` / `co-`. The brand and the domain the link really goes to.
    private static func brandInFront(_ name: HostName) -> (brand: String, domain: String)? {
        let lower = name.unicodeLabels.map { $0.lowercased() }
        let start = registrableStart(lower)
        guard start > 0 else { return nil }
        for index in 0..<start {
            let skeleton = confusableSkeleton(name.unicodeLabels[index])
            guard let brand = brands.first(where: { (brandSkeletons[$0] ?? $0) == skeleton }),
                  lower[start] != brand else { continue }
            let next = lower[index + 1]
            let endingFollows = index + 1 < start
                ? topLevelLikeLabels.contains(next) || (next.count == 2 && next.unicodeScalars.allSatisfy { ("a"..."z").contains($0) })
                : next.hasPrefix("com-") || next.hasPrefix("co-")
            if endingFollows { return (brand, lower[start...].joined(separator: ".")) }
        }
        return nil
    }

    /// The Latin letters a label passes for: capital I and digits folded onto
    /// the letters they are drawn like, other alphabets' look-alikes onto the
    /// ASCII letter they imitate, accents dropped, `rn` read as `m` and `vv`
    /// as `w`. Two labels with the same skeleton look the same at a glance.
    static func confusableSkeleton(_ label: String) -> String {
        // Capital I is drawn exactly like a lower-case l in most sans-serif
        // faces ("paypaI"), so it is folded before case is lost.
        let lowered = label.replacingOccurrences(of: "I", with: "l").lowercased()
        var out = String.UnicodeScalarView()
        for scalar in lowered.decomposedStringWithCanonicalMapping.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark: continue
            default: break
            }
            if let ascii = latinLookalikes[scalar.value] { out.append(ascii) } else { out.append(scalar) }
        }
        return String(out).replacingOccurrences(of: "rn", with: "m").replacingOccurrences(of: "vv", with: "w")
    }

    /// `label` is `brand` with one letter doubled or two neighbours swapped.
    private static func isSlip(_ label: [Unicode.Scalar], of brand: [Unicode.Scalar]) -> Bool {
        if label.count == brand.count + 1 {
            for k in 1..<label.count where label[k] == label[k - 1] {
                var shorter = label
                shorter.remove(at: k)
                if shorter == brand { return true }
            }
            return false
        }
        guard label.count == brand.count, label != brand else { return false }
        let differ = label.indices.filter { label[$0] != brand[$0] }
        return differ.count == 2 && differ[1] == differ[0] + 1
            && label[differ[0]] == brand[differ[1]] && label[differ[1]] == brand[differ[0]]
    }

    /// `word` occurs in `text` with no ASCII letter directly before or after
    /// it, so "claim" is bait but "disclaimer" is not. Compared in UTF-16
    /// units, as the Kotlin port does.
    private static func containsWord(_ word: String, in text: String) -> Bool {
        let t = Array(text.utf16), w = Array(word.utf16)
        guard !w.isEmpty, w.count <= t.count else { return false }
        func isLetter(_ unit: UInt16) -> Bool { (0x41...0x5A).contains(unit) || (0x61...0x7A).contains(unit) }
        for start in 0...(t.count - w.count) where t[start..<(start + w.count)].elementsEqual(w) {
            let before = start > 0 && isLetter(t[start - 1])
            let end = start + w.count
            let after = end < t.count && isLetter(t[end])
            if !before && !after { return true }
        }
        return false
    }

    /// Where a redirector link really sends you, when that is a different
    /// site from the link's own: a redirect parameter whose decoded value is
    /// an absolute web address (`url=`, `next=`, DuckDuckGo's `uddg=`,
    /// Google's `q=` on /url, Bing's base64 `u=a1…`), Yahoo's `/RU=…/` path
    /// segment, or Google's `/amp/s/<host>` path. Same-site hops — a sign-in
    /// page returning to its own site — are what those parameters are for.
    private static func redirectTarget(of url: DecodedURL, host: String) -> (via: String, host: String)? {
        let site = registrableDomain(host)
        let siteLabel = site.split(separator: ".").first.map(String.init) ?? ""
        let path = url.path.lowercased()
        let searchRedirect = (siteLabel == "google" && path == "/url") || (site == "youtube.com" && path == "/redirect")
        for (name, value) in queryItems(url.query) {
            let key = name.lowercased()
            guard redirectParameterKeys.contains(key) || (key == "q" && searchRedirect) else { continue }
            var target = absoluteWebURL(value)
            if target == nil, key == "u", value.hasPrefix("a1") { target = absoluteWebURL(base64URLDecoded(value.dropFirst(2))) }
            if let target, let other = foreignHost(target, site: site) { return ("its `\(name)` value", other) }
        }
        if siteLabel == "yahoo", let range = url.path.range(of: "/RU=", options: .caseInsensitive) {
            let value = url.path[range.upperBound...].prefix { $0 != "/" }
            if let target = absoluteWebURL(String(value)), let other = foreignHost(target, site: site) {
                return ("its `RU` path segment", other)
            }
        }
        if siteLabel == "google", path.hasPrefix("/amp/s/") {
            let rest = url.path.dropFirst("/amp/s/".count)
            if let target = absoluteWebURL("https://" + rest), let other = foreignHost(target, site: site) {
                return ("its `/amp/s/` path", other)
            }
        }
        return nil
    }

    /// The host of `url` when it is on another site than `site`.
    private static func foreignHost(_ url: DecodedURL, site: String) -> String? {
        let host = HostName(url.host).normalized
        guard !host.isEmpty, registrableDomain(host) != site else { return nil }
        return host
    }

    /// A redirect value read as a web address: absolute http(s), or `//host`,
    /// after up to two rounds of percent-decoding.
    private static func absoluteWebURL(_ value: String?) -> DecodedURL? {
        guard var text = value else { return nil }
        for round in 0..<3 {
            let candidate = text.hasPrefix("//") ? "https:" + text : text
            if let url = webURL(in: candidate), !url.host.isEmpty { return url }
            guard round < 2, let decoded = HostName.percentDecoded(text), decoded != text else { return nil }
            text = decoded
        }
        return nil
    }

    /// A query string's name/value pairs, split on `&` and `;`, each side
    /// percent-decoded (kept as written when the escape is malformed). `+`
    /// stays a plus.
    private static func queryItems(_ query: String?) -> [(String, String)] {
        guard let query else { return [] }
        return query.split(whereSeparator: { $0 == "&" || $0 == ";" }).map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = String(parts[0]), value = parts.count > 1 ? String(parts[1]) : ""
            return (HostName.percentDecoded(name) ?? name, HostName.percentDecoded(value) ?? value)
        }
    }

    /// Base64url (or plain base64) text decoded as UTF-8, padding optional.
    private static func base64URLDecoded(_ text: Substring) -> String? {
        var standard = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard standard.count % 4 != 1 else { return nil }
        while standard.count % 4 != 0 { standard += "=" }
        guard let data = Data(base64Encoded: standard) else { return nil }
        return String(validating: Array(data), as: UTF8.self)
    }

    private static func exposedSecretKind(_ raw: String) -> String? {
        let lower = raw.lowercased()
        // PEM ("…PRIVATE KEY-----") and PGP ("…PRIVATE KEY BLOCK-----") alike.
        if lower.contains("-----begin") && lower.contains("private key") { return "private key" }
        if containsWIFKey(raw) { return "private key" }
        if lower.hasPrefix("nsec1") || lower.hasPrefix("nostr:nsec1") { return "Nostr secret key" }
        if lower.hasPrefix("xprv") || lower.hasPrefix("zprv") || lower.hasPrefix("tprv") { return "extended wallet key" }
        if lower.contains("m/44'") || lower.contains("m/84'") { return "wallet derivation path" }
        if SeedPhrase.isMnemonic(raw) { return "seed phrase" }
        return nil
    }

    /// A Bitcoin private key in wallet-import format — what a paper wallet
    /// prints: 51 or 52 Base58 characters starting 5, K or L (the shape the
    /// redaction blanks) whose Base58Check checksum holds, so a random token
    /// of that length is not taken for one. A bare 64-digit hex string is
    /// deliberately not a key here: transaction hashes and file digests look
    /// exactly the same.
    static func containsWIFKey(_ text: String) -> Bool {
        var run: [UInt8] = []
        func runIsKey() -> Bool {
            defer { run.removeAll() }
            guard run.count == 51 || run.count == 52, let first = run.first,
                  first == UInt8(ascii: "5") || first == UInt8(ascii: "K") || first == UInt8(ascii: "L"),
                  let bytes = base58Decoded(run) else { return false }
            let compressed = bytes.count == 38 && bytes[33] == 0x01
            guard bytes.count == 37 || compressed, bytes[0] == 0x80 else { return false }
            let digest = SHA256.hash(data: Data(SHA256.hash(data: Data(bytes.prefix(bytes.count - 4)))))
            return Array(digest.prefix(4)) == Array(bytes.suffix(4))
        }
        for scalar in text.unicodeScalars {
            if ("0"..."9").contains(scalar) || ("A"..."Z").contains(scalar) || ("a"..."z").contains(scalar) {
                run.append(UInt8(scalar.value))
            } else if runIsKey() {
                return true
            }
        }
        return runIsKey()
    }

    /// Base58 (the Bitcoin alphabet) to bytes, nil on a character outside it.
    private static func base58Decoded(_ text: [UInt8]) -> [UInt8]? {
        var bytes: [UInt8] = []
        for character in text {
            guard let digit = base58Alphabet.firstIndex(of: character) else { return nil }
            var carry = digit
            for index in bytes.indices.reversed() {
                carry += Int(bytes[index]) * 58
                bytes[index] = UInt8(carry & 0xFF)
                carry >>= 8
            }
            while carry > 0 {
                bytes.insert(UInt8(carry & 0xFF), at: 0)
                carry >>= 8
            }
        }
        let zeros = text.prefix { $0 == UInt8(ascii: "1") }.count
        return [UInt8](repeating: 0, count: zeros) + bytes
    }

    private static let base58Alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8)

    /// Free text that reads like a payment lure rather than something a venue
    /// prints — the "scan to pay £1 / contact us on Telegram" table tent.
    /// Whole words only, so "blocked" is not "locked".
    private static func lureInText(_ text: String) -> Bool {
        let lower = text.lowercased()
        let hasInstruction = lurePhrases.contains { containsWord($0, in: lower) }
            || phishingKeywords.contains { containsWord($0, in: lower) }
        let hasContactHandle = lower.contains("t.me/") || lower.contains("telegram")
            || lower.contains("whatsapp") || lower.contains("wa.me/")
            || lower.contains("@gmail.com") || lower.contains("@mail.ru")
        return hasInstruction && hasContactHandle
    }

    /// At least 24 base64 / base64url characters straight after `data=`.
    private static func looksLikeBase64(_ query: String) -> Bool {
        guard let range = query.range(of: "data=") else { return false }
        let tail = query[range.upperBound...].unicodeScalars.prefix(64)
        return tail.count >= 24 && tail.allSatisfy { s in
            ("a"..."z").contains(s) || ("A"..."Z").contains(s) || ("0"..."9").contains(s) || "+/=_-".unicodeScalars.contains(s)
        }
    }

    // MARK: Tables

    private static let brands = [
        "paypal", "netflix", "amazon", "google", "apple", "microsoft", "facebook",
        "instagram", "whatsapp", "telegram", "revolut", "wise", "barclays",
        "hsbc", "n26", "coinbase", "binance", "trustwallet", "metamask",
        "tiktok", "twitter", "spotify", "airbnb", "uber", "deliveroo",
        "ebay", "aliexpress", "dhl", "fedex", "ups", "westunion", "westernunion",
        "youtube", "linkedin", "adobe", "usps",
    ]

    private static let brandSkeletons: [String: String] =
        Dictionary(uniqueKeysWithValues: brands.map { ($0, confusableSkeleton($0)) })

    /// Brands that are also everyday words. As one word of a hyphenated name
    /// they count only next to a `phishingContextWords` word.
    private static let commonWordBrands: Set<String> = [
        "apple", "amazon", "wise", "uber", "ups", "telegram", "twitter",
    ]

    /// What a fake brand domain is about: signing in, paying, a parcel.
    private static let phishingContextWords: Set<String> = [
        "login", "signin", "logon", "secure", "security", "verify", "verification",
        "account", "accounts", "id", "auth", "password", "support", "help", "service",
        "care", "customer", "billing", "pay", "payment", "refund", "invoice", "update",
        "unlock", "recovery", "wallet", "transfer", "delivery", "redelivery", "track",
        "tracking", "parcel", "package", "shipment",
    ]

    /// Hyphenated domains the brand itself runs.
    private static let brandOwnedDomains: Set<String> = ["youtube-nocookie.com"]

    /// Labels that read as a domain ending when they follow a brand
    /// (`paypal.com.…`); any two-letter label (`.de`, `.uk`) does too.
    private static let topLevelLikeLabels: Set<String> = [
        "com", "net", "org", "co", "io", "app", "info", "biz", "gov", "edu",
    ]

    /// Display spellings for brands whose lowercased key is not how people
    /// write them. Anything absent falls back to a capitalised first letter.
    private static let brandNames: [String: String] = [
        "paypal": "PayPal", "youtube": "YouTube", "instagram": "Instagram",
        "whatsapp": "WhatsApp", "revolut": "Revolut", "hsbc": "HSBC",
        "n26": "N26", "coinbase": "Coinbase", "binance": "Binance",
        "trustwallet": "Trust Wallet", "metamask": "MetaMask",
        "tiktok": "TikTok", "twitter": "X (Twitter)", "airbnb": "Airbnb",
        "deliveroo": "Deliveroo", "ebay": "eBay", "aliexpress": "AliExpress",
        "dhl": "DHL", "fedex": "FedEx", "ups": "UPS",
        "westunion": "Western Union", "westernunion": "Western Union",
        "microsoft": "Microsoft", "facebook": "Facebook", "netflix": "Netflix",
        "amazon": "Amazon", "google": "Google", "apple": "Apple",
        "telegram": "Telegram", "spotify": "Spotify", "uber": "Uber",
        "wise": "Wise", "barclays": "Barclays", "linkedin": "LinkedIn",
        "adobe": "Adobe", "usps": "USPS",
    ]

    /// What `confusableSkeleton` folds each look-alike onto: digits and the
    /// dotted i that pass for Latin letters, the Latin letters other
    /// alphabets imitate (Cyrillic, Greek, Armenian), and the IPA forms of
    /// a, g and i. Lower-case only — the skeleton is built after case-folding.
    private static let latinLookalikes: [UInt32: Unicode.Scalar] = [
        // Digits and Latin
        0x30: "o", 0x31: "l", 0x33: "e", 0x35: "s", 0x69: "l",
        0x131: "l", 0x251: "a", 0x261: "g", 0x269: "l",
        // Cyrillic
        0x430: "a", 0x441: "c", 0x501: "d", 0x435: "e", 0x4BB: "h", 0x456: "l",
        0x458: "j", 0x4CF: "l", 0x43E: "o", 0x440: "p", 0x51B: "q", 0x455: "s",
        0x51D: "w", 0x445: "x", 0x443: "y", 0x4AF: "y",
        // Greek
        0x3B1: "a", 0x3B3: "y", 0x3B9: "l", 0x3BA: "k", 0x3BD: "v", 0x3BF: "o",
        0x3C1: "p", 0x3C5: "u", 0x3C7: "x", 0x3F2: "c", 0x3F3: "j",
        // Armenian
        0x570: "h", 0x578: "n", 0x57D: "u", 0x581: "g", 0x585: "o", 0x566: "q",
    ]

    /// Phrases that turn a free-text QR into a payment instruction. A venue
    /// that really wants money prints the account on the receipt; a code
    /// that tells you to scan and hurry, then asks you to message someone,
    /// is the shape of the table-sticker scam.
    private static let lurePhrases = [
        "scan this code", "scan the code", "scan to pay", "scan and pay",
        "scan here", "scan now", "to pay", "send to", "transfer to",
        "wire to", "send money", "pay us", "pay now", "urgent",
        "do not share", "don't share", "cash app", "cashapp", "venmo",
    ]

    /// Redirect services that hide the destination. Chat deep links
    /// (`wa.me/<number>`, `t.me/<name>`) are not here: their destination is
    /// right there in the path.
    private static let shorteners: Set<String> = [
        "bit.ly", "tinyurl.com", "t.co", "goo.gl", "is.gd", "buff.ly", "ow.ly",
        "bit.do", "shorturl.at", "cutt.ly", "rb.gy", "rebrand.ly", "tiny.cc",
        "shorte.st", "lnkd.in", "lnk.to", "dlvr.it", "ift.tt",
        "tiny.one", "s.id", "linktr.ee",
    ]

    /// Short links that can only lead to one place: Google Maps' share links
    /// open a Maps place, and the parser already reads them as Google Maps.
    private static let shortenerExceptions: Set<String> = ["maps.app.goo.gl"]

    private static let abuseTLDs: Set<String> = [
        // Only endings that are cheap, bulk-registered and rarely used by
        // real businesses — `.shop` / `.live` are popular with legitimate
        // traders, so flagging them would train users to ignore the badge.
        "zip", "mov", "top", "xyz", "cyou", "sbs", "lol", "mom", "click", "icu",
        "quest", "monster", "autos", "beauty", "bond", "rest", "skin", "hair",
    ]

    /// Parameter names, compared whole and case-insensitively. Google's and
    /// YouTube's `q` counts only on their redirect paths (`redirectTarget`).
    private static let redirectParameterKeys: Set<String> = [
        "url", "u", "redirect", "redirect_uri", "redirecturl", "next", "target",
        "dest", "destination", "to", "link", "goto", "continue", "returnurl",
        "uddg", "adurl",
    ]

    private static let phishingKeywords = [
        "verify", "verification", "confirm-your", "unusual-activity", "refund",
        "invoice", "payment-required", "unlock", "suspend", "locked", "kyc",
        "claim", "winner", "prize", "package", "delivery-failed", "overdue",
    ]

    /// The public suffixes of more than one label a scanner realistically
    /// meets — commercial, government and academic second levels, Japan's
    /// prefectures, and Amazon S3's bucket hosts (`*` is any one label) — a
    /// curated slice of the Public Suffix List, the same on both ports.
    private static let multiPartSuffixes: [[String]] = [
        // The United Kingdom
        "co.uk", "org.uk", "me.uk", "ltd.uk", "plc.uk", "net.uk", "ac.uk", "gov.uk",
        "sch.uk", "nhs.uk", "police.uk", "mod.uk",
        // Australia, New Zealand
        "com.au", "net.au", "org.au", "edu.au", "gov.au", "asn.au", "id.au",
        "qld.gov.au", "sa.gov.au", "tas.gov.au", "vic.gov.au", "wa.gov.au",
        "co.nz", "net.nz", "org.nz", "ac.nz", "govt.nz", "school.nz",
        // The Americas
        "com.br", "net.br", "org.br", "gov.br", "edu.br", "com.mx", "org.mx", "gob.mx",
        "edu.mx", "com.ar", "gob.ar", "com.co", "gov.co", "com.pe", "gob.pe", "gc.ca",
        // Asia
        "co.jp", "ne.jp", "or.jp", "ac.jp", "go.jp", "lg.jp", "ed.jp", "gr.jp",
        "co.kr", "go.kr", "or.kr", "ac.kr", "ne.kr",
        "com.cn", "net.cn", "org.cn", "gov.cn", "edu.cn",
        "com.tw", "org.tw", "gov.tw", "edu.tw", "com.hk", "org.hk", "gov.hk", "edu.hk",
        "com.sg", "org.sg", "gov.sg", "edu.sg",
        "co.in", "net.in", "org.in", "gov.in", "nic.in", "ac.in", "edu.in", "res.in",
        "co.id", "or.id", "go.id", "ac.id", "co.th", "or.th", "go.th", "ac.th", "in.th",
        "com.my", "gov.my", "edu.my", "com.ph", "gov.ph", "com.vn", "gov.vn", "com.pk", "gov.pk",
        // The Middle East, Africa
        "co.il", "org.il", "ac.il", "gov.il", "com.tr", "gov.tr", "edu.tr", "org.tr",
        "com.sa", "gov.sa", "co.ae", "gov.ae", "ac.ae", "com.eg", "gov.eg",
        "co.za", "org.za", "gov.za", "ac.za", "co.ke", "go.ke", "com.ng", "gov.ng",
        // Europe
        "com.pl", "net.pl", "org.pl", "gov.pl", "edu.pl", "com.ru", "net.ru", "org.ru",
        "com.ua", "gov.ua", "org.ua", "co.rs", "org.rs", "edu.rs", "in.rs", "gov.rs", "ac.rs",
        "gouv.fr", "com.es", "org.es", "gob.es", "co.at", "or.at", "gv.at", "ac.at",
        "com.gr", "gov.gr", "com.pt", "gov.pt", "com.cy", "com.mt",
        // Japan's prefectures
        "aichi.jp", "akita.jp", "aomori.jp", "chiba.jp", "ehime.jp", "fukui.jp", "fukuoka.jp",
        "fukushima.jp", "gifu.jp", "gunma.jp", "hiroshima.jp", "hokkaido.jp", "hyogo.jp",
        "ibaraki.jp", "ishikawa.jp", "iwate.jp", "kagawa.jp", "kagoshima.jp", "kanagawa.jp",
        "kochi.jp", "kumamoto.jp", "kyoto.jp", "mie.jp", "miyagi.jp", "miyazaki.jp",
        "nagano.jp", "nagasaki.jp", "nara.jp", "niigata.jp", "oita.jp", "okayama.jp",
        "okinawa.jp", "osaka.jp", "saga.jp", "saitama.jp", "shiga.jp", "shimane.jp",
        "shizuoka.jp", "tochigi.jp", "tokushima.jp", "tokyo.jp", "tottori.jp", "toyama.jp",
        "wakayama.jp", "yamagata.jp", "yamaguchi.jp", "yamanashi.jp",
        // Amazon S3 bucket hosts
        "s3.amazonaws.com", "s3.*.amazonaws.com", "s3-website.*.amazonaws.com",
        "s3.dualstack.*.amazonaws.com",
    ].map { $0.split(separator: ".").map(String.init) }
}

// MARK: - URL and host parsing

/// The slice of a URL the risk checks need, split by hand the way a browser
/// splits it (the WHATWG URL Standard). `userInfo` is non-nil the moment an
/// `@` appears in the authority, which is the whole point of the
/// `credentials-in-url` check. The Kotlin port's `parseUrl` splits the same
/// way, so both ports grade the same host.
struct DecodedURL: Equatable {
    let scheme: String          // lower-cased
    let userInfo: String?
    let host: String            // as written; IPv6 without its brackets
    let port: String?           // ASCII digits only
    let path: String
    let query: String?
    let absoluteString: String  // trimmed, with tabs and line breaks taken out

    /// Nil unless the text is `scheme:` and an authority whose host has no
    /// space or control character in it. Read the way a browser reads it:
    /// the ends trimmed, every tab and line break dropped, and for http and
    /// https any run of `/` and `\` — none at all included — taken as the
    /// `//`, so `https:paypa1.com` is paypa1.com. Other schemes need `//`.
    /// The authority ends at `/`, `?`, `#` or `\` — except that a `\` with an
    /// `@` after it (before the next `/`, `?` or `#`) is read as part of the
    /// login, the way Foundation reads it, because Foundation's reading is
    /// what iOS opens: `https://paypal.com\@evil.example` goes to evil.example.
    static func parse(_ raw: String) -> DecodedURL? {
        let s = normalised(raw)
        guard let colon = s.firstIndex(of: ":"), colon > 0, isASCIILetter(s[0]),
              s[1..<colon].allSatisfy({ isASCIILetter($0) || ("0"..."9").contains($0) || "+-.".unicodeScalars.contains($0) })
        else { return nil }
        let scheme = string(s[..<colon]).lowercased()

        var start = colon + 1
        if scheme == "http" || scheme == "https" {
            while start < s.count, s[start] == "/" || s[start] == "\\" { start += 1 }
        } else {
            guard start + 1 < s.count, s[start] == "/", s[start + 1] == "/" else { return nil }
            start += 2
        }
        let terminator = s[start...].firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? s.count
        var authorityEnd = terminator
        if let backslash = s[start..<terminator].firstIndex(of: "\\"),
           !s[(backslash + 1)..<terminator].contains("@") {
            authorityEnd = backslash
        }
        let authority = s[start..<authorityEnd]
        let at = authority.lastIndex(of: "@")
        let userInfo = at.map { string(s[start..<$0]) }
        let hostPort = at.map { s[($0 + 1)..<authorityEnd] } ?? authority
        guard !hostPort.contains(where: { $0.value <= 0x20 || $0.value == 0x7F || "<>^|".unicodeScalars.contains($0) })
        else { return nil }

        var host = string(hostPort)
        var port: String?
        func digits(_ part: ArraySlice<Unicode.Scalar>) -> Bool { part.allSatisfy { ("0"..."9").contains($0) } }
        if hostPort.first == "[" {
            if let close = hostPort.firstIndex(of: "]") {
                host = string(hostPort[(hostPort.startIndex + 1)..<close])
                let after = hostPort[(close + 1)...]
                if after.first == ":", after.count > 1, digits(after.dropFirst()) { port = string(after.dropFirst()) }
            }
        } else if let colon = hostPort.lastIndex(of: ":") {
            let maybePort = hostPort[(colon + 1)...]
            if digits(maybePort) {
                host = string(hostPort[..<colon])
                port = maybePort.isEmpty ? nil : string(maybePort)
            }
        }

        let tail = s[authorityEnd...]
        let beforeFragment = tail[..<(tail.firstIndex(of: "#") ?? tail.endIndex)]
        let question = beforeFragment.firstIndex(of: "?")
        let path = string(beforeFragment[..<(question ?? beforeFragment.endIndex)])
        let query = question.map { string(beforeFragment[($0 + 1)...]) }
        return DecodedURL(scheme: scheme, userInfo: userInfo, host: host, port: port,
                          path: path, query: query, absoluteString: string(s[...]))
    }

    /// `raw` with the white space and control characters at either end
    /// trimmed — the C0 controls and space a browser trims, plus what
    /// Swift's `whitespacesAndNewlines` holds — and every tab, line feed and
    /// carriage return inside dropped, as a browser drops them. Scalars, so a
    /// "\r\n" pair is two characters to drop.
    private static func normalised(_ raw: String) -> [Unicode.Scalar] {
        var scalars = Array(raw.unicodeScalars)
        func trimmed(_ s: Unicode.Scalar) -> Bool {
            switch s.value {
            case 0...0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200B, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000: return true
            default: return false
            }
        }
        while let last = scalars.last, trimmed(last) { scalars.removeLast() }
        let lead = scalars.prefix(while: trimmed).count
        return scalars[lead...].filter { $0 != "\t" && $0 != "\n" && $0 != "\r" }
    }

    private static func isASCIILetter(_ s: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(s) || ("A"..."Z").contains(s)
    }

    private static func string(_ scalars: ArraySlice<Unicode.Scalar>) -> String {
        String(String.UnicodeScalarView(scalars))
    }
}

/// A host the way a browser reads it, for the checks: percent-escapes
/// decoded, compatibility forms folded (fullwidth letters are ordinary
/// letters), invisible characters dropped, `。` read as a dot, and each
/// `xn--` label decoded back to the letters it stands for.
struct HostName {
    /// Lower-cased — what the findings name and the ASCII tables compare.
    let normalized: String
    /// Every label in Unicode with its case kept, for the alphabet and
    /// look-alike checks.
    let unicodeLabels: [String]
    /// An `xn--` label that does not decode.
    let hasMalformedPunycode: Bool

    init(_ raw: String) {
        let decoded = (Self.percentDecoded(raw) ?? raw).precomposedStringWithCompatibilityMapping
        var folded = String.UnicodeScalarView()
        for scalar in decoded.unicodeScalars where !Self.invisible.contains(scalar.value) {
            folded.append(scalar.value == 0x3002 ? "." : scalar)
        }
        var host = String(folded)
        if host.hasSuffix(".") { host.removeLast() }
        normalized = host.lowercased()

        var malformed = false
        unicodeLabels = host.split(separator: ".").map { piece in
            let label = String(piece)
            guard label.lowercased().hasPrefix("xn--") else { return label }
            // A valid A-label always stands for something outside ASCII.
            if let unicode = Punycode.decode(String(label.dropFirst(4))),
               unicode.unicodeScalars.contains(where: { !$0.isASCII }) { return unicode }
            malformed = true
            return label
        }
        hasMalformedPunycode = malformed
    }

    /// Soft hyphen, zero-width space / joiners, word joiner, BOM.
    private static let invisible: Set<UInt32> = [0xAD, 0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF]

    /// A label mixing letters of two alphabets that imitate each other —
    /// Latin with Cyrillic, Greek, Armenian or Cherokee. Accents (münchen)
    /// and Latin next to CJK are not a mix.
    var mixesAlphabets: Bool {
        unicodeLabels.contains { label in
            Set(label.unicodeScalars.compactMap(HostAlphabet.init)).count > 1
        }
    }

    /// A label spelled entirely in one non-Latin alphabet with letters that
    /// all pass for Latin ones ("аррӏе" in Cyrillic reads as "apple"), under
    /// a top-level domain that is not in that alphabet. президент.рф is not
    /// one: its letters do not look Latin, and .рф is Cyrillic too.
    var isWholeScriptLookalike: Bool {
        guard unicodeLabels.count >= 2, let tld = unicodeLabels.last else { return false }
        let tldAlphabets = Set(tld.unicodeScalars.compactMap(HostAlphabet.init))
        for label in unicodeLabels.dropLast() {
            let letters = label.lowercased().unicodeScalars.filter(HostAlphabet.isLetter)
            guard let first = letters.first.flatMap(HostAlphabet.init), first != .latin,
                  !tldAlphabets.contains(first),
                  letters.allSatisfy({ HostAlphabet($0) == first && QrRiskAssessor.passesForLatin($0) })
            else { continue }
            return true
        }
        return false
    }

    /// `%XX` escapes decoded as UTF-8, or nil when an escape is malformed or
    /// the bytes are not UTF-8 — the caller then keeps the text as written.
    static func percentDecoded(_ s: String) -> String? {
        guard s.contains("%") else { return s }
        let source = Array(s.utf8)
        var bytes: [UInt8] = []
        var i = 0
        while i < source.count {
            if source[i] == UInt8(ascii: "%") {
                guard i + 2 < source.count,
                      let hi = hexValue(source[i + 1]), let lo = hexValue(source[i + 2]) else { return nil }
                bytes.append(hi << 4 | lo)
                i += 3
            } else {
                bytes.append(source[i])
                i += 1
            }
        }
        return String(validating: bytes, as: UTF8.self)
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return byte - UInt8(ascii: "A") + 10
        default: return nil
        }
    }
}

extension QrRiskAssessor {
    /// A letter `confusableSkeleton` folds onto an ASCII letter.
    fileprivate static func passesForLatin(_ scalar: Unicode.Scalar) -> Bool {
        guard let ascii = latinLookalikes[scalar.value] else { return false }
        return ("a"..."z").contains(ascii)
    }
}

/// The alphabets whose letters stand in for one another in homoglyph
/// attacks. Code-point ranges rather than the Unicode Script property, so
/// both ports classify identically whatever Unicode version their OS ships.
enum HostAlphabet {
    case latin, greek, cyrillic, armenian, cherokee

    init?(_ scalar: Unicode.Scalar) {
        guard HostAlphabet.isLetter(scalar) else { return nil }
        switch scalar.value {
        case 0x41...0x5A, 0x61...0x7A, 0xAA, 0xBA, 0xC0...0x2AF, 0x1E00...0x1EFF,
             0x2C60...0x2C7F, 0xA720...0xA7FF, 0xAB30...0xAB6F:
            self = .latin
        case 0x370...0x3FF, 0x1F00...0x1FFF:
            self = .greek
        case 0x400...0x52F, 0x1C80...0x1C8F, 0x2DE0...0x2DFF, 0xA640...0xA69F:
            self = .cyrillic
        case 0x531...0x58F, 0xFB13...0xFB17:
            self = .armenian
        case 0x13A0...0x13FF, 0xAB70...0xABBF:
            self = .cherokee
        default:
            return nil
        }
    }

    /// Unicode general category L* — Kotlin's `Character.isLetter`.
    static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
            return true
        default:
            return false
        }
    }
}

/// RFC 3492 decoding of an IDNA label's `xn--` tail, so a punycoded host is
/// checked as the letters it stands for. Nil when the text is not valid
/// punycode. The Kotlin port is the same algorithm line for line.
enum Punycode {
    private static let base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700
    private static let maxValue = 0x7FFF_FFFF

    static func decode(_ input: String) -> String? {
        let units = Array(input.unicodeScalars)
        guard units.allSatisfy({ $0.isASCII }) else { return nil }
        let delimiter = units.lastIndex(of: "-")
        var output: [UInt32] = delimiter.map { units[..<$0].map(\.value) } ?? []
        var index = delimiter.map { $0 + 1 } ?? 0
        var n = 128, i = 0, bias = 72
        while index < units.count {
            let oldI = i
            var w = 1
            var k = base
            while true {
                guard index < units.count, let digit = digitValue(units[index]) else { return nil }
                index += 1
                guard digit <= (maxValue - i) / w else { return nil }
                i += digit * w
                let t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
                if digit < t { break }
                guard w <= maxValue / (base - t) else { return nil }
                w *= base - t
                k += base
            }
            let count = output.count + 1
            bias = adapt(i - oldI, count, oldI == 0)
            guard i / count <= maxValue - n else { return nil }
            n += i / count
            i %= count
            guard n <= 0x10FFFF, !(0xD800...0xDFFF).contains(n) else { return nil }
            output.insert(UInt32(n), at: i)
            i += 1
        }
        var scalars = String.UnicodeScalarView()
        for value in output {
            guard let scalar = Unicode.Scalar(value) else { return nil }
            scalars.append(scalar)
        }
        return String(scalars)
    }

    private static func digitValue(_ scalar: Unicode.Scalar) -> Int? {
        switch scalar.value {
        case 0x30...0x39: return Int(scalar.value) - 0x30 + 26
        case 0x41...0x5A: return Int(scalar.value) - 0x41
        case 0x61...0x7A: return Int(scalar.value) - 0x61
        default: return nil
        }
    }

    private static func adapt(_ delta: Int, _ count: Int, _ first: Bool) -> Int {
        var delta = first ? delta / damp : delta / 2
        delta += delta / count
        var k = 0
        while delta > ((base - tMin) * tMax) / 2 {
            delta /= base - tMin
            k += base
        }
        return k + (base - tMin + 1) * delta / (delta + skew)
    }
}

// MARK: - Seed phrases

/// BIP-39 recovery phrases — the "seed" a crypto wallet is restored from —
/// recognised the same way by the safety check and by the redaction in front
/// of the language model, and the same way on both ports: 12, 15, 18, 21 or
/// 24 words, every one of them in the BIP-39 English wordlist, in any case,
/// separated by white space or commas, optionally numbered ("1.", "1)",
/// "01:") and optionally after a label such as "Seed:" or "Recovery phrase:".
/// An ordinary twelve-word sentence is not one: "welcome" is a BIP-39 word,
/// "guests" is not. The Kotlin port (`SeedPhrase` in QrRisk.kt) is the same
/// code over the same embedded list.
enum SeedPhrase {

    /// Whether the whole of `text` is a recovery phrase.
    static func isMnemonic(_ text: String) -> Bool {
        var count = 0
        for token in unlabelled(Array(text.unicodeScalars)).split(whereSeparator: { isSeparator($0) || $0 == "," }) {
            guard let word = word(token) else { continue }
            guard englishWords.contains(word), count < 24 else { return false }
            count += 1
        }
        return [12, 15, 18, 21, 24].contains(count)
    }

    /// `text` less a leading "Seed:"-style label.
    private static func unlabelled(_ text: [Unicode.Scalar]) -> ArraySlice<Unicode.Scalar> {
        guard let colon = text.firstIndex(of: ":"), colon <= 40 else { return text[...] }
        let label = text[..<colon].split(whereSeparator: isSeparator).map(ascii).joined(separator: " ")
        return labels.contains(label) ? text[(colon + 1)...] : text[...]
    }

    /// A token as a candidate word, less any "12." / "3)" / "01:" numbering
    /// in front, or nil when it is nothing but numbering.
    private static func word(_ token: ArraySlice<Unicode.Scalar>) -> String? {
        var rest = token
        let digits = rest.prefix(while: { ("0"..."9").contains($0) }).count
        if (1...2).contains(digits) {
            let after = rest.dropFirst(digits)
            guard let mark = after.first else { return nil }
            if ".):".unicodeScalars.contains(mark) {
                rest = after.dropFirst()
                if rest.isEmpty { return nil }
            }
        }
        return ascii(rest)
    }

    /// The scalars as a string with A–Z lower-cased and nothing else
    /// touched — the wordlist is ASCII, and both ports fold the same way.
    private static func ascii(_ scalars: ArraySlice<Unicode.Scalar>) -> String {
        var out = String.UnicodeScalarView()
        for scalar in scalars {
            out.append(("A"..."Z").contains(scalar) ? Unicode.Scalar(scalar.value + 0x20)! : scalar)
        }
        return String(out)
    }

    /// White space, spelled out so both ports agree whatever Unicode version
    /// their platform ships: tab to carriage return, next line, and the
    /// space, line and paragraph separators.
    private static func isSeparator(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09...0x0D, 0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000:
            return true
        default:
            return false
        }
    }

    private static let labels: Set<String> = [
        "seed", "seed phrase", "seed words", "mnemonic", "mnemonic phrase", "recovery phrase",
        "recovery words", "recovery seed", "backup phrase", "backup words", "backup seed",
        "secret phrase", "secret recovery phrase", "wallet seed", "wallet seed phrase",
    ]

    private static let englishWords = Set(englishWordlist)

    /// The BIP-39 English wordlist in order — github.com/bitcoin/bips,
    /// bip-0039/english.txt, whose SHA-256 is 2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda
    /// (the tests check it). The Kotlin port embeds the same lines.
    static let englishWordlist: [String] = """
        abandon ability able about above absent absorb abstract absurd abuse access accident
        account accuse achieve acid acoustic acquire across act action actor actress actual
        adapt add addict address adjust admit adult advance advice aerobic affair afford
        afraid again age agent agree ahead aim air airport aisle alarm album
        alcohol alert alien all alley allow almost alone alpha already also alter
        always amateur amazing among amount amused analyst anchor ancient anger angle angry
        animal ankle announce annual another answer antenna antique anxiety any apart apology
        appear apple approve april arch arctic area arena argue arm armed armor
        army around arrange arrest arrive arrow art artefact artist artwork ask aspect
        assault asset assist assume asthma athlete atom attack attend attitude attract auction
        audit august aunt author auto autumn average avocado avoid awake aware away
        awesome awful awkward axis baby bachelor bacon badge bag balance balcony ball
        bamboo banana banner bar barely bargain barrel base basic basket battle beach
        bean beauty because become beef before begin behave behind believe below belt
        bench benefit best betray better between beyond bicycle bid bike bind biology
        bird birth bitter black blade blame blanket blast bleak bless blind blood
        blossom blouse blue blur blush board boat body boil bomb bone bonus
        book boost border boring borrow boss bottom bounce box boy bracket brain
        brand brass brave bread breeze brick bridge brief bright bring brisk broccoli
        broken bronze broom brother brown brush bubble buddy budget buffalo build bulb
        bulk bullet bundle bunker burden burger burst bus business busy butter buyer
        buzz cabbage cabin cable cactus cage cake call calm camera camp can
        canal cancel candy cannon canoe canvas canyon capable capital captain car carbon
        card cargo carpet carry cart case cash casino castle casual cat catalog
        catch category cattle caught cause caution cave ceiling celery cement census century
        cereal certain chair chalk champion change chaos chapter charge chase chat cheap
        check cheese chef cherry chest chicken chief child chimney choice choose chronic
        chuckle chunk churn cigar cinnamon circle citizen city civil claim clap clarify
        claw clay clean clerk clever click client cliff climb clinic clip clock
        clog close cloth cloud clown club clump cluster clutch coach coast coconut
        code coffee coil coin collect color column combine come comfort comic common
        company concert conduct confirm congress connect consider control convince cook cool copper
        copy coral core corn correct cost cotton couch country couple course cousin
        cover coyote crack cradle craft cram crane crash crater crawl crazy cream
        credit creek crew cricket crime crisp critic crop cross crouch crowd crucial
        cruel cruise crumble crunch crush cry crystal cube culture cup cupboard curious
        current curtain curve cushion custom cute cycle dad damage damp dance danger
        daring dash daughter dawn day deal debate debris decade december decide decline
        decorate decrease deer defense define defy degree delay deliver demand demise denial
        dentist deny depart depend deposit depth deputy derive describe desert design desk
        despair destroy detail detect develop device devote diagram dial diamond diary dice
        diesel diet differ digital dignity dilemma dinner dinosaur direct dirt disagree discover
        disease dish dismiss disorder display distance divert divide divorce dizzy doctor document
        dog doll dolphin domain donate donkey donor door dose double dove draft
        dragon drama drastic draw dream dress drift drill drink drip drive drop
        drum dry duck dumb dune during dust dutch duty dwarf dynamic eager
        eagle early earn earth easily east easy echo ecology economy edge edit
        educate effort egg eight either elbow elder electric elegant element elephant elevator
        elite else embark embody embrace emerge emotion employ empower empty enable enact
        end endless endorse enemy energy enforce engage engine enhance enjoy enlist enough
        enrich enroll ensure enter entire entry envelope episode equal equip era erase
        erode erosion error erupt escape essay essence estate eternal ethics evidence evil
        evoke evolve exact example excess exchange excite exclude excuse execute exercise exhaust
        exhibit exile exist exit exotic expand expect expire explain expose express extend
        extra eye eyebrow fabric face faculty fade faint faith fall false fame
        family famous fan fancy fantasy farm fashion fat fatal father fatigue fault
        favorite feature february federal fee feed feel female fence festival fetch fever
        few fiber fiction field figure file film filter final find fine finger
        finish fire firm first fiscal fish fit fitness fix flag flame flash
        flat flavor flee flight flip float flock floor flower fluid flush fly
        foam focus fog foil fold follow food foot force forest forget fork
        fortune forum forward fossil foster found fox fragile frame frequent fresh friend
        fringe frog front frost frown frozen fruit fuel fun funny furnace fury
        future gadget gain galaxy gallery game gap garage garbage garden garlic garment
        gas gasp gate gather gauge gaze general genius genre gentle genuine gesture
        ghost giant gift giggle ginger giraffe girl give glad glance glare glass
        glide glimpse globe gloom glory glove glow glue goat goddess gold good
        goose gorilla gospel gossip govern gown grab grace grain grant grape grass
        gravity great green grid grief grit grocery group grow grunt guard guess
        guide guilt guitar gun gym habit hair half hammer hamster hand happy
        harbor hard harsh harvest hat have hawk hazard head health heart heavy
        hedgehog height hello helmet help hen hero hidden high hill hint hip
        hire history hobby hockey hold hole holiday hollow home honey hood hope
        horn horror horse hospital host hotel hour hover hub huge human humble
        humor hundred hungry hunt hurdle hurry hurt husband hybrid ice icon idea
        identify idle ignore ill illegal illness image imitate immense immune impact impose
        improve impulse inch include income increase index indicate indoor industry infant inflict
        inform inhale inherit initial inject injury inmate inner innocent input inquiry insane
        insect inside inspire install intact interest into invest invite involve iron island
        isolate issue item ivory jacket jaguar jar jazz jealous jeans jelly jewel
        job join joke journey joy judge juice jump jungle junior junk just
        kangaroo keen keep ketchup key kick kid kidney kind kingdom kiss kit
        kitchen kite kitten kiwi knee knife knock know lab label labor ladder
        lady lake lamp language laptop large later latin laugh laundry lava law
        lawn lawsuit layer lazy leader leaf learn leave lecture left leg legal
        legend leisure lemon lend length lens leopard lesson letter level liar liberty
        library license life lift light like limb limit link lion liquid list
        little live lizard load loan lobster local lock logic lonely long loop
        lottery loud lounge love loyal lucky luggage lumber lunar lunch luxury lyrics
        machine mad magic magnet maid mail main major make mammal man manage
        mandate mango mansion manual maple marble march margin marine market marriage mask
        mass master match material math matrix matter maximum maze meadow mean measure
        meat mechanic medal media melody melt member memory mention menu mercy merge
        merit merry mesh message metal method middle midnight milk million mimic mind
        minimum minor minute miracle mirror misery miss mistake mix mixed mixture mobile
        model modify mom moment monitor monkey monster month moon moral more morning
        mosquito mother motion motor mountain mouse move movie much muffin mule multiply
        muscle museum mushroom music must mutual myself mystery myth naive name napkin
        narrow nasty nation nature near neck need negative neglect neither nephew nerve
        nest net network neutral never news next nice night noble noise nominee
        noodle normal north nose notable note nothing notice novel now nuclear number
        nurse nut oak obey object oblige obscure observe obtain obvious occur ocean
        october odor off offer office often oil okay old olive olympic omit
        once one onion online only open opera opinion oppose option orange orbit
        orchard order ordinary organ orient original orphan ostrich other outdoor outer output
        outside oval oven over own owner oxygen oyster ozone pact paddle page
        pair palace palm panda panel panic panther paper parade parent park parrot
        party pass patch path patient patrol pattern pause pave payment peace peanut
        pear peasant pelican pen penalty pencil people pepper perfect permit person pet
        phone photo phrase physical piano picnic picture piece pig pigeon pill pilot
        pink pioneer pipe pistol pitch pizza place planet plastic plate play please
        pledge pluck plug plunge poem poet point polar pole police pond pony
        pool popular portion position possible post potato pottery poverty powder power practice
        praise predict prefer prepare present pretty prevent price pride primary print priority
        prison private prize problem process produce profit program project promote proof property
        prosper protect proud provide public pudding pull pulp pulse pumpkin punch pupil
        puppy purchase purity purpose purse push put puzzle pyramid quality quantum quarter
        question quick quit quiz quote rabbit raccoon race rack radar radio rail
        rain raise rally ramp ranch random range rapid rare rate rather raven
        raw razor ready real reason rebel rebuild recall receive recipe record recycle
        reduce reflect reform refuse region regret regular reject relax release relief rely
        remain remember remind remove render renew rent reopen repair repeat replace report
        require rescue resemble resist resource response result retire retreat return reunion reveal
        review reward rhythm rib ribbon rice rich ride ridge rifle right rigid
        ring riot ripple risk ritual rival river road roast robot robust rocket
        romance roof rookie room rose rotate rough round route royal rubber rude
        rug rule run runway rural sad saddle sadness safe sail salad salmon
        salon salt salute same sample sand satisfy satoshi sauce sausage save say
        scale scan scare scatter scene scheme school science scissors scorpion scout scrap
        screen script scrub sea search season seat second secret section security seed
        seek segment select sell seminar senior sense sentence series service session settle
        setup seven shadow shaft shallow share shed shell sheriff shield shift shine
        ship shiver shock shoe shoot shop short shoulder shove shrimp shrug shuffle
        shy sibling sick side siege sight sign silent silk silly silver similar
        simple since sing siren sister situate six size skate sketch ski skill
        skin skirt skull slab slam sleep slender slice slide slight slim slogan
        slot slow slush small smart smile smoke smooth snack snake snap sniff
        snow soap soccer social sock soda soft solar soldier solid solution solve
        someone song soon sorry sort soul sound soup source south space spare
        spatial spawn speak special speed spell spend sphere spice spider spike spin
        spirit split spoil sponsor spoon sport spot spray spread spring spy square
        squeeze squirrel stable stadium staff stage stairs stamp stand start state stay
        steak steel stem step stereo stick still sting stock stomach stone stool
        story stove strategy street strike strong struggle student stuff stumble style subject
        submit subway success such sudden suffer sugar suggest suit summer sun sunny
        sunset super supply supreme sure surface surge surprise surround survey suspect sustain
        swallow swamp swap swarm swear sweet swift swim swing switch sword symbol
        symptom syrup system table tackle tag tail talent talk tank tape target
        task taste tattoo taxi teach team tell ten tenant tennis tent term
        test text thank that theme then theory there they thing this thought
        three thrive throw thumb thunder ticket tide tiger tilt timber time tiny
        tip tired tissue title toast tobacco today toddler toe together toilet token
        tomato tomorrow tone tongue tonight tool tooth top topic topple torch tornado
        tortoise toss total tourist toward tower town toy track trade traffic tragic
        train transfer trap trash travel tray treat tree trend trial tribe trick
        trigger trim trip trophy trouble truck true truly trumpet trust truth try
        tube tuition tumble tuna tunnel turkey turn turtle twelve twenty twice twin
        twist two type typical ugly umbrella unable unaware uncle uncover under undo
        unfair unfold unhappy uniform unique unit universe unknown unlock until unusual unveil
        update upgrade uphold upon upper upset urban urge usage use used useful
        useless usual utility vacant vacuum vague valid valley valve van vanish vapor
        various vast vault vehicle velvet vendor venture venue verb verify version very
        vessel veteran viable vibrant vicious victory video view village vintage violin virtual
        virus visa visit visual vital vivid vocal voice void volcano volume vote
        voyage wage wagon wait walk wall walnut want warfare warm warrior wash
        wasp waste water wave way wealth weapon wear weasel weather web wedding
        weekend weird welcome west wet whale what wheat wheel when where whip
        whisper wide width wife wild will win window wine wing wink winner
        winter wire wisdom wise wish witness wolf woman wonder wood wool word
        work world worry worth wrap wreck wrestle wrist write wrong yard year
        yellow you young youth zebra zero zone zoo
        """.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
}

private extension Array {
    /// Index that returns nil instead of trapping — the IPv4 checks below
    /// run on hostile input.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
