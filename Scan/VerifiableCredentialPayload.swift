//
//  VerifiableCredentialPayload.swift
//  Scan
//
//  eIDAS 2.0 / OpenID4VC wallet codes: the QR a verifier site shows so an
//  EU Digital Identity Wallet (or any OpenID4VC wallet) hands it attributes,
//  the QR an issuer shows to put a credential into one, and the credential
//  itself.
//
//  The shapes that arrive in practice:
//
//    openid4vp://?client_id=x509_hash%3A…&request_uri=https%3A%2F%2F…    (VP request, by reference)
//    openid4vp://?client_id=redirect_uri%3A…&dcql_query=%7B…&nonce=…    (VP request, by value)
//    openid-credential-offer://?credential_offer=%7B…%7D                (offer, by value)
//    openid-credential-offer://?credential_offer_uri=https%3A%2F%2F…    (offer, by reference)
//    eyJhbGciOi…​.eyJ2Y3QiO…​.…~WyJ…~                                    (SD-JWT VC)
//
//  A request or offer *by reference* carries almost nothing: the wallet
//  fetches the real one — with its nonce, its claims and its signature —
//  from the verifier's or issuer's server. Scan says so rather than calling
//  a nonce "missing" that was never meant to be in the code, and it never
//  fetches the document itself: that would tell the server this phone
//  scanned it.
//
//  Scan decodes these codes to answer "what is this asking me to release,
//  and to whom" — and stops there. We do **not** verify signatures: no
//  trust anchors, no revocation lists, and above all no network round-trip
//  with the user's credential data. The result sheet says that explicitly,
//  in the same voice as the FIDO passkey rows from 1.10.
//
//  Specs: OpenID4VP 1.0 (Client Identifier Prefixes §5.9.3,
//  `request_uri_method` §5.1, DCQL §6, claims paths §7), OpenID4VCI 1.0
//  (Credential Offer §4.1), OpenID4VC HAIP 1.0 (`haip-vp`, `haip-vci`),
//  ISO/IEC 18013-7 Annex B (`mdoc-openid4vp`), RFC 9901 (SD-JWT).
//

import Foundation

/// An OpenID4VP request, an OpenID4VCI credential offer, or a
/// credential / presentation token.
struct VerifiableCredentialPayload: Equatable {
    enum Kind: String, Equatable {
        case presentationRequest = "Credential request"
        case credentialOffer     = "Credential offer"
        case credential          = "Verifiable credential"
        case presentation        = "Verifiable presentation"
    }

    var kind: Kind
    var raw: String
    /// Wire format — `dc+sd-jwt`, `mso_mdoc`, `jwt_vc_json` … — or, for a
    /// DCQL request, every format its credential queries name.
    var format: String?
    /// `client_id` (verifier) or `credential_issuer` (issuer), verbatim.
    var counterparty: String?
    /// Host the counterparty names, when it names one — the thing a user
    /// can actually compare against the site they are standing on. Every
    /// host field holds `ShownHost.unusual` when the address hides its host.
    var counterpartyHost: String?
    /// Where the wallet is told to send its answer.
    var responseURI: String?
    var noncePresent: Bool
    var statePresent: Bool
    /// Issuer of a credential token.
    var issuer: String?
    /// Credential type — SD-JWT VC `vct`, or the `scope` of a request.
    var credentialType: String?
    var issuedAt: Date?
    var expiresAt: Date?
    /// Number of selectively-disclosable claims (`_sd`).
    var selectivelyDisclosable: Int?
    /// Whether the token binds a key (proof-of-possession) — `cnf`.
    var keyBinding: Bool?
    /// What the verifier wants, or the issuer offers, flattened to
    /// human-readable names.
    var requested: [String]
    /// False when the code was recognised but its contents did not decode.
    var decoded: Bool

    /// A verifier identity that is not a host: a DID, an attestation
    /// subject, a pre-registered client id.
    var counterpartyName: String? = nil
    /// The OpenID4VP 1.0 Client Identifier Prefix `client_id` carries
    /// (`x509_hash`, `redirect_uri`, …), when it carries one.
    var clientIDPrefix: String? = nil
    /// The code only points at the request or offer (`request_uri`,
    /// `credential_offer_uri`); the wallet fetches the document itself.
    var byReference: Bool = false
    /// Host the wallet fetches a by-reference request or offer from.
    var referenceHost: String? = nil
    /// OpenID4VP `request_uri_method=post`: the wallet POSTs its
    /// capabilities to the verifier to get the request.
    var referenceByPost: Bool = false
    /// A Request Object passed by value (`request=`) whose payload did not
    /// decode — the nonce may well be in it.
    var signedRequestUnreadable: Bool = false
    /// The DCQL claims paths a request asks for, as a person reads them.
    var claims: [String] = []
    /// The same claims credential by credential — "given name, portrait
    /// from Mobile driving licence (ISO 18013-5)" — for the explanation.
    var claimsByCredential: [String] = []
    /// The requested claims that are biometric data (a portrait, a
    /// signature image, a biometric template), as a person reads them.
    var biometricClaims: [String] = []
    /// OpenID4VCI grants. The pre-authorised code itself is a bearer
    /// secret and is never kept, let alone shown; nor is `issuer_state`.
    var preAuthorized: Bool = false
    var transactionCodeRequired: Bool = false
    var transactionCodeLength: Int? = nil
    var transactionCodeIsText: Bool = false
    var authorizationCodeGrant: Bool = false
    var authorizationServerHost: String? = nil

    /// The counterparty as it reads in a sentence ("issued by …").
    var counterpartyDescription: String {
        if let host = counterpartyHost, !host.isEmpty { return ShownHost.inSentence(host) }
        if let name = counterpartyName, !name.isEmpty { return name }
        if clientIDPrefix == "x509_hash" { return "a verifier identified only by a certificate hash" }
        return counterparty ?? "Not stated"
    }

    /// "PID + 2 more" style summary used in the result header.
    var requestedSummary: String {
        guard !requested.isEmpty else { return "Nothing stated" }
        if requested.count == 1 { return requested[0] }
        return "\(requested[0]) + \(requested.count - 1) more"
    }

