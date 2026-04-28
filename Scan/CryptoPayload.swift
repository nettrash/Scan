//
//  CryptoPayload.swift
//  Scan
//
//  Recognises cryptocurrency wallet URIs — BIP-21 (Bitcoin and friends),
//  EIP-681 (Ethereum), and BOLT-11 Lightning invoices — so we can show
//  the user what's actually inside the QR before they tap "Open in
//  Wallet".
//

import Foundation

/// A parsed crypto payment URI.
struct CryptoPayload: Equatable {

    enum Chain: String, Equatable {
        case bitcoin     = "Bitcoin"
        case ethereum    = "Ethereum"
        case litecoin    = "Litecoin"
        case bitcoinCash = "Bitcoin Cash"
        case dogecoin    = "Dogecoin"
        case monero      = "Monero"
        case cardano     = "Cardano"
        case solana      = "Solana"
        case lightning   = "Lightning"
        case lnurl       = "LNURL"
        case lightningAddress = "Lightning Address"
        case ripple      = "XRP"
        case stellar     = "Stellar"
        case cosmos      = "Cosmos"
        case other       = "Crypto"
    }

    let chain: Chain
    let scheme: String
    /// For most chains, the destination address.
    /// For Lightning, the entire bolt11 invoice (the part after `lightning:`).
    let address: String
    let amount: String?
    let label: String?
    let message: String?
    /// EIP-681 chain ID for Ethereum (`@137` etc.). Nil otherwise.
    let chainId: String?
    /// The original URI — what we'd hand to a wallet app via UIApplication.open.
    let raw: String

    var labelledFields: [LabelledField] {
        var rows: [LabelledField] = []
        rows.append(.init(label: "Chain", value: chain.rawValue))
        rows.append(.init(label: chain == .lightning ? "Invoice" : "Address",
                          value: address))
        if let a = amount   { rows.append(.init(label: "Amount", value: a)) }
        if let l = label    { rows.append(.init(label: "Label", value: l)) }
        if let m = message  { rows.append(.init(label: "Message", value: m)) }
        if let id = chainId { rows.append(.init(label: "Chain ID", value: id)) }
        return rows
    }
}

// MARK: - Parser

enum CryptoURIParser {

    /// Map of supported URI schemes (lowercased) to chain identifiers.
    /// Add more here as wallets we want to recognise multiply.
    private static let chainByScheme: [String: CryptoPayload.Chain] = [
        "bitcoin":      .bitcoin,
        "ethereum":     .ethereum,
        "litecoin":     .litecoin,
        "bitcoincash":  .bitcoinCash,
        "dogecoin":     .dogecoin,
        "monero":       .monero,
        "cardano":      .cardano,
        "solana":       .solana,
        "lightning":    .lightning,
        "ripple":       .ripple,
        "xrp":          .ripple,
        "xrpl":         .ripple,
        "stellar":      .stellar,
        "web+stellar":  .stellar,
        "cosmos":       .cosmos
    ]

    // MARK: - Bare-address & Lightning-Address recognition

    /// Bitcoin pubkey hash (legacy `1...`, P2SH `3...`) — base58, 25–35 chars.
    /// Plus bech32 segwit (`bc1...`, lowercase, 14+ chars).
    private static let bitcoinAddressRegex = try! NSRegularExpression(
        pattern: #"^([13][a-km-zA-HJ-NP-Z1-9]{25,34}|bc1[02-9ac-hj-np-z]{6,87})$"#
    )

    /// Ethereum 0x-prefixed 40 hex chars.
    private static let ethereumAddressRegex = try! NSRegularExpression(
        pattern: #"^0x[a-fA-F0-9]{40}$"#
    )

    /// XRP classic address: starts with `r`, 25–35 chars, base58.
    private static let xrpAddressRegex = try! NSRegularExpression(
        pattern: #"^r[1-9A-HJ-NP-Za-km-z]{24,34}$"#
    )

    /// Stellar public key: G + 55 chars (base32 modified).
    private static let stellarAddressRegex = try! NSRegularExpression(
        pattern: #"^G[A-Z2-7]{55}$"#
    )

    /// Cosmos / Atom bech32: starts with `cosmos1`, ~45 chars total.
    private static let cosmosAddressRegex = try! NSRegularExpression(
        pattern: #"^cosmos1[02-9ac-hj-np-z]{30,50}$"#
    )

    /// Lightning bare bolt11 — starts with `lnbc` (or `lntb` for testnet),
    /// then an amount/multiplier (optional), then the `1` separator, then
    /// bech32 data. The `1` *is* the separator inside bolt11, so we can't
    /// drop it from the alphabet here. Permissive: lowercase alnum.
    private static let bareBolt11Regex = try! NSRegularExpression(
        pattern: #"^ln(bc|tb)[a-z0-9]{50,}$"#, options: [.caseInsensitive]
    )

    /// LNURL: bech32-encoded URL with prefix `LNURL1`, length 50+ tail.
    /// Same caveat — the `1` is the separator, so the data alphabet is
    /// bech32-strict after it.
    private static let lnurlRegex = try! NSRegularExpression(
        pattern: #"^LNURL1[a-z0-9]{50,}$"#, options: [.caseInsensitive]
    )

    /// Lightning Address — looks like an email but is the canonical
    /// LNURL-pay shorthand (e.g. `nettrash@walletofsatoshi.com`).
    /// We accept anything that matches `local@domain.tld` with at least one
    /// dot in the host. Caller decides whether to prefer this over `.email`.
    private static let lightningAddressRegex = try! NSRegularExpression(
        pattern: #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
    )

