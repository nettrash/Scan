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
        "lightning":    .lightning
    ]

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