    var labelledFields: [LabelledField] {
        var rows: [LabelledField] = [
            .init(label: "Type", value: kind.rawValue),
        ]
        if let f = format, !f.isEmpty {
            rows.append(.init(label: "Format", value: f))
        }
        switch kind {
        case .presentationRequest:
            rows.append(.init(label: "Asking for", value: requestedRow))
            rows.append(.init(label: "Verifier", value: counterpartyRow))
            if let r = responseURI, !r.isEmpty {
                rows.append(.init(label: "Answer goes to", value: host(of: r) ?? r))
            }
            if byReference {
                rows.append(.init(label: "Request", value: fetchedFrom(referenceHostInSentence ?? "the verifier")))
            }
            rows.append(.init(label: "Anti-replay", value: replayProtection))
        case .credentialOffer:
            rows.append(.init(label: "Offering", value: requestedRow))
            rows.append(.init(label: "Issuer", value: counterpartyRow))
            if byReference {
                rows.append(.init(label: "Offer", value: fetchedFrom(referenceHostInSentence ?? "the issuer")))
            }
            if let s = signIn {
                rows.append(.init(label: "Sign-in", value: s))
            }
            if preAuthorized {
                rows.append(.init(label: "Transaction code", value: transactionCodeRow))
            }
        case .credential, .presentation:
            rows.append(.init(label: "Credential",
                              value: VerifiableCredentialParser.typeName(credentialType)))
            rows.append(.init(label: "Issuer",
                              value: issuer.flatMap { host(of: $0) } ?? issuer ?? "Not stated"))
            if let d = issuedAt { rows.append(.init(label: "Issued", value: Self.stamp(d))) }
            if let d = expiresAt { rows.append(.init(label: "Expires", value: Self.stamp(d))) }
            if let n = selectivelyDisclosable {
                rows.append(.init(label: "Hidden claims",
                                  value: n == 1 ? "1 (selective disclosure)"
                                                : "\(n) (selective disclosure)"))
            }
            if let kb = keyBinding {
                rows.append(.init(label: "Proof of possession",
                                  value: kb ? "Bound to a device key" : "Not bound"))
            }
            if let t = credentialType, !VerifiableCredentialParser.isKnownType(t) {
                rows.append(.init(label: "Type id", value: t))
            }
        }
        for item in requested.dropFirst().prefix(24) {
            rows.append(.init(label: "↳", value: item))
        }
        if !claims.isEmpty {
            rows.append(.init(label: "Claims asked for", value: claimsSummary))
        }
        if !decoded {
            rows.append(.init(label: "Claims", value: "Not decodable — possibly a newer format"))
        }
        return rows
    }

    /// Rows the result sheet shows under the fields: what Scan did *not* do.
    var cautions: [String] {
        var notes: [String] = []
        switch kind {
        case .presentationRequest:
            notes.append("Only approve a request you started yourself — approving one someone sent you releases your data to them.")
            // By reference the nonce is inside the request the wallet
            // fetches, so its absence from the code means nothing.
            if !byReference, !signedRequestUnreadable, !noncePresent {
                notes.append("No nonce: the same code can be replayed, so treat its contents as untrusted.")
            }
            if clientIDPrefix == "origin" {
                notes.append("The verifier uses the origin: prefix, which is reserved for browser requests — a wallet must refuse it in a QR code.")
            }
            if !biometricClaims.isEmpty {
                notes.append("It asks for biometric data (\(biometricClaims.joined(separator: ", "))): only approve that for a verifier you trust.")
            }
        case .credentialOffer:
            notes.append("Installing a credential from an unsolicited QR is how fake wallets and impersonation kits spread.")
            if preAuthorized, !transactionCodeRequired {
                notes.append("Pre-authorised with no transaction code: whoever redeems this code first gets the credential, so do not share or post it.")
            }
        case .credential, .presentation:
            notes.append("This is the credential's own text. Scan does not verify the issuer's signature, its revocation status, or that the document is genuine.")
        }
        let hosts = [counterpartyHost, referenceHost].compactMap { $0 }
        if hosts.contains(where: { $0 != ShownHost.unusual && QrRiskAssessor.looksLookalike($0) }) {
            notes.append("The requesting domain looks like a typosquat of a well-known brand.")
        }
        let shown = [counterpartyHost, referenceHost, authorizationServerHost, responseURI.flatMap(ShownHost.of)]
        if shown.contains(ShownHost.unusual) {
            notes.append(ShownHost.hiddenHostCaution)
        }
        return notes
    }

    /// The line under the cautions: what Scan did not do with this code.
    var footnote: String {
        switch kind {
        case .presentationRequest:
            return byReference
                ? "Scan decodes this code to explain it. It does not fetch the request, answer it, or verify any signature."
                : "Scan decodes this code to explain it. It does not answer the request or verify its signature."
        case .credentialOffer:
            return byReference
                ? "Scan decodes this code to explain it. It does not fetch the offer or contact the issuer."
                : "Scan decodes this code to explain it. It does not redeem the offer or contact the issuer."
        case .credential, .presentation:
            return "Scan decodes this code to explain it. It does not verify the signature, check revocation, or contact the issuer."
        }
    }

    /// The built-in explainer's key points for this code.
    var explanationPoints: [String] {
        switch kind {
        case .presentationRequest:
            var points = ["A site is asking your digital-identity wallet to release attributes."]
            if requested.isEmpty, byReference {
                points.append("The request itself is not in the code: your wallet fetches it from \(referenceHostInSentence ?? "the verifier").")
            } else if !claimsByCredential.isEmpty {
                // The claims themselves, not the credentials' names: a
                // name says what a credential *can* hold, which is not
                // what this verifier asked for.
                points.append("Requested: \(claimsByCredential.joined(separator: "; ")).")
            } else {
                points.append("Requested: \(requestedSummary).")
            }
            points.append("Verifier: \(counterpartyRow).")
            return points
        case .credentialOffer:
            var points = ["An issuer is offering to add a credential to your digital-identity wallet."]
            if requested.isEmpty, byReference {
                points.append("The offer itself is not in the code: your wallet fetches it from \(referenceHostInSentence ?? "the issuer").")
            } else {
                points.append("Offered: \(requestedSummary).")
            }
            points.append("Issuer: \(counterpartyRow).")
            if preAuthorized {
                points.append(transactionCodeRequired
                    ? "Your wallet will ask for a transaction code before the credential is issued."
                    : "No sign-in or code is needed: whoever redeems the code gets the credential.")
            } else if authorizationCodeGrant {
                points.append("You'll sign in at \(authorizationServerHost.map(ShownHost.inSentence) ?? "the issuer") before the credential is issued.")
            }
            return points
        case .credential:
            return ["A digital-identity credential issued by \(counterpartyDescription).",
                    "Credential: \(VerifiableCredentialParser.typeName(credentialType))."]
        case .presentation:
            return ["A wallet's presentation of digital-identity credentials, from \(counterpartyDescription).",
                    "Credential: \(VerifiableCredentialParser.typeName(credentialType))."]
        }
    }