    /// Try to recognise a *bare* (no scheme) address or LN-related token.
    /// Returns nil if the input doesn't match any of the known shapes.
    static func parseBare(_ raw: String) -> CryptoPayload? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(s.startIndex..., in: s)

        func matches(_ regex: NSRegularExpression) -> Bool {
            regex.firstMatch(in: s, range: range) != nil
        }

        // LNURL bech32 — most distinctive, check first.
        if matches(lnurlRegex) {
            return CryptoPayload(
                chain: .lnurl, scheme: "", address: s,
                amount: nil, label: nil, message: nil, chainId: nil, raw: s
            )
        }
        // Bare bolt11 invoice.
        if matches(bareBolt11Regex) {
            return CryptoPayload(
                chain: .lightning, scheme: "", address: s,
                amount: nil, label: nil, message: nil, chainId: nil, raw: s
            )
        }
        // Bitcoin (legacy + bech32). Match bech32 first because the legacy
        // regex tail `[a-km-zA-HJ-NP-Z1-9]` could greedily eat a bech32 too.
        if matches(bitcoinAddressRegex) {
            return CryptoPayload(
                chain: .bitcoin, scheme: "", address: s,
                amount: nil, label: nil, message: nil, chainId: nil, raw: s
            )
        }
        if matches(ethereumAddressRegex) {
            return CryptoPayload(
                chain: .ethereum, scheme: "", address: s,
                amount: nil, label: nil, message: nil, chainId: nil, raw: s
            )
        }
        if matches(xrpAddressRegex) {
            return CryptoPayload(
                chain: .ripple, scheme: "", address: s,
                amount: nil, label: nil, message: nil, chainId: nil, raw: s
            )
        }
        if matches(stellarAddressRegex) {
            return CryptoPayload(
                chain: .stellar, scheme: "", address: s,
                amount: nil, label: nil, message: nil, chainId: nil, raw: s
            )
        }
        if matches(cosmosAddressRegex) {
            return CryptoPayload(
                chain: .cosmos, scheme: "", address: s,
                amount: nil, label: nil, message: nil, chainId: nil, raw: s
            )
        }
        // Lightning Address: only if the host part actually exists in the
        // wild as an LN provider domain. We can't easily verify that
        // statically, so we accept any well-formed `local@domain.tld` and
        // *also* require it not be classifiable as an emailable address
        // (callers handle that by checking before falling through to email).
        if matches(lightningAddressRegex) {
            // Heuristic: classify as Lightning Address if the local part
            // doesn't contain typical email-only characters (e.g. `+`)
            // — otherwise prefer .email. Pretty loose but works for
            // 99 % of LN addresses you see in the wild.
            let local = s.split(separator: "@").first.map(String.init) ?? ""
            if !local.contains("+") && !local.contains("%") {
                // Don't claim this as the chosen path unless caller asks
                // — return nil so the email parser takes precedence by
                // default; callers wanting Lightning Address detection
                // call `parseLightningAddress` explicitly.
            }
            return nil
        }
        return nil
    }

    /// Explicit Lightning Address detection — call when you know the user
    /// wants LN treatment over email.
    static func parseLightningAddress(_ raw: String) -> CryptoPayload? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(s.startIndex..., in: s)
        guard lightningAddressRegex.firstMatch(in: s, range: range) != nil else {
            return nil
        }
        return CryptoPayload(
            chain: .lightningAddress, scheme: "", address: s,
            amount: nil, label: nil, message: nil, chainId: nil, raw: s
        )
    }

    /// Lowercased schemes the detector should treat as "potentially crypto".
    static var knownSchemes: Set<String> { Set(chainByScheme.keys) }

    static func parse(_ raw: String) -> CryptoPayload? {
        // Find the colon that separates scheme from body. URL parsing isn't
        // reliable for non-http schemes with characters like `?` and `&`.
        guard let colon = raw.firstIndex(of: ":") else { return nil }
        let scheme = String(raw[..<colon]).lowercased()
        guard let chain = chainByScheme[scheme] else { return nil }
        let body = String(raw[raw.index(after: colon)...])

        // Lightning: the remainder is the bolt11 invoice. No params.
        if chain == .lightning {
            let invoice = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !invoice.isEmpty else { return nil }
            return CryptoPayload(
                chain: .lightning,
                scheme: scheme,
                address: invoice,
                amount: nil, label: nil, message: nil, chainId: nil,
                raw: raw
            )
        }

        // BIP-21 / EIP-681 form:  scheme:address[@chainId]?key=val&key=val
        // Some non-conforming wallets emit `scheme://address?…`; tolerate that.
        var workingBody = body
        if workingBody.hasPrefix("//") {
            workingBody = String(workingBody.dropFirst(2))
        }
        let querySplit = workingBody.split(separator: "?", maxSplits: 1).map(String.init)
        let pathPart = querySplit.first ?? ""
        let queryPart = querySplit.count > 1 ? querySplit[1] : ""

        var address = pathPart
        var chainId: String?
        if chain == .ethereum, let at = pathPart.firstIndex(of: "@") {
            address = String(pathPart[..<at])
            chainId = String(pathPart[pathPart.index(after: at)...])
                .split(separator: "/").first.map(String.init)  // strip function part
        }
        guard !address.isEmpty else { return nil }

        var amount: String?
        var label: String?
        var message: String?
        for pair in queryPart.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            let k = kv[0].lowercased()
            let v = kv[1].removingPercentEncoding ?? kv[1]
            switch k {
            case "amount", "value":
                amount = v
            case "label":
                label = v
            case "message":
                message = v
            default:
                break
            }
        }

        return CryptoPayload(
            chain: chain,
            scheme: scheme,
            address: address,
            amount: amount,
            label: label,
            message: message,
            chainId: chainId,
            raw: raw
        )
    }
}
