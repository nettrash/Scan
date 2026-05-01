//
//  CryptoPayload.swift
//  Scan
//
//  Recognises cryptocurrency wallet URIs — BIP-21 (Bitcoin and friends),
//  EIP-681 (Ethereum), and BOLT-11 Lightning invoices — so we can show
//  the user what's actually inside the QR before they tap "Open in
//  Wallet".
//
//  In 1.4 also recognises the major stablecoins (USDC / USDT / DAI) on
//  Ethereum (ERC-20), Tron (TRC-20), and Solana (SPL) — both as
//  EIP-681 token-transfer URIs (`ethereum:CONTRACT@1/transfer?address=…`),
//  as Solana Pay SPL-token URIs (`solana:RECIPIENT?spl-token=MINT`),
//  and as bare Tron addresses (`T…`, base58, 34 chars). When the
//  contract / mint matches a well-known stablecoin it surfaces the
//  symbol + chain so the result sheet can read "USDC on Ethereum"
//  instead of "ERC-20 transfer to 0xA0b8…".
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
        /// New in 1.4. TRON's mainnet — host of TRC-20 stablecoins
        /// (USDT-TRC20 is the most-traded stablecoin globally by
        /// volume, despite being underrepresented in Western wallet
        /// docs). Bare addresses start with `T` and are 34 chars.
        case tron        = "TRON"
        case other       = "Crypto"
    }

    /// New in 1.4. Surfaces *what* is being moved when a transfer is
    /// against a token contract rather than the chain's native asset
    /// (e.g. an ERC-20 USDC payment looks like `ethereum:CONTRACT@1/transfer?…`
    /// — the destination in the URI's path is the token contract,
    /// not the recipient). `chain` here is the L1 the contract lives
    /// on, not necessarily the same as the host's `chain` for Solana
    /// SPL where chain stays `.solana` and the recipient is the
    /// path part.
    struct Token: Equatable {
        let symbol: String     // "USDC", "USDT", "DAI"
        let contract: String   // canonical-cased contract / mint address
        let chain: Chain       // .ethereum / .tron / .solana
    }

    let chain: Chain
    let scheme: String
    /// For most chains, the destination address.
    /// For Lightning, the entire bolt11 invoice (the part after `lightning:`).
    /// For ERC-20 token transfers, the *recipient* extracted from the
    /// `address=` query param (not the contract — that lives in `token`).
    let address: String
    let amount: String?
    let label: String?
    let message: String?
    /// EIP-681 chain ID for Ethereum (`@137` etc.). Nil otherwise.
    let chainId: String?
    /// Token context for ERC-20 / TRC-20 / SPL transfers. Nil for
    /// native-asset payments.
    let token: Token?
    /// The original URI — what we'd hand to a wallet app via UIApplication.open.
    let raw: String

    /// Convenience initialiser preserving the pre-1.4 signature so
    /// every site that constructed a CryptoPayload (the bare-address
    /// path, parser fallbacks, tests) keeps compiling without
    /// touching every call.
    init(
        chain: Chain,
        scheme: String,
        address: String,
        amount: String?,
        label: String?,
        message: String?,
        chainId: String?,
        raw: String,
        token: Token? = nil
    ) {
        self.chain   = chain
        self.scheme  = scheme
        self.address = address
        self.amount  = amount
        self.label   = label
        self.message = message
        self.chainId = chainId
        self.token   = token
        self.raw     = raw
    }

    var labelledFields: [LabelledField] {
        var rows: [LabelledField] = []
        // Token-aware header. "USDC on Ethereum" is more useful than
        // a raw ERC-20 contract address, so when `token` is present
        // we lead with that.
        if let token = token {
            rows.append(.init(label: "Token", value: "\(token.symbol) on \(token.chain.rawValue)"))
            rows.append(.init(label: "Contract", value: token.contract))
        } else {
            rows.append(.init(label: "Chain", value: chain.rawValue))
        }
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
        "cosmos":       .cosmos,
        "tron":         .tron,
        "tronlink":     .tron,
    ]

    /// Well-known stablecoin contracts. Keyed on lowercased contract /
    /// mint address so detection is case-insensitive (Ethereum
    /// addresses are checksum-cased and Solana mints are base58-cased).
    /// Restricted to the heavyweight stablecoins because that's where
    /// 95 % of "what *is* this token?" confusion happens; extending
    /// the registry is a matter of dropping more entries here.
    private static let knownTokens: [String: CryptoPayload.Token] = [
        // ERC-20 — Ethereum mainnet
        "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48":
            .init(symbol: "USDC", contract: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", chain: .ethereum),
        "0xdac17f958d2ee523a2206206994597c13d831ec7":
            .init(symbol: "USDT", contract: "0xdAC17F958D2ee523a2206206994597C13D831ec7", chain: .ethereum),
        "0x6b175474e89094c44da98b954eedeac495271d0f":
            .init(symbol: "DAI",  contract: "0x6B175474E89094C44Da98b954EedeAC495271d0F", chain: .ethereum),

        // TRC-20 — Tron mainnet
        "tr7nhqjekqxgtci8q8zy4pl8otszgjlj6t":
            .init(symbol: "USDT", contract: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t", chain: .tron),
        "thb4cqifcwoyalsl6bwuthba5krshxtrjq":
            .init(symbol: "USDC", contract: "THb4CqiFcwoyaL5L6bWuThbA5krsHXtrJq", chain: .tron),

        // SPL — Solana mainnet
        "epjfwdd5aufqssqem2qn1xzybapc8g4weggkzwytdt1v":
            .init(symbol: "USDC", contract: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", chain: .solana),
        "es9vmfrzacermjfrf4h2fyd4kconky11mcce8benwnyb":
            .init(symbol: "USDT", contract: "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB", chain: .solana),
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

    /// Tron base58 address: starts with `T`, exactly 34 chars total.
    /// Strict on length because the alphabet alone overlaps with
    /// Bitcoin's regex too much to disambiguate otherwise.
    private static let tronAddressRegex = try! NSRegularExpression(
        pattern: #"^T[1-9A-HJ-NP-Za-km-z]{33}$"#
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
        // Tron addresses — 34-char, T-prefixed, base58. Check before
        // Bitcoin so the `T1...` shape doesn't get swallowed by the
        // legacy-Bitcoin regex (which would mis-classify it).
        if matches(tronAddressRegex) {
            // If it matches a known TRC-20 contract address, surface
            // the token. Bare-address scans of *contracts* aren't
            // typical (users scan recipient addresses, not contracts)
            // but the registry lookup is cheap and avoids surprises.
            let token = knownTokens[s.lowercased()]
            return CryptoPayload(
                chain: .tron, scheme: "", address: s,
                amount: nil, label: nil, message: nil, chainId: nil,
                raw: s, token: token
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
            // Same registry trick for ERC-20 contract addresses
            // scanned in isolation.
            let token = knownTokens[s.lowercased()]
            return CryptoPayload(
                chain: .ethereum, scheme: "", address: s,
                amount: nil, label: nil, message: nil, chainId: nil,
                raw: s, token: token
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

        // BIP-21 / EIP-681 form:  scheme:address[@chainId][/function]?key=val&key=val
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
        /// EIP-681 function name on the path — e.g. `transfer`, `approve`.
        /// We only act on `transfer` (everything else is unusual enough
        /// to display as raw); the parser captures it for future use.
        var function: String?
        if chain == .ethereum, let at = pathPart.firstIndex(of: "@") {
            address = String(pathPart[..<at])
            let afterAt = pathPart[pathPart.index(after: at)...]
            let fn = afterAt.split(separator: "/", maxSplits: 1).map(String.init)
            chainId = fn.first
            function = fn.count > 1 ? fn[1] : nil
        }
        guard !address.isEmpty else { return nil }

        // Parse query params. Spec says case-sensitive, but real-world
        // wallets vary — we lowercase at the lookup site.
        var params: [String: String] = [:]
        for pair in queryPart.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            let k = kv[0].lowercased()
            let v = kv[1].removingPercentEncoding ?? kv[1]
            params[k] = v
        }

        var amount: String? = params["amount"] ?? params["value"]
        let label:  String? = params["label"]
        let message: String? = params["message"]

        // EIP-681 ERC-20 transfer: the path's `address` is the token
        // *contract*, the recipient is in the `address=` query param,
        // and the amount is in `uint256=`. When we recognise the
        // contract as a known stablecoin we surface the symbol + chain.
        var resolvedAddress = address
        var token: CryptoPayload.Token? = nil
        if chain == .ethereum && function?.lowercased() == "transfer",
           let recipient = params["address"], !recipient.isEmpty {
            token = knownTokens[address.lowercased()]
                ?? .init(symbol: "ERC-20", contract: address, chain: .ethereum)
            resolvedAddress = recipient
            // EIP-681's amount param for a token transfer is `uint256`,
            // not `amount` — but some wallets emit both. Prefer
            // uint256 if present.
            if let raw = params["uint256"] { amount = raw }
        }

        // Solana Pay SPL token: `solana:RECIPIENT?spl-token=MINT&amount=…`.
        // Recipient stays in the path; the token comes from the query.
        if chain == .solana, let mint = params["spl-token"], !mint.isEmpty {
            token = knownTokens[mint.lowercased()]
                ?? .init(symbol: "SPL", contract: mint, chain: .solana)
        }

        // TRC-20: `tron:CONTRACT?address=RECIPIENT&amount=…` mirrors
        // the EIP-681 layout for some wallets, but most TRC-20 QRs
        // emit the recipient *as* the path and the contract via a
        // separate `contract=` field. Handle both shapes.
        if chain == .tron {
            if let recipient = params["address"], !recipient.isEmpty,
               address.hasPrefix("T") {
                token = knownTokens[address.lowercased()]
                    ?? .init(symbol: "TRC-20", contract: address, chain: .tron)
                resolvedAddress = recipient
            } else if let contract = params["contract"], !contract.isEmpty {
                token = knownTokens[contract.lowercased()]
                    ?? .init(symbol: "TRC-20", contract: contract, chain: .tron)
            }
        }

        return CryptoPayload(
            chain: chain,
            scheme: scheme,
            address: resolvedAddress,
            amount: amount,
            label: label,
            message: message,
            chainId: chainId,
            raw: raw,
            token: token
        )
    }
}