    // MARK: Row text

    private var requestedRow: String {
        if !requested.isEmpty { return requestedSummary }
        return byReference ? "Not in the code — your wallet fetches the details" : "Not stated"
    }

    /// The Verifier / Issuer row: a host, a DID, or what kind of identifier
    /// it is when it names nobody.
    private var counterpartyRow: String {
        if clientIDPrefix == "x509_hash" { return "Unnamed — identified by certificate hash" }
        guard let c = counterparty, !c.isEmpty else { return byReference ? "Not in the code" : "Not stated" }
        if counterpartyHost == ShownHost.unusual { return ShownHost.unusual }
        return counterpartyDescription
    }

    private var referenceHostInSentence: String? {
        referenceHost.map(ShownHost.inSentence)
    }

    private func fetchedFrom(_ host: String) -> String {
        referenceByPost ? "Your wallet fetches it from \(host) by POST" : "Your wallet fetches it from \(host)"
    }

    private var replayProtection: String {
        if byReference { return "Inside the fetched request — not in the code" }
        if signedRequestUnreadable { return "Inside the signed request — not readable" }
        if noncePresent { return statePresent ? "Nonce + state" : "Nonce present" }
        return "Missing — can be replayed"
    }

    private var signIn: String? {
        let at = authorizationServerHost.map(ShownHost.inSentence) ?? "the issuer"
        switch (preAuthorized, authorizationCodeGrant) {
        case (true, true):   return "Pre-authorised, or you sign in at \(at) — your wallet picks"
        case (true, false):  return "Not needed — pre-authorised by the issuer"
        case (false, true):  return "You'll sign in at \(at)"
        case (false, false): return nil
        }
    }

    private var transactionCodeRow: String {
        guard transactionCodeRequired else {
            return "Not required — whoever redeems the code gets the credential"
        }
        guard let n = transactionCodeLength else { return "Required" }
        let unit = transactionCodeIsText ? (n == 1 ? "character" : "characters") : (n == 1 ? "digit" : "digits")
        return "Required — \(n) \(unit)"
    }

    private var claimsSummary: String {
        let shown = claims.prefix(12).joined(separator: ", ")
        return claims.count > 12 ? "\(shown) + \(claims.count - 12) more" : shown
    }

    private static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    /// The "Answer goes to" and token "Issuer" rows' host (see `ShownHost`).
    private func host(of raw: String) -> String? {
        ShownHost.of(raw)
    }
}

enum VerifiableCredentialParser {

    /// URI schemes that invoke an OpenID4VC wallet. Deliberately narrow —
    /// a bare `https://` must never land here.
    ///
    /// - `openid4vp` — OpenID4VP 1.0 §13.1.2 (IANA, provisional).
    /// - `eudi-openid4vp`, `mdoc-openid4vp` — the EU reference wallet's;
    ///   the second is ISO/IEC 18013-7 Annex B (IANA, provisional).
    /// - `haip-vp`, `haip-vci` — OpenID4VC HAIP 1.0 §5.1 / §4.2 (IANA,
    ///   permanent); `haip` is the HAIP drafts' single scheme before them.
    /// - `openid-credential-offer` — OpenID4VCI 1.0 §4.1 (IANA, permanent).
    /// - `openid-vc` — Microsoft Entra Verified ID.
    static let requestSchemes: Set<String> = [
        "openid4vp", "eudi-openid4vp", "mdoc-openid4vp", "haip-vp", "haip",
        "openid-vc", "openid-credential-offer", "haip-vci",
    ]

    /// The schemes that only ever carry a credential offer.
    private static let offerSchemes: Set<String> = ["openid-credential-offer", "haip-vci"]

    // MARK: Recognition

    static func looksLikeCredentialRequest(_ raw: String) -> Bool {
        guard let (scheme, rest) = splitScheme(raw) else { return false }
        guard requestSchemes.contains(scheme.lowercased()) else { return false }
        // A request must carry at least one protocol parameter.
        let lower = rest.lowercased()
        return lower.contains("client_id") || lower.contains("request_uri")
            || lower.contains("request=")
            || lower.contains("dcql_query") || lower.contains("presentation_definition")
            || lower.contains("credential_offer") || lower.contains("scope=")
            || lower.contains("nonce")
    }

    /// Three dot-separated base64URL segments with a JSON object payload —
    /// and only with claim names that mean "credential", so ordinary login
    /// tokens a user pastes in are not dragged into this category. An
    /// SD-JWT appends `~`-separated disclosures (RFC 9901 §4); only the
    /// issuer-signed JWT in front of them is tested here.
    static func looksLikeCredentialToken(_ raw: String) -> Bool {
        let jwt = sdJWTParts(raw).jwt
        let segments = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 || segments.count == 4 else { return false }
        guard segments[0].count > 8, segments[0].allSatisfy(isBase64URLChar),
              segments[1].allSatisfy(isBase64URLChar) else { return false }
        guard let claims = PayloadCodec.jsonObject(fromBase64URL: String(segments[1])) else { return false }
        if claims["vct"] != nil || claims["_sd"] != nil || claims["_sd_alg"] != nil { return true }
        if claims["vp"] != nil { return true }
        if claims["vc"] != nil { return true }
        return false
    }

    private static func isBase64URLChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "-" || c == "_"
    }

    // MARK: Parsing

    static func parse(_ raw: String) -> VerifiableCredentialPayload? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if looksLikeCredentialToken(trimmed) {
            return parseToken(trimmed)
        }
        return parseRequest(trimmed)
    }

    // MARK: Requests & offers

    private static func parseRequest(_ raw: String) -> VerifiableCredentialPayload? {
        guard let (rawScheme, afterScheme) = splitScheme(raw) else { return nil }
        let scheme = rawScheme.lowercased()
        // These are not ordinary URLs: `openid4vp://authorize?…` carries the
        // parameters after an authority that does not exist, and
        // `openid-credential-offer://?…` after an empty one. Only the query
        // matters: everything after the first `?`, up to a fragment.
        let query = afterScheme.utf8.firstIndex(of: UInt8(ascii: "?")).map {
            String(decoding: afterScheme.utf8[afterScheme.utf8.index(after: $0)...], as: UTF8.self)
        } ?? ""
        let items = queryItems(query)

        let isOffer = offerSchemes.contains(scheme) || items["credential_offer"] != nil
            || items["credential_offer_uri"] != nil
        return isOffer ? parseOffer(raw, items: items)
                       : parsePresentationRequest(raw, scheme: scheme, items: items)
    }

    /// The query's parameters, split by hand: names lower-cased, a later
    /// duplicate winning, and a part with no `=` clearing the name, as a
    /// nil `URLQueryItem.value` did. Each name and value is percent-decoded
    /// on its own (`+` stays `+`), and one that does not decode — a stray
    /// `%`, bytes that are not UTF-8 — is kept as written. `URLComponents`
    /// is no use here: one raw space, brace or stray `%` anywhere makes it
    /// re-encode every `%` in the query, so every well-formed parameter
    /// came back still encoded and the verifier, the request and the
    /// cautions went missing. The Kotlin port's
    /// `queryItemsByLowercasedName` splits the same way.
    private static func queryItems(_ query: String) -> [String: String] {
        func decoded(_ bytes: Substring.UTF8View) -> String {
            let text = String(decoding: bytes, as: UTF8.self)
            return HostName.percentDecoded(text) ?? text
        }
        let utf8 = query.utf8
        let body = utf8[..<(utf8.firstIndex(of: UInt8(ascii: "#")) ?? utf8.endIndex)]
        var items: [String: String] = [:]
        for part in body.split(separator: UInt8(ascii: "&"), omittingEmptySubsequences: true) {
            if let eq = part.firstIndex(of: UInt8(ascii: "=")) {
                items[decoded(part[..<eq]).lowercased()] = decoded(part[part.index(after: eq)...])
            } else {
                items[decoded(part).lowercased()] = nil
            }
        }
        return items
    }

    /// OpenID4VP Authorization Request. By value, every parameter is in the
    /// query — or inside a Request Object JWT passed as `request` (RFC 9101),
    /// which a wallet reads instead of the query. By reference
    /// (`request_uri`), the query holds only `client_id` and where to fetch
    /// the rest.
    private static func parsePresentationRequest(_ raw: String, scheme: String,
                                                 items: [String: String]) -> VerifiableCredentialPayload {
        var params: [String: Any] = items
        var signedRequestUnreadable = false
        if let jwt = nonEmpty(items["request"]) {
            if let payload = jwtPayload(jwt) {
                params = payload
                if params["client_id"] == nil, let outer = items["client_id"] { params["client_id"] = outer }
            } else {
                signedRequestUnreadable = true
            }
        }

        let requestURI = nonEmpty(items["request_uri"])
        let byReference = requestURI != nil

        var requested: [String] = []
        var formats: [String] = []
        var claims: [String] = []
        var claimsByCredential: [String] = []
        var biometric: [String] = []
        if let dcql = jsonDocument(params["dcql_query"]) {
            let query = dcqlCredentials(dcql)
            requested += query.names
            formats += query.formats
            claims += query.claims
            claimsByCredential = query.byCredential
            biometric = query.biometric
        }
        if let pd = jsonDocument(params["presentation_definition"]) {
            requested += presentationDefinitionCredentials(pd)
        }
        if let pdUri = nonEmpty(params["presentation_definition_uri"] as? String) {
            requested.append("presentation definition fetched from \(host(of: pdUri).map(ShownHost.inSentence) ?? pdUri)")
        }
        if let scope = params["scope"] as? String {
            requested += scope.split(separator: " ").map(String.init)
                .filter { !$0.isEmpty }
                .map(scopeName)
        }

        var format = dedupe(formats).joined(separator: ", ")
        if format.isEmpty, let f = nonEmpty(params["format"] as? String) { format = f }
        // ISO/IEC 18013-7 Annex B: this scheme only ever asks for an mdoc.
        if format.isEmpty, scheme == "mdoc-openid4vp" { format = "mso_mdoc" }

        let clientID = nonEmpty(params["client_id"] as? String)
        let identity = clientIdentity(clientID, legacyScheme: params["client_id_scheme"] as? String)

        var p = VerifiableCredentialPayload(
            kind: .presentationRequest,
            raw: raw,
            format: format.isEmpty ? nil : format,
            counterparty: clientID,
            counterpartyHost: identity.host,
            responseURI: nonEmpty(params["response_uri"] as? String)
                ?? nonEmpty(params["redirect_uri"] as? String),
            noncePresent: nonEmpty(params["nonce"] as? String) != nil,
            statePresent: nonEmpty(params["state"] as? String) != nil,
            issuer: nil,
            credentialType: nil,
            issuedAt: nil,
            expiresAt: nil,
            selectivelyDisclosable: nil,
            keyBinding: nil,
            requested: dedupe(requested),
            decoded: true
        )
        p.counterpartyName = identity.name
        p.clientIDPrefix = identity.prefix
        p.byReference = byReference
        p.referenceHost = requestURI.flatMap { host(of: $0) }
        p.referenceByPost = items["request_uri_method"]?.lowercased() == "post"
        p.signedRequestUnreadable = signedRequestUnreadable && !byReference
        p.claims = Array(dedupe(claims).prefix(64))
        p.claimsByCredential = claimsByCredential
        p.biometricClaims = dedupe(biometric)
        // A request with nothing decodable in it is still a request; only
        // mark it undecoded when there is genuinely no protocol content.
        p.decoded = !requested.isEmpty || clientID != nil || byReference
        return p
    }

    /// OpenID4VCI 1.0 Credential Offer (§4.1): `credential_issuer`,
    /// `credential_configuration_ids` and `grants`, by value in
    /// `credential_offer` or by reference in `credential_offer_uri`.
    private static func parseOffer(_ raw: String, items: [String: String]) -> VerifiableCredentialPayload {
        var p = VerifiableCredentialPayload(
            kind: .credentialOffer, raw: raw, format: nil, counterparty: nil,
            counterpartyHost: nil, responseURI: nil, noncePresent: false, statePresent: false,
            issuer: nil, credentialType: nil, issuedAt: nil, expiresAt: nil,
            selectivelyDisclosable: nil, keyBinding: nil, requested: [], decoded: false
        )
        var issuer = nonEmpty(items["credential_issuer"])
        if let text = items["credential_offer"], let offer = jsonObject(fromString: text) {
            if let i = nonEmpty(offer["credential_issuer"] as? String) { issuer = i }
            if let ids = offer["credential_configuration_ids"] as? [String] {
                p.requested = dedupe(ids.filter { !$0.isEmpty }.map { typeName($0) })
            } else if let legacy = offer["credentials"] as? [Any] {
                // Drafts before 1.0: configuration ids as strings, or (draft
                // 11) objects spelling out a format and a type.
                p.requested = dedupe(legacy.compactMap(legacyOfferedName))
            }
            readGrants(offer["grants"] as? [String: Any], into: &p)
        } else if let uri = nonEmpty(items["credential_offer_uri"]) {
            p.byReference = true
            p.referenceHost = host(of: uri)
        }
        p.counterparty = issuer
        p.counterpartyHost = issuer.flatMap { host(of: $0) }
        p.decoded = p.byReference || issuer != nil || !p.requested.isEmpty
        return p
    }

    private static let preAuthorizedGrant = "urn:ietf:params:oauth:grant-type:pre-authorized_code"

    /// Which way the wallet will redeem the offer. Only the *shape* of each
    /// grant is read: `pre-authorized_code` is a bearer secret and
    /// `issuer_state` is opaque, so neither is kept.
    private static func readGrants(_ grants: [String: Any]?, into p: inout VerifiableCredentialPayload) {
        guard let grants else { return }
        if let pre = grants[preAuthorizedGrant] as? [String: Any] {
            p.preAuthorized = true
            // `tx_code` present — even empty — means a code will be asked
            // for; draft 12 and earlier said `user_pin_required` instead.
            if let tx = pre["tx_code"] as? [String: Any] {
                p.transactionCodeRequired = true
                p.transactionCodeLength = jsonInteger(tx["length"]).flatMap { (1...100).contains($0) ? $0 : nil }
                p.transactionCodeIsText = (tx["input_mode"] as? String) == "text"
            } else if let legacy = jsonBool(pre["user_pin_required"]) {
                p.transactionCodeRequired = legacy
            }
        }
        if let auth = grants["authorization_code"] as? [String: Any] {
            p.authorizationCodeGrant = true
            p.authorizationServerHost = (auth["authorization_server"] as? String).flatMap { host(of: $0) }
        }
    }

    private static func legacyOfferedName(_ entry: Any) -> String? {
        if let id = entry as? String { return id.isEmpty ? nil : typeName(id) }
        guard let object = entry as? [String: Any] else { return nil }
        if let doctype = nonEmpty(object["doctype"] as? String) { return typeName(doctype) }
        if let vct = nonEmpty(object["vct"] as? String) { return typeName(vct) }
        if let types = object["types"] as? [String], let last = nonEmpty(types.last) { return typeName(last) }
        if let definition = object["credential_definition"] as? [String: Any],
           let types = definition["type"] as? [String], let last = nonEmpty(types.last) {
            return typeName(last)
        }
        return nonEmpty(object["format"] as? String)
    }

    // MARK: Verifier identity

    /// OpenID4VP 1.0 Client Identifier Prefixes (§5.9.3), plus the
    /// `x509_san_uri` of the drafts before it.
    private static let clientIDPrefixes = [
        "redirect_uri", "x509_san_dns", "x509_hash", "decentralized_identifier",
        "verifier_attestation", "openid_federation", "origin", "x509_san_uri",
    ]

    /// Pre-1.0 requests named the prefix in a separate `client_id_scheme`.
    private static let legacyClientIDSchemes: [String: String] = [
        "redirect_uri": "redirect_uri", "x509_san_dns": "x509_san_dns",
        "x509_san_uri": "x509_san_uri", "did": "decentralized_identifier",
        "entity_id": "openid_federation", "verifier_attestation": "verifier_attestation",
    ]

    /// What `client_id` says about the verifier: the prefix it uses, the
    /// host it names, or the non-host name (a DID, a client id) to show.
    private static func clientIdentity(_ clientID: String?, legacyScheme: String?)
        -> (prefix: String?, host: String?, name: String?) {
        guard let clientID else { return (nil, nil, nil) }
        for prefix in clientIDPrefixes where hasASCIIPrefix(clientID, prefix + ":") {
            return identity(prefix: prefix, value: dropASCIIPrefix(clientID, prefix + ":"))
        }
        if let scheme = legacyScheme.flatMap({ legacyClientIDSchemes[$0] }) {
            return identity(prefix: scheme, value: clientID)
        }
        if hasASCIIPrefix(clientID, "did:") {
            return identity(prefix: "decentralized_identifier", value: clientID)
        }
        return identity(prefix: nil, value: clientID)
    }

    private static func identity(prefix: String?, value: String)
        -> (prefix: String?, host: String?, name: String?) {
        switch prefix ?? "" {
        case "x509_hash":
            // A hash of the signing certificate: it names nobody.
            return (prefix, nil, nil)
        case "decentralized_identifier":
            let did = didIdentity(value)
            return (prefix, did.host, did.name)
        case "x509_san_dns":
            return (prefix, isHostName(value) ? value : nil, isHostName(value) ? nil : value)
        default:
            // A URL (redirect_uri, openid_federation, origin, x509_san_uri,
            // an https client id) names its host; an attestation subject
            // or a bare client id may itself be a host name.
            if let host = host(of: value) { return (prefix, host, nil) }
            if isHostName(value) { return (prefix, value, nil) }
            return (prefix, nil, value)
        }
    }

    /// `did:web` names a host; key-only DIDs name nobody; any other DID is
    /// shown as itself, unless it is too long to read.
    private static func didIdentity(_ did: String) -> (host: String?, name: String) {
        guard hasASCIIPrefix(did, "did:") else { return (nil, did) }
        let method = text(dropASCIIPrefix(did, "did:"), before: ":")
        if method == "web" {
            // did:web:<host>[%3A<port>][:<path>…] — a DNS name has no `%`.
            let host = text(text(dropASCIIPrefix(did, "did:web:"), before: ":"), before: "%")
            if isHostName(host) { return (host, host) }
        }
        if ["key", "jwk", "peer"].contains(method) {
            return (nil, "Unnamed — a bare key (did:\(method))")
        }
        if did.utf8.count > 64 {
            return (nil, "did:\(method) (long identifier)")
        }
        return (nil, did)
    }

    /// An ASCII DNS name with at least one dot.
    private static func isHostName(_ s: String) -> Bool {
        guard s.utf8.count <= 253, s.contains("."), !s.hasPrefix("."), !s.hasSuffix("."),
              !s.hasPrefix("-") else { return false }
        return s.utf8.allSatisfy { b in
            (b >= 0x61 && b <= 0x7A) || (b >= 0x41 && b <= 0x5A) || (b >= 0x30 && b <= 0x39)
                || b == 0x2E || b == 0x2D
        }
    }

    // MARK: Tokens (SD-JWT VC / VP JWT)

    private static func parseToken(_ raw: String) -> VerifiableCredentialPayload? {
        let parts = sdJWTParts(raw)
        let segments = parts.jwt.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard segments.count >= 3,
              let header = PayloadCodec.jsonObject(fromBase64URL: segments[0]),
              let claims = PayloadCodec.jsonObject(fromBase64URL: segments[1]) else { return nil }

        let typ = (header["typ"] as? String)?.lowercased()
        // An SD-JWT followed by a Key Binding JWT is what a wallet sends a
        // verifier (RFC 9901 §4), not what an issuer hands out.
        let isPresentation = claims["vp"] != nil || typ?.contains("kb") == true || parts.keyBindingJWT
        let sd = (claims["_sd"] as? [Any])?.count

        var p = VerifiableCredentialPayload(
            kind: isPresentation ? .presentation : .credential,
            raw: raw,
            format: typ.map { $0.contains("sd-jwt") ? "dc+sd-jwt" : $0 },
            counterparty: (claims["iss"] as? String) ?? (claims["client_id"] as? String),
            counterpartyHost: nil,
            responseURI: nil,
            noncePresent: (claims["nonce"] as? String) != nil,
            statePresent: (claims["state"] as? String) != nil,
            issuer: claims["iss"] as? String,
            credentialType: (claims["vct"] as? String) ?? typeFromLegacy(claims),
            issuedAt: date(from: claims["iat"]),
            expiresAt: date(from: claims["exp"]),
            selectivelyDisclosable: sd,
            keyBinding: claims["cnf"] != nil,
            requested: [],
            decoded: true
        )
        p.counterpartyHost = p.issuer.flatMap { host(of: $0) }
        if let vc = claims["vp"] as? [String: Any],
           let inner = vc["verifiableCredential"] as? [Any] {
            p.requested = inner.compactMap { ($0 as? [String: Any])?["id"] as? String }
            if p.credentialType == nil {
                p.credentialType = (vc["@context"] as? [String])?.last
            }
        }
        p.decoded = p.issuer != nil || p.credentialType != nil
        return p
    }

    /// `<issuer-signed JWT>~<disclosure>~…~<KB-JWT or nothing>`: the JWT in
    /// front, and whether a Key Binding JWT closes it. Split on the byte,
    /// so a combining mark after a `~` cannot hide it.
    private static func sdJWTParts(_ raw: String) -> (jwt: String, keyBindingJWT: Bool) {
        let tilde = UInt8(ascii: "~")
        guard let first = raw.utf8.firstIndex(of: tilde) else { return (raw, false) }
        let jwt = String(decoding: raw.utf8[..<first], as: UTF8.self)
        let last = raw.utf8.lastIndex(of: tilde) ?? first
        let tail = raw.utf8[raw.utf8.index(after: last)...]
        return (jwt, tail.filter { $0 == UInt8(ascii: ".") }.count == 2)
    }

    /// W3C VC-JWT puts the type list under `vc.type`.
    private static func typeFromLegacy(_ claims: [String: Any]) -> String? {
        guard let vc = claims["vc"] as? [String: Any],
              let types = vc["type"] as? [String], !types.isEmpty else { return nil }
        return types.last
    }

    // MARK: Request-document extraction

    /// DCQL (OpenID4VP 1.0 §6): each Credential Query has a verifier-local
    /// `id` ("pid", "my_credential"), a `format`, and a `meta` that says
    /// what credential it actually is — so `meta` names it.
    ///
    /// `byCredential` reads the claims credential by credential — up to
    /// four credentials and eight claims each, the rest counted — and is
    /// empty when the query names no claims at all.
    private static func dcqlCredentials(_ json: [String: Any])
        -> (names: [String], formats: [String], claims: [String], byCredential: [String], biometric: [String]) {
        guard let credentials = json["credentials"] as? [[String: Any]] else { return ([], [], [], [], []) }
        var names: [String] = []
        var formats: [String] = []
        var claims: [String] = []
        var byCredential: [String] = []
        var biometric: [String] = []
        for entry in credentials {
            let format = nonEmpty(entry["format"] as? String)
            let name = dcqlName(entry, format: format)
            names.append(name)
            if let format { formats.append(format) }
            var spoken: [String] = []
            for claim in entry["claims"] as? [[String: Any]] ?? [] {
                if let path = claim["path"] as? [Any],
                   let shown = claimPath(path, mdoc: format == "mso_mdoc"),
                   let leaf = claimLeaf(path) {
                    claims.append(shown)
                    let said = leaf.replacingOccurrences(of: "_", with: " ")
                    spoken.append(said)
                    if isBiometric(leaf) { biometric.append(said) }
                }
            }
            spoken = dedupe(spoken)
            if spoken.isEmpty {
                byCredential.append(name)
            } else {
                let shown = spoken.prefix(8).joined(separator: ", ")
                byCredential.append((spoken.count > 8 ? "\(shown) + \(spoken.count - 8) more" : shown) + " from \(name)")
            }
        }
        if claims.isEmpty {
            byCredential = []
        } else if byCredential.count > 4 {
            byCredential = Array(byCredential.prefix(4)) + ["+ \(byCredential.count - 4) more"]
        }
        return (names, formats, claims, byCredential, biometric)
    }

    /// The last name in a claims path — `street_address` of
    /// `["address", "street_address"]`, the element of an mdoc path.
    private static func claimLeaf(_ path: [Any]) -> String? {
        path.compactMap { $0 as? String }.filter { !$0.isEmpty }.last
    }

    /// A portrait (ISO/IEC 18013-5 and the PID's mdoc), the PID's SD-JWT
    /// `picture`, a signature image or any ISO biometric template.
    private static func isBiometric(_ leaf: String) -> Bool {
        let name = leaf.lowercased()
        return ["portrait", "picture", "signature_usual_mark", "fingerprint", "iris"].contains(name)
            || name.hasPrefix("biometric_template")
    }

    /// `meta.vct_values` (SD-JWT VC), `meta.doctype_value` (mdoc) or
    /// `meta.type_values` (W3C VC) first, then the `id`, then the format.
    private static func dcqlName(_ entry: [String: Any], format: String?) -> String {
        if let meta = entry["meta"] as? [String: Any] {
            if let vct = meta["vct_values"] as? [String], let first = nonEmpty(vct.first) {
                return typeName(first)
            }
            if let doctype = nonEmpty(meta["doctype_value"] as? String) {
                return typeName(doctype)
            }
            if let types = meta["type_values"] as? [[String]], let last = nonEmpty(types.first?.last) {
                return typeName(last)
            }
        }
        if let id = nonEmpty(entry["id"] as? String) { return typeName(id) }
        return format ?? "credential"
    }

    /// A claims path pointer (§7) as a person reads it: its names joined
    /// with dots; array indices and the `null` wildcard are dropped. An mdoc
    /// path is `[namespace, element]`, and the element is what matters.
    private static func claimPath(_ path: [Any], mdoc: Bool) -> String? {
        let names = path.compactMap { $0 as? String }.filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }
        if mdoc, path.count == 2, names.count == 2 { return names[1] }
        return names.joined(separator: ".")
    }

    private static func presentationDefinitionCredentials(_ json: [String: Any]) -> [String] {
        guard let descriptors = json["input_descriptors"] as? [[String: Any]] else { return [] }
        return descriptors.map { descriptor in
            if let name = descriptor["name"] as? String, !name.isEmpty { return name }
            if let id = descriptor["id"] as? String, !id.isEmpty { return typeName(id) }
            if let fields = descriptor["constraints"] as? [String: Any],
               let arr = fields["fields"] as? [[String: Any]],
               let path = arr.first?["path"] as? [String], let first = path.first {
                return first
            }
            return "credential"
        }
    }

    // MARK: Naming

    /// Known `vct` / doctype / credential-configuration identifiers.
    /// Unmatched ones are shown verbatim rather than guessed at.
    static func typeName(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "Not stated" }
        var key = raw.lowercased()
        if let known = knownTypes[key] { return known }
        if hasASCIIPrefix(key, eudiPrefix) {
            // The EU reference issuer names its credential configurations
            // `<attestation>_<format>`: `eu.europa.ec.eudi.pid_mdoc`.
            if let suffix = configurationSuffixes.first(where: { hasASCIISuffix(key, $0) }) {
                key = String(decoding: key.utf8.dropLast(suffix.utf8.count), as: UTF8.self)
            }
            if let alias = configurationAliases[dropASCIIPrefix(key, eudiPrefix)],
               let known = knownTypes[alias] {
                return known
            }
        }
        if hasASCIIPrefix(key, "urn:eudi:pid:") {
            // A national PID extends the EU type: `urn:eudi:pid:de:1`.
            let country = text(dropASCIIPrefix(key, "urn:eudi:pid:"), before: ":")
            if country.utf8.count == 2, country.utf8.allSatisfy({ $0 >= 0x61 && $0 <= 0x7A }) {
                return "EU Digital Identity — PID (\(country.uppercased()))"
            }
        }
        // Families: every `urn:eu.europa.ec.eudi:*` is an eIDAS attribute set.
        if hasASCIIPrefix(key, "urn:eu.europa.ec.eudi:") || hasASCIIPrefix(key, eudiPrefix)
            || hasASCIIPrefix(key, "urn:eudi:") {
            // The interesting part is the attribute-set name: the last
            // non-numeric segment of `urn:eu.europa.ec.eudi:pid:1`.
            let separators: Set<Unicode.Scalar> = [":", ".", "/"]
            let parts = key.unicodeScalars.split(whereSeparator: { separators.contains($0) })
                .map { String(String.UnicodeScalarView($0)) }
            if let leaf = parts.reversed().first(where: { part in
                !part.isEmpty && !part.utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 }
            }) {
                return "eIDAS \(leaf.replacingOccurrences(of: "_", with: " ").uppercased()) attribute set"
            }
            return "eIDAS attribute set"
        }
        if hasASCIIPrefix(key, "https://") || hasASCIIPrefix(key, "http://") {
            if let host = host(of: raw), host != ShownHost.unusual { return host }
            return raw
        }
        return raw
    }

    static func isKnownType(_ raw: String) -> Bool {
        knownTypes[raw.lowercased()] != nil
    }

    /// No list of attributes in the name: a request shows it next to what
    /// it asks for, and a PID can hold far more than a name, a birth date
    /// and a nationality.
    private static let pidName = "EU Digital Identity — PID"
    private static let ehicName = "European Health Insurance Card"

    /// Lower-cased keys. The PID and EHIC identifiers are the ARF's and the
    /// EU reference issuer's (`urn:eudi:pid:1` since ARF 1.8; the older
    /// `urn:eu.europa.ec.eudi:pid:1` is still issued); the ISO doctypes are
    /// the ones OpenID4VP 1.0's own DCQL examples request.
    private static let knownTypes: [String: String] = [
        "urn:eudi:pid:1":                           pidName,
        "urn:eu.europa.ec.eudi:pid:1":              pidName,
        "eu.europa.ec.eudi.pid.1":                  pidName,
        "urn:eu.europa.ec.eudi:pid:1:strict":       "EU Digital Identity — PID (full)",
        "urn:eu.europa.ec.eudi:attestation:1":      "eIDAS attribute attestation",
        "urn:eu.europa.ec.eudi:attest:1":           "eIDAS attribute attestation",
        "urn:eudi:ehic:1":                          ehicName,
        "urn:eu.europa.ec.eudi:ehic:1":             ehicName,
        "eu.europa.ec.eudi.ehic.1":                 ehicName,
        "urn:eu.europa.ec.eudi:age:1":              "eIDAS age attribute set",
        "urn:eu.europa.ec.eudi:mdl:1":              "eIDAS driving licence attributes",
        "urn:eu.europa.ec.eudi:attributes:1":       "eIDAS general attributes",
        "org.iso.18013.5.1.mdl":                    "Mobile driving licence (ISO 18013-5)",
        "org.iso.23220.photoid.1":                  "Photo ID (ISO/IEC 23220)",
        "org.iso.23220.2.photoid.1":                "Photo ID (ISO/IEC 23220)",
        "org.iso.7367.1.mvrc":                      "Vehicle registration certificate (ISO 7367)",
        "identity_proof_request":                   "Identity proof request",
        "high_age_request":                         "Age verification request",
        "email_proof_request":                      "Email ownership proof",
        "phone_proof_request":                      "Phone ownership proof",
        "wallet_unit_token":                        "Wallet attestation",
    ]

    private static let eudiPrefix = "eu.europa.ec.eudi."

    /// Longest first: `_mdoc_deferred` must not lose only its `_mdoc`.
    private static let configurationSuffixes = ["_mdoc_deferred", "_vc_sd_jwt", "_sd_jwt_vc", "_mdoc"]

    /// Configuration names whose attestation is not `eu.europa.ec.eudi.<name>.1`.
    private static let configurationAliases: [String: String] = [
        "pid": "eu.europa.ec.eudi.pid.1",
        "ehic": "eu.europa.ec.eudi.ehic.1",
        "mdl": "org.iso.18013.5.1.mdl",
        "photoid": "org.iso.23220.photoid.1",
    ]

    /// OpenID4VP `scope` shorthand — the EUDI reference implementation uses
    /// terse scope names rather than full `vct` URNs. A scope that is a
    /// credential identifier reads as one; anything else is title-cased.
    static func scopeName(_ scope: String) -> String {
        let named = typeName(scope)
        if !scope.isEmpty, named != scope { return named }
        return scope.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK: Small utilities

    /// `scheme` and everything after its `:`, split on the byte so a
    /// combining mark after the colon cannot move it.
    private static func splitScheme(_ raw: String) -> (String, String)? {
        guard let colon = raw.utf8.firstIndex(of: UInt8(ascii: ":")) else { return nil }
        return (String(decoding: raw.utf8[..<colon], as: UTF8.self),
                String(decoding: raw.utf8[raw.utf8.index(after: colon)...], as: UTF8.self))
    }

    private static func hasASCIIPrefix(_ s: String, _ prefix: String) -> Bool {
        s.utf8.starts(with: prefix.utf8)
    }

    private static func hasASCIISuffix(_ s: String, _ suffix: String) -> Bool {
        s.utf8.count >= suffix.utf8.count && s.utf8.reversed().starts(with: suffix.utf8.reversed())
    }

    private static func dropASCIIPrefix(_ s: String, _ prefix: String) -> String {
        guard hasASCIIPrefix(s, prefix) else { return s }
        return String(decoding: s.utf8.dropFirst(prefix.utf8.count), as: UTF8.self)
    }

    /// Everything before the first `separator` byte (all of `s` without one).
    private static func text(_ s: String, before separator: Unicode.Scalar) -> String {
        guard let end = s.utf8.firstIndex(of: UInt8(separator.value)) else { return s }
        return String(decoding: s.utf8[..<end], as: UTF8.self)
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }

    private static func jsonObject(fromString raw: String) -> [String: Any]? {
        PayloadCodec.jsonObject(fromJSONData: Data(raw.utf8))
    }

    /// A query parameter carries a JSON document as text; inside a Request
    /// Object the same parameter is the JSON object itself.
    private static func jsonDocument(_ value: Any?) -> [String: Any]? {
        if let text = value as? String { return jsonObject(fromString: text) }
        return value as? [String: Any]
    }

    /// The claims of a compact JWS, unverified.
    private static func jwtPayload(_ jwt: String) -> [String: Any]? {
        let segments = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return nil }
        return PayloadCodec.jsonObject(fromBase64URL: String(segments[1]))
    }

    /// A JSON integer literal. `JSONSerialization` hands back `NSNumber`,
    /// which would also turn `true` or `4.0` into an `Int`; the Android
    /// reader keeps those apart, and so does this.
    private static func jsonInteger(_ value: Any?) -> Int? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              String(cString: n.objCType) == "q" else { return nil }
        return n.intValue
    }

    /// A JSON `true` / `false` — not the numbers 1 and 0.
    private static func jsonBool(_ value: Any?) -> Bool? {
        guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
        return n.boolValue
    }

    /// The host a URL-valued parameter names (see `ShownHost`); nil for a
    /// URN or anything that is not a `scheme://` address.
    private static func host(of raw: String) -> String? {
        if hasASCIIPrefix(raw, "urn:") { return nil }
        return ShownHost.of(raw)
    }

    /// The last instant `iat` / `exp` may name: 9999-12-31T23:59:59Z.
    private static let latestDate: Double = 253_402_300_799

    /// `iat` / `exp`: epoch seconds as a JSON number (`JSONSerialization`
    /// hands back `NSNumber`, booleans included, so they are turned away)
    /// or as a string of ASCII digits with at most one fraction, between
    /// 1970 and the end of 9999. Anything else is no date: Foundation
    /// would print NaN, an infinity or 1e300 as an empty row, `Double`
    /// reads "nan" and "inf", and Kotlin saturates the same values to
    /// year 292278994 — a different meaningless date on each phone.
    private static func date(from value: Any?) -> Date? {
        let seconds: Double
        if let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() {
            seconds = n.doubleValue
        } else if let s = value as? String, isDecimalNumeral(s), let d = Double(s) {
            seconds = d
        } else {
            return nil
        }
        guard seconds.isFinite, seconds >= 0, seconds <= latestDate else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// `123` or `123.45`: ASCII digits, optionally one `.` and more digits.
    private static func isDecimalNumeral(_ s: String) -> Bool {
        let parts = s.utf8.split(separator: UInt8(ascii: "."), omittingEmptySubsequences: false)
        return (1...2).contains(parts.count)
            && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0 >= 0x30 && $0 <= 0x39 } }
    }

    private static func dedupe(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }
}
