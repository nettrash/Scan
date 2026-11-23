//
//  ScanTests.swift
//  ScanTests
//
//  Created by nettrash on 16/09/2023.
//

import CoreNFC
import XCTest
@testable import Scan

final class ScanTests: XCTestCase {

    // MARK: - URL

    func testParsesHttpsURL() {
        let p = ScanPayloadParser.parse("https://nettrash.me")
        if case .url(let u) = p {
            XCTAssertEqual(u.absoluteString, "https://nettrash.me")
        } else {
            XCTFail("Expected .url, got \(p)")
        }
    }

    func testNonURLFallsBackToText() {
        let p = ScanPayloadParser.parse("not a url, just text")
        if case .text(let s) = p {
            XCTAssertEqual(s, "not a url, just text")
        } else {
            XCTFail("Expected .text, got \(p)")
        }
    }

    // MARK: - Wi-Fi

    func testParsesWifi() {
        let p = ScanPayloadParser.parse("WIFI:T:WPA;S:HomeNet;P:supersecret;H:false;;")
        if case .wifi(let ssid, let password, let security, let hidden) = p {
            XCTAssertEqual(ssid, "HomeNet")
            XCTAssertEqual(password, "supersecret")
            XCTAssertEqual(security, "WPA")
            XCTAssertFalse(hidden)
        } else {
            XCTFail("Expected .wifi, got \(p)")
        }
    }

    func testParsesWifiWithEscapedSemicolon() {
        // Password contains an escaped ';'
        let p = ScanPayloadParser.parse(#"WIFI:T:WPA;S:Cafe;P:p\;ass;;"#)
        if case .wifi(_, let password, _, _) = p {
            XCTAssertEqual(password, "p;ass")
        } else {
            XCTFail("Expected .wifi, got \(p)")
        }
    }

    // MARK: - mailto / tel / sms

    func testParsesMailto() {
        let p = ScanPayloadParser.parse("mailto:hi@example.com?subject=Hello&body=World")
        if case .email(let address, let subject, let body) = p {
            XCTAssertEqual(address, "hi@example.com")
            XCTAssertEqual(subject, "Hello")
            XCTAssertEqual(body, "World")
        } else {
            XCTFail("Expected .email, got \(p)")
        }
    }

    func testParsesTel() {
        let p = ScanPayloadParser.parse("tel:+15551234567")
        if case .phone(let n) = p {
            XCTAssertEqual(n, "+15551234567")
        } else {
            XCTFail("Expected .phone, got \(p)")
        }
    }

    func testParsesSMSTo() {
        let p = ScanPayloadParser.parse("smsto:+15551234567:Howdy")
        if case .sms(let num, let body) = p {
            XCTAssertEqual(num, "+15551234567")
            XCTAssertEqual(body, "Howdy")
        } else {
            XCTFail("Expected .sms, got \(p)")
        }
    }

    // MARK: - geo

    func testParsesGeo() {
        let p = ScanPayloadParser.parse("geo:37.3349,-122.0090?q=Apple+Park")
        if case .geo(let lat, let lon, let q) = p {
            XCTAssertEqual(lat, 37.3349, accuracy: 0.0001)
            XCTAssertEqual(lon, -122.0090, accuracy: 0.0001)
            XCTAssertEqual(q, "Apple+Park")
        } else {
            XCTFail("Expected .geo, got \(p)")
        }
    }

    // MARK: - vCard / MECARD

    func testParsesMECard() {
        let p = ScanPayloadParser.parse("MECARD:N:Doe,Jane;TEL:+15551234567;EMAIL:jane@example.com;;")
        if case .contact(let c) = p {
            XCTAssertEqual(c.fullName, "Jane Doe")
            XCTAssertEqual(c.phones, ["+15551234567"])
            XCTAssertEqual(c.emails, ["jane@example.com"])
        } else {
            XCTFail("Expected .contact, got \(p)")
        }
    }

    func testParsesVCard() {
        let v = """
        BEGIN:VCARD
        VERSION:3.0
        FN:Jane Doe
        TEL;TYPE=CELL:+15551234567
        EMAIL:jane@example.com
        END:VCARD
        """
        let p = ScanPayloadParser.parse(v)
        if case .contact(let c) = p {
            XCTAssertEqual(c.fullName, "Jane Doe")
            XCTAssertEqual(c.phones, ["+15551234567"])
            XCTAssertEqual(c.emails, ["jane@example.com"])
        } else {
            XCTFail("Expected .contact, got \(p)")
        }
    }

    // MARK: - Product codes

    func testEAN13ProductCode() {
        let p = ScanPayloadParser.parse("4006381333931", symbology: .ean13)
        if case .productCode(let code, let system) = p {
            XCTAssertEqual(code, "4006381333931")
            XCTAssertEqual(system, "EAN-13")
        } else {
            XCTFail("Expected .productCode, got \(p)")
        }
    }

    func testKindLabels() {
        XCTAssertEqual(ScanPayload.text("hi").kindLabel, "Text")
        XCTAssertEqual(ScanPayload.url(URL(string: "https://x")!).kindLabel, "URL")
        XCTAssertEqual(ScanPayload.productCode("123", system: "EAN-13").kindLabel, "Product")
    }

    // MARK: - Composer round-trips

    /// Compose a vCard from structured fields, parse it back, and assert the
    /// fields survived the round-trip.
    func testVCardComposerRoundTrip() {
        let composed = CodeComposer.vCard(
            fullName: "Jane Doe",
            phone: "+15551234567",
            email: "jane@example.com",
            organization: "Acme Inc."
        )
        let payload = ScanPayloadParser.parse(composed)
        guard case .contact(let c) = payload else {
            return XCTFail("Expected .contact, got \(payload)")
        }
        XCTAssertEqual(c.fullName, "Jane Doe")
        XCTAssertEqual(c.phones, ["+15551234567"])
        XCTAssertEqual(c.emails, ["jane@example.com"])
        XCTAssertEqual(c.organization, "Acme Inc.")
    }

    /// Compose a Wi-Fi payload and parse it back.
    func testWifiComposerRoundTrip() {
        let composed = CodeComposer.wifi(
            ssid: "Home Net",
            password: "p@ss;wo,rd",
            security: .wpa,
            hidden: true
        )
        XCTAssertTrue(composed.hasPrefix("WIFI:"))
        XCTAssertTrue(composed.hasSuffix(";;"))

        let payload = ScanPayloadParser.parse(composed)
        guard case .wifi(let ssid, let pwd, let sec, let hidden) = payload else {
            return XCTFail("Expected .wifi, got \(payload)")
        }
        XCTAssertEqual(ssid, "Home Net")
        XCTAssertEqual(pwd, "p@ss;wo,rd")
        XCTAssertEqual(sec, "WPA")
        XCTAssertTrue(hidden)
    }

    /// Open networks should not include the password field.
    func testWifiComposerOpenNetworkSkipsPassword() {
        let composed = CodeComposer.wifi(
            ssid: "Cafe",
            password: "ignored",
            security: .open,
            hidden: false
        )
        XCTAssertFalse(composed.contains(";P:"),
                       "Open networks must not embed a password field")
    }

    // MARK: - Bank / receipt payloads

    func testParsesEPCSEPAPayment() {
        // Canonical EPC v002 example (no BIC).
        let raw = """
        BCD
        002
        1
        SCT

        Acme GmbH
        DE89370400440532013000
        EUR12.34
        OTHR

        Invoice 2024-0001
        """
        let p = ScanPayloadParser.parse(raw)
        guard case .epcPayment(let epc) = p else {
            return XCTFail("Expected .epcPayment, got \(p)")
        }
        XCTAssertEqual(epc.beneficiaryName, "Acme GmbH")
        XCTAssertEqual(epc.iban, "DE89370400440532013000")
        XCTAssertEqual(epc.currency, "EUR")
        XCTAssertEqual(epc.amount, "12.34")
        XCTAssertEqual(epc.unstructuredRemittance, "Invoice 2024-0001")
    }

    func testParsesRussianUnifiedPayment() {
        let raw = "ST00012|Name=ООО Ромашка|PersonalAcc=40702810000000000000|BankName=Сбербанк|BIC=044525225|CorrespAcc=30101810400000000225|PayeeINN=7707083893|Sum=12345|Purpose=Оплата по счёту 7"
        let p = ScanPayloadParser.parse(raw)
        guard case .ruPayment(let ru) = p else {
            return XCTFail("Expected .ruPayment, got \(p)")
        }
        XCTAssertEqual(ru.version, "ST00012")

        // Spot-check some labelled fields the UI will render.
        let dict = Dictionary(
            uniqueKeysWithValues: ru.labelledFields.map { ($0.label, $0.value) }
        )
        XCTAssertEqual(dict["Recipient"], "ООО Ромашка")
        XCTAssertEqual(dict["Account"], "40702810000000000000")
        XCTAssertEqual(dict["BIC"], "044525225")
        XCTAssertEqual(dict["Recipient INN"], "7707083893")
        // Sum is in kopecks → rubles.
        XCTAssertEqual(dict["Amount"], "123.45 ₽")
    }

    func testParsesFNSReceipt() {
        let raw = "t=20231225T1530&s=1234.56&fn=8710000100000123&i=12345&fp=987654321&n=1"
        let p = ScanPayloadParser.parse(raw)
        guard case .fnsReceipt(let r) = p else {
            return XCTFail("Expected .fnsReceipt, got \(p)")
        }
        XCTAssertEqual(r.rawTimestamp, "20231225T1530")
        XCTAssertEqual(r.sum, "1234.56")
        XCTAssertEqual(r.fiscalNumber, "8710000100000123")
        XCTAssertEqual(r.receiptNumber, "12345")
        XCTAssertEqual(r.fiscalSign, "987654321")
        XCTAssertEqual(r.receiptTypeLabel, "Sale")
        XCTAssertNotNil(r.date, "Should parse the timestamp into a Date")
    }

    func testParsesEMVCoMerchantQR() {
        // A minimal-but-valid EMVCo payload with merchant info, currency,
        // amount, country, name, city, and a CRC. Lengths are 2-digit decimal.
        // 00 02 01            Payload format
        // 01 02 12            Initiation: dynamic
        // 52 04 5812          Merchant category
        // 53 03 986           Currency BRL
        // 54 05 12.34         Amount
        // 58 02 BR            Country
        // 59 09 ACME LTDA     Merchant name (9 chars)
        // 60 08 SAOPAULO      Merchant city (8 chars)
        // 63 04 ABCD          CRC (placeholder)
        let raw = "000201"
            + "010212"
            + "52045812"
            + "5303986"
            + "540512.34"
            + "5802BR"
            + "5909ACME LTDA"
            + "6008SAOPAULO"
            + "6304ABCD"
        let p = ScanPayloadParser.parse(raw)
        guard case .emvPayment(let emv) = p else {
            return XCTFail("Expected .emvPayment, got \(p)")
        }
        XCTAssertEqual(emv.merchantName, "ACME LTDA")
        XCTAssertEqual(emv.merchantCity, "SAOPAULO")
        XCTAssertEqual(emv.country, "BR")
        XCTAssertEqual(emv.amount, "12.34")
        XCTAssertEqual(emv.currency, "986")
        // Currency renders via ISO mapping in labelled fields.
        let labels = Dictionary(
            uniqueKeysWithValues: emv.labelledFields.map { ($0.label, $0.value) }
        )
        XCTAssertEqual(labels["Currency"], "BRL (986)")
    }

    /// Detection priority: BCD-prefixed strings are EPC, not generic text,
    /// so a Wi-Fi or URL test should still take precedence over EPC parsing
    /// only if the prefix matches their own pattern.
    func testEPCIsRecognisedBeforeGenericText() {
        let raw = "BCD\n001\n1\nSCT\n\nAcme\nDE12345\nEUR1.00\n\n\nNote\n"
        let p = ScanPayloadParser.parse(raw)
        if case .text = p { XCTFail("Should not fall through to .text") }
    }

    // MARK: - Crypto wallet URIs

    func testParsesBitcoinURI() {
        let raw = "bitcoin:1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2?amount=0.0001&label=Donation&message=Thanks"
        let p = ScanPayloadParser.parse(raw)
        guard case .crypto(let c) = p else {
            return XCTFail("Expected .crypto, got \(p)")
        }
        XCTAssertEqual(c.chain, .bitcoin)
        XCTAssertEqual(c.address, "1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2")
        XCTAssertEqual(c.amount, "0.0001")
        XCTAssertEqual(c.label, "Donation")
        XCTAssertEqual(c.message, "Thanks")
    }

    func testParsesEthereumURIWithChainID() {
        let raw = "ethereum:0x89205A3A3b2A69De6Dbf7f01ED13B2108B2c43e7@137?value=1e18"
        let p = ScanPayloadParser.parse(raw)
        guard case .crypto(let c) = p else {
            return XCTFail("Expected .crypto, got \(p)")
        }
        XCTAssertEqual(c.chain, .ethereum)
        XCTAssertEqual(c.address, "0x89205A3A3b2A69De6Dbf7f01ED13B2108B2c43e7")
        XCTAssertEqual(c.chainId, "137")
        XCTAssertEqual(c.amount, "1e18")
    }

    func testParsesLightningInvoice() {
        let raw = "lightning:lnbc1pvjluezpp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdpl"
        let p = ScanPayloadParser.parse(raw)
        guard case .crypto(let c) = p else {
            return XCTFail("Expected .crypto, got \(p)")
        }
        XCTAssertEqual(c.chain, .lightning)
        XCTAssertTrue(c.address.hasPrefix("lnbc"))
        XCTAssertNil(c.amount)
    }

    // MARK: - Swiss QR-bill

    func testParsesSwissQRBill() {
        // 31-line minimum QR-bill with QRR reference and unstructured message.
        let raw = """
        SPC
        0200
        1
        CH4431999123000889012
        S
        Robert Schneider AG
        Rue du Lac
        1268
        2501
        Biel
        CH







        199.95
        CHF
        S
        Pia-Maria Rutschmann-Schnyder
        Grosse Marktgasse
        28
        9400
        Rorschach
        CH
        QRR
        210000000003139471430009017
        Order of 19 May 2024
        EPD
        """
        let p = ScanPayloadParser.parse(raw)
        guard case .swissQRBill(let s) = p else {
            return XCTFail("Expected .swissQRBill, got \(p)")
        }
        XCTAssertEqual(s.iban, "CH4431999123000889012")
        XCTAssertEqual(s.creditor?.name, "Robert Schneider AG")
        XCTAssertEqual(s.amount, "199.95")
        XCTAssertEqual(s.currency, "CHF")
        XCTAssertEqual(s.ultimateDebtor?.name, "Pia-Maria Rutschmann-Schnyder")
        XCTAssertEqual(s.referenceType, "QRR")
        XCTAssertEqual(s.reference, "210000000003139471430009017")
        XCTAssertEqual(s.unstructuredMessage, "Order of 19 May 2024")
    }

    // MARK: - iCalendar

    func testParsesICalendarEvent() {
        let raw = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//EN
        BEGIN:VEVENT
        UID:abc-123
        SUMMARY:Quarterly review
        DTSTART:20260115T140000Z
        DTEND:20260115T150000Z
        LOCATION:Conference Room 4
        DESCRIPTION:Discuss Q1 plans
        ORGANIZER:mailto:alice@example.com
        URL:https://example.com/meeting
        END:VEVENT
        END:VCALENDAR
        """
        let p = ScanPayloadParser.parse(raw)
        guard case .calendar(let c) = p else {
            return XCTFail("Expected .calendar, got \(p)")
        }
        XCTAssertEqual(c.summary, "Quarterly review")
        XCTAssertEqual(c.location, "Conference Room 4")
        XCTAssertEqual(c.description, "Discuss Q1 plans")
        XCTAssertEqual(c.organizer, "alice@example.com")
        XCTAssertEqual(c.url?.absoluteString, "https://example.com/meeting")
        XCTAssertNotNil(c.startDate)
        XCTAssertNotNil(c.endDate)
        // Start in UTC: 2026-01-15 14:00 UTC.
        let comps = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(identifier: "UTC")!, from: c.startDate!)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 1)
        XCTAssertEqual(comps.day, 15)
        XCTAssertEqual(comps.hour, 14)
    }

    // MARK: - Serbian SUF fiscal receipt

    func testParsesSerbianSUFReceipt() {
        let raw = "https://suf.purs.gov.rs/v/?vl=A1F2VktKTjZUNFY3MEs1WmVsLVNlY3JldA"
        let p = ScanPayloadParser.parse(raw)
        guard case .sufReceipt(let r) = p else {
            return XCTFail("Expected .sufReceipt, got \(p)")
        }
        XCTAssertEqual(r.url.absoluteString, raw)
    }

    func testNonSerbianSUFURLFallsThroughToURL() {
        // Make sure we don't classify any old https URL as a Serbian receipt.
        let raw = "https://example.com/v/?vl=anything"
        let p = ScanPayloadParser.parse(raw)
        if case .sufReceipt = p { XCTFail("Should be .url, not .sufReceipt") }
    }

    // MARK: - Serbian NBS IPS QR

    func testParsesNBSIPSPrintedBill() {
        // PR — printed bill on a utility invoice.
        let raw = "K:PR|V:01|C:1|R:160600000007029817|N:Acme%20DOO|I:RSD250%2C00|SF:289|S:Test%20payment|RO:00%201234567890"
        let p = ScanPayloadParser.parse(raw)
        guard case .ipsPayment(let ips) = p else {
            return XCTFail("Expected .ipsPayment, got \(p)")
        }
        XCTAssertEqual(ips.kind, "PR")
        XCTAssertEqual(ips.recipientAccount, "160600000007029817")
        // recipientName is the raw value; labelled fields decode percent.
        XCTAssertEqual(ips.recipientName, "Acme%20DOO")

        let labels = Dictionary(
            uniqueKeysWithValues: ips.labelledFields.map { ($0.label, $0.value) }
        )
        XCTAssertEqual(labels["Recipient"], "Acme DOO")
        XCTAssertEqual(labels["Amount"], "RSD250,00")
        XCTAssertEqual(labels["Code"], "Bill payment (PR)")
        XCTAssertEqual(labels["Account"], "160600000007029817")
    }

    func testRejectsInvalidIPSPayload() {
        // Missing required R and V fields.
        let raw = "K:PR|C:1|N:Acme"
        let p = ScanPayloadParser.parse(raw)
        if case .ipsPayment = p { XCTFail("Should not be .ipsPayment without required fields") }
    }

    // MARK: - UPI

    func testParsesUPIPayURI() {
        let raw = "upi://pay?pa=merchant@upi&pn=Acme%20Store&am=199.99&cu=INR&tn=Order%20%23123"
        let p = ScanPayloadParser.parse(raw)
        guard case .upiPayment(let upi) = p else {
            return XCTFail("Expected .upiPayment, got \(p)")
        }
        XCTAssertEqual(upi.payeeAddress, "merchant@upi")
        XCTAssertEqual(upi.payeeName, "Acme Store")
        XCTAssertEqual(upi.amount, "199.99")
        XCTAssertEqual(upi.currency, "INR")
        XCTAssertEqual(upi.note, "Order #123")
    }

    func testRejectsUPIWithoutPayeeAddress() {
        let raw = "upi://pay?am=100&cu=INR"
        let p = ScanPayloadParser.parse(raw)
        if case .upiPayment = p { XCTFail("Should not be .upiPayment without payee address") }
    }

    // MARK: - Czech SPD

    func testParsesCzechSPD() {
        let raw = "SPD*1.0*ACC:CZ4912340000004567890123*AM:1500.00*CC:CZK*MSG:Faktura+2024+09*X-VS:202409*"
        let p = ScanPayloadParser.parse(raw)
        guard case .czechSPD(let spd) = p else {
            return XCTFail("Expected .czechSPD, got \(p)")
        }
        XCTAssertEqual(spd.version, "1.0")
        XCTAssertEqual(spd.iban, "CZ4912340000004567890123")
        XCTAssertEqual(spd.amount, "1500.00")
        XCTAssertEqual(spd.currency, "CZK")
        // `+` decoded to space per SPD escaping rules.
        XCTAssertEqual(spd.message, "Faktura 2024 09")
        XCTAssertEqual(spd.variableSymbol, "202409")
    }

    // MARK: - Slovak Pay by Square

    func testRecognisesPayBySquare() {
        // 32+ char base32hex string starting with a valid header.
        let raw = "0000A00000000000000000000000000000000000ABCDEF"
        let p = ScanPayloadParser.parse(raw)
        guard case .paBySquare = p else {
            return XCTFail("Expected .paBySquare, got \(p)")
        }
    }

    func testDoesNotMisclassifyPayBySquareLookalike() {
        // Has the right length but wrong header.
        let raw = "ABCDEF0000000000000000000000000000000000ABCDEF"
        let p = ScanPayloadParser.parse(raw)
        if case .paBySquare = p { XCTFail("Should not classify as Pay by Square") }
    }

    // MARK: - Regional URI schemes

    func testParsesBezahlcode() {
        let raw = "bank://singlepaymentsepa?name=Acme%20GmbH&iban=DE89370400440532013000&amount=42.00&currency=EUR&reason=Invoice%20%2342"
        let p = ScanPayloadParser.parse(raw)
        guard case .regionalPayment(let r) = p else {
            return XCTFail("Expected .regionalPayment, got \(p)")
        }
        XCTAssertEqual(r.scheme, .bezahlcode)
        let labels = Dictionary(uniqueKeysWithValues: r.parsed.map { ($0.label, $0.value) })
        XCTAssertEqual(labels["Beneficiary"], "Acme GmbH")
        XCTAssertEqual(labels["IBAN"], "DE89370400440532013000")
        XCTAssertEqual(labels["Amount"], "42.00")
        XCTAssertEqual(labels["Purpose"], "Invoice #42")
    }

    func testParsesSwishWithBase64JSON() {
        let json = #"{"payee":"+46701234567","amount":"100","message":"Lunch"}"#
        let b64 = Data(json.utf8).base64EncodedString()
        let raw = "swish://payment?data=\(b64)"
        let p = ScanPayloadParser.parse(raw)
        guard case .regionalPayment(let r) = p else {
            return XCTFail("Expected .regionalPayment, got \(p)")
        }
        XCTAssertEqual(r.scheme, .swish)
        let labels = Dictionary(uniqueKeysWithValues: r.parsed.map { ($0.label, $0.value) })
        XCTAssertEqual(labels["Payee"], "+46701234567")
        XCTAssertEqual(labels["Amount"], "100")
        XCTAssertEqual(labels["Message"], "Lunch")
    }

    /// Swish's data= JSON is refused past 64 nested containers
    /// (PayloadCodec.jsonNestingIsWithinLimit): 64 still parses, 65 shows
    /// the raw blob. Mirrors Android's swishJsonNestingIsCappedLikeEveryOtherBlob.
    func testSwishJSONNestingIsCappedLikeEveryOtherBlob() {
        func swish(_ arrays: Int) -> RegionalPaymentPayload? {
            let json = #"{"payee":"+46701234567","x":"#
                + String(repeating: "[", count: arrays) + String(repeating: "]", count: arrays) + "}"
            let raw = "swish://payment?data=\(Data(json.utf8).base64EncodedString())"
            guard case .regionalPayment(let r) = ScanPayloadParser.parse(raw) else { return nil }
            return r
        }
        // The object plus 63 arrays = 64 containers: still parsed.
        let shallow = Dictionary(uniqueKeysWithValues: (swish(63)?.parsed ?? []).map { ($0.label, $0.value) })
        XCTAssertEqual(shallow["Payee"], "+46701234567")
        // One more: shown raw, never parsed.
        XCTAssertEqual(swish(64)?.parsed.map(\.label), ["Data"])
    }

    func testRecognisesVippsURI() {
        let raw = "vipps://?phonenumber=+4791234567&amount=200&message=Pizza"
        let p = ScanPayloadParser.parse(raw)
        guard case .regionalPayment(let r) = p else {
            return XCTFail("Expected .regionalPayment, got \(p)")
        }
        XCTAssertEqual(r.scheme, .vipps)
    }

    // MARK: - EMVCo nested template drilling

    func testDrillsIntoEMVCoMerchantAccountTemplate() {
        // Merchant account info template at tag 26 carrying a Pix GUID
        // (sub-tag 00) + key (sub-tag 01).
        //   00 14 BR.GOV.BCB.PIX   (length 14)
        //   01 14 alice@bcb.gov.br (length 14)
        let guid = "BR.GOV.BCB.PIX"
        let key  = "alice@bcb.gov.br"
        precondition(guid.count == 14 && key.count == 16,
                     "EMV nested test fixture lengths drifted")
        let inner = "00" + String(format: "%02d", guid.count) + guid
                  + "01" + String(format: "%02d", key.count)  + key
        let merchantField = "26" + String(format: "%02d", inner.count) + inner
        // Surrounding minimal EMV envelope.
        let raw = "000201"           // payload format
            + "010211"               // initiation method
            + merchantField
            + "5303986"              // currency BRL
            + "5802BR"
            + "5907Test BR"
            + "6304ABCD"

        let p = ScanPayloadParser.parse(raw)
        guard case .emvPayment(let emv) = p else {
            return XCTFail("Expected .emvPayment, got \(p)")
        }
        let labels = emv.labelledFields.map { $0.label }
        XCTAssertTrue(labels.contains("Pix account (26)"),
                      "Expected the merchant-account row to be labelled with the Pix scheme")
        // Sub-fields are surfaced after the parent row with a "↳" marker.
        XCTAssertTrue(labels.contains(where: { $0.contains("Scheme GUID") }))
        XCTAssertTrue(labels.contains(where: { $0.contains("Identifier") }))
    }

    // MARK: - VEVENT all-day

    func testParsesICalendarAllDayEvent() {
        let raw = """
        BEGIN:VEVENT
        SUMMARY:Holiday
        DTSTART;VALUE=DATE:20260101
        DTEND;VALUE=DATE:20260102
        END:VEVENT
        """
        let p = ScanPayloadParser.parse(raw)
        guard case .calendar(let c) = p else {
            return XCTFail("Expected .calendar, got \(p)")
        }
        XCTAssertEqual(c.summary, "Holiday")
        XCTAssertTrue(c.allDay)
    }

    // MARK: - Edge cases & gap coverage
    //
    // Everything below this line is new on top of the 38-test core suite.
    // Each block targets a parser path the original tests didn't exercise.

    // MARK: Russian unified payment (ST00011)

    func testParsesRussianUnifiedPaymentLegacyHeader() {
        // ST00011 is the older header — same field grammar, different prefix.
        let raw = "ST00011|Name=Acme LLC|PersonalAcc=40702810000000000000|Sum=500"
        let p = ScanPayloadParser.parse(raw)
        guard case .ruPayment(let ru) = p else {
            return XCTFail("Expected .ruPayment, got \(p)")
        }
        XCTAssertEqual(ru.version, "ST00011")
        let dict = Dictionary(uniqueKeysWithValues: ru.labelledFields.map { ($0.label, $0.value) })
        XCTAssertEqual(dict["Recipient"], "Acme LLC")
        XCTAssertEqual(dict["Amount"], "5.00 ₽")
    }

    // MARK: FNS receipt — non-Sale receipt types

    func testFNSReceiptRefundType() {
        let raw = "t=20240101T1000&s=99.00&fn=8710000100000123&i=1&fp=1&n=2"
        let p = ScanPayloadParser.parse(raw)
        guard case .fnsReceipt(let r) = p else {
            return XCTFail("Expected .fnsReceipt, got \(p)")
        }
        XCTAssertEqual(r.receiptTypeLabel, "Sale refund")
    }

    func testFNSReceiptExpenseType() {
        let raw = "t=20240101T1000&s=10&fn=1&i=1&fp=1&n=3"
        let p = ScanPayloadParser.parse(raw)
        guard case .fnsReceipt(let r) = p else {
            return XCTFail("Expected .fnsReceipt, got \(p)")
        }
        XCTAssertEqual(r.receiptTypeLabel, "Expense")
    }

    // MARK: Serbian SUF receipt — host strictness

    func testParsesSerbianSUFReceiptOnSandboxSubdomain() {
        // Sandbox env — should still classify as a SUF receipt.
        let raw = "https://tap.sandbox.suf.purs.gov.rs/v/?vl=encoded"
        let p = ScanPayloadParser.parse(raw)
        guard case .sufReceipt = p else {
            return XCTFail("Sandbox subdomain should still be recognised as .sufReceipt, got \(p)")
        }
    }

    func testRejectsSUFLookalikeHost() {
        // The host `notsuf.purs.gov.rs` ends with `suf.purs.gov.rs` literally
        // but isn't a real subdomain — must not classify.
        let raw = "https://notsuf.purs.gov.rs/v/?vl=anything"
        let p = ScanPayloadParser.parse(raw)
        if case .sufReceipt = p { XCTFail("Lookalike host should fall through to .url") }
    }

    // MARK: NBS IPS — POS variants

    func testParsesNBSIPSMerchantPresentedQR() {
        // PT — merchant-presented QR at point of sale.
        let raw = "K:PT|V:01|C:1|R:160600000007029817|N:Acme%20DOO|I:RSD100"
        let p = ScanPayloadParser.parse(raw)
        guard case .ipsPayment(let ips) = p else {
            return XCTFail("Expected .ipsPayment, got \(p)")
        }
        XCTAssertEqual(ips.kind, "PT")
        let labels = Dictionary(uniqueKeysWithValues: ips.labelledFields.map { ($0.label, $0.value) })
        XCTAssertEqual(labels["Code"], "POS — merchant QR (PT)")
    }

    func testParsesNBSIPSCustomerPresentedQR() {
        // PK — customer-presented QR at point of sale.
        let raw = "K:PK|V:01|C:1|R:160600000007029817|N:Buyer|I:RSD50"
        let p = ScanPayloadParser.parse(raw)
        guard case .ipsPayment(let ips) = p else {
            return XCTFail("Expected .ipsPayment, got \(p)")
        }
        XCTAssertEqual(ips.kind, "PK")
        let labels = Dictionary(uniqueKeysWithValues: ips.labelledFields.map { ($0.label, $0.value) })
        XCTAssertEqual(labels["Code"], "POS — customer QR (PK)")
    }

    // MARK: geo / sms / mailto — minimal forms

    func testParsesGeoWithoutQuery() {
        let p = ScanPayloadParser.parse("geo:51.5074,-0.1278")
        guard case .geo(let lat, let lon, let q) = p else {
            return XCTFail("Expected .geo, got \(p)")
        }
        XCTAssertEqual(lat, 51.5074, accuracy: 0.0001)
        XCTAssertEqual(lon, -0.1278, accuracy: 0.0001)
        XCTAssertNil(q)
    }

    func testParsesSMSWithoutBody() {
        // Plain `sms:NUMBER` form — no body query.
        let p = ScanPayloadParser.parse("sms:+447400123456")
        guard case .sms(let num, let body) = p else {
            return XCTFail("Expected .sms, got \(p)")
        }
        XCTAssertEqual(num, "+447400123456")
        XCTAssertNil(body)
    }

    func testParsesMailtoWithoutQueryParameters() {
        let p = ScanPayloadParser.parse("mailto:bare@example.com")
        guard case .email(let address, let subject, let body) = p else {
            return XCTFail("Expected .email, got \(p)")
        }
        XCTAssertEqual(address, "bare@example.com")
        XCTAssertNil(subject)
        XCTAssertNil(body)
    }

    // MARK: Composer — fields not exercised by the round-trip tests

    func testVCardComposerIncludesURLField() {
        // The earlier round-trip omits `url`; verify it survives parsing.
        let composed = CodeComposer.vCard(
            fullName: "Jane Doe",
            phone: nil,
            email: nil,
            organization: nil,
            url: "https://nettrash.me"
        )
        let payload = ScanPayloadParser.parse(composed)
        guard case .contact(let c) = payload else {
            return XCTFail("Expected .contact, got \(payload)")
        }
        XCTAssertEqual(c.fullName, "Jane Doe")
        XCTAssertEqual(c.urls, ["https://nettrash.me"])
    }

    func testWifiComposerEmitsHiddenFlag() {
        let composed = CodeComposer.wifi(
            ssid: "Stealth",
            password: "x",
            security: .wpa,
            hidden: true
        )
        XCTAssertTrue(composed.contains(";H:true"),
                      "Composer must emit ;H:true for hidden networks")
    }

    // MARK: vCard — repeated fields

    func testParsesVCardWithMultiplePhonesAndEmails() {
        // Repeated TEL / EMAIL lines should both end up in the contact.
        let v = """
        BEGIN:VCARD
        VERSION:3.0
        FN:Bob Smith
        TEL;TYPE=CELL:+15551111111
        TEL;TYPE=HOME:+15552222222
        EMAIL;TYPE=WORK:bob@work.example
        EMAIL;TYPE=HOME:bob@home.example
        END:VCARD
        """
        let p = ScanPayloadParser.parse(v)
        guard case .contact(let c) = p else {
            return XCTFail("Expected .contact, got \(p)")
        }
        XCTAssertEqual(c.phones, ["+15551111111", "+15552222222"])
        XCTAssertEqual(c.emails, ["bob@work.example", "bob@home.example"])
    }

    // MARK: EMV — defensive rejection

    func testRejectsEMVWithoutPayloadFormatPrefix() {
        // EMVCo payloads must start with the Payload-Format-Indicator
        // "000201" (tag 00, length 02, value "01"). A string composed of
        // valid-looking TLV fields but missing that prefix must not
        // classify as `.emvPayment`.
        let raw = "5303123" + "5802BR" + "5907Test BR" + "6304ABCD"
        let p = ScanPayloadParser.parse(raw)
        if case .emvPayment = p {
            XCTFail("Non-prefixed input must not classify as .emvPayment, got \(p)")
        }
    }

    func testRejectsEMVWithMalformedLength() {
        // Has the right prefix, but a later TLV declares a length larger
        // than the bytes that follow. The defensive TLV decoder must bail
        // out and the parser must fall through.
        let raw = "000201" + "5399BAD" + "6304ABCD"
        let p = ScanPayloadParser.parse(raw)
        if case .emvPayment = p {
            XCTFail("Malformed-length input must not classify as .emvPayment")
        }
    }

    // MARK: UPI — mandate command

    func testParsesUPIMandateURI() {
        // The parser tolerates `mandate` in addition to `pay`.
        let raw = "upi://mandate?pa=biller@upi&pn=Subscription&am=99"
        let p = ScanPayloadParser.parse(raw)
        guard case .upiPayment(let upi) = p else {
            return XCTFail("Expected .upiPayment, got \(p)")
        }
        XCTAssertEqual(upi.payeeAddress, "biller@upi")
    }

    // MARK: Crypto — Bitcoin Cash chain identification

    func testParsesBitcoinCashURI() {
        let raw = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a?amount=1.0"
        let p = ScanPayloadParser.parse(raw)
        guard case .crypto(let c) = p else {
            return XCTFail("Expected .crypto, got \(p)")
        }
        XCTAssertEqual(c.chain, .bitcoinCash)
        XCTAssertEqual(c.amount, "1.0")
    }

    // MARK: - Pass 1: rich URLs / magnet / new chains / bare addresses

    // Magnet

    func testParsesMagnetURI() {
        let raw = "magnet:?xt=urn:btih:c12fe1c06bba254a9dc9f519b335aa7c1367a88a&dn=ubuntu-22.04.iso&xl=4294967296&tr=udp%3A%2F%2Ftracker.openbittorrent.com%3A80"
        let p = ScanPayloadParser.parse(raw)
        guard case .magnet(let m) = p else {
            return XCTFail("Expected .magnet, got \(p)")
        }
        XCTAssertEqual(m.infoHash, "c12fe1c06bba254a9dc9f519b335aa7c1367a88a")
        XCTAssertEqual(m.displayName, "ubuntu-22.04.iso")
        XCTAssertEqual(m.exactLength, 4_294_967_296)
        XCTAssertEqual(m.trackers, ["udp://tracker.openbittorrent.com:80"])
    }

    func testRejectsMagnetWithoutHashOrName() {
        let raw = "magnet:?tr=http://example.com/announce"
        let p = ScanPayloadParser.parse(raw)
        if case .magnet = p { XCTFail("Should not classify as .magnet without xt or dn") }
    }

    // Rich URLs

    func testRecognisesWhatsAppClickToChat() {
        let raw = "https://wa.me/12025551212?text=Hello%20there"
        let p = ScanPayloadParser.parse(raw)
        guard case .richURL(let r) = p else {
            return XCTFail("Expected .richURL, got \(p)")
        }
        XCTAssertEqual(r.kind, .whatsApp)
        let dict = Dictionary(uniqueKeysWithValues: r.fields.map { ($0.label, $0.value) })
        XCTAssertEqual(dict["Phone"], "12025551212")
        XCTAssertEqual(dict["Message"], "Hello there")
    }

    func testRecognisesTelegramLink() {
        let raw = "https://t.me/nettrash"
        let p = ScanPayloadParser.parse(raw)
        guard case .richURL(let r) = p, r.kind == .telegram else {
            return XCTFail("Expected Telegram .richURL, got \(p)")
        }
        let dict = Dictionary(uniqueKeysWithValues: r.fields.map { ($0.label, $0.value) })
        XCTAssertEqual(dict["Target"], "@nettrash")
    }

    func testRecognisesPkpassURL() {
        let raw = "https://example.com/passes/boarding.pkpass"
        let p = ScanPayloadParser.parse(raw)
        guard case .richURL(let r) = p, r.kind == .appleWallet else {
            return XCTFail("Expected Apple Wallet .richURL, got \(p)")
        }
        let dict = Dictionary(uniqueKeysWithValues: r.fields.map { ($0.label, $0.value) })
        XCTAssertEqual(dict["Pass file"], "boarding.pkpass")
    }

    func testRecognisesAppStoreLink() {
        let raw = "https://apps.apple.com/us/app/nettrash-scan/id6763932723"
        let p = ScanPayloadParser.parse(raw)
        guard case .richURL(let r) = p, r.kind == .appStore else {
            return XCTFail("Expected App Store .richURL, got \(p)")
        }
        let dict = Dictionary(uniqueKeysWithValues: r.fields.map { ($0.label, $0.value) })
        XCTAssertEqual(dict["App ID"], "6763932723")
    }

    func testRecognisesPlayStoreLink() {
        let raw = "https://play.google.com/store/apps/details?id=me.nettrash.scan"
        let p = ScanPayloadParser.parse(raw)
        guard case .richURL(let r) = p, r.kind == .playStore else {
            return XCTFail("Expected Play Store .richURL, got \(p)")
        }
        let dict = Dictionary(uniqueKeysWithValues: r.fields.map { ($0.label, $0.value) })
        XCTAssertEqual(dict["Package"], "me.nettrash.scan")
    }

    func testRecognisesYouTubeShortLink() {
        let raw = "https://youtu.be/dQw4w9WgXcQ"
        let p = ScanPayloadParser.parse(raw)
        guard case .richURL(let r) = p, r.kind == .youtube else {
            return XCTFail("Expected YouTube .richURL, got \(p)")
        }
        let dict = Dictionary(uniqueKeysWithValues: r.fields.map { ($0.label, $0.value) })
        XCTAssertEqual(dict["Video"], "dQw4w9WgXcQ")
    }

    func testRecognisesYouTubeWatchLink() {
        let raw = "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s"
        let p = ScanPayloadParser.parse(raw)
        guard case .richURL(let r) = p, r.kind == .youtube else {
            return XCTFail("Expected YouTube .richURL, got \(p)")
        }
        let dict = Dictionary(uniqueKeysWithValues: r.fields.map { ($0.label, $0.value) })
        XCTAssertEqual(dict["Video"], "dQw4w9WgXcQ")
    }

    func testRecognisesSpotifyTrackLink() {
        let raw = "https://open.spotify.com/track/6rqhFgbbKwnb9MLmUQDhG6"
        let p = ScanPayloadParser.parse(raw)
        guard case .richURL(let r) = p, r.kind == .spotify else {
            return XCTFail("Expected Spotify .richURL, got \(p)")
        }
        let dict = Dictionary(uniqueKeysWithValues: r.fields.map { ($0.label, $0.value) })
        XCTAssertEqual(dict["Kind"], "Track")
        XCTAssertEqual(dict["ID"], "6rqhFgbbKwnb9MLmUQDhG6")
    }

    func testGoogleMapsURLRoundsToGeo() {
        // Google's `@<lat>,<lon>,<zoom>z` form.
        let raw = "https://www.google.com/maps/place/Apple+Park/@37.3349,-122.009,17z"
        let p = ScanPayloadParser.parse(raw)
        guard case .geo(let lat, let lon, _) = p else {
            return XCTFail("Expected .geo (re-classified from rich URL), got \(p)")
        }
        XCTAssertEqual(lat, 37.3349, accuracy: 0.001)
        XCTAssertEqual(lon, -122.009, accuracy: 0.001)
    }

    func testAppleMapsURLRoundsToGeo() {
        let raw = "https://maps.apple.com/?ll=37.3349,-122.009&q=Apple+Park"
        let p = ScanPayloadParser.parse(raw)
        guard case .geo(let lat, let lon, let q) = p else {
            return XCTFail("Expected .geo, got \(p)")
        }
        XCTAssertEqual(lat, 37.3349, accuracy: 0.001)
        XCTAssertEqual(lon, -122.009, accuracy: 0.001)
        XCTAssertEqual(q, "Apple+Park")
    }

    // Crypto chains added in this pass

    func testParsesXRPURI() {
        let raw = "xrpl:r9cZA1mLK5R5Am25ArfXFmqgNwjZgnfk59"
        let p = ScanPayloadParser.parse(raw)
        guard case .crypto(let c) = p else {
            return XCTFail("Expected .crypto, got \(p)")
        }
        XCTAssertEqual(c.chain, .ripple)
    }

    func testParsesStellarURI() {
        let raw = "web+stellar:tx?xdr=AAAAAA"
        let p = ScanPayloadParser.parse(raw)
        guard case .crypto(let c) = p else {
            return XCTFail("Expected .crypto, got \(p)")
        }
        XCTAssertEqual(c.chain, .stellar)
    }

    func testParsesCosmosURI() {
        let raw = "cosmos:cosmos1abc?amount=1000000uatom"
        let p = ScanPayloadParser.parse(raw)
        guard case .crypto(let c) = p else {
            return XCTFail("Expected .crypto, got \(p)")
        }
        XCTAssertEqual(c.chain, .cosmos)
    }

    // Bare addresses

    func testRecognisesBareBitcoinAddress() {
        let raw = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
        let p = ScanPayloadParser.parse(raw)
        guard case .crypto(let c) = p else {
            return XCTFail("Expected .crypto, got \(p)")
        }
        XCTAssertEqual(c.chain, .bitcoin)
        XCTAssertEqual(c.address, raw)
    }

    func testRecognisesBareEthereumAddress() {
        let raw = "0x89205A3A3b2A69De6Dbf7f01ED13B2108B2c43e7"
        let p = ScanPayloadParser.parse(raw)
        guard case .crypto(let c) = p else {
            return XCTFail("Expected .crypto, got \(p)")
        }
        XCTAssertEqual(c.chain, .ethereum)
    }

    func testRecognisesLNURL() {
        // 60-char placeholder that matches the LNURL bech32 shape.
        let raw = "LNURL1DP68GURN8GHJ7AMPD3KX2AR0VEEKZAR0WD5XJTNRDAKJ7TNHV4KX2EPCV4ENXAR"
        let p = ScanPayloadParser.parse(raw)
        guard case .crypto(let c) = p else {
            return XCTFail("Expected .crypto, got \(p)")
        }
        XCTAssertEqual(c.chain, .lnurl)
    }

    func testRecognisesBareLightningInvoice() {
        // Stub of a bolt11 — short for the test, but begins with `lnbc`.
        let raw = "lnbc1pvjluezpp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdpl"
        let p = ScanPayloadParser.parse(raw)
        guard case .crypto(let c) = p else {
            return XCTFail("Expected .crypto, got \(p)")
        }
        XCTAssertEqual(c.chain, .lightning)
    }

    // vCard 4.0

    func testParsesVCard4() {
        let v = """
        BEGIN:VCARD
        VERSION:4.0
        FN:Jane Doe
        N:Doe;Jane;;;
        TEL;TYPE=cell:+15551234567
        EMAIL;TYPE=work:jane@example.com
        END:VCARD
        """
        let p = ScanPayloadParser.parse(v)
        guard case .contact(let c) = p else {
            return XCTFail("Expected .contact, got \(p)")
        }
        XCTAssertEqual(c.fullName, "Jane Doe")
        XCTAssertEqual(c.phones, ["+15551234567"])
        XCTAssertEqual(c.emails, ["jane@example.com"])
    }

    // MARK: - Pass 2: GS1 / IATA BCBP / AAMVA

    // GS1 — parens form

    func testParsesGS1ParensForm() {
        let raw = "(01)09506000134352(17)201225(10)ABC123(21)SN-001"
        let p = ScanPayloadParser.parse(raw)
        guard case .gs1(let g) = p else {
            return XCTFail("Expected .gs1, got \(p)")
        }
        XCTAssertEqual(g.form, .parens)
        XCTAssertEqual(g.gtin,     "09506000134352")
        XCTAssertEqual(g.expiry,   "201225")
        XCTAssertEqual(g.batchLot, "ABC123")
        XCTAssertEqual(g.serial,   "SN-001")
        // Date rendering pivots: 20 -> 2020.
        let labels = Dictionary(uniqueKeysWithValues: g.labelledFields.map { ($0.label, $0.value) })
        XCTAssertEqual(labels["Expiry (17)"], "2020-12-25")
    }

    // GS1 — Digital Link

    func testParsesGS1DigitalLink() {
        let raw = "https://id.gs1.org/01/09506000134352/10/ABC123"
        let p = ScanPayloadParser.parse(raw)
        guard case .gs1(let g) = p else {
            return XCTFail("Expected .gs1, got \(p)")
        }
        XCTAssertEqual(g.form, .digitalLink)
        XCTAssertEqual(g.gtin,     "09506000134352")
        XCTAssertEqual(g.batchLot, "ABC123")
    }

    // GS1 — FNC1-separated form (no parens, GS=)

    func testParsesGS1FNC1Form() {
        let raw = "0109506000134352\u{001D}10ABC123\u{001D}21SN-001"
        let p = ScanPayloadParser.parse(raw)
        guard case .gs1(let g) = p else {
            return XCTFail("Expected .gs1, got \(p)")
        }
        XCTAssertEqual(g.gtin, "09506000134352")
        XCTAssertEqual(g.batchLot, "ABC123")
        XCTAssertEqual(g.serial, "SN-001")
    }

    // IATA BCBP

    func testParsesIATABoardingPass() {
        // RP 1740c minimum mandatory section: exactly 60 chars, every
        // field at the right fixed-position offset.
        let raw = "M1NETTRASH/TEST       EABC123 LHRJFKBA  0175020M013D0028 100"
        XCTAssertEqual(raw.count, 60, "Test fixture must be exactly 60 chars")
        let p = ScanPayloadParser.parse(raw)
        guard case .boardingPass(let bp) = p else {
            return XCTFail("Expected .boardingPass, got \(p)")
        }
        XCTAssertEqual(bp.formatCode, "M")
        XCTAssertEqual(bp.numberOfLegs, 1)
        XCTAssertEqual(bp.passengerName, "NETTRASH/TEST")
        XCTAssertTrue(bp.electronicTicket)
        XCTAssertEqual(bp.legs.count, 1)
        let leg = bp.legs[0]
        XCTAssertEqual(leg.pnr, "ABC123")
        XCTAssertEqual(leg.from, "LHR")
        XCTAssertEqual(leg.to,   "JFK")
        XCTAssertEqual(leg.carrier, "BA")
        XCTAssertEqual(leg.dateJulian, 20)
    }

    func testRejectsNonBoardingPassPayload() {
        // Same length but starts with `X` instead of `M`.
        let raw = "X1NETTRASH/TEST       EABC123 LHRJFKBA  0175020M013D0028 100"
        let p = ScanPayloadParser.parse(raw)
        if case .boardingPass = p { XCTFail("Expected fall-through, got .boardingPass") }
    }

    // AAMVA driver's licence

    func testParsesAAMVADriverLicense() {
        // Minimal AAMVA fixture — header + a few common element IDs.
        let raw = """
        @
        ANSI 636026100002DL00410288ZV03190008DLDAQABC1234567
        DCSDOE
        DACJOHN
        DADM
        DBA12312030
        DBB04151985
        DBC1
        DAG123 MAIN ST
        DAICOLUMBIA
        DAJSC
        DAK29201
        """
        let p = ScanPayloadParser.parse(raw)
        guard case .drivingLicense(let dl) = p else {
            return XCTFail("Expected .drivingLicense, got \(p)")
        }
        XCTAssertEqual(dl.issuerIIN, "636026")
        XCTAssertEqual(dl.issuerName, "South Carolina")
        XCTAssertEqual(dl.licenseNumber, "ABC1234567")
        XCTAssertEqual(dl.firstName, "JOHN")
        XCTAssertEqual(dl.middleName, "M")
        XCTAssertEqual(dl.lastName, "DOE")
        XCTAssertEqual(dl.sex, "Male")
        XCTAssertEqual(dl.city, "COLUMBIA")
        XCTAssertEqual(dl.state, "SC")
        XCTAssertEqual(dl.postalCode, "29201")
        XCTAssertNotNil(dl.dateOfBirth)
        XCTAssertNotNil(dl.expiry)
    }

    func testRejectsNonAAMVAPayload() {
        let raw = "@\nNotAAMVAStuff"
        let p = ScanPayloadParser.parse(raw)
        if case .drivingLicense = p { XCTFail("Should not classify as AAMVA") }
    }

    // MARK: - WalletConnect (1.9)

    func testParsesWalletConnectV2() {
        let raw = "wc:7f6e504bfad60b485450578e05678ed3e8e8c4751d3c6160be17160d63ec90f9@2?relay-protocol=irn&symKey=587d5484ce2a2a6ee3ba1962fdd7e8588e06200c46823bd18fbd67def96ad303"
        guard case .walletConnect(let p) = ScanPayloadParser.parse(raw) else {
            return XCTFail("Expected .walletConnect, got \(ScanPayloadParser.parse(raw))")
        }
        XCTAssertEqual(p.version, "2")
        XCTAssertEqual(p.topic, "7f6e504bfad60b485450578e05678ed3e8e8c4751d3c6160be17160d63ec90f9")
        XCTAssertEqual(p.relayProtocol, "irn")
        XCTAssertTrue(p.hasKey)
    }

    func testParsesWalletConnectV1() {
        let raw = "wc:8a5e5bdc-a0e4-4702-ba63-8f1a5655744f@1?bridge=https%3A%2F%2Fbridge.walletconnect.org&key=41791102999c339c844880b23950704cc43aa840f3739e365323cda4dfa89e7a"
        guard case .walletConnect(let p) = ScanPayloadParser.parse(raw) else {
            return XCTFail("Expected .walletConnect")
        }
        XCTAssertEqual(p.version, "1")
        XCTAssertEqual(p.bridge, "https://bridge.walletconnect.org")
        XCTAssertTrue(p.hasKey)
    }

    // MARK: - Nostr (1.9)

    func testParsesNostrURI() {
        let raw = "nostr:npub1sn0wdenkukak0d9dfczzeacvhkrgz92ak56egt7vdgzn8pv2wfqqhrjdv9"
        guard case .nostr(let p) = ScanPayloadParser.parse(raw) else {
            return XCTFail("Expected .nostr")
        }
        XCTAssertEqual(p.entity, .profile)
        XCTAssertFalse(p.isPrivateKey)
    }

    func testParsesBareNostrNoteAndNsecWarning() {
        if case .nostr(let note) = ScanPayloadParser.parse("note1fntxtkcy9pjwucqwa9mddn7v03wwwsu9j330jj350nvhpky2tuaspk6nqc") {
            XCTAssertEqual(note.entity, .note)
        } else { XCTFail("Expected bare .nostr note") }

        if case .nostr(let nsec) = ScanPayloadParser.parse("nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5") {
            XCTAssertTrue(nsec.isPrivateKey)
        } else { XCTFail("Expected bare .nostr nsec") }
    }

    // MARK: - 2FA migration (1.9)

    func testParsesGoogleAuthenticatorExport() {
        // Well-formed single-account export: issuer "Example",
        // name "Example:alice@google.com", TOTP.
        let raw = "otpauth-migration://offline?data=CjUKCkhlbGxvId6tvu8SGEV4YW1wbGU6YWxpY2VAZ29vZ2xlLmNvbRoHRXhhbXBsZSABKAEwAhABGAEgACgq"
        guard case .otpMigration(let p) = ScanPayloadParser.parse(raw) else {
            return XCTFail("Expected .otpMigration, got \(ScanPayloadParser.parse(raw))")
        }
        XCTAssertEqual(p.accounts.count, 1)
        XCTAssertEqual(p.accounts.first?.issuer, "Example")
        XCTAssertEqual(p.accounts.first?.name, "Example:alice@google.com")
        XCTAssertEqual(p.accounts.first?.type, "TOTP")
    }

    // MARK: - Plus Code (1.9)

    func testParsesPlusCode() {
        guard case .plusCode(let p) = ScanPayloadParser.parse("849VCWC8+R9") else {
            return XCTFail("Expected .plusCode")
        }
        XCTAssertEqual(p.code, "849VCWC8+R9")
        XCTAssertNil(p.locality)
    }

    func testParsesPlusCodeWithLocality() {
        guard case .plusCode(let p) = ScanPayloadParser.parse("849VCWC8+R9 Stockholm, Sweden") else {
            return XCTFail("Expected .plusCode with locality")
        }
        XCTAssertEqual(p.code, "849VCWC8+R9")
        XCTAssertEqual(p.locality, "Stockholm, Sweden")
        XCTAssertEqual(p.mapsQuery, "849VCWC8+R9 Stockholm, Sweden")
    }

    // MARK: - what3words (1.9)

    func testParsesWhat3Words() {
        guard case .what3words(let w) = ScanPayloadParser.parse("///filled.count.soap") else {
            return XCTFail("Expected .what3words")
        }
        XCTAssertEqual(w.words, "filled.count.soap")
        XCTAssertEqual(w.address, "///filled.count.soap")
    }

    func testW3WSchemeForm() {
        if case .what3words(let w) = ScanPayloadParser.parse("w3w://filled.count.soap") {
            XCTAssertEqual(w.words, "filled.count.soap")
        } else { XCTFail("Expected .what3words from w3w:// form") }
    }

    // MARK: - IBAN (1.9)

    func testParsesValidIBAN() {
        guard case .iban(let p) = ScanPayloadParser.parse("GB82WEST12345698765432") else {
            return XCTFail("Expected .iban")
        }
        XCTAssertEqual(p.countryCode, "GB")
        XCTAssertEqual(p.formatted, "GB82 WEST 1234 5698 7654 32")
    }

    func testRejectsIBANWithBadChecksum() {
        // Same structure, wrong check digits → must NOT be classified as IBAN.
        if case .iban = ScanPayloadParser.parse("GB00WEST12345698765432") {
            XCTFail("Bad-checksum IBAN should not classify as .iban")
        }
    }

    // MARK: - Payment handles & messaging (1.9)

    func testParsesPayPalMe() {
        guard case .richURL(let r) = ScanPayloadParser.parse("https://paypal.me/alice") else {
            return XCTFail("Expected .richURL")
        }
        XCTAssertEqual(r.kind, .payPal)
    }

    func testParsesCashApp() {
        if case .richURL(let r) = ScanPayloadParser.parse("https://cash.app/$alice") {
            XCTAssertEqual(r.kind, .cashApp)
        } else { XCTFail("Expected Cash App .richURL") }
    }

    func testParsesAlipayAppScheme() {
        if case .richURL(let r) = ScanPayloadParser.parse("alipays://platformapi/startapp?saId=10000007") {
            XCTAssertEqual(r.kind, .aliPay)
            XCTAssertTrue(r.kind.isPayment)
        } else { XCTFail("Expected Alipay .richURL") }
    }

    func testParsesSignalAndMeeting() {
        if case .richURL(let s) = ScanPayloadParser.parse("https://signal.me/#p/+15551234567") {
            XCTAssertEqual(s.kind, .signal)
        } else { XCTFail("Expected Signal .richURL") }

        if case .richURL(let m) = ScanPayloadParser.parse("https://meet.google.com/abc-defg-hij") {
            XCTAssertEqual(m.kind, .meeting)
        } else { XCTFail("Expected meeting .richURL") }
    }

    // MARK: - Passkey / FIDO hybrid transport (1.10)

    // digitEncode(CBOR map {0: 33-byte key, 1: 16-byte secret, 2: 2,
    // 3: 1721400000, 4: true, 5: "ga"}) per CTAP 2.2 §11.5.
    private static let fidoSignInQR = "FIDO:/005640586143991420254210104918118704520152650222346064982042512635050847625585230466405085311340191775070633618515609790059716415128245854177999084978946107096654083332"

    // Same shape with {2: 3, 3: 1755763200, 4: false, 5: "mc", 6: true} —
    // key 6 is a newer addition the parser must tolerate.
    private static let fidoCreateQR = "FIDO:/00564058614399143025421010491811870452015265022234606498204251263505084762558523046640508531134019177507063361851560979005971641512824580023161215293926701798171307406340245"

    func testParsesPasskeySignInQR() {
        guard case .passkey(let p) = ScanPayloadParser.parse(Self.fidoSignInQR) else {
            return XCTFail("Expected .passkey")
        }
        XCTAssertTrue(p.decoded)
        XCTAssertEqual(p.operationHint, "ga")
        XCTAssertEqual(p.purposeDescription, "Sign in with a passkey")
        XCTAssertEqual(p.tunnelDomains, 2)
        XCTAssertEqual(p.linkable, true)
        XCTAssertEqual(p.generatedAt, Date(timeIntervalSince1970: 1_721_400_000))
        XCTAssertEqual(ScanPayloadParser.parse(Self.fidoSignInQR).kindLabel, "Passkey")
    }

    func testParsesPasskeyCreateQRAndToleratesUnknownKeys() {
        guard case .passkey(let p) = ScanPayloadParser.parse(Self.fidoCreateQR) else {
            return XCTFail("Expected .passkey")
        }
        XCTAssertTrue(p.decoded)
        XCTAssertEqual(p.operationHint, "mc")
        XCTAssertEqual(p.purposeDescription, "Create a passkey")
        XCTAssertEqual(p.tunnelDomains, 3)
        XCTAssertEqual(p.linkable, false)
    }

    func testPasskeyPrefixIsCaseInsensitive() {
        let lower = "fido:/" + Self.fidoSignInQR.dropFirst("FIDO:/".count)
        guard case .passkey(let p) = ScanPayloadParser.parse(lower) else {
            return XCTFail("Expected .passkey from lowercase prefix")
        }
        XCTAssertEqual(p.operationHint, "ga")
    }

    func testUndecodablePasskeyStillRecognised() {
        // Valid digits that aren't a CBOR map (or a malformed chunk
        // length) → recognised as a passkey QR, flagged undecodable.
        for raw in ["FIDO:/123", "FIDO:/1234", "FIDO:/99999999999999999"] {
            guard case .passkey(let p) = ScanPayloadParser.parse(raw) else {
                return XCTFail("Expected undecodable .passkey for \(raw)")
            }
            XCTAssertFalse(p.decoded, raw)
            XCTAssertNil(p.operationHint, raw)
        }
    }

    func testFidoPrefixWithNonDigitsFallsBackToText() {
        guard case .text = ScanPayloadParser.parse("FIDO:/hello-world") else {
            return XCTFail("Expected .text for non-digit FIDO payload")
        }
    }

    // MARK: - CBOR reader (1.10)

    /// Mirrors the Android port's `capsNestingInsteadOfOverflowingTheStack`.
    func testCBORReaderCapsNestingInsteadOfOverflowingTheStack() {
        func nested(_ levels: Int, _ opener: UInt8) -> CBORReader.Value? {
            var reader = CBORReader([UInt8](repeating: opener, count: levels) + [0x01])
            return reader.readValue()
        }
        XCTAssertNotNil(nested(CBORReader.maxDepth, 0x81))
        XCTAssertNil(nested(CBORReader.maxDepth + 1, 0x81))
        XCTAssertEqual(nested(CBORReader.maxDepth, 0xC1), .other)
        XCTAssertNil(nested(CBORReader.maxDepth + 1, 0xC1))
        // A QR-sized payload of nothing but openers: one level per byte.
        XCTAssertNil(nested(20_000, 0x81))
        XCTAssertNil(nested(20_000, 0xA1))
    }

    // MARK: - eIDAS 2.0 / OpenID4VP (1.10)

    func testParsesOpenID4VPPresentationRequest() {
        let dcql = "{\"credentials\":[{\"id\":\"eu.europa.ec.eudi.pid.1\",\"format\":\"dc+sd-jwt\"}]}"
        let raw = "openid4vp://authorize?client_id=https%3A%2F%2Fverifier.example.gov"
            + "&response_uri=https%3A%2F%2Fwallet.example%2Fcb&nonce=abc123&state=xyz"
            + "&dcql_query=" + dcql.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        guard case .verifiableCredential(let p) = ScanPayloadParser.parse(raw) else {
            return XCTFail("Expected .verifiableCredential")
        }
        XCTAssertEqual(p.kind, .presentationRequest)
        XCTAssertEqual(p.counterpartyHost, "verifier.example.gov")
        XCTAssertTrue(p.noncePresent)
        XCTAssertTrue(p.statePresent)
        XCTAssertTrue(p.requested.first?.contains("PID") == true, "\(p.requested)")
        XCTAssertTrue(p.responseURI?.contains("wallet.example") == true, "\(String(describing: p.responseURI))")
        XCTAssertTrue(p.labelledFields.contains { $0.label == "Asking for" }, "\(p.labelledFields)")
        XCTAssertTrue(p.cautions.contains { $0.contains("started") }, "\(p.cautions)")
    }

    func testParsesCredentialOffer() {
        let offer = "{\"credential_issuer\":\"https://issuer.example\","
            + "\"credential_configuration_ids\":[\"urn:eu.europa.ec.eudi:pid:1\"]}"
        let raw = "openid-credential-offer://?credential_offer="
            + offer.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        guard case .verifiableCredential(let p) = ScanPayloadParser.parse(raw) else {
            return XCTFail("Expected a credential offer")
        }
        XCTAssertEqual(p.kind, .credentialOffer)
        XCTAssertTrue(p.requested.first?.contains("PID") == true, "\(p.requested)")
        XCTAssertTrue(p.cautions.contains { $0.contains("unsolicited") }, "\(p.cautions)")
    }

    func testParsesSDJWTVerifiableCredential() {
        let header = base64URL(Array("{\"alg\":\"ES256\",\"typ\":\"dc+sd-jwt\"}".utf8))
        let claims = base64URL(Array((
            "{\"iss\":\"https://issuer.example\",\"iat\":1750000000,\"exp\":1800000000,"
            + "\"vct\":\"urn:eu.europa.ec.eudi:pid:1\",\"_sd\":[\"a\",\"b\",\"c\"],"
            + "\"cnf\":{\"x\":1}}"
        ).utf8))
        let token = "\(header).\(claims).Zm9vYmFy"
        XCTAssertTrue(VerifiableCredentialParser.looksLikeCredentialToken(token))

        guard case .verifiableCredential(let p) = ScanPayloadParser.parse(token) else {
            return XCTFail("Expected the SD-JWT to classify as a credential")
        }
        XCTAssertEqual(p.kind, .credential)
        XCTAssertEqual(p.issuer, "https://issuer.example")
        XCTAssertEqual(p.selectivelyDisclosable, 3)
        XCTAssertEqual(p.keyBinding, true)
        XCTAssertTrue(p.labelledFields.contains { $0.value.contains("PID") }, "\(p.labelledFields)")
        XCTAssertTrue(p.labelledFields.contains { $0.label == "Issued" }, "\(p.labelledFields)")
    }

    func testOrdinaryLoginJWTStaysText() {
        let plain = base64URL(Array("{\"alg\":\"HS256\"}".utf8)) + "."
            + base64URL(Array("{\"sub\":\"12345\",\"exp\":1800000000}".utf8)) + ".c2ln"
        XCTAssertFalse(VerifiableCredentialParser.looksLikeCredentialToken(plain))
        XCTAssertEqual(ScanPayloadParser.parse(plain).kindLabel, "Text")
    }

    // MARK: - EN 16931 e-invoice (1.10)

    static let xrechnungXML = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<rsm:CrossIndustryInvoice xmlns:rsm=\"urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100\"",
            " xmlns:ram=\"urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100\">",
            " <rsm:ExchangedDocumentContext>",
            "  <ram:GuidelineSpecifiedDocumentContextParameter>",
            "   <ram:ID>urn:cen.eu:en16931:2017#compliant#urn:xeinkauf.de:kosit:xrechnung_3.0</ram:ID>",
            "  </ram:GuidelineSpecifiedDocumentContextParameter>",
            " </rsm:ExchangedDocumentContext>",
            " <rsm:ExchangedDocument><ram:ID>RE-2026-0042</ram:ID>",
            "  <ram:IssueDateTime><udt:DateTimeString xmlns:udt=\"urn:un:unece:uncefact:data:standard:UniqueDataType\">20260514</udt:DateTimeString></ram:IssueDateTime>",
            " </rsm:ExchangedDocument>",
            " <rsm:SupplyChainTradeTransaction>",
            "  <ram:ApplicableHeaderTradeAgreement>",
            "   <ram:BuyerReference>04011000-00000-55</ram:BuyerReference>",
            "   <ram:SellerTradeParty><ram:Name>Example GmbH</ram:Name>",
            "    <ram:SpecifiedLegalOrganization><ram:ID>DE812345678</ram:ID></ram:SpecifiedLegalOrganization>",
            "   </ram:SellerTradeParty>",
            "   <ram:BuyerTradeParty><ram:Name>Stadt Musterstadt</ram:Name></ram:BuyerTradeParty>",
            "  </ram:ApplicableHeaderTradeAgreement>",
            "  <ram:ApplicableHeaderTradeSettlement>",
            "   <ram:PaymentDueDate><udt:DateTimeString xmlns:udt=\"urn:un:unece:uncefact:data:standard:UniqueDataType\">20260613</udt:DateTimeString></ram:PaymentDueDate>",
            "   <ram:SpecifiedTradeSettlementHeaderMonetarySummation>",
            "    <ram:LineTotalAmount>1000.00</ram:LineTotalAmount>",
            "    <ram:TaxTotalAmount>190.00</ram:TaxTotalAmount>",
            "    <ram:GrandTotalAmount>1190.00</ram:GrandTotalAmount>",
            "    <ram:DuePayableAmount>1190.00</ram:DuePayableAmount>",
            "   </ram:SpecifiedTradeSettlementHeaderMonetarySummation>",
            "   <ram:CreditTransferTransferSettlement>",
            "    <ram:PayeePartyCreditorFinancialAccount><ram:IBANID>DE89370400440532013000</ram:IBANID></ram:PayeePartyCreditorFinancialAccount>",
            "   </ram:CreditTransferTransferSettlement>",
            "  </ram:ApplicableHeaderTradeSettlement>",
            " </rsm:SupplyChainTradeTransaction>",
            "</rsm:CrossIndustryInvoice>",
        ].joined(separator: "\n")

    func testParsesXRechnungInvoice() {
        guard case .eInvoice(let p) = ScanPayloadParser.parse(Self.xrechnungXML) else {
            return XCTFail("Expected .eInvoice")
        }
        XCTAssertTrue(p.standard.contains("XRechnung"), p.standard)
        XCTAssertEqual(p.invoiceNumber, "RE-2026-0042")
        XCTAssertEqual(p.sellerName, "Example GmbH")
        XCTAssertEqual(p.sellerVAT, "DE812345678")
        XCTAssertEqual(p.buyerName, "Stadt Musterstadt")
        XCTAssertEqual(p.buyerReference, "04011000-00000-55")
        XCTAssertEqual(p.totalAmount, "1190.00")
        XCTAssertEqual(p.issueDate, "2026-05-14")
        XCTAssertEqual(p.dueDate, "2026-06-13")
        XCTAssertTrue(p.guideline?.contains("xrechnung_3.0") == true, "\(String(describing: p.guideline))")
        XCTAssertFalse(p.wasEncoded)
        // No BT-5 element in this fixture, so the total carries no currency.
        XCTAssertNil(p.currency)
        XCTAssertEqual(p.iban, "DE89370400440532013000")
    }

    func testParsesBase64EncodedInvoiceCarrier() {
        let encoded = Data(Self.xrechnungXML.utf8).base64EncodedString()
        guard case .eInvoice(let p)? = Optional(ScanPayloadParser.parse(encoded)) else {
            return XCTFail("Expected the base64 carrier to classify as an invoice")
        }
        XCTAssertTrue(p.wasEncoded)
        XCTAssertEqual(p.invoiceNumber, "RE-2026-0042")
    }

    func testInvoiceDoesNotStealFieldsFromTheWrongParent() {
        // The guideline identifier is also a `<ram:ID>`; anchoring must keep
        // it out of the invoice-number slot.
        guard case .eInvoice(let p)? = Optional(ScanPayloadParser.parse(Self.xrechnungXML)) else {
            return XCTFail("Expected .eInvoice")
        }
        XCTAssertNotEqual(p.invoiceNumber, p.guideline)
    }

    func testArbitraryBase64IsNotAnInvoice() {
        let noise = Data(String(repeating: "not an invoice ", count: 40).utf8).base64EncodedString()
        XCTAssertFalse(InvoiceParser.looksLikeEInvoice(noise))
    }

    /// EN 16931 CII as written: BT-23 (business process) ahead of BT-24
    /// (guideline), BT-5 `InvoiceCurrencyCode` in the header settlement,
    /// BT-9 under `SpecifiedTradePaymentTerms`, BT-31 as a `VA` tax
    /// registration and the buyer's VAT id right after the seller's. The
    /// same document as the Android port's `InvoicePayloadTest.xml`.
    static let ciiInvoiceXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rsm:CrossIndustryInvoice xmlns:rsm="urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100"
            xmlns:ram="urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100"
            xmlns:udt="urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100">
          <rsm:ExchangedDocumentContext>
            <ram:BusinessProcessSpecifiedDocumentContextParameter>
              <ram:ID>urn:fdc:peppol.eu:2017:poacc:billing:01:1.0</ram:ID>
            </ram:BusinessProcessSpecifiedDocumentContextParameter>
            <ram:GuidelineSpecifiedDocumentContextParameter>
              <ram:ID>urn:cen.eu:en16931:2017#compliant#urn:xeinkauf.de:kosit:xrechnung_3.0</ram:ID>
            </ram:GuidelineSpecifiedDocumentContextParameter>
          </rsm:ExchangedDocumentContext>
          <rsm:ExchangedDocument>
            <ram:ID>R-2026-0142</ram:ID>
            <ram:TypeCode>380</ram:TypeCode>
            <ram:IssueDateTime>
              <udt:DateTimeString format="102">20260514</udt:DateTimeString>
            </ram:IssueDateTime>
          </rsm:ExchangedDocument>
          <rsm:SupplyChainTradeTransaction>
            <ram:IncludedSupplyChainTradeLineItem>
              <ram:AssociatedDocumentLineDocument>
                <ram:LineID>1</ram:LineID>
              </ram:AssociatedDocumentLineDocument>
              <ram:SpecifiedTradeProduct>
                <ram:GlobalID schemeID="0160">4012345678901</ram:GlobalID>
                <ram:Name>Beratungsleistung</ram:Name>
              </ram:SpecifiedTradeProduct>
              <ram:SpecifiedLineTradeSettlement>
                <ram:ApplicableTradeTax>
                  <ram:TypeCode>VAT</ram:TypeCode>
                  <ram:CategoryCode>S</ram:CategoryCode>
                  <ram:RateApplicablePercent>19.00</ram:RateApplicablePercent>
                </ram:ApplicableTradeTax>
                <ram:SpecifiedTradeSettlementLineMonetarySummation>
                  <ram:LineTotalAmount>1000.00</ram:LineTotalAmount>
                </ram:SpecifiedTradeSettlementLineMonetarySummation>
              </ram:SpecifiedLineTradeSettlement>
            </ram:IncludedSupplyChainTradeLineItem>
            <ram:ApplicableHeaderTradeAgreement>
              <ram:BuyerReference>04011000-12345-81</ram:BuyerReference>
              <ram:SellerTradeParty>
                <ram:Name>Muster GmbH</ram:Name>
                <ram:SpecifiedLegalOrganization>
                  <ram:ID>HRB 12345</ram:ID>
                </ram:SpecifiedLegalOrganization>
                <ram:PostalTradeAddress>
                  <ram:CityName>Berlin</ram:CityName>
                  <ram:CountryID>DE</ram:CountryID>
                </ram:PostalTradeAddress>
                <ram:SpecifiedTaxRegistration>
                  <ram:ID schemeID="FC">201/113/40209</ram:ID>
                </ram:SpecifiedTaxRegistration>
                <ram:SpecifiedTaxRegistration>
                  <ram:ID schemeID="VA">DE813792021</ram:ID>
                </ram:SpecifiedTaxRegistration>
              </ram:SellerTradeParty>
              <ram:BuyerTradeParty>
                <ram:Name>Beispiel Stadt</ram:Name>
                <ram:PostalTradeAddress>
                  <ram:CityName>Muenchen</ram:CityName>
                  <ram:CountryID>DE</ram:CountryID>
                </ram:PostalTradeAddress>
                <ram:SpecifiedTaxRegistration>
                  <ram:ID schemeID="VA">DE129273398</ram:ID>
                </ram:SpecifiedTaxRegistration>
              </ram:BuyerTradeParty>
            </ram:ApplicableHeaderTradeAgreement>
            <ram:ApplicableHeaderTradeDelivery/>
            <ram:ApplicableHeaderTradeSettlement>
              <ram:PaymentReference>R-2026-0142</ram:PaymentReference>
              <ram:InvoiceCurrencyCode>EUR</ram:InvoiceCurrencyCode>
              <ram:SpecifiedTradeSettlementPaymentMeans>
                <ram:TypeCode>58</ram:TypeCode>
                <ram:PayeePartyCreditorFinancialAccount>
                  <ram:IBANID>DE02120300000000202051</ram:IBANID>
                </ram:PayeePartyCreditorFinancialAccount>
              </ram:SpecifiedTradeSettlementPaymentMeans>
              <ram:ApplicableTradeTax>
                <ram:CalculatedAmount>190.00</ram:CalculatedAmount>
                <ram:TypeCode>VAT</ram:TypeCode>
                <ram:BasisAmount>1000.00</ram:BasisAmount>
                <ram:CategoryCode>S</ram:CategoryCode>
                <ram:RateApplicablePercent>19.00</ram:RateApplicablePercent>
              </ram:ApplicableTradeTax>
              <ram:SpecifiedTradePaymentTerms>
                <ram:Description>Zahlbar innerhalb von 30 Tagen</ram:Description>
                <ram:DueDateDateTime>
                  <udt:DateTimeString format="102">20260613</udt:DateTimeString>
                </ram:DueDateDateTime>
              </ram:SpecifiedTradePaymentTerms>
              <ram:SpecifiedTradeSettlementHeaderMonetarySummation>
                <ram:LineTotalAmount>1000.00</ram:LineTotalAmount>
                <ram:TaxBasisTotalAmount>1000.00</ram:TaxBasisTotalAmount>
                <ram:TaxTotalAmount currencyID="EUR">190.00</ram:TaxTotalAmount>
                <ram:GrandTotalAmount>1190.00</ram:GrandTotalAmount>
                <ram:DuePayableAmount>1190.00</ram:DuePayableAmount>
              </ram:SpecifiedTradeSettlementHeaderMonetarySummation>
            </ram:ApplicableHeaderTradeSettlement>
          </rsm:SupplyChainTradeTransaction>
        </rsm:CrossIndustryInvoice>
        """

    func testParsesCIIInvoiceInTheRealSyntaxBinding() {
        guard case .eInvoice(let p) = ScanPayloadParser.parse(Self.ciiInvoiceXML) else {
            return XCTFail("Expected .eInvoice")
        }
        XCTAssertEqual(p.standard, "XRechnung (EN 16931, Germany)")
        XCTAssertEqual(p.invoiceNumber, "R-2026-0142")
        XCTAssertEqual(p.sellerName, "Muster GmbH")
        XCTAssertEqual(p.sellerVAT, "DE813792021")
        XCTAssertEqual(p.buyerName, "Beispiel Stadt")
        XCTAssertEqual(p.buyerReference, "04011000-12345-81")
        XCTAssertEqual(p.totalAmount, "1190.00")
        XCTAssertEqual(p.currency, "EUR")
        XCTAssertEqual(p.taxAmount, "190.00")
        XCTAssertEqual(p.issueDate, "2026-05-14")
        XCTAssertEqual(p.dueDate, "2026-06-13")
        XCTAssertEqual(p.iban, "DE02120300000000202051")
        XCTAssertEqual(p.guideline,
                       "urn:cen.eu:en16931:2017#compliant#urn:xeinkauf.de:kosit:xrechnung_3.0")
        XCTAssertFalse(p.wasEncoded)
        XCTAssertEqual(p.labelledFields.map(\.label), [
            "Format", "Invoice no.", "Seller", "Seller VAT", "Buyer", "Buyer ref / Leitweg-ID",
            "Total", "Tax", "Issued", "Due", "IBAN", "Guideline",
        ])
        XCTAssertEqual(p.labelledFields.first { $0.label == "Total" }?.value, "1190.00 EUR")
    }

    func testInvoiceGuidelineIsTheSpecificationNotTheBusinessProcess() {
        // BT-23 comes first in CII and also ends in `DocumentContextParameter`;
        // only BT-24 is the guideline.
        guard let p = InvoiceParser.parse(Self.ciiInvoiceXML) else { return XCTFail("Expected an invoice") }
        XCTAssertFalse(p.guideline?.contains("poacc") ?? true, "\(String(describing: p.guideline))")
        XCTAssertNotEqual(p.guideline, p.invoiceNumber)

        let noGuideline = Self.ciiInvoiceXML.replacingOccurrences(
            of: #"<ram:GuidelineSpecifiedDocumentContextParameter>[\s\S]*?</ram:GuidelineSpecifiedDocumentContextParameter>"#,
            with: "", options: .regularExpression)
        XCTAssertNotNil(InvoiceParser.parse(noGuideline))
        XCTAssertNil(InvoiceParser.parse(noGuideline)?.guideline)
    }

    func testInvoiceCurrencyIsTheInvoiceCurrencyNeverTheVATAccountingCurrency() {
        // BT-6 `TaxCurrencyCode` is the VAT accounting currency; quoting it
        // next to the grand total would misstate the total.
        let vatOnly = Self.ciiInvoiceXML.replacingOccurrences(
            of: "<ram:InvoiceCurrencyCode>EUR</ram:InvoiceCurrencyCode>",
            with: "<ram:TaxCurrencyCode>CHF</ram:TaxCurrencyCode>")
        guard let p = InvoiceParser.parse(vatOnly) else { return XCTFail("Expected an invoice") }
        XCTAssertNil(p.currency)
        XCTAssertEqual(p.labelledFields.first { $0.label == "Total" }?.value, "1190.00")

        // UBL's name for BT-5 is still read.
        let ublName = Self.ciiInvoiceXML.replacingOccurrences(
            of: "<ram:InvoiceCurrencyCode>EUR</ram:InvoiceCurrencyCode>",
            with: "<cbc:DocumentCurrencyCode>SEK</cbc:DocumentCurrencyCode>")
        XCTAssertEqual(InvoiceParser.parse(ublName)?.currency, "SEK")
    }

    func testInvoiceSellerVATIsTheSellersVARegistration() {
        // Not the FC tax number, not the legal registration, not the buyer's VA id.
        XCTAssertEqual(InvoiceParser.parse(Self.ciiInvoiceXML)?.sellerVAT, "DE813792021")
        let fcOnly = Self.ciiInvoiceXML.replacingOccurrences(
            of: "<ram:ID schemeID=\"VA\">DE813792021</ram:ID>", with: "")
        XCTAssertNotNil(InvoiceParser.parse(fcOnly))
        XCTAssertNil(InvoiceParser.parse(fcOnly)?.sellerVAT)
    }

    func testInvoiceSellerVATIsNeverBorrowedFromAnotherParty() {
        // A VAT-shaped invoice number comes first in the document, and the
        // buyer has a VA registration: neither is the seller's VAT id.
        let noSellerVAT = Self.ciiInvoiceXML
            .replacingOccurrences(of: "<ram:ID>R-2026-0142</ram:ID>", with: "<ram:ID>INV20260001</ram:ID>")
            .replacingOccurrences(of: "<ram:ID schemeID=\"VA\">DE813792021</ram:ID>", with: "")
        guard let p = InvoiceParser.parse(noSellerVAT) else { return XCTFail("Expected an invoice") }
        XCTAssertEqual(p.invoiceNumber, "INV20260001")
        XCTAssertNil(p.sellerVAT)
        XCTAssertFalse(p.labelledFields.map(\.label).contains("Seller VAT"))
    }

    func testInvoiceAnchoringKeepsLookalikeElementNamesApart() {
        // `Name` under a tax representative must not become the seller, and
        // an anchor that is absent means no match at all.
        let swapped = Self.ciiInvoiceXML
            .replacingOccurrences(of: "<ram:SellerTradeParty>", with: "<ram:TaxRepresentativeTradeParty>")
            .replacingOccurrences(of: "</ram:SellerTradeParty>", with: "</ram:TaxRepresentativeTradeParty>")
            .replacingOccurrences(of: "<ram:BuyerTradeParty>", with: "<ram:TaxRepresentativeTradeParty>")
            .replacingOccurrences(of: "</ram:BuyerTradeParty>", with: "</ram:TaxRepresentativeTradeParty>")
        let p = InvoiceParser.parse(swapped)
        XCTAssertNil(p?.sellerName)
        XCTAssertNil(p?.buyerName)
        XCTAssertNil(p?.sellerVAT)
        // Still an invoice — the number and total carry it.
        XCTAssertEqual(p?.invoiceNumber, "R-2026-0142")
        XCTAssertEqual(p?.totalAmount, "1190.00")
    }

    // MARK: - Digital Product Passport (1.10)

    func testGS1PassportBecomesItsOwnKind() {
        // GTIN + origin + a date + a unit identifier is what separates a
        // passport from an ordinary product code.
        let passport = "(01)04012345678901(17)260101(11)250601(10)LOT42"
            + "(21)SER0001(422)276"
        guard case .digitalProductPassport(let p) = ScanPayloadParser.parse(passport) else {
            return XCTFail("Expected .digitalProductPassport, got \(ScanPayloadParser.parse(passport).kindLabel)")
        }
        XCTAssertEqual(p.gtin, "04012345678901")
        XCTAssertFalse(p.labelledFields.isEmpty)
    }

    func testPlainGS1StaysAProductCode() {
        guard case .gs1 = ScanPayloadParser.parse("(01)09506000134352(17)201225(10)ABC123") else {
            return XCTFail("A plain GS1 carrier must stay .gs1")
        }
    }

    func testPassportCountryOfOriginIsTheISOAssignment() {
        // 528 is the Netherlands; the table once printed it as Morocco, along
        // with three other neighbouring-code mix-ups. Mirrors the Android
        // port's `countryOfOriginIsTheIsoAssignment`.
        func origin(_ numeric: String) -> String? {
            guard let gs1 = GS1Parser.parse("(01)04012345678901(17)261231(10)LOT42(422)\(numeric)") else {
                return nil
            }
            return DigitalProductPassportParser.parse(gs1).originDescription
        }
        XCTAssertEqual(origin("528"), "Netherlands (NLD)")
        XCTAssertEqual(origin("504"), "Morocco (MAR)")
        XCTAssertEqual(origin("470"), "Malta (MLT)")
        XCTAssertEqual(origin("466"), "Mali (MLI)")
        XCTAssertEqual(origin("600"), "Paraguay (PRY)")
        XCTAssertEqual(origin("710"), "South Africa (ZAF)")
        XCTAssertEqual(origin("324"), "Guinea (GIN)")
        XCTAssertEqual(origin("624"), "Guinea-Bissau (GNB)")
        XCTAssertEqual(origin("276"), "Germany (DEU)")
        XCTAssertNil(origin("999"))
    }

    // MARK: - QR risk assessment (1.10)

    private func assess(_ raw: String, codesInFrame: Int = 1) -> QrRiskReport {
        QrRiskAssessor.assess(raw: raw, payload: ScanPayloadParser.parse(raw), codesInFrame: codesInFrame)
    }

    func testRiskDetectsPunycodeHost() {
        let r = assess("https://xn--80ak6aa92e.com/login")
        XCTAssertEqual(r.level, .danger)
        XCTAssertTrue(r.findings.contains { $0.code == "punycode-host" })
    }

    func testRiskDetectsLookalikeAndNamesTheBrand() {
        let r = assess("https://paypaI.com/signin")
        XCTAssertEqual(r.level, .danger)
        XCTAssertTrue(r.findings.contains { $0.code == "lookalike-domain" })
        XCTAssertTrue(r.findings.contains { $0.title.contains("PayPal") },
                      "\(r.findings.map(\.title))")
    }

    func testRiskDetectsMixedScriptHost() {
        let r = assess("https://paypa\u{0435}l.com/")
        XCTAssertTrue(r.findings.contains { $0.code == "mixed-script-host" },
                      "\(r.findings.map(\.code))")
    }

    func testRiskFlagsShortenersButStaysAtCaution() {
        let r = assess("https://bit.ly/3xYzAbC")
        XCTAssertTrue(r.findings.contains { $0.code == "url-shortener" })
        XCTAssertEqual(r.level, .caution)
    }

    func testRiskDetectsCredentialsInURL() {
        let r = assess("https://paypal.com@evil.example/checkout")
        XCTAssertTrue(r.findings.contains { $0.code == "credentials-in-url" })
    }

    func testRiskDetectsPlainHTTPAndMultipleCodes() {
        XCTAssertTrue(assess("http://shop.example/cart").findings.contains { $0.code == "plain-http" })
        XCTAssertTrue(assess("https://parking.example/pay", codesInFrame: 2)
            .findings.contains { $0.code == "multi-code-frame" })
    }

    func testRiskFlagsExposedPrivateKey() {
        let key = "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEA\n-----END RSA PRIVATE KEY-----"
        let r = assess(key)
        XCTAssertEqual(r.level, .danger)
        XCTAssertTrue(r.findings.contains { $0.code == "secret-exposed" })
    }

    func testRiskDetectsOpenRedirect() {
        let r = assess("https://bank.example/redirect?url=https%3A%2F%2Fevil.example%2Flogin")
        XCTAssertTrue(r.findings.contains { $0.code == "open-redirect" })
    }

    func testCleanCodesAreNotNagged() {
        let menu = assess("https://example.com/menu")
        XCTAssertTrue(menu.findings.filter { $0.severity != .note }.isEmpty,
                      "\(menu.findings.map(\.code))")
        XCTAssertEqual(menu.level, .safe)

        let product = assess("https://example.net/01/04006000200007")
        XCTAssertEqual(product.level, .safe, "\(product.findings.map(\.code))")
    }

    func testRiskFlagsStaticPaymentCodesWithoutAMerchant() {
        let emv = "000201" + "010211" + "52045812" + "5303978" + "540512.00"
            + "5802RS" + "6008BELGRADE" + "6304A1B2"
        let r = assess(emv)
        let codes = r.findings.map(\.code)
        XCTAssertTrue(codes.contains("payment-no-merchant"), "\(codes)")
        XCTAssertTrue(codes.contains("static-amount-poster"), "\(codes)")
        XCTAssertTrue(codes.contains("static-payment-code"), "\(codes)")
    }

    func testRiskWarnsAboutSharedOTPCodes() {
        let r = assess("otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP&issuer=Example")
        XCTAssertTrue(r.findings.contains { $0.code == "otp-share-warning" })
    }

    func testRiskDetectsPaymentLureInFreeText() {
        let r = assess("Scan this code to pay 39 EUR now. Questions? "
            + "Contact us on Telegram t.me/support_pay")
        XCTAssertTrue(r.findings.contains { $0.code == "lure-text" }, "\(r.findings.map(\.code))")
    }

    func testLookalikeHelperIsReusable() {
        XCTAssertTrue(QrRiskAssessor.looksLookalike("revolut-pay.example"))
        XCTAssertFalse(QrRiskAssessor.looksLookalike("revolut.com"))
    }

    // The Android port's `QrRiskAssessorTest` cases on the same inputs, so the
    // two assessors keep giving the same verdicts (the shared corpus is in
    // `SafetyParityTests`).

    func testRiskHostChecksMatchAndroid() {
        let puny = QrRiskAssessor.assess(raw: "https://xn--80ak6aa92e.com/",
                                         payload: .url(URL(string: "https://xn--80ak6aa92e.com/")!))
        XCTAssertEqual(puny.level, .danger)
        XCTAssertEqual(puny.headline, "Internationalised domain")

        let lookalike = assess("https://paypaI.com/checkout")
        XCTAssertEqual(lookalike.level, .danger)
        let finding = lookalike.findings.first { $0.code == "lookalike-domain" }
        XCTAssertEqual(finding?.title, "Impersonates PayPal")
        XCTAssertTrue(finding?.detail.contains("PayPal does not operate on this domain") == true)
        XCTAssertTrue(QrRiskAssessor.assess(raw: "https://paypaI.com/").findings
            .contains { $0.code == "lookalike-domain" })

        // Cyrillic "а" in аpple.com: caught on the host as written.
        let mixedRaw = "https://\u{0430}pple.com/shop"
        let mixed = QrRiskAssessor.assess(raw: mixedRaw, payload: ScanPayloadParser.parse(mixedRaw))
        XCTAssertTrue(mixed.findings.contains { $0.code == "mixed-script-host" }, "\(mixed.findings.map(\.code))")
        XCTAssertEqual(mixed.level, .danger)

        XCTAssertEqual(assess("https://bit.ly/3xYzAb").level, .caution)
        XCTAssertEqual(assess("https://paypal.com@evil.example/checkout").level, .danger)
        XCTAssertEqual(assess("http://shop.example/cart").level, .caution)
        XCTAssertTrue(assess("https://trusted.example/go?url=https://evil.example/login")
            .findings.contains { $0.code == "open-redirect" })

        XCTAssertTrue(assess("http://203.0.113.9:9000/pay").findings.contains { $0.code == "odd-port" })
        XCTAssertFalse(assess("https://example.com:8443/pay").findings.contains { $0.code == "odd-port" })
        XCTAssertTrue(assess("http://203.0.113.9/pay").findings.contains { $0.code == "ip-literal-host" })
        // A private address is only worth a note — it is usually a printer.
        XCTAssertEqual(QrRiskAssessor.assess(raw: "http://192.168.1.10/admin").findings
            .first { $0.code == "ip-literal-host" }?.severity, .note)

        XCTAssertTrue(assess("https://giveaway.top/claim").findings.contains { $0.code == "abuse-tld" })
        XCTAssertTrue(assess("https://a.b.c.paypaI.example/").findings.contains { $0.code == "deep-subdomain" })

        let script = QrRiskAssessor.assess(raw: "javascript:alert(1)")
        XCTAssertTrue(script.findings.contains { $0.code == "dangerous-scheme" })
        XCTAssertEqual(script.level, .danger)

        let twoCodes = QrRiskAssessor.assess(raw: "https://example.com/menu",
                                             payload: .url(URL(string: "https://example.com/menu")!),
                                             codesInFrame: 2)
        XCTAssertEqual(twoCodes.findings.first { $0.code == "multi-code-frame" }?.title, "2 codes in this frame")
        XCTAssertEqual(twoCodes.level, .caution)

        XCTAssertTrue(QrRiskAssessor.looksLookalike("paypa1.com"))
        XCTAssertTrue(QrRiskAssessor.looksLookalike("paypaI.com"))
        XCTAssertFalse(QrRiskAssessor.looksLookalike("example.com"))
        XCTAssertFalse(QrRiskAssessor.looksLookalike("nettrash.me"))
        XCTAssertEqual(QrRiskAssessor.registrableDomain("shop.example.co.uk"), "example.co.uk")
        XCTAssertEqual(QrRiskAssessor.registrableDomain("a.b.example.com"), "example.com")
    }

    func testRiskPayloadChecksMatchAndroid() {
        let key = """
            -----BEGIN RSA PRIVATE KEY-----
            MIIEowIBAAKCAQEAy7Kd3nZ0m1VhQ3YrT0pLbCjFgHsN2wXkLdJnBq9RtUvWxYz
            AbCdEfGhIjKlMnOpQrStUvWxYz0123456789+/abcdefghijklmnOPQRSTUVWXYZ
            -----END RSA PRIVATE KEY-----
            """
        let keyReport = assess(key)
        XCTAssertEqual(keyReport.level, .danger)
        XCTAssertTrue(keyReport.findings.first { $0.code == "secret-exposed" }?.detail.contains("private key") == true)

        let nostr = QrRiskAssessor.assess(raw: "nsec1qvz8cq6d8t0f0y3gqk0q0m3v9z2xk")
        XCTAssertTrue(nostr.findings.contains { $0.code == "secret-exposed" })
        XCTAssertEqual(nostr.level, .caution)

        let staticEMV = "000201" + "010211" + "52045812" + "5303986" + "540525.00"
            + "5802BR" + "6008SAOPAULO" + "6304ABCD"
        guard case .emvPayment = ScanPayloadParser.parse(staticEMV) else {
            return XCTFail("Expected .emvPayment")
        }
        let emvCodes = assess(staticEMV).findings.map(\.code)
        XCTAssertTrue(emvCodes.contains("payment-no-merchant"), "\(emvCodes)")
        XCTAssertTrue(emvCodes.contains("static-amount-poster"), "\(emvCodes)")
        XCTAssertTrue(emvCodes.contains("static-payment-code"), "\(emvCodes)")
        let namedEMV = "000201" + "010212" + "52045812" + "5303986" + "540512.34"
            + "5802BR" + "5909ACME LTDA" + "6008SAOPAULO" + "6304ABCD"
        XCTAssertFalse(assess(namedEMV).findings.contains { $0.code == "payment-no-merchant" })

        XCTAssertTrue(assess("WIFI:T:NOPASS;S:Cafe Guest;H:false;;").findings.contains { $0.code == "open-wifi" })
        XCTAssertTrue(assess("Scan this code to pay \u{00A3}1.00 \u{2014} contact us on Telegram @pay2me")
            .findings.contains { $0.code == "lure-text" })
        XCTAssertTrue(assess("Meeting point: main entrance, third floor, room 12").findings.isEmpty)

        let wifi = assess("WIFI:T:WPA;S:CafeNet;P:coffee2026;H:false;;")
        XCTAssertEqual(wifi.level, .safe)
        XCTAssertTrue(wifi.findings.filter { $0.severity != .note }.isEmpty)
    }

    // MARK: - On-device assistant (1.10)

    func testBuiltInExplainerDescribesWifiWithoutLeakingThePassword() {
        let wifi = "WIFI:T:WPA;S:BlueHouse;P:hunter2;H:true;;"
        let e = HeuristicExplainer.explain(raw: wifi, payload: ScanPayloadParser.parse(wifi))
        XCTAssertEqual(e.headline, "A Wi-Fi login")
        XCTAssertTrue(e.keyPoints.contains { $0.contains("BlueHouse") })
        XCTAssertFalse(e.cautions.isEmpty)
        XCTAssertEqual(e.source, .builtIn)
    }

    func testExplainerCautionsAboutIdentityRequests() {
        let mdl = HeuristicExplainer.explain(raw: MdocEngagementTests.annexDQR,
                                             payload: ScanPayloadParser.parse(MdocEngagementTests.annexDQR))
        XCTAssertTrue(mdl.cautions.contains { $0.contains("wallet") }, "\(mdl.cautions)")

        let invoice = HeuristicExplainer.explain(raw: Self.xrechnungXML,
                                                 payload: ScanPayloadParser.parse(Self.xrechnungXML))
        XCTAssertTrue(invoice.headline.contains("invoice"), invoice.headline)
    }

    func testSecretRedactionBlanksCredentials() {
        XCTAssertFalse(SecretRedaction.redactForModel("WIFI:T:WPA;S:Net;P:hunter2;;")
            .contains("hunter2"))
        XCTAssertFalse(SecretRedaction.redactForModel(
            "otpauth://totp/x?secret=JBSWY3DPEHPK3PXP").contains("JBSWY3DPEHPK3PXP"))
        XCTAssertFalse(SecretRedaction.redactForModel("password=correcthorsebattery")
            .contains("correcthorsebattery"))
        XCTAssertTrue(SecretRedaction.redactForModel(String(repeating: "a", count: 5000)).count <= 2000)
    }

    func testComposeFallbackReadsWifiAndUrl() {
        guard let wifi = HeuristicExplainer.compose(
            request: "wifi network BlueHouse password hunter2 hidden") else {
            return XCTFail("Expected a wifi compose result")
        }
        XCTAssertEqual(wifi.kind, .wifi)
        XCTAssertEqual(wifi.value("ssid"), "BlueHouse")
        XCTAssertEqual(wifi.value("password"), "hunter2")
        XCTAssertEqual(wifi.value("hidden"), "true")

        guard let url = HeuristicExplainer.compose(request: "url https://example.com/a") else {
            return XCTFail("Expected a url compose result")
        }
        XCTAssertEqual(url.kind, .url)
        XCTAssertEqual(url.text, "https://example.com/a")

        XCTAssertNil(HeuristicExplainer.compose(request: "just some words"))
    }

    // The Android port's `AssistantTest` cases, on the same inputs: the rule
    // engine and the redaction in front of it are deterministic, so both
    // ports must give the same answers word for word.

    func testRedactionKeepsFieldNamesAndBlanksValues() {
        let wifi = SecretRedaction.redactForModel("WIFI:T:WPA;S:BlueHouse;P:hunter2hidden;H:false;;")
        XCTAssertFalse(wifi.contains("hunter2hidden"), wifi)
        XCTAssertTrue(wifi.contains("P:<redacted>"), wifi)
        XCTAssertTrue(wifi.contains("S:BlueHouse"), wifi)

        let otp = SecretRedaction.redactForModel(
            "otpauth://totp/ACME:alice@acme.com?secret=JBSWY3DPEHPK3PXP&issuer=ACME")
        XCTAssertFalse(otp.contains("JBSWY3DPEHPK3PXP"), otp)
        XCTAssertTrue(otp.contains("secret=<redacted>"), otp)

        XCTAssertFalse(SecretRedaction.redactForModel("password: sunshine2026").contains("sunshine2026"))
        XCTAssertFalse(SecretRedaction.redactForModel("pin = 4821").contains("4821"))

        let nostr = SecretRedaction.redactForModel("nsec1qvz8cq6d8t0f0y3gqk0q0m3v9z2xk")
        XCTAssertFalse(nostr.contains("qvz8cq6d8t0f0y3gqk0q0m3v9z2xk"), nostr)
        XCTAssertTrue(nostr.hasPrefix("nsec1"), nostr)

        let pem = SecretRedaction.redactForModel(
            "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEAy7Kd3nZ0m1VhQ3YrT0pLbCjF\n-----END RSA PRIVATE KEY-----")
        XCTAssertFalse(pem.contains("MIIEowIBAAKCAQEAy7Kd3nZ0m1VhQ3YrT0pLbCjF"), pem)
        XCTAssertTrue(pem.contains("-----BEGIN RSA PRIVATE KEY-----"), pem)

        XCTAssertTrue(SecretRedaction.redactForModel("lnbc" + String(repeating: "u", count: 400))
            .contains("<encoded-data omitted>"))
        XCTAssertEqual(SecretRedaction.redactForModel(String(repeating: "scan this ", count: 600)).count, 2000)
    }

    func testBuiltInExplainerWordingMatchesAndroid() {
        let wifi = "WIFI:T:WPA;S:BlueHouse;P:hunter2;H:true;;"
        let e = HeuristicExplainer.explain(raw: wifi, payload: ScanPayloadParser.parse(wifi))
        XCTAssertTrue(e.keyPoints.contains("Joins the Wi-Fi network \u{201C}BlueHouse\u{201D}."), "\(e.keyPoints)")
        XCTAssertTrue(e.keyPoints.contains("Security: WPA / WPA2."), "\(e.keyPoints)")
        XCTAssertTrue(e.keyPoints.contains("The network hides its name."), "\(e.keyPoints)")
        XCTAssertTrue(e.cautions.contains("Only join networks whose name you can see printed by the venue."),
                      "\(e.cautions)")

        let otp = "otpauth://totp/ACME:alice@acme.com?secret=JBSWY3DPEHPK3PXP&issuer=ACME"
        let o = HeuristicExplainer.explain(raw: otp, payload: ScanPayloadParser.parse(otp))
        XCTAssertEqual(o.headline, "A two-factor enrolment")
        XCTAssertTrue(o.cautions.contains { $0.localizedCaseInsensitiveContains("anyone holding this code") },
                      "\(o.cautions)")

        let mdl = HeuristicExplainer.explain(raw: MdocEngagementTests.annexDQR,
                                             payload: ScanPayloadParser.parse(MdocEngagementTests.annexDQR))
        XCTAssertEqual(mdl.headline, "A digital-ID engagement code")
        XCTAssertTrue(mdl.keyPoints.first?.hasPrefix("A digital-ID wallet's code for an ID reader") == true,
                      "\(mdl.keyPoints)")
        XCTAssertTrue(mdl.cautions.contains("Only show your own code to the reader you mean to share with."),
                      "\(mdl.cautions)")
    }

    func testComposeRuleEngineMatchesAndroid() {
        let named = HeuristicExplainer.compose(request: "wifi network named Casa Verde password verde2026 wpa3")
        XCTAssertEqual(named?.value("ssid"), "Casa Verde")
        XCTAssertEqual(named?.value("security"), "WPA3")
        XCTAssertEqual(named?.value("password"), "verde2026")
        XCTAssertEqual(named?.wifiSecurityTag, "SAE")

        let plain = HeuristicExplainer.compose(request: "wifi BlueHouse password hunter2 hidden")
        XCTAssertEqual(plain?.value("ssid"), "BlueHouse")
        XCTAssertEqual(plain?.source, .builtIn)
        XCTAssertEqual(plain?.isHiddenNetwork, true)

        let url = HeuristicExplainer.compose(request: "url https://example.com/menu")
        XCTAssertEqual(url?.kind, .url)
        XCTAssertEqual(url?.text, "https://example.com/menu")
        XCTAssertEqual(url?.values.isEmpty, true)
        XCTAssertEqual(url?.isBlank, false)

        XCTAssertNil(HeuristicExplainer.compose(request: "make me a code for my coffee shop"))
        XCTAssertNil(HeuristicExplainer.compose(request: "wifi"))

        let blank = ComposeResult(kind: .wifi, values: ["ssid": "  ", "password": "hunter2"],
                                  text: "", source: .builtIn)
        XCTAssertNil(blank.value("SSID"))
        XCTAssertEqual(blank.value("Password"), "hunter2")
        XCTAssertNil(blank.value("missing"))
    }

    // MARK: - NFC tag codec (1.10)
    //
    // The pure half of `NFCTagWriter.swift`: what goes onto a tag and what
    // comes back off one. No Core NFC types are involved, so it runs on the
    // simulator; the session half needs a real iPhone and a real tag.

    func testNDEFTextRecordIsStatusLanguageThenUTF8() {
        let r = NDEFRecordCodec.textRecord("Pass #42", languageTag: "en")
        XCTAssertEqual(r.format, 0x01)
        XCTAssertEqual(r.type, Data("T".utf8))
        // Status byte: UTF-16 bit clear, low six bits = "en".count.
        XCTAssertEqual(r.payload, Data([0x02]) + Data("en".utf8) + Data("Pass #42".utf8))
        XCTAssertEqual(NDEFRecordCodec.textFromPayload(r.payload), "Pass #42")

        let unicode = NDEFRecordCodec.textRecord("Grüße ✓ 日本", languageTag: "DE-de ")
        XCTAssertEqual(unicode.payload.prefix(6), Data([0x05]) + Data("de-de".utf8))
        XCTAssertEqual(NDEFRecordCodec.textFromPayload(unicode.payload), "Grüße ✓ 日本")

        XCTAssertEqual(NDEFRecordCodec.normalizedLanguageTag(""), "en")
        XCTAssertEqual(NDEFRecordCodec.normalizedLanguageTag("!!!"), "en")
        XCTAssertEqual(NDEFRecordCodec.normalizedLanguageTag("  fr "), "fr")
        XCTAssertEqual(NDEFRecordCodec.normalizedLanguageTag(String(repeating: "a", count: 80)).count, 63)
    }

    func testNDEFTextReaderAcceptsEveryUTF16Spelling() {
        let language = Data("en".utf8)
        // What Core NFC's own `wellKnownTypeTextPayload(string:locale:)` writes.
        var littleEndianBOM = Data([0x82]) + language + Data([0xFF, 0xFE])
        littleEndianBOM.append("Hi ✓".data(using: .utf16LittleEndian)!)
        XCTAssertEqual(NDEFRecordCodec.textFromPayload(littleEndianBOM), "Hi ✓")
        // RTD Text means big-endian when there is no byte-order mark.
        var bigEndian = Data([0x82]) + language
        bigEndian.append("Hi ✓".data(using: .utf16BigEndian)!)
        XCTAssertEqual(NDEFRecordCodec.textFromPayload(bigEndian), "Hi ✓")
        var bigEndianBOM = Data([0x82]) + language + Data([0xFE, 0xFF])
        bigEndianBOM.append("Hi ✓".data(using: .utf16BigEndian)!)
        XCTAssertEqual(NDEFRecordCodec.textFromPayload(bigEndianBOM), "Hi ✓")

        XCTAssertNil(NDEFRecordCodec.textFromPayload(Data()))
        // Claims a four-byte language tag but carries two bytes in total.
        XCTAssertNil(NDEFRecordCodec.textFromPayload(Data([0x04, 0x65])))
        XCTAssertEqual(NDEFRecordCodec.textFromPayload(Data([0x00]) + Data("bare".utf8)), "bare")
    }

    func testNDEFURIRecordUsesTheLongestPrefix() {
        let codes: [(String, UInt8)] = [
            ("https://www.nettrash.me", 0x02), ("https://nettrash.me", 0x04),
            ("http://www.example.com", 0x01), ("tel:+15551234", 0x05), ("nettrash.me", 0x00),
            ("urn:epc:id:sgtin:1", 0x1E), ("ftp://ftp.x.org", 0x08),
            ("ftp://anonymous:anonymous@x", 0x07), ("urn:nfc:sn:1", 0x23),
            ("HTTPS://X.ORG", 0x00), ("mailto:a@b.c", 0x06),
        ]
        for (uri, code) in codes {
            let r = NDEFRecordCodec.uriRecord(uri)
            XCTAssertEqual(r.format, 0x01, uri)
            XCTAssertEqual(r.type, Data("U".utf8), uri)
            XCTAssertEqual(r.payload.first, code, uri)
            XCTAssertEqual(NDEFRecordCodec.uriFromPayload(r.payload), uri)
        }
        // An IRI keeps its exact characters rather than coming back percent-encoded.
        let iri = NDEFRecordCodec.uriRecord("https://example.com/ä")
        XCTAssertEqual(NDEFRecordCodec.uriFromPayload(iri.payload), "https://example.com/ä")
        XCTAssertNil(NDEFRecordCodec.uriFromPayload(Data([0x7F, 0x41])), "reserved identifier code")
        XCTAssertNil(NDEFRecordCodec.uriFromPayload(Data()))
        XCTAssertEqual(NDEFRecordCodec.uriPrefixes.count, 0x24)
    }

    func testNFCKindIsInferredFromWhatTheCodeEncodes() {
        let wifi = CodeComposer.wifi(ssid: "Guest", password: "s3cret", security: .wpa)
        let vcard = CodeComposer.vCard(fullName: "Jane Doe", phone: "+15551234")
        XCTAssertEqual(NFCTagPayloadKind.inferred(from: wifi), .wifi)
        XCTAssertEqual(NFCTagPayloadKind.inferred(from: vcard), .contact)
        XCTAssertEqual(NFCTagPayloadKind.inferred(from: "https://nettrash.me"), .url)
        XCTAssertEqual(NFCTagPayloadKind.inferred(from: "HTTP://x.org"), .url)
        XCTAssertEqual(NFCTagPayloadKind.inferred(from: "httpfoo"), .text)
        XCTAssertEqual(NFCTagPayloadKind.inferred(from: "tel:+15551234"), .url)
        XCTAssertEqual(NFCTagPayloadKind.inferred(from: "hello"), .text)
    }

    func testNFCWriteRequestValidity() {
        XCTAssertFalse(NFCTagWriteRequest(kind: .url, value: "nettrash.me").isValid)
        XCTAssertTrue(NFCTagWriteRequest(kind: .url, value: "https://nettrash.me").isValid)
        XCTAssertFalse(NFCTagWriteRequest(kind: .text, value: "   ").isValid)
        XCTAssertTrue(NFCTagWriteRequest(kind: .text, value: "  hi  ").isValid)
        XCTAssertNil(NDEFRecordCodec.records(for: NFCTagWriteRequest(kind: .url, value: "nettrash.me")))

        XCTAssertTrue(NDEFRecordCodec.hasScheme("web+scan://x"))
        XCTAssertTrue(NDEFRecordCodec.hasScheme("mailto:hi@example.com"))
        XCTAssertFalse(NDEFRecordCodec.hasScheme("12:30"))
        XCTAssertFalse(NDEFRecordCodec.hasScheme(":nope"))
        XCTAssertFalse(NDEFRecordCodec.hasScheme("nettrash.me"))

        // A URL is trimmed and abbreviated on its way onto the tag.
        let url = NDEFRecordCodec.records(for: NFCTagWriteRequest(kind: .url,
                                                                  value: "  https://www.nettrash.me/scan "))
        XCTAssertEqual(url?.count, 1)
        XCTAssertEqual(url?.first?.payload.first, 0x02)
        XCTAssertEqual(url.flatMap(NDEFRecordCodec.readableString(in:)), "https://www.nettrash.me/scan")
    }

    func testWiFiTagIsAWSCTokenThatReadsBackAsTheSameNetwork() {
        let value = CodeComposer.wifi(ssid: "Guest;Net", password: "s3cr:et", security: .wpa)
        guard let records = NDEFRecordCodec.records(for: NFCTagWriteRequest(kind: .wifi, value: value)),
              let record = records.first else { return XCTFail("Expected a record") }
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(record.format, 0x02)
        XCTAssertEqual(record.type, Data("application/vnd.wfa.wsc".utf8))
        guard case let .wifi(ssid, password, security, hidden) =
                ScanPayloadParser.parse(NDEFRecordCodec.readableString(in: records) ?? "") else {
            return XCTFail("Expected the token to read back as Wi-Fi")
        }
        XCTAssertEqual(ssid, "Guest;Net")
        XCTAssertEqual(password, "s3cr:et")
        XCTAssertEqual(security, "WPA")
        XCTAssertFalse(hidden)

        // The token byte for byte — the same fixture and bytes as the Android
        // port's `wpaNetworkBecomesAWifiSimpleConfigToken`: Version 1.0;
        // Credential { index 1, SSID, WPA2-Personal, AES, key, broadcast MAC };
        // the WFA vendor extension with Version2 = 2.0.
        let guest = "WIFI:T:WPA;S:Guest;P:s3cret;;"
        let expected = Data(hex: "104A 0001 10" + "100E 002E" + "1026 0001 01"
            + "1045 0005 4775657374" + "1003 0002 0020" + "100F 0002 0008"
            + "1027 0006 733363726574" + "1020 0006 FFFFFFFFFFFF" + "1049 0006 00372A000120")
        XCTAssertEqual(WiFiSimpleConfig.token(forWiFiString: guest), expected)
        XCTAssertEqual(NDEFRecordCodec.records(for: NFCTagWriteRequest(kind: .wifi, value: guest))?.first?.payload,
                       expected)
        XCTAssertEqual(WiFiSimpleConfig.wifiString(fromToken: expected), guest)

        // An open network is a WSC token too, and reads back as open.
        let open = CodeComposer.wifi(ssid: "Cafe", security: .open)
        let openRecords = NDEFRecordCodec.records(for: NFCTagWriteRequest(kind: .wifi, value: open))
        XCTAssertEqual(openRecords?.first?.format, 0x02)
        guard case let .wifi(openSSID, openPassword, openSecurity, _) =
                ScanPayloadParser.parse(openRecords.flatMap(NDEFRecordCodec.readableString(in:)) ?? "") else {
            return XCTFail("Expected the open token to read back as Wi-Fi")
        }
        XCTAssertEqual(openSSID, "Cafe")
        XCTAssertTrue(openPassword?.isEmpty ?? true)
        XCTAssertEqual(openSecurity, "nopass")
    }

    func testWiFiNetworksWSCCannotDescribeKeepTheirWIFIText() {
        let cases: [(String, String)] = [
            ("WPA3", CodeComposer.wifi(ssid: "Home", password: "longpassword", security: .wpa3)),
            ("WEP", CodeComposer.wifi(ssid: "Old", password: "12345", security: .wep)),
            ("Passpoint", CodeComposer.wifi(ssid: "Air", password: "x", security: .passpoint)),
            ("hidden", CodeComposer.wifi(ssid: "Hid", password: "longpassword", security: .wpa, hidden: true)),
            ("long SSID", CodeComposer.wifi(ssid: String(repeating: "x", count: 33),
                                            password: "longpassword", security: .wpa)),
            ("WPA without a password", "WIFI:T:WPA;S:Net;;"),
        ]
        for (label, value) in cases {
            let records = NDEFRecordCodec.records(for: NFCTagWriteRequest(kind: .wifi, value: value))
            XCTAssertEqual(records?.first?.format, 0x01, label)
            XCTAssertEqual(records?.first?.type, Data("T".utf8), label)
            XCTAssertEqual(records.flatMap(NDEFRecordCodec.readableString(in:)), value, label)
        }
        // No type but a password is ambiguous, so it stays text too.
        XCTAssertNil(WiFiSimpleConfig.token(forWiFiString: "WIFI:S:Ambiguous;P:secret12;;"))

        XCTAssertNil(WiFiSimpleConfig.wifiString(fromToken: Data([0x10, 0x0E, 0x00, 0x10, 0x01])),
                     "a truncated token is rejected")
        XCTAssertNil(WiFiSimpleConfig.wifiString(fromToken: Data(hex: "100E 00FF 1045")))
        XCTAssertNil(WiFiSimpleConfig.wifiString(fromToken: Data()))
        // An enterprise (EAP) network's sign-in can't ride in a WIFI: string.
        let enterprise = Data(hex: "104A 0001 10" + "100E 0016" + "1045 0006 4F6666696365"
            + "1003 0002 0010" + "100F 0002 0008")
        XCTAssertNil(WiFiSimpleConfig.wifiString(fromToken: enterprise))
    }

    func testContactTagIsAVCardMediaRecord() {
        let vcard = CodeComposer.vCard(fullName: "Jane Doe", phone: "+15551234",
                                       email: "jane@example.com", organization: "ACME")
        let records = NDEFRecordCodec.records(for: NFCTagWriteRequest(kind: .contact, value: vcard))
        XCTAssertEqual(records?.first?.format, 0x02)
        XCTAssertEqual(records?.first?.type, Data("text/vcard".utf8))
        XCTAssertEqual(records.flatMap(NDEFRecordCodec.readableString(in:)), vcard)

        // A contact that isn't a vCard rides as text, as its QR would.
        let mecard = "MECARD:N:Doe,Jane;;"
        let text = NDEFRecordCodec.records(for: NFCTagWriteRequest(kind: .contact, value: mecard))
        XCTAssertEqual(text?.first?.format, 0x01)
        XCTAssertEqual(text.flatMap(NDEFRecordCodec.readableString(in:)), mecard)
    }

    func testNDEFReadTakesTheFirstReadableRecord() {
        let first = NDEFRecordCodec.readableString(in: [
            .init(format: 0x04, type: Data("android.com:pkg".utf8), payload: Data("me.nettrash.scan".utf8)),
            NDEFRecordCodec.uriRecord("https://nettrash.me"),
            NDEFRecordCodec.textRecord("title", languageTag: "en"),
        ])
        XCTAssertEqual(first, "https://nettrash.me", "external types are skipped; the first readable record wins")
        XCTAssertNil(NDEFRecordCodec.readableString(in: [NDEFRecordCodec.textRecord("   ", languageTag: "en")]))
        XCTAssertNil(NDEFRecordCodec.readableString(in: [.init(format: 0x01, type: Data("Sp".utf8),
                                                               payload: Data([0xD1]))]),
                     "a smart poster whose payload isn't a whole NDEF message is skipped")

        // NDEF 1.0 puts an absolute URI in the TYPE field; some writers use the payload.
        XCTAssertEqual(NDEFRecordCodec.readableString(in: .init(format: 0x03,
                                                                type: Data("https://abs.example/x".utf8),
                                                                payload: Data())),
                       "https://abs.example/x")
        XCTAssertEqual(NDEFRecordCodec.readableString(in: .init(format: 0x03, type: Data(),
                                                                payload: Data("https://abs.example/y".utf8))),
                       "https://abs.example/y")
        let legacyVCard = NDEFRecordCodec.Record(format: 0x02,
                                                 type: Data("Text/X-VCard; charset=utf-8".utf8),
                                                 payload: Data("BEGIN:VCARD\r\nFN:A\r\nEND:VCARD".utf8))
        XCTAssertEqual(NDEFRecordCodec.readableString(in: legacyVCard)?.hasPrefix("BEGIN:VCARD"), true)
    }

    // MARK: - Bulk capture (1.10)

    @MainActor
    func testBulkSessionDedupesByValue() {
        let session = BulkScanSession()
        session.start()
        func code(_ v: String) -> ScannedCode {
            ScannedCode(value: v, symbology: .qr, avType: "org.iso.QRCode",
                        timestamp: Date(), previewRect: nil)
        }
        XCTAssertTrue(session.ingest(code("a")))
        XCTAssertFalse(session.ingest(code("a")), "a repeat must not count as new")
        XCTAssertTrue(session.ingest(code("b")))
        XCTAssertEqual(session.count, 2)
        XCTAssertEqual(session.entries.first(where: { $0.value == "a" })?.sightings, 2)
    }

    @MainActor
    func testBulkSessionExportsCSVAndDeletes() {
        let session = BulkScanSession()
        session.start()
        func code(_ v: String) -> ScannedCode {
            ScannedCode(value: v, symbology: .qr, avType: "org.iso.QRCode",
                        timestamp: Date(), previewRect: nil)
        }
        session.ingest(code("plain"))
        session.ingest(code("has,comma"))
        let csv = session.csvText()
        XCTAssertTrue(csv.hasPrefix("value,symbology,kind,sightings,first_seen"), csv)
        XCTAssertTrue(csv.contains("\"has,comma\""), csv)

        session.remove(at: IndexSet(integer: 0))
        XCTAssertEqual(session.count, 1)
        // Deleting frees the dedupe slot, so the removed value is new again.
        XCTAssertTrue(session.ingest(code("plain")))
    }

    // The Android port's `BulkScanSessionTest` cases on the same inputs.

    @MainActor
    private func bulkCode(_ value: String, symbology: Symbology = .qr,
                          at timestamp: Date = Date()) -> ScannedCode {
        ScannedCode(value: value, symbology: symbology, avType: "org.iso.QRCode",
                    timestamp: timestamp, previewRect: nil)
    }

    @MainActor
    func testBulkCSVHasTheHistoryShapeAndKeepsMultiLineValuesInOneRow() {
        let session = BulkScanSession()
        session.start()
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        session.ingest(bulkCode("HELLO,WORLD", symbology: .code128, at: stamp))
        session.ingest(bulkCode("say \"hi\"", at: stamp))
        let csv = session.csvText()
        XCTAssertTrue(csv.hasPrefix("value,symbology,kind,sightings,first_seen\n"), csv)
        // A comma forces quoting; an embedded quote is doubled and the whole
        // field wrapped — the same escape the History export uses.
        XCTAssertTrue(csv.contains("\"HELLO,WORLD\",Code 128,"), csv)
        XCTAssertTrue(csv.contains("\"say \"\"hi\"\"\""), csv)
        XCTAssertTrue(csv.contains(",1,2023-11-14T22:13:20.000Z"), csv)

        let cards = BulkScanSession()
        cards.start()
        let card = "BEGIN:VCARD\nVERSION:3.0\nFN:Jo\nEND:VCARD"
        cards.ingest(bulkCode(card, at: stamp))
        cards.ingest(bulkCode("plain", at: stamp))
        let lines = cards.csvLines()
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "value,symbology,kind,sightings,first_seen")
        XCTAssertTrue(lines[1].hasPrefix("\"BEGIN:VCARD\nVERSION:3.0\nFN:Jo\nEND:VCARD\",QR,"), lines[1])
        XCTAssertTrue(lines[2].hasPrefix("plain,QR,"), lines[2])
        XCTAssertEqual(cards.csvText(), lines.joined(separator: "\n"))
    }

    @MainActor
    func testBulkRemovalReindexesTheSurvivors() {
        let session = BulkScanSession()
        session.start()
        session.ingest(bulkCode("A"))
        session.ingest(bulkCode("B"))
        session.ingest(bulkCode("A"))
        session.remove(at: IndexSet(integer: 0))
        XCTAssertEqual(session.entries.map(\.value), ["B"])
        XCTAssertTrue(session.ingest(bulkCode("A")), "a removed value is new again")
        // A later sighting of B lands on B's row, not on whatever moved into
        // its old index.
        XCTAssertFalse(session.ingest(bulkCode("B")))
        XCTAssertEqual(session.entries.map(\.value), ["B", "A"])
        XCTAssertEqual(session.entries.map(\.sightings), [2, 1])

        let three = BulkScanSession()
        three.start()
        for value in ["A", "B", "C"] { three.ingest(bulkCode(value)) }
        guard let target = three.entries.first(where: { $0.value == "B" }) else { return XCTFail("Expected B") }
        three.remove(target)
        XCTAssertEqual(three.entries.map(\.value), ["A", "C"])
        XCTAssertTrue(three.ingest(bulkCode("B")))
    }

    @MainActor
    func testBulkCapacityStartAndStopRules() {
        let session = BulkScanSession()
        XCTAssertFalse(session.ingest(bulkCode("A")), "ignored while stopped")
        session.start()
        XCTAssertFalse(session.ingest(bulkCode("")), "empty values are ignored")

        var added = 0
        for i in 0..<(BulkScanSession.capacity + 20) where session.ingest(bulkCode("code-\(i)")) {
            added += 1
        }
        XCTAssertEqual(added, BulkScanSession.capacity)
        XCTAssertTrue(session.isFull)
        // Still counts sightings on codes already in the list at the cap.
        XCTAssertFalse(session.ingest(bulkCode("code-0")))
        XCTAssertEqual(session.entries.first?.sightings, 2)

        session.reset()
        XCTAssertTrue(session.isEmpty)
        XCTAssertTrue(session.ingest(bulkCode("A")))
        // Entering Bulk again resumes the same capture; only Clear empties it.
        session.stop()
        session.start()
        XCTAssertEqual(session.entries.map(\.value), ["A"])
        XCTAssertTrue(session.isRunning)
    }
}

// MARK: - CBOR test fixtures (ISO 18013-5 handovers)
//
// Just enough of a CBOR encoder (RFC 8949 definite-length heads, text/byte
// strings, arrays, maps, booleans) to build reader requests byte by byte, so
// the mDL tests don't depend on the reader they are testing.

private func cborHead(_ major: UInt8, _ arg: Int) -> [UInt8] {
    let m = major << 5
    if arg < 24 { return [UInt8(m | UInt8(arg))] }
    if arg < 256 { return [UInt8(m | 24), UInt8(arg)] }
    return [UInt8(m | 25), UInt8(arg >> 8), UInt8(arg & 0xFF)]
}

private func cborText(_ s: String) -> [UInt8] {
    let b = Array(s.utf8)
    return cborHead(3, b.count) + b
}

private func cborBytes(_ b: [UInt8]) -> [UInt8] { cborHead(2, b.count) + b }
private func cborBool(_ v: Bool) -> [UInt8] { [UInt8(v ? 0xF5 : 0xF4)] }

private func cborArray(_ items: [[UInt8]]) -> [UInt8] {
    cborHead(4, items.count) + items.flatMap { $0 }
}

private func cborMap(_ pairs: [([UInt8], [UInt8])]) -> [UInt8] {
    cborHead(5, pairs.count) + pairs.flatMap { $0.0 + $0.1 }
}

private extension Data {
    /// Bytes from a hex string; spaces are ignored. Test fixtures only.
    init(hex: String) {
        let digits = hex.filter { !$0.isWhitespace }
        var bytes: [UInt8] = []
        var index = digits.startIndex
        while index < digits.endIndex {
            let next = digits.index(index, offsetBy: 2)
            bytes.append(UInt8(digits[index..<next], radix: 16) ?? 0)
            index = next
        }
        self.init(bytes)
    }
}

private func base64URL(_ bytes: [UInt8]) -> String {
    Data(bytes).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

// MARK: - ISO/IEC 18013-5 / 18013-7 mdoc engagement (1.10)
//
// `mdoc:` and `mdoc://` codes, mirrored fixture for fixture (and row for row)
// by the Android port's `IdentityPayloadTest`. The first fixture is the
// standard's own DeviceEngagement test vector; the others reuse its key.

final class MdocEngagementTests: XCTestCase {

    /// ISO/IEC 18013-5:2021 Annex D.3.1: the DeviceEngagement test vector, as printed.
    static let annexDHex =
        "a30063312e30018201d818584ba4010220012158205a88d182bce5f42efa59943f33359d2e8a968ff289d93e"
        + "5fa444b624343167fe225820b16e8cf858ddc7690407ba61d4c338237a8cfcf3de6aa672fc60a557aa32fc67"
        + "0281830201a300f401f50b5045efef742b2c4837a9a3b0e1d05a6917"

    /// `annexDHex` as clause 8.2.2.3 puts it in a QR: `mdoc:` + base64url, no padding.
    static let annexDQR =
        "mdoc:owBjMS4wAYIB2BhYS6QBAiABIVggWojRgrzl9C76WZQ_MzWdLoqWj_KJ2T5fpES2JDQxZ_4iWCCxboz4WN3"
        + "HaQQHumHUwzgjeoz8895qpnL8YKVXqjL8ZwKBgwIBowD0AfULUEXv73QrLEg3qaOw4dBaaRc"

    /// Spruce isomdl's QR example: Bluetooth peripheral server mode only.
    static let isomdlQR =
        "mdoc:owBjMS4wAYIB2BhYS6QBAiABIVgglyWXuAyJ6iRNc8OlYXenvkJt23rJPdtIhlawXqr-yf0iWCC1GQSH8tI"
        + "wTYVwha_ZoPL20_saYXrGIbrCm133H0ki-QKBgwIBowD1AfQKUH2RiuAEbUVzrsrOiUnSPDw"

    /// Annex D's key with NFC, both Bluetooth modes (UUIDs and an address), Wi-Fi Aware with the
    /// passphrase "wifi-pass-hunter2", and WebAPI + OIDC server retrieval with tokens.
    static let richQR =
        "mdoc:pABjMS4wAYIB2BhYS6QBAiABIVggWojRgrzl9C76WZQ_MzWdLoqWj_KJ2T5fpES2JDQxZ_4iWCCxboz4WN3"
        + "HaQQHumHUwzgjeoz8895qpnL8YKVXqjL8ZwKDgwEBogAY_wEZAQCDAgGlAPUB9QpQRe_vdCssSDepo7Dh0FppFwt"
        + "QRe_vdCssSDepo7Dh0FppFxRGChssPU5fgwMBogBxd2lmaS1wYXNzLWh1bnRlcjICBgOiZndlYkFwaYMBeCFodHR"
        + "wczovL21kbC5pc3N1ZXIuZXhhbXBsZS9hcGkvdjFzV0VCQVBJLVRPS0VOLVNFQ1JFVGRvaWRjgwF4I2h0dHBzOi8"
        + "vSUQuSXNzdWVyLkV4YW1wbGU6ODQ0My9vaWRjcU9JREMtVE9LRU4tU0VDUkVU"

    /// A second-edition Reader QR: ReaderEngagement 1.1, Bluetooth only, no keys 5 or 6.
    static let readerQR =
        "mdoc:owBjMS4xAYIB2BhYS6QBAiABIVggWojRgrzl9C76WZQ_MzWdLoqWj_KJ2T5fpES2JDQxZ_4iWCCxboz4WN3"
        + "HaQQHumHUwzgjeoz8895qpnL8YKVXqjL8ZwKBgwIBowD0AfULUEXv73QrLEg3qaOw4dBaaRc"

    /// DeviceEngagement 1.1 with OriginInfos (5) and Capabilities (6) and an X25519 key.
    static let deviceEngagement11QR =
        "mdoc:pQBjMS4xAYIB2BhYKKMBASAEIVggWojRgrzl9C76WZQ_MzWdLoqWj_KJ2T5fpES2JDQxZ_4CgYMCAaMA9QH"
        + "0ClBF7-90KyxIN6mjsOHQWmkXBYAGoQL1"

    /// ISO/IEC 18013-7 Annex A, laid out as the multipaz verifier builds it: an HTTP method
    /// (type 4) to https://verifier.example.com/verifier/annexARequest?sessionId=1234.
    static let onlineURI =
        "mdoc://pABjMS4xAYIB2BhYS6QBAiABIVggWojRgrzl9C76WZQ_MzWdLoqWj_KJ2T5fpES2JDQxZ_4iWCCxboz4W"
        + "N3HaQQHumHUwzgjeoz8895qpnL8YKVXqjL8ZwKBgwQBoQB4Qmh0dHBzOi8vdmVyaWZpZXIuZXhhbXBsZS5jb20vd"
        + "mVyaWZpZXIvYW5uZXhBUmVxdWVzdD9zZXNzaW9uSWQ9MTIzNAWA"

    /// The same request to https://issuer.gov@evil.example/x — user-info hiding the real host.
    static let spoofURI =
        "mdoc://pABjMS4xAYIB2BhYS6QBAiABIVggWojRgrzl9C76WZQ_MzWdLoqWj_KJ2T5fpES2JDQxZ_4iWCCxboz4W"
        + "N3HaQQHumHUwzgjeoz8895qpnL8YKVXqjL8ZwKBgwQBoQB4IWh0dHBzOi8vaXNzdWVyLmdvdkBldmlsLmV4YW1wb"
        + "GUveAWA"

    /// `{0: "1.0", 1: "nope", 2: []}` — Security is not an array.
    static let badSecurityQR = "mdoc:owBjMS4wAWRub3BlAoA"

    /// Cipher suite 2, a key on curve 300, method type 9 and a Bluetooth method with no options.
    static let oddQR = "mdoc:owBjMS4wAYIC2BhHogECIBkBLAKCgwkBoIMCAaA"

    /// Version "1.0-beta", NFC only.
    static let oddVersionQR =
        "mdoc:owBoMS4wLWJldGEBggHYGFhLpAECIAEhWCBaiNGCvOX0LvpZlD8zNZ0uipaP8onZPl-kRLYkNDFn_iJYILF"
        + "ujPhY3cdpBAe6YdTDOCN6jPzz3mqmcvxgpVeqMvxnAoGDAQGiABj_ARkBAA"

    /// A COSE key labelled by text: present, but not readable.
    static let textLabelKeyQR = "mdoc:ogBjMS4wAYIB2BhGoWNrdHkC"

    /// No Security at all.
    static let noKeyQR = "mdoc:ogBjMS4wAoGDAgGiAPUB9A"

    /// multipaz's second-edition device QR transcript: DeviceEngagement 1.1, OriginInfos, Capabilities.
    static let multipazDeviceQR =
        "mdoc:pQBjMS4xAYIB2BhYS6QBAiABIVggWojRgrzl9C76WZQ_MzWdLoqWj_KJ2T5fpES2JDQxZ_4iWCCxboz4WN3"
        + "HaQQHumHUwzgjeoz8895qpnL8YKVXqjL8ZwKBgwIBowD0AfULUAAAAAGhI0jOiWtMdpczc-YFgAaiA_UE9Q"

    /// multipaz's Reader QR transcript (Annex D's reader key): ReaderEngagement 1.1, GATT central.
    static let multipazReaderQR =
        "mdoc:owBjMS4xAYIB2BhYS6QBAiABIVggYOM5I4UEH1FAMFHyQVUxy1bdP5mccWhwE6rGdovIGH4iWCDljeuP2-k"
        + "H991TaCRVUaNHlvfSIVxEDDObsPe2e-zN-gKBgwIBowD0AfULUAAAAAGhI0jOiWtMdpczc-Y"

    /// The same reader offering both GATT modes plus L2CAP (BleOptions keys 2, 3 and 21).
    static let multipazReaderL2capQR =
        "mdoc:owBjMS4xAYIB2BhYS6QBAiABIVggYOM5I4UEH1FAMFHyQVUxy1bdP5mccWhwE6rGdovIGH4iWCDljeuP2-k"
        + "H991TaCRVUaNHlvfSIVxEDDObsPe2e-zN-gKBgwIBpwD1AfUC9AP1ClAAAAACoSNIzolrTHaXM3PmC1AAAAABoSN"
        + "IzolrTHaXM3PmFRiA"


    private func engagement(_ raw: String, file: StaticString = #filePath,
                            line: UInt = #line) -> MobileDrivingLicensePayload? {
        guard case .mobileDrivingLicense(let p) = ScanPayloadParser.parse(raw) else {
            XCTFail("Expected .mobileDrivingLicense for \(raw.prefix(48))", file: file, line: line)
            return nil
        }
        return p
    }

    private func rows(_ p: MobileDrivingLicensePayload) -> [String] {
        p.labelledFields.map { "\($0.label): \($0.value)" }
    }

    private static let holderRows = [
        "Format: ISO/IEC 18013-5 device engagement",
        "Shown by: A digital-ID wallet (mDL, EU PID or other mdoc)",
        "Meant for: An ID reader",
    ]

    func testAnnexDFixtureIsTheStandardsOwnBytes() {
        XCTAssertEqual("mdoc:" + base64URL(Array(Data(hex: Self.annexDHex))), Self.annexDQR)
        XCTAssertEqual(MobileDrivingLicenseParser.decodeBase64URL(String(Self.annexDQR.dropFirst(5))),
                       Array(Data(hex: Self.annexDHex)))
    }

    func testDecodesTheAnnexDDeviceEngagement() {
        guard let p = engagement(Self.annexDQR) else { return }
        XCTAssertEqual(p.kind, .deviceEngagement)
        XCTAssertTrue(p.decoded)
        XCTAssertEqual(p.version, "1.0")
        XCTAssertEqual(p.cipherSuite, 1)
        XCTAssertEqual(p.key, .init(kty: 2, crv: 1))
        XCTAssertEqual(p.channels, [.bluetooth(peripheralServer: false, centralClient: true)])
        XCTAssertTrue(p.serverRetrieval.isEmpty)
        XCTAssertEqual(ScanPayloadParser.parse(Self.annexDQR).kindLabel, "Digital ID")
        XCTAssertEqual(rows(p), Self.holderRows + [
            "ID data: None — only how to connect",
            "Version: 1.0",
            "Channels: Bluetooth LE",
            "Bluetooth LE: Central client mode",
            "Cipher suite: 1 (ECDH, AES-256-GCM)",
            "Device key: P-256 (EC2), one-time key",
        ])

        let e = HeuristicExplainer.explain(raw: Self.annexDQR, payload: ScanPayloadParser.parse(Self.annexDQR))
        XCTAssertEqual(e.headline, "A digital-ID engagement code")
        XCTAssertEqual(e.keyPoints, [
            "A digital-ID wallet's code for an ID reader (ISO/IEC 18013-5), for a mobile driving licence, an EU PID or another mdoc.",
            "A reader can connect over Bluetooth LE.",
            "It carries a fresh one-time key, not the ID itself.",
        ])
        for caution in [
            "Scan is not an ID reader: it cannot request or read the document.",
            "A nearby reader can use this code to start a request, which the wallet still asks its holder to approve.",
            "Only show your own code to the reader you mean to share with.",
        ] {
            XCTAssertTrue(e.cautions.contains(caution), caution)
        }
    }

    func testDecodesIsomdlsPeripheralServerExample() {
        guard let p = engagement(Self.isomdlQR) else { return }
        XCTAssertEqual(p.kind, .deviceEngagement)
        XCTAssertEqual(p.channels, [.bluetooth(peripheralServer: true, centralClient: false)])
        XCTAssertEqual(rows(p), Self.holderRows + [
            "ID data: None — only how to connect",
            "Version: 1.0",
            "Channels: Bluetooth LE",
            "Bluetooth LE: Peripheral server mode",
            "Cipher suite: 1 (ECDH, AES-256-GCM)",
            "Device key: P-256 (EC2), one-time key",
        ])
    }

    func testShowsHostsButNeverTokensPassphrasesOrRadioIdentifiers() {
        guard let p = engagement(Self.richQR) else { return }
        XCTAssertEqual(p.channels, [.nfc, .bluetooth(peripheralServer: true, centralClient: true), .wifiAware])
        XCTAssertEqual(p.serverRetrieval, [.init(method: "WebAPI", host: "mdl.issuer.example"),
                                           .init(method: "OIDC", host: "id.issuer.example")])
        XCTAssertEqual(rows(p), Self.holderRows + [
            "ID data: None — only how to connect",
            "Version: 1.0",
            "Channels: NFC, Bluetooth LE, Wi-Fi Aware",
            "Bluetooth LE: Peripheral server and central client modes",
            "Server retrieval: WebAPI at mdl.issuer.example, OIDC at id.issuer.example",
            "Cipher suite: 1 (ECDH, AES-256-GCM)",
            "Device key: P-256 (EC2), one-time key",
        ])
        let token = "It also carries a server-retrieval token: whoever scans it can ask the issuer for the holder's data directly."
        XCTAssertEqual(p.warnings, ["Only show your own code to the reader you mean to share with.", token])

        let e = HeuristicExplainer.explain(raw: Self.richQR, payload: ScanPayloadParser.parse(Self.richQR))
        XCTAssertTrue(e.keyPoints.contains("A reader can connect over NFC, Bluetooth LE or Wi-Fi Aware."), "\(e.keyPoints)")
        XCTAssertTrue(e.cautions.contains(token), "\(e.cautions)")
        let shown = (rows(p) + e.keyPoints + e.cautions + p.warnings + [e.headline, e.summary, p.notice])
            .joined(separator: "\n")
        for secret in ["hunter2", "TOKEN", "SECRET", "45ef", "45EF", "0a1b2c", "/api/v1", "8443", "/oidc"] {
            XCTAssertFalse(shown.contains(secret), secret)
        }
    }

    func testReaderQRIsTheReadersCodeNotTheHolders() {
        guard let p = engagement(Self.readerQR) else { return }
        XCTAssertEqual(p.kind, .readerEngagement)
        XCTAssertEqual(ScanPayloadParser.parse(Self.readerQR).kindLabel, "ID Reader")
        XCTAssertEqual(rows(p), [
            "Format: ISO/IEC 18013-5 reader engagement",
            "Shown by: An ID reader",
            "Meant for: A digital-ID wallet (mDL, EU PID or other mdoc)",
            "ID data: None — only how to connect",
            "Version: 1.1",
            "Channels: Bluetooth LE",
            "Bluetooth LE: Central client mode",
            "Cipher suite: 1 (ECDH, AES-256-GCM)",
            "Reader key: P-256 (EC2), one-time key",
        ])
        let e = HeuristicExplainer.explain(raw: Self.readerQR, payload: ScanPayloadParser.parse(Self.readerQR))
        XCTAssertEqual(e.headline, "An ID reader's engagement code")
        XCTAssertEqual(e.keyPoints, [
            "An ID reader's code for a digital-ID wallet (ISO/IEC 18013-5): it invites a wallet to connect so the reader can ask for an ID.",
            "A wallet would connect over Bluetooth LE.",
            "It carries the reader's one-time key, not anyone's ID.",
        ])
        for caution in [
            "Scan is not a wallet: it cannot answer the reader or share a document.",
            "Scanned with a wallet, it lets the reader ask for data, and the wallet asks you to approve what is shared.",
            "Only scan a reader's code with your wallet where you meant to show your ID.",
        ] {
            XCTAssertTrue(e.cautions.contains(caution), caution)
        }
    }

    func testDeviceEngagement11StaysTheHolders() {
        // OriginInfos and Capabilities only ever ride in a DeviceEngagement.
        guard let p = engagement(Self.deviceEngagement11QR) else { return }
        XCTAssertEqual(p.kind, .deviceEngagement)
        XCTAssertEqual(p.key, .init(kty: 1, crv: 4))
        XCTAssertEqual(rows(p), Self.holderRows + [
            "ID data: None — only how to connect",
            "Version: 1.1",
            "Channels: Bluetooth LE",
            "Bluetooth LE: Peripheral server mode",
            "Cipher suite: 1 (ECDH, AES-256-GCM)",
            "Device key: X25519 (OKP), one-time key",
        ])
    }

    func testSecondEditionQRsAreToldApart() {
        // multipaz's transcripts: its device QR carries OriginInfos and
        // Capabilities, its Reader QR (Annex D's reader key) neither.
        guard let device = engagement(Self.multipazDeviceQR), let reader = engagement(Self.multipazReaderQR),
              let l2cap = engagement(Self.multipazReaderL2capQR) else { return }
        XCTAssertEqual(device.kind, .deviceEngagement)
        XCTAssertEqual(rows(device), Self.holderRows + [
            "ID data: None — only how to connect",
            "Version: 1.1",
            "Channels: Bluetooth LE",
            "Bluetooth LE: Central client mode",
            "Cipher suite: 1 (ECDH, AES-256-GCM)",
            "Device key: P-256 (EC2), one-time key",
        ])
        XCTAssertEqual(reader.kind, .readerEngagement)
        XCTAssertEqual(Array(rows(reader).prefix(3)), [
            "Format: ISO/IEC 18013-5 reader engagement",
            "Shown by: An ID reader",
            "Meant for: A digital-ID wallet (mDL, EU PID or other mdoc)",
        ])
        XCTAssertEqual(rows(reader).last, "Reader key: P-256 (EC2), one-time key")
        XCTAssertEqual(l2cap.kind, .readerEngagement)
        XCTAssertTrue(rows(l2cap).contains("Bluetooth LE: Peripheral server and central client modes"), "\(rows(l2cap))")
    }

    func testOnlineRequestShowsTheSitesHostOnly() {
        guard let p = engagement(Self.onlineURI) else { return }
        XCTAssertEqual(p.kind, .onlineRequest)
        XCTAssertEqual(p.channels, [.website(host: "verifier.example.com")])
        XCTAssertEqual(ScanPayloadParser.parse(Self.onlineURI).kindLabel, "ID Request")
        XCTAssertEqual(rows(p), [
            "Format: ISO/IEC 18013-7 online request",
            "Shown by: A website",
            "Meant for: A digital-ID wallet (mDL, EU PID or other mdoc)",
            "ID data: None — only how to connect",
            "Version: 1.1",
            "Channels: Website",
            "Website: verifier.example.com",
            "Cipher suite: 1 (ECDH, AES-256-GCM)",
            "Reader key: P-256 (EC2), one-time key",
        ])
        let e = HeuristicExplainer.explain(raw: Self.onlineURI, payload: ScanPayloadParser.parse(Self.onlineURI))
        XCTAssertEqual(e.headline, "An online ID request")
        XCTAssertEqual(e.keyPoints, [
            "A website's request for a digital ID (ISO/IEC 18013-7): it asks a wallet to share a mobile driving licence, an EU PID or another mdoc online.",
            "A wallet would connect to verifier.example.com.",
            "It carries the site's one-time key, not anyone's ID.",
        ])
        for caution in [
            "Scan is not a wallet: it cannot answer this request or share a document.",
            "Opened in a wallet, it lets the site ask for data, and the wallet asks you to approve what is shared.",
            "Only continue in your wallet for a site you opened yourself, and check its address.",
        ] {
            XCTAssertTrue(e.cautions.contains(caution), caution)
        }
        let shown = (rows(p) + e.keyPoints + e.cautions).joined(separator: "\n")
        XCTAssertFalse(shown.contains("sessionId"))
        XCTAssertFalse(shown.contains("1234"))

        // Only the authority is the engagement; a path or query after it is not.
        guard let extra = engagement(Self.onlineURI + "/ignored?x=1#y") else { return }
        XCTAssertEqual(rows(extra), rows(p))
    }

    func testWebsiteBehindUserInfoIsNotShown() {
        guard let p = engagement(Self.spoofURI) else { return }
        XCTAssertEqual(p.channels, [.website(host: nil)])
        XCTAssertTrue(rows(p).contains("Website: Unusual address — not shown"), "\(rows(p))")
        let e = HeuristicExplainer.explain(raw: Self.spoofURI, payload: ScanPayloadParser.parse(Self.spoofURI))
        let shown = (rows(p) + e.keyPoints + e.cautions).joined(separator: "\n")
        XCTAssertFalse(shown.contains("issuer.gov"))
        XCTAssertFalse(shown.contains("evil"))
    }

    func testSheetTextPerKind() {
        guard let device = engagement(Self.annexDQR), let reader = engagement(Self.readerQR),
              let online = engagement(Self.onlineURI) else { return }
        XCTAssertEqual(device.warnings, ["Only show your own code to the reader you mean to share with."])
        XCTAssertEqual(reader.warnings, ["Only scan a reader's code with your wallet where you meant to show your ID."])
        XCTAssertEqual(online.warnings, ["Only continue in your wallet for a site you opened yourself, and check its address."])
        XCTAssertEqual(device.notice, "Scan is not an ID reader and cannot request or read the document. A nearby reader can use this code to start a request, which the wallet still asks its holder to approve. The code carries a fresh one-time key, so it is not the ID itself.")
        XCTAssertEqual(reader.notice, "Scan is not a wallet and cannot answer the reader. Scanned with a wallet, the code lets the reader ask for data, and the wallet asks you to approve what is shared. It carries the reader's one-time key, not anyone's ID.")
        XCTAssertEqual(online.notice, "Scan is not a wallet and cannot answer this request. Opened in a wallet, the code lets the site ask for data, and the wallet asks you to approve what is shared. It carries the site's one-time key, not anyone's ID.")
    }

    func testHostIsStrictAndASCIIOnly() {
        let cases: [(String, String?)] = [
            ("https://Verifier.Example.COM:443/x", "verifier.example.com"),
            ("HTTP://192.168.1.10/a?b#c", "192.168.1.10"),
            ("https://xn--mller-kva.de", "xn--mller-kva.de"),
            ("https://example.com?x", "example.com"),
            ("https://a@b.example/", nil),
            ("https://example.com\\@evil.example/", nil),
            ("https://exa\u{212A}mple.com/", nil),      // Kelvin sign, which lower-cases to "k"
            ("https://ex\u{0430}mple.com/", nil),       // Cyrillic a
            ("https://example..com/", nil),
            ("https://.example.com/", nil),
            ("https://example.com:65536/", nil),
            ("https://example.com:/", nil),
            ("https://[::1]/", nil),
            ("https://exa mple.com/", nil),
            ("ftp://example.com/", nil),
            ("https://", nil),
            ("example.com", nil),
        ]
        for (url, expected) in cases {
            XCTAssertEqual(MobileDrivingLicenseParser.host(ofURL: url), expected, url)
        }
    }

    func testRecognisesOnlyTheMdocScheme() {
        for raw in [Self.annexDQR, "MDOC:" + String(Self.annexDQR.dropFirst(5)), Self.onlineURI, "mdoc:AAAA"] {
            XCTAssertTrue(MobileDrivingLicenseParser.looksLikeMdocURI(raw), raw)
        }
        let annexB = "mdoc-openid4vp://?client_id=x&request_uri=https%3A%2F%2Fv.example%2Fr"
        for raw in ["mdoc:", "mdoc://", "mdoc:///x", "mdocx:owBj", "mdoc owBj", "mdoc:owBj ok",
                    "https://example.com/mdoc:owBj", "mdoc:owBj\u{301}",
                    "mDL=?docType=org.iso.18013.5.1.mDL&readerRequest=oQ", annexB] {
            XCTAssertFalse(MobileDrivingLicenseParser.looksLikeMdocURI(raw), raw)
        }
        // ISO/IEC 18013-7 Annex B is an OpenID4VP request, not an engagement:
        // the dispatch leaves it to the verifiable-credential parser.
        if case .mobileDrivingLicense = ScanPayloadParser.parse(annexB) {
            XCTFail("mdoc-openid4vp:// is not an mdoc engagement")
        }
    }

    func testUndecodableMdocIsRecognisedButSaysSo() {
        let undecodable = [
            "mdoc:AAAA",                                    // CBOR 0 0 0: not one map
            Self.badSecurityQR,                             // Security is text
            String(Self.annexDQR.dropLast()) + "d",         // spare bits set
            "mdoc:ow=Bj",                                   // padding in the middle
            "mdoc:o",                                       // impossible length
            Self.annexDQR + "AAAA",                         // data after the map
            "mdoc:" + String(repeating: "A", count: 5_000), // over the length cap
        ]
        for raw in undecodable {
            guard let p = engagement(raw) else { continue }
            XCTAssertFalse(p.decoded, raw)
            XCTAssertEqual(rows(p), Self.holderRows + ["Contents: Not decodable — damaged or a newer version"], raw)
        }
        let e = HeuristicExplainer.explain(raw: "mdoc:AAAA", payload: ScanPayloadParser.parse("mdoc:AAAA"))
        XCTAssertEqual(e.keyPoints, [
            "A digital-ID wallet's code for an ID reader (ISO/IEC 18013-5), for a mobile driving licence, an EU PID or another mdoc.",
            "Its contents could not be decoded — it may be damaged or a newer version.",
        ])
        guard let online = engagement("mdoc://AAAA") else { return }
        XCTAssertEqual(online.kind, .onlineRequest)
        XCTAssertFalse(online.decoded)
    }

    func testOddValuesAreNamedNotGuessed() {
        guard let odd = engagement(Self.oddQR) else { return }
        XCTAssertEqual(odd.channels, [.other(type: 9), .bluetooth(peripheralServer: false, centralClient: false)])
        XCTAssertEqual(rows(odd), Self.holderRows + [
            "ID data: None — only how to connect",
            "Version: 1.0",
            "Channels: Type 9, Bluetooth LE",
            "Bluetooth LE: No mode stated",
            "Cipher suite: 2 (unknown)",
            "Device key: Curve 300 (EC2), one-time key",
        ])
        let e = HeuristicExplainer.explain(raw: Self.oddQR, payload: ScanPayloadParser.parse(Self.oddQR))
        XCTAssertTrue(e.keyPoints.contains("A reader can connect over Bluetooth LE."), "\(e.keyPoints)")

        guard let version = engagement(Self.oddVersionQR), let textLabel = engagement(Self.textLabelKeyQR),
              let noKey = engagement(Self.noKeyQR) else { return }
        XCTAssertEqual(Array(rows(version).dropFirst(3)), [
            "ID data: None — only how to connect",
            "Version: Unrecognised",
            "Channels: NFC",
            "Cipher suite: 1 (ECDH, AES-256-GCM)",
            "Device key: P-256 (EC2), one-time key",
        ])
        XCTAssertEqual(Array(rows(textLabel).suffix(3)), [
            "Channels: None stated",
            "Cipher suite: 1 (ECDH, AES-256-GCM)",
            "Device key: Present, type not readable",
        ])
        XCTAssertEqual(Array(rows(noKey).suffix(4)), [
            "Channels: Bluetooth LE",
            "Bluetooth LE: Peripheral server mode",
            "Cipher suite: Not stated",
            "Device key: Missing",
        ])
    }

    func testHostileEngagementsFailCleanly() {
        let version = (cborHead(0, 0), cborText("1.0"))
        // Retrieval methods nested far past the reader's cap — decoded
        // directly, and through a code short enough to stay under the
        // length cap.
        XCTAssertNil(MobileDrivingLicenseParser.decodeEngagement(
            cborMap([version, (cborHead(0, 2), [UInt8](repeating: 0x81, count: 20_000) + [0x01])])))
        let deep = cborMap([version, (cborHead(0, 2), [UInt8](repeating: 0x81, count: 2_000) + [0x01])])
        XCTAssertEqual(engagement("mdoc:" + base64URL(deep))?.decoded, false)
        // A map that promises four billion entries, and a Security array
        // that promises as many.
        XCTAssertNil(MobileDrivingLicenseParser.decodeEngagement([0xBA, 0xFF, 0xFF, 0xFF, 0xFF] + version.0 + version.1))
        XCTAssertNil(MobileDrivingLicenseParser.decodeEngagement(
            cborMap([version, (cborHead(0, 1), [0x9A, 0xFF, 0xFF, 0xFF, 0xFF, 0x01])])))

        // Random bytes, half of them behind a map head: never a crash.
        var state: UInt32 = 0x9E37_79B9
        func next() -> UInt32 {
            state ^= state << 13
            state ^= state >> 17
            state ^= state << 5
            return state
        }
        for round in 0..<3_000 {
            var bytes = (0..<Int(next() % 96)).map { _ in UInt8(truncatingIfNeeded: next()) }
            if round % 2 == 0 { bytes.insert(0xA0 | UInt8(next() % 8), at: 0) }
            let raw = (round % 3 == 0 ? "mdoc://" : "mdoc:") + base64URL(bytes)
            _ = MobileDrivingLicenseParser.parse(raw)?.labelledFields
        }
    }

    // MARK: PayloadCodec — the Android port's `PayloadCodecTest` runs the same documents

    private func json(_ text: String) -> [String: Any]? {
        PayloadCodec.jsonObject(fromJSONData: Data(text.utf8))
    }

    func testJSONNestingStopsAtTheSharedCap() {
        func objects(_ n: Int) -> String { String(repeating: #"{"a":"#, count: n) + "1" + String(repeating: "}", count: n) }
        func arrays(_ n: Int) -> String { #"{"a":"# + String(repeating: "[", count: n) + String(repeating: "]", count: n) + "}" }
        XCTAssertEqual(PayloadCodec.maxJSONDepth, 64)
        XCTAssertNotNil(json(objects(64)))
        XCTAssertNil(json(objects(65)))
        XCTAssertNotNil(json(arrays(63)))           // 64 containers, counting the object
        XCTAssertNil(json(arrays(64)))
        XCTAssertNil(json(arrays(100_000)))
        // Brackets inside a string are text, escaped quotes and all.
        let text = #"{"s":""# + String(repeating: "[{", count: 200) + #"\"]}","n":"#
        XCTAssertNotNil(json(text + objects(63) + "}"))
        XCTAssertNil(json(text + objects(64) + "}"))
        XCTAssertTrue(PayloadCodec.jsonNestingIsWithinLimit(Data(#"{"a":"[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[["}"#.utf8)))
    }

    func testJSONIsUTF8WithoutNULs() {
        XCTAssertNotNil(json(#"{"a":1}"#))
        XCTAssertNotNil(PayloadCodec.jsonObject(fromJSONData: Data([0xEF, 0xBB, 0xBF] + Array(#"{"a":1}"#.utf8))))
        XCTAssertNotNil(json(#"{"a":"\u0000"}"#))   // an escaped NUL is text
        XCTAssertNil(PayloadCodec.jsonObject(fromJSONData: Data([0x7B, 0x00, 0x7D, 0x00])))              // UTF-16LE
        XCTAssertNil(PayloadCodec.jsonObject(fromJSONData: Data([0xFF, 0xFE, 0x7B, 0x00, 0x7D, 0x00])))  // with a BOM
        XCTAssertNil(PayloadCodec.jsonObject(fromJSONData: Data([0x00, 0x7B, 0x00, 0x7D])))              // UTF-16BE
        XCTAssertNil(PayloadCodec.jsonObject(fromJSONData: Data([0x7B, 0x7D, 0x00])))
        XCTAssertNil(PayloadCodec.jsonObject(fromJSONData: Data([0x7B, 0x22, 0x61, 0x22, 0x3A, 0x22, 0xFF, 0x22, 0x7D])))
    }

    func testBase64URLTrimsSwiftsWhitespaceOnly() {
        XCTAssertEqual(PayloadCodec.base64URLString(" aGk\n"), "hi")
        XCTAssertEqual(PayloadCodec.base64URLString("\u{85}aGk\u{2028}"), "hi")
        XCTAssertEqual(PayloadCodec.base64URLString("\u{200B}aGk"), "hi")
        XCTAssertNil(PayloadCodec.base64URLString("\u{1F}aGk"))
        XCTAssertNil(PayloadCodec.base64URLString("aGk\u{1C}"))
    }
} // MdocEngagementTests

// MARK: - OpenID4VP / OpenID4VCI / HAIP and GS1 country AIs (1.10)
//
// Spec fixtures for the wallet codes (OpenID4VP 1.0, OpenID4VCI 1.0, HAIP
// 1.0, ISO/IEC 18013-7 Annex B, RFC 9901) and the Digital Product
// Passport's GS1 country AIs 421–426. The Android port's
// `VerifiableCredentialPayloadTest` and `DigitalProductPassportTest` run
// the same inputs, byte for byte, against the same expected rows.

import CoreImage    // CIDetector: the fixture-corpus test's QR decoder in the Simulator

final class CredentialAndPassportSpecTests: XCTestCase {

    private let pidName = "EU Digital Identity — PID"
    private let mdlName = "Mobile driving licence (ISO 18013-5)"
    private let approveOnlyYours = "Only approve a request you started yourself — approving one "
        + "someone sent you releases your data to them."
    private let unsolicited = "Installing a credential from an unsolicited QR is how fake wallets "
        + "and impersonation kits spread."

    /// HAIP 1.0: signed request by reference, `x509_hash` verifier, POST fetch.
    private let haipRequest = "haip-vp://?client_id=x509_hash%3AUvo3HtuIxuhC92rShpgqcT3YXwrqRxWEviRiA0OZszk"
        + "&request_uri=https%3A%2F%2Fverifier.example.org%2Frequest%2Fvapof4ql2i7m41m68uep"
        + "&request_uri_method=post"

    /// OpenID4VP 1.0 §5.10's by-reference shape with an `x509_san_dns` verifier.
    private let x509DnsRequest = "openid4vp://?client_id=x509_san_dns%3Aclient.example.org"
        + "&request_uri=https%3A%2F%2Fclient.example.org%2F567545564"

    /// The IANA registration's example for ISO/IEC 18013-7 Annex B.
    private let mdocRequest = "mdoc-openid4vp://?client_id=example.com"
        + "&request_uri=https%3A%2F%2Fexample.com%2F567545564"

    /// OpenID4VCI 1.0 §4.1.2's by-value offer URI, verbatim.
    private let specOffer = "openid-credential-offer://?credential_offer=%7B%22credential_issuer%22:"
        + "%22https://credential-issuer.example.com%22,%22credential_configuration_ids%22:"
        + "%5B%22org.iso.18013.5.1.mDL%22%5D,%22grants%22:%7B%22urn:ietf:params:oauth:grant-type:"
        + "pre-authorized_code%22:%7B%22pre-authorized_code%22:%22oaKazRN8I0IbtZ0C7JuMn5%22,"
        + "%22tx_code%22:%7B%22input_mode%22:%22text%22,%22description%22:%22Please%20enter%20the%20"
        + "serial%20number%20of%20your%20physical%20drivers%20license%22%7D%7D%7D%7D"

    /// OpenID4VCI 1.0 §4.1.3's by-reference offer URI, verbatim.
    private let specOfferByReference = "openid-credential-offer://?credential_offer_uri="
        + "https%3A%2F%2Fserver%2Eexample%2Ecom%2Fcredential-offer%2FGkurKxf5T0Y-mnPFCHqWOMiZi4VS138cQO_V7PZHAdM"

    /// A by-value request for a PID and an mDL (OpenID4VP 1.0 Appendix D.2 shape).
    private var dcqlRequest: String {
        "openid4vp://?response_type=vp_token&response_mode=direct_post"
            + "&client_id=redirect_uri%3Ahttps%3A%2F%2Fclient.example.org%2Fpost"
            + "&response_uri=https%3A%2F%2Fclient.example.org%2Fpost"
            + "&nonce=n-0S6_WzA2Mj&state=eyJhb4f&dcql_query=" + alnum(
                #"{"credentials":[{"id":"pid","format":"dc+sd-jwt","meta":{"vct_values":["urn:eudi:pid:1"]},"#
                + #""claims":[{"path":["given_name"]},{"path":["family_name"]},{"path":["address","street_address"]}]},"#
                + #"{"id":"mdl","format":"mso_mdoc","meta":{"doctype_value":"org.iso.18013.5.1.mDL"},"#
                + #""claims":[{"path":["org.iso.18013.5.1","given_name"]},{"path":["org.iso.18013.5.1","portrait"]}]}]}"#
            )
    }

    // MARK: Helpers

    private func alnum(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
    }

    private func b64(_ s: String) -> String { base64URL(Array(s.utf8)) }

    private func parse(_ raw: String, file: StaticString = #filePath, line: UInt = #line)
        -> VerifiableCredentialPayload? {
        let p = VerifiableCredentialParser.parse(raw)
        XCTAssertNotNil(p, "Expected a wallet code: \(raw)", file: file, line: line)
        return p
    }

    private func offer(_ json: String) -> VerifiableCredentialPayload? {
        parse("openid-credential-offer://?credential_offer=" + alnum(json))
    }

    /// Label → value, the last row winning, as Kotlin's `associate` does.
    private func rows(_ p: VerifiableCredentialPayload?) -> [String: String] {
        Dictionary((p?.labelledFields ?? []).map { ($0.label, $0.value) }, uniquingKeysWith: { _, last in last })
    }

    private func fields(_ pairs: [(String, String)]) -> [LabelledField] {
        pairs.map { LabelledField(label: $0.0, value: $0.1) }
    }

    private func assertContainsInOrder(_ haystack: [String], _ needles: [String],
                                       file: StaticString = #filePath, line: UInt = #line) {
        var index = haystack.startIndex
        for needle in needles {
            guard let found = haystack[index...].firstIndex(of: needle) else {
                return XCTFail("\(needle) missing or out of order in \(haystack)", file: file, line: line)
            }
            index = haystack.index(after: found)
        }
    }

    // MARK: Presentation requests

    func testHAIPByReferenceRequestIsNotAReplayAlarm() {
        XCTAssertTrue(VerifiableCredentialParser.looksLikeCredentialRequest(haipRequest))
        guard case .verifiableCredential(let vc) = ScanPayloadParser.parse(haipRequest) else {
            return XCTFail("Expected .verifiableCredential")
        }
        XCTAssertEqual(vc.kind, .presentationRequest)
        XCTAssertTrue(vc.byReference)
        XCTAssertEqual(vc.referenceHost, "verifier.example.org")
        XCTAssertNil(vc.counterpartyHost)
        XCTAssertTrue(vc.decoded)
        XCTAssertEqual(vc.labelledFields, fields([
            ("Type", "Credential request"),
            ("Asking for", "Not in the code — your wallet fetches the details"),
            ("Verifier", "Unnamed — identified by certificate hash"),
            ("Request", "Your wallet fetches it from verifier.example.org by POST"),
            ("Anti-replay", "Inside the fetched request — not in the code"),
        ]))
        XCTAssertEqual(vc.cautions, [approveOnlyYours])
        XCTAssertEqual(vc.counterpartyDescription, "a verifier identified only by a certificate hash")
        XCTAssertEqual(vc.footnote, "Scan decodes this code to explain it. It does not fetch the request, "
            + "answer it, or verify any signature.")
    }

    func testByReferenceRequestNamesTheDNSVerifierAndTheFetch() {
        let vc = parse(x509DnsRequest)
        let r = rows(vc)
        XCTAssertEqual(r["Verifier"], "client.example.org")
        XCTAssertEqual(r["Request"], "Your wallet fetches it from client.example.org")
        XCTAssertEqual(r["Anti-replay"], "Inside the fetched request — not in the code")
        XCTAssertEqual(vc?.counterpartyHost, "client.example.org")
        XCTAssertEqual(vc?.clientIDPrefix, "x509_san_dns")
        XCTAssertEqual(vc?.cautions, [approveOnlyYours])
    }

    func testMdocOpenID4VPRequestFromISO18013Part7() {
        XCTAssertTrue(VerifiableCredentialParser.looksLikeCredentialRequest(mdocRequest))
        guard case .verifiableCredential(let vc) = ScanPayloadParser.parse(mdocRequest) else {
            return XCTFail("Expected .verifiableCredential, got \(ScanPayloadParser.parse(mdocRequest).kindLabel)")
        }
        XCTAssertEqual(vc.labelledFields, fields([
            ("Type", "Credential request"),
            ("Format", "mso_mdoc"),
            ("Asking for", "Not in the code — your wallet fetches the details"),
            ("Verifier", "example.com"),
            ("Request", "Your wallet fetches it from example.com"),
            ("Anti-replay", "Inside the fetched request — not in the code"),
        ]))
    }

    func testDCQLQueriesAreNamedByWhatTheyAskFor() {
        guard let vc = parse(dcqlRequest) else { return }
        XCTAssertEqual(vc.requested, [pidName, mdlName])
        XCTAssertEqual(vc.claims, ["given_name", "family_name", "address.street_address", "portrait"])
        XCTAssertEqual(vc.labelledFields, fields([
            ("Type", "Credential request"),
            ("Format", "dc+sd-jwt, mso_mdoc"),
            ("Asking for", "\(pidName) + 1 more"),
            ("Verifier", "client.example.org"),
            ("Answer goes to", "client.example.org"),
            ("Anti-replay", "Nonce + state"),
            ("↳", mdlName),
            ("Claims asked for", "given_name, family_name, address.street_address, portrait"),
        ]))
        // The verifier-local query ids are never what the user is shown.
        XCTAssertFalse(vc.labelledFields.contains { $0.value == "pid" || $0.value == "mdl" })
        XCTAssertEqual(vc.clientIDPrefix, "redirect_uri")
        XCTAssertEqual(vc.cautions, [approveOnlyYours, biometricCaution("portrait")])
        XCTAssertEqual(vc.footnote,
                       "Scan decodes this code to explain it. It does not answer the request or verify its signature.")
    }

    func testDCQLSpecExampleAndClaimPaths() {
        func request(_ dcql: String) -> VerifiableCredentialPayload? {
            parse("openid4vp://?client_id=redirect_uri%3Ahttps%3A%2F%2Fv.example%2Fcb&nonce=1&dcql_query="
                  + alnum(dcql))
        }
        // OpenID4VP 1.0 Appendix D.1, verbatim.
        let d1 = request(#"{"credentials":[{"id":"my_credential","format":"mso_mdoc","#
            + #""meta":{"doctype_value":"org.iso.7367.1.mVRC"},"claims":["#
            + #"{"path":["org.iso.7367.1","vehicle_holder"]},{"path":["org.iso.18013.5.1","first_name"]}]}]}"#)
        XCTAssertEqual(d1?.requested, ["Vehicle registration certificate (ISO 7367)"])
        XCTAssertEqual(d1?.claims, ["vehicle_holder", "first_name"])

        // Array indices and the null wildcard drop out of a path; a path of
        // nothing but them is no claim at all.
        let paths = request(#"{"credentials":[{"id":"pid","format":"dc+sd-jwt","meta":{"vct_values":["urn:eudi:pid:1"]},"#
            + #""claims":[{"path":["nationalities",null]},{"path":["degrees",0,"type"]},{"path":[1]},"#
            + #"{"path":"given_name"},{"id":"x"}]}]}"#)
        XCTAssertEqual(paths?.claims, ["nationalities", "degrees.type"])

        // Twelve claims shown, the rest counted.
        let many = (1...15).map { "{\"path\":[\"c\($0)\"]}" }.joined(separator: ",")
        let capped = request(#"{"credentials":[{"id":"pid","format":"dc+sd-jwt","meta":{"vct_values":["urn:eudi:pid:1"]},"#
            + #""claims":["# + many + "]}]}")
        XCTAssertEqual(rows(capped)["Claims asked for"],
                       "c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12 + 3 more")
    }

    func testDCQLNamesByMetaThenIDThenFormat() {
        // The Android port's `dcqlNamesByMetaThenIdThenFormat`.
        let dcql = #"{"credentials":[{"id":"eu.europa.ec.eudi.pid.1"},"#
            + #"{"format":"dc+sd-jwt","meta":{"vct_values":["urn:eu.europa.ec.eudi:ehic:1"]}},"#
            + #"{"id":"pid","format":"dc+sd-jwt","meta":{"vct_values":[]}},"#
            + #"{"id":"ehic","format":"mso_mdoc","meta":{"doctype_value":"eu.europa.ec.eudi.ehic.1"}},"#
            + #"{"format":"mso_mdoc"},{}]}"#
        let vc = parse("openid4vp://authorize?client_id=https%3A%2F%2Fv.example&nonce=1&dcql_query=" + alnum(dcql))
        XCTAssertEqual(vc?.requested, [pidName, "European Health Insurance Card", "pid", "mso_mdoc", "credential"])
        XCTAssertEqual(vc?.format, "dc+sd-jwt, mso_mdoc")
    }

    func testSignedRequestObjectByValueCarriesItsNonce() {
        let payload = #"{"client_id":"x509_san_dns:client.example.org","response_type":"vp_token","#
            + #""response_mode":"direct_post","response_uri":"https://client.example.org/post","#
            + #""nonce":"n-0S6_WzA2Mj","dcql_query":{"credentials":[{"id":"pid","format":"dc+sd-jwt","#
            + #""meta":{"vct_values":["urn:eudi:pid:1"]}}]}}"#
        let jwt = b64(#"{"alg":"ES256","typ":"oauth-authz-req+jwt"}"#) + "." + b64(payload) + ".c2ln"
        let vc = parse("openid4vp://?client_id=x509_san_dns%3Aclient.example.org&request=\(jwt)")
        XCTAssertEqual(vc?.noncePresent, true)
        XCTAssertEqual(vc?.requested, [pidName])
        let r = rows(vc)
        XCTAssertEqual(r["Anti-replay"], "Nonce present")
        XCTAssertEqual(r["Answer goes to"], "client.example.org")
        XCTAssertEqual(r["Verifier"], "client.example.org")
        XCTAssertEqual(vc?.cautions, [approveOnlyYours])

        // A request object that does not decode may still hold a nonce.
        let opaque = parse("openid4vp://?client_id=x509_san_dns%3Aclient.example.org&request=a.b.c")
        XCTAssertEqual(opaque?.signedRequestUnreadable, true)
        XCTAssertEqual(rows(opaque)["Anti-replay"], "Inside the signed request — not readable")
        XCTAssertEqual(opaque?.cautions, [approveOnlyYours])
    }

    func testClientIdentifierPrefixesNameTheVerifier() {
        func verifier(_ clientID: String, _ extra: String = "") -> VerifiableCredentialPayload? {
            parse("openid4vp://?client_id=" + alnum(clientID) + extra
                  + "&request_uri=https%3A%2F%2Fverifier.example.org%2Fr%2F1")
        }
        let cases: [(String, String)] = [
            ("redirect_uri:https://client.example.org/cb", "client.example.org"),
            ("x509_san_dns:client.example.org", "client.example.org"),
            ("x509_hash:Uvo3HtuIxuhC92rShpgqcT3YXwrqRxWEviRiA0OZszk", "Unnamed — identified by certificate hash"),
            ("decentralized_identifier:did:example:123", "did:example:123"),
            ("decentralized_identifier:did:web:verifier.example.org", "verifier.example.org"),
            ("decentralized_identifier:did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK",
             "Unnamed — a bare key (did:key)"),
            ("verifier_attestation:verifier.example", "verifier.example"),
            ("openid_federation:https://federation-verifier.example.com", "federation-verifier.example.com"),
            ("origin:https://verifier.example.com/", "verifier.example.com"),
            ("s6BhdRkqt3", "s6BhdRkqt3"),
            ("https://verifier.example.gov", "verifier.example.gov"),
            ("did:example:123", "did:example:123"),
        ]
        for (clientID, expected) in cases {
            XCTAssertEqual(rows(verifier(clientID))["Verifier"], expected, clientID)
        }
        // A pre-1.0 request named its prefix in `client_id_scheme`.
        XCTAssertEqual(rows(verifier("verifier.example.org", "&client_id_scheme=x509_san_dns"))["Verifier"],
                       "verifier.example.org")
        XCTAssertEqual(verifier("decentralized_identifier:did:web:verifier.example.org")?.counterpartyHost,
                       "verifier.example.org")
        // `origin:` is reserved for browser requests; a QR must not use it.
        XCTAssertTrue(verifier("origin:https://verifier.example.com/")?.cautions.contains(
            "The verifier uses the origin: prefix, which is reserved for browser requests — "
                + "a wallet must refuse it in a QR code.") == true)
    }

    func testOnlyRealWalletSchemesAreClaimed() {
        XCTAssertEqual(VerifiableCredentialParser.requestSchemes, [
            "openid4vp", "eudi-openid4vp", "mdoc-openid4vp", "haip-vp", "haip",
            "openid-vc", "openid-credential-offer", "haip-vci",
        ])
        XCTAssertFalse(VerifiableCredentialParser.looksLikeCredentialRequest("pre-authorized-code://?client_id=x"))
        XCTAssertFalse(VerifiableCredentialParser.looksLikeCredentialRequest("openid-fhie://?client_id=x"))
        XCTAssertTrue(VerifiableCredentialParser.looksLikeCredentialRequest(
            "eudi-openid4vp://?client_id=x509_san_dns%3Averifier.example.org"
                + "&request_uri=https%3A%2F%2Fverifier.example.org%2Fr%2F1"))
        let vci = parse("haip-vci://?credential_offer_uri=https%3A%2F%2Fissuer.example.eu%2Fo%2F9")
        XCTAssertEqual(vci?.kind, .credentialOffer)
        XCTAssertEqual(rows(vci)["Offer"], "Your wallet fetches it from issuer.example.eu")

        // Microsoft Entra Verified ID: a request_uri and nothing else.
        let entra = parse("openid-vc://?request_uri=https%3A%2F%2Fverifiedid.example%2Freq%2F1")
        XCTAssertEqual(entra?.decoded, true)
        XCTAssertEqual(rows(entra)["Verifier"], "Not in the code")
        XCTAssertNil(rows(entra)["Claims"])
    }

    // MARK: Credential offers

    func testSpecCredentialOfferByValue() {
        XCTAssertTrue(VerifiableCredentialParser.looksLikeCredentialRequest(specOffer))
        guard case .verifiableCredential(let vc) = ScanPayloadParser.parse(specOffer) else {
            return XCTFail("Expected .verifiableCredential")
        }
        XCTAssertEqual(vc.labelledFields, fields([
            ("Type", "Credential offer"),
            ("Offering", mdlName),
            ("Issuer", "credential-issuer.example.com"),
            ("Sign-in", "Not needed — pre-authorised by the issuer"),
            ("Transaction code", "Required"),
        ]))
        XCTAssertEqual(vc.cautions, [unsolicited])
        XCTAssertEqual(vc.footnote,
                       "Scan decodes this code to explain it. It does not redeem the offer or contact the issuer.")
        // The pre-authorised code is a bearer secret.
        XCTAssertFalse(vc.labelledFields.contains { $0.value.contains("oaKazRN8I0IbtZ0C7JuMn5") })
        XCTAssertFalse(vc.explanationPoints.contains { $0.contains("oaKazRN8I0IbtZ0C7JuMn5") })
    }

    func testCredentialOfferGrants() {
        let issuer = #""credential_issuer":"https://credential-issuer.example.com""#
        let pre = #""urn:ietf:params:oauth:grant-type:pre-authorized_code""#
        // OpenID4VCI 1.0 §4.1.1.
        let twoConfigs = offer("{\(issuer),\"credential_configuration_ids\":[\"UniversityDegreeCredential\",\"org.iso.18013.5.1.mDL\"],"
            + "\"grants\":{\(pre):{\"pre-authorized_code\":\"oaKazRN8I0IbtZ0C7JuMn5\",\"tx_code\":{\"length\":4,"
            + "\"input_mode\":\"numeric\",\"description\":\"Please provide the one-time code that was sent via e-mail\"}}}}")
        XCTAssertEqual(rows(twoConfigs)["Offering"], "UniversityDegreeCredential + 1 more")
        XCTAssertEqual(rows(twoConfigs)["↳"], mdlName)
        XCTAssertEqual(rows(twoConfigs)["Transaction code"], "Required — 4 digits")
        XCTAssertEqual(twoConfigs?.cautions, [unsolicited])

        // §4.1.3, authorization code flow: the issuer_state stays out of sight.
        let signIn = offer("{\(issuer),\"credential_configuration_ids\":[\"UniversityDegreeCredential\"],"
            + "\"grants\":{\"authorization_code\":{\"issuer_state\":\"eyJhbGciOiJSU0Et...FYUaBy\"}}}")
        XCTAssertEqual(rows(signIn)["Sign-in"], "You'll sign in at the issuer")
        XCTAssertNil(rows(signIn)["Transaction code"])
        XCTAssertFalse(signIn?.labelledFields.contains { $0.value.contains("eyJhbGciOiJSU0Et") } ?? true)

        // §4.1.3, an empty tx_code still means a code will be asked for.
        let empty = offer("{\(issuer),\"credential_configuration_ids\":[\"UniversityDegree_LDP_VC\"],"
            + "\"grants\":{\(pre):{\"pre-authorized_code\":\"adhjhdjajkdkhjhdj\",\"tx_code\":{}}}}")
        XCTAssertEqual(rows(empty)["Transaction code"], "Required")

        // No tx_code: a bearer offer.
        let bearer = offer("{\(issuer),\"credential_configuration_ids\":[\"eu.europa.ec.eudi.pid_mdoc\"],"
            + "\"grants\":{\(pre):{\"pre-authorized_code\":\"adhjhdjajkdkhjhdj\"}}}")
        XCTAssertEqual(rows(bearer)["Transaction code"], "Not required — whoever redeems the code gets the credential")
        XCTAssertEqual(bearer?.cautions, [
            unsolicited,
            "Pre-authorised with no transaction code: whoever redeems this code first gets the "
                + "credential, so do not share or post it.",
        ])

        // Both grants, text code: the wallet picks.
        let both = offer("{\(issuer),\"credential_configuration_ids\":[\"UniversityDegreeCredential\"],"
            + "\"grants\":{\"authorization_code\":{\"authorization_server\":\"https://auth.example.com\"},"
            + "\(pre):{\"pre-authorized_code\":\"x\",\"tx_code\":{\"length\":6,\"input_mode\":\"text\"}}}}")
        XCTAssertEqual(rows(both)["Sign-in"], "Pre-authorised, or you sign in at auth.example.com — your wallet picks")
        XCTAssertEqual(rows(both)["Transaction code"], "Required — 6 characters")

        // A length that is not a JSON integer is not a length; `1` is not `true`.
        func txRow(_ tx: String) -> String? {
            rows(offer("{\(issuer),\"credential_configuration_ids\":[\"x\"],\"grants\":{\(pre):{\"pre-authorized_code\":\"x\",\(tx)}}}"))["Transaction code"]
        }
        XCTAssertEqual(txRow(#""tx_code":{"length":4.0}"#), "Required")
        XCTAssertEqual(txRow(#""tx_code":{"length":true}"#), "Required")
        XCTAssertEqual(txRow(#""tx_code":{"length":1}"#), "Required — 1 digit")
        XCTAssertEqual(txRow(#""user_pin_required":true"#), "Required")
        XCTAssertEqual(txRow(#""user_pin_required":1"#), "Not required — whoever redeems the code gets the credential")
    }

    func testSpecCredentialOfferByReference() {
        guard let vc = parse(specOfferByReference) else { return }
        XCTAssertEqual(vc.kind, .credentialOffer)
        XCTAssertTrue(vc.decoded)
        XCTAssertEqual(vc.labelledFields, fields([
            ("Type", "Credential offer"),
            ("Offering", "Not in the code — your wallet fetches the details"),
            ("Issuer", "Not in the code"),
            ("Offer", "Your wallet fetches it from server.example.com"),
        ]))
        XCTAssertEqual(vc.footnote,
                       "Scan decodes this code to explain it. It does not fetch the offer or contact the issuer.")
        XCTAssertEqual(vc.explanationPoints, [
            "An issuer is offering to add a credential to your digital-identity wallet.",
            "The offer itself is not in the code: your wallet fetches it from server.example.com.",
            "Issuer: Not in the code.",
        ])
    }

    func testEUReferenceIdentifiersReadAsTheirCredential() {
        let vc = offer(#"{"credential_issuer":"https://issuer.example.eu","credential_configuration_ids":["#
            + #""eu.europa.ec.eudi.pid_vc_sd_jwt","eu.europa.ec.eudi.pid_mdoc","#
            + #""eu.europa.ec.eudi.mdl_mdoc","eu.europa.ec.eudi.por_sd_jwt_vc"]}"#)
        XCTAssertEqual(vc?.requested, [pidName, mdlName, "eIDAS POR attribute set"])
        let names: [(String, String)] = [
            ("urn:eudi:pid:1", pidName),
            ("urn:eudi:pid:de:1", "EU Digital Identity — PID (DE)"),
            ("eu.europa.ec.eudi.photoid", "Photo ID (ISO/IEC 23220)"),
            ("eu.europa.ec.eudi.ehic_sd_jwt_vc", "European Health Insurance Card"),
            ("urn:eudi:ehic:1", "European Health Insurance Card"),
            ("eu.europa.ec.eudi.pid_mdoc_deferred", pidName),
            ("eu.europa.ec.eudi.tax_residency_vc_sd_jwt", "eIDAS TAX RESIDENCY attribute set"),
            ("org.iso.18013.5.1.mDL", mdlName),
            ("org.iso.23220.photoid.1", "Photo ID (ISO/IEC 23220)"),
            ("eu.europa.ec.eudi.mdl.1", "eIDAS MDL attribute set"),
            ("urn:eu.europa.ec.eudi:pboc:1", "eIDAS PBOC attribute set"),
            ("urn:eu.europa.ec.eudi:purse:1", "eIDAS PURSE attribute set"),
        ]
        for (id, expected) in names {
            XCTAssertEqual(VerifiableCredentialParser.typeName(id), expected, id)
        }
        // A `scope` that is a credential identifier reads as one.
        XCTAssertEqual(VerifiableCredentialParser.scopeName("urn:eudi:pid:de:1"), "EU Digital Identity — PID (DE)")
        XCTAssertEqual(VerifiableCredentialParser.scopeName("eu.europa.ec.eudi.pid_mdoc"), pidName)
        XCTAssertEqual(VerifiableCredentialParser.scopeName("some_brand_scope"), "Some Brand Scope")
        XCTAssertEqual(VerifiableCredentialParser.scopeName(""), "")
    }

    func testLegacyDraftOfferStillReads() {
        // Draft 11 (EBSI-era): `credentials` objects and `user_pin_required`.
        let vc = offer(#"{"credential_issuer":"https://issuer.example.eu","credentials":[{"format":"jwt_vc","#
            + #""types":["VerifiableCredential","VerifiableAttestation","CTWalletSamePreAuthorisedInTime"]},"#
            + #""UniversityDegree"],"grants":{"urn:ietf:params:oauth:grant-type:pre-authorized_code":"#
            + #"{"pre-authorized_code":"eyJ0eXAi","user_pin_required":true}}}"#)
        XCTAssertEqual(vc?.requested, ["CTWalletSamePreAuthorisedInTime", "UniversityDegree"])
        XCTAssertEqual(rows(vc)["Transaction code"], "Required")
        XCTAssertEqual(rows(vc)["Issuer"], "issuer.example.eu")

        // Each entry of a pre-1.0 `credentials` list is read on its own.
        let mixed = offer(#"{"credential_issuer":"https://i.example","formats":["jwt_vc_json"],"#
            + #""credentials":["UniversityDegree",{"credential_issuer":"https://other.example/x"}]}"#)
        XCTAssertEqual(mixed?.requested, ["UniversityDegree"])
        XCTAssertNil(mixed?.format)
        XCTAssertEqual(rows(mixed)["Offering"], "UniversityDegree")
    }

    // MARK: Tokens

    func testSDJWTWithKeyBindingIsAPresentation() {
        let issuerJWT = b64(#"{"alg":"ES256","typ":"dc+sd-jwt"}"#) + "."
            + b64(#"{"iss":"https://pid-issuer.example.eu","vct":"urn:eudi:pid:1","iat":1750000000,"#
                  + #""_sd":["a1","b2"],"_sd_alg":"sha-256","cnf":{"jwk":{"kty":"EC"}}}"#) + ".c2lnbmF0dXJl"
        let disclosure = b64(#"["2GLC42sKQveCfGfryNRN9w","given_name","Erika"]"#)
        let kb = b64(#"{"alg":"ES256","typ":"kb+jwt"}"#) + "."
            + b64(#"{"nonce":"1234567890","aud":"x509_hash:abc","iat":1750000100,"sd_hash":"0_Af-2B"}"#) + ".a2Jz"

        let presentation = "\(issuerJWT)~\(disclosure)~\(kb)"
        XCTAssertTrue(VerifiableCredentialParser.looksLikeCredentialToken(presentation))
        guard case .verifiableCredential(let vp) = ScanPayloadParser.parse(presentation) else {
            return XCTFail("Expected an SD-JWT presentation")
        }
        XCTAssertEqual(vp.kind, .presentation)
        XCTAssertEqual(vp.credentialType, "urn:eudi:pid:1")
        XCTAssertEqual(rows(vp)["Credential"], pidName)
        XCTAssertEqual(rows(vp)["Issuer"], "pid-issuer.example.eu")

        let credential = parse("\(issuerJWT)~\(disclosure)~")
        XCTAssertEqual(credential?.kind, .credential)
        XCTAssertEqual(credential?.selectivelyDisclosable, 2)
    }

    // MARK: Explainer

    func testExplainerSpeaksPerKind() {
        let offerExplained = HeuristicExplainer.explain(raw: specOffer, payload: ScanPayloadParser.parse(specOffer))
        XCTAssertEqual(offerExplained.headline, "Credential offer")
        assertContainsInOrder(offerExplained.keyPoints, [
            "An issuer is offering to add a credential to your digital-identity wallet.",
            "Offered: \(mdlName).",
            "Issuer: credential-issuer.example.com.",
            "Your wallet will ask for a transaction code before the credential is issued.",
        ])
        XCTAssertFalse(offerExplained.keyPoints.contains { $0.contains("oaKazRN8I0IbtZ0C7JuMn5") })
        XCTAssertFalse(offerExplained.summary.contains("oaKazRN8I0IbtZ0C7JuMn5"))

        let requestExplained = HeuristicExplainer.explain(raw: haipRequest,
                                                          payload: ScanPayloadParser.parse(haipRequest))
        assertContainsInOrder(requestExplained.keyPoints, [
            "A site is asking your digital-identity wallet to release attributes.",
            "The request itself is not in the code: your wallet fetches it from verifier.example.org.",
            "Verifier: Unnamed — identified by certificate hash.",
        ])
        XCTAssertFalse(requestExplained.cautions.contains(
            "No nonce: the same code can be replayed, so treat its contents as untrusted."))
    }

    // MARK: Digital Product Passport — GS1 country AIs

    func testShipToPostalCodeIsNotACountryOfOrigin() {
        // AI 421 is "ship to — deliver to postal code with ISO country
        // code": where the parcel goes, not where the product is from.
        let shipTo = "(01)04012345678901(17)261231(10)LOT42(421)27610115"
        guard case .gs1 = ScanPayloadParser.parse(shipTo) else {
            return XCTFail("A ship-to postal code must not make a passport")
        }
        guard let payload = GS1Parser.parse(shipTo) else { return XCTFail("Expected GS1") }
        XCTAssertFalse(DigitalProductPassportParser.looksLikePassport(payload))
        let dpp = DigitalProductPassportParser.parse(payload)
        XCTAssertNil(dpp.originNumeric)
        XCTAssertFalse(dpp.labelledFields.contains { $0.label == "Country of origin" })

        // With both, the origin is AI 422's, never the destination's.
        guard let both = GS1Parser.parse("(01)04012345678901(17)261231(10)LOT42(421)25075001(422)276") else {
            return XCTFail("Expected GS1")
        }
        XCTAssertEqual(DigitalProductPassportParser.parse(both).originDescription, "Germany (DEU)")
    }

    func testProcessingCountriesAreLabelledByTheirAI() {
        let raw = "(01)04012345678901(10)LOT42(17)261231(422)724(423)724250(424)276(425)276"
        guard case .digitalProductPassport(let dpp) = ScanPayloadParser.parse(raw) else {
            return XCTFail("Expected .digitalProductPassport")
        }
        XCTAssertEqual(dpp.labelledFields, fields([
            ("Format", "GS1 Digital Product Passport carrier"),
            ("Product (GTIN)", "04012345678901"),
            ("Batch / lot", "LOT42"),
            ("Expiry", "2026-12-31"),
            ("Country of origin", "Spain (ESP)"),
            ("Country of initial processing", "Spain (ESP), France (FRA)"),
            ("Country of processing", "Germany (DEU)"),
            ("Country of disassembly", "Germany (DEU)"),
            ("Read from", "the code itself — nothing was fetched"),
        ]))
    }

    func testFullProcessChainCountryMakesAPassport() {
        // GS1 uses 426 *instead of* 422 when one country covers it all.
        guard case .digitalProductPassport(let dpp) =
                ScanPayloadParser.parse("(01)04012345678901(10)LOT42(17)261231(426)380") else {
            return XCTFail("Expected .digitalProductPassport")
        }
        let r = Dictionary(dpp.labelledFields.map { ($0.label, $0.value) }, uniquingKeysWith: { _, last in last })
        XCTAssertEqual(r["Country covering full process chain"], "Italy (ITA)")
        XCTAssertNil(r["Country of origin"])
    }

    func testCountryAIsSurviveDigitalLinkAndFNC1() {
        guard case .digitalProductPassport(let link) =
                ScanPayloadParser.parse("https://id.gs1.org/01/04012345678901/10/LOT42?17=261231&426=380") else {
            return XCTFail("Expected the Digital Link carrier to keep AI 426")
        }
        XCTAssertTrue(link.labelledFields.contains(
            LabelledField(label: "Country covering full process chain", value: "Italy (ITA)")))

        guard case .digitalProductPassport(let fnc1) =
                ScanPayloadParser.parse("0104012345678901" + "10LOT42\u{1D}" + "17261231" + "426380") else {
            return XCTFail("Expected the FNC1 carrier to keep AI 426")
        }
        XCTAssertEqual(fnc1.batchLot, "LOT42")
        XCTAssertEqual(fnc1.fullProcessNumeric, "380")
        // The plain GS1 view names the AI too.
        XCTAssertEqual(GS1Parser.parse("(01)04012345678901(426)380")?.labelledFields.last,
                       LabelledField(label: "Country covering full process chain (426)", value: "380"))
    }

    func testCountryListsNeedEveryCountryNamed() {
        func dpp(_ tail: String) -> DigitalProductPassportPayload? {
            GS1Parser.parse("(01)04012345678901(17)261231(10)LOT42" + tail).map(DigitalProductPassportParser.parse)
        }
        // One unknown code in a list would make the rest a false answer.
        XCTAssertEqual(dpp("(423)276999")?.labelledFields.contains { $0.label == "Country of initial processing" },
                       false)
        XCTAssertNil(dpp("(423)2762")?.initialProcessingNumeric)
        XCTAssertNil(dpp("(425)276276276276276276")?.disassemblyNumeric)
        XCTAssertNil(dpp("(422)27")?.originNumeric)
        XCTAssertNil(dpp("(422)27A")?.originNumeric)
        XCTAssertEqual(ISOCountry.names(numericList: "276250"), "Germany (DEU), France (FRA)")
        XCTAssertNil(ISOCountry.names(numericList: "2762"))
    }

    // MARK: Review fixes — the same vectors run in the Android port's
    // `VerifiableCredentialPayloadTest`, `DigitalProductPassportTest`,
    // `InvoicePayloadTest` and `FixtureCorpusTest`.

    private let typosquat = "The requesting domain looks like a typosquat of a well-known brand."
    private let bearer = "Pre-authorised with no transaction code: whoever redeems this code first gets the "
        + "credential, so do not share or post it."

    private func biometricCaution(_ claims: String) -> String {
        "It asks for biometric data (\(claims)): only approve that for a verifier you trust."
    }

    private func utf16LE(_ s: String) -> [UInt8] { s.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] } }

    private func utf32LE(_ s: String) -> [UInt8] {
        s.unicodeScalars.flatMap { scalar in (0..<4).map { UInt8((scalar.value >> (8 * UInt32($0))) & 0xFF) } }
    }

    private func percentEncoded(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%%%02X", $0) }.joined()
    }

    /// Every byte but ASCII letters and digits percent-encoded — the Android
    /// suite's `alnumEncoded`, byte for byte. (`.alphanumerics` would leave
    /// `ü`, a fullwidth or a Cyrillic letter as it is.)
    private func asciiAlnum(_ s: String) -> String {
        s.utf8.map { b in
            (0x30...0x39).contains(b) || (0x41...0x5A).contains(b) || (0x61...0x7A).contains(b)
                ? String(UnicodeScalar(b)) : String(format: "%%%02X", b)
        }.joined()
    }

    /// A by-value request whose verifier and answer address are the given URLs.
    private func hostRequest(_ clientID: String, _ responseURI: String) -> VerifiableCredentialPayload? {
        parse("openid4vp://?client_id=" + asciiAlnum(clientID) + "&response_uri=" + asciiAlnum(responseURI) + "&nonce=n-1")
    }

    // R1-01: only a structural `dpp` marker makes a passport.

    func testDPPInsideTheTextIsNoPassportMarker() {
        for raw in ["(01)09506000134352(10)ADPPX",
                    "0109506000134352" + "10ABC\u{1D}" + "21DPP9",
                    "https://developer.example.org/docs/01/12345678?unit=dppx",
                    "https://www.dppnews.example/2024/01/20240115/story",
                    "https://id.gs1.org/01/09506000134352/10/dpp"] {
            guard case .gs1 = ScanPayloadParser.parse(raw) else {
                return XCTFail("\(raw) is an ordinary GS1 code, not \(ScanPayloadParser.parse(raw).kindLabel)")
            }
        }
        for raw in ["https://id.example.eu/dpp/01/04012345678901",
                    "https://id.example.eu/01/04012345678901?dpp=1",
                    "https://id.example.eu/DPP/01/04012345678901"] {
            guard case .digitalProductPassport(let dpp) = ScanPayloadParser.parse(raw) else {
                return XCTFail("\(raw) carries the dpp marker")
            }
            XCTAssertEqual(dpp.gtin, "04012345678901", raw)
            XCTAssertEqual(dpp.resolverHost, "id.example.eu", raw)
        }
    }

    func testPassportKeepsEveryOtherElementOfTheCarrier() {
        // An EU beef-traceability label: net weight, packaging and
        // best-before dates and an approval number besides the passport AIs.
        let beef = "(01)09506000134352(3103)000750(13)261101(15)261210(17)261130(10)LOT42(422)276(7030)276DE-EZ-123"
        guard case .digitalProductPassport(let dpp) = ScanPayloadParser.parse(beef) else {
            return XCTFail("Expected .digitalProductPassport")
        }
        XCTAssertEqual(dpp.labelledFields, fields([
            ("Format", "GS1 Digital Product Passport carrier"),
            ("Product (GTIN)", "09506000134352"),
            ("Batch / lot", "LOT42"),
            ("Expiry", "2026-11-30"),
            ("Country of origin", "Germany (DEU)"),
            ("AI 3103 (3103)", "000750"),
            ("Packaging date (13)", "2026-11-01"),
            ("Best before (15)", "2026-12-10"),
            ("AI 7030 (7030)", "276DE-EZ-123"),
            ("Read from", "the code itself — nothing was fetched"),
        ]))
        guard case .digitalProductPassport(let link) =
                ScanPayloadParser.parse("https://id.gs1.org/01/09506000134352/10/ABC123?15=261210&422=276&17=261130") else {
            return XCTFail("Expected .digitalProductPassport")
        }
        XCTAssertEqual(link.labelledFields, fields([
            ("Format", "GS1 Digital Product Passport carrier"),
            ("Product (GTIN)", "09506000134352"),
            ("Batch / lot", "ABC123"),
            ("Expiry", "2026-11-30"),
            ("Country of origin", "Germany (DEU)"),
            ("Passport hosted at", "id.gs1.org"),
            ("Best before (15)", "2026-12-10"),
            ("Read from", "the code itself — nothing was fetched"),
        ]))
    }

    // R8-04: a Digital Link in capitals is still a Digital Link.

    func testUppercaseDigitalLinkIsReadAsALink() {
        guard case .digitalProductPassport(let dpp) =
                ScanPayloadParser.parse("HTTPS://ID.GS1.ORG/01/04012345678901/21/SN1?17=261231&422=276") else {
            return XCTFail("Expected the upper-case Digital Link to be a passport")
        }
        XCTAssertEqual(dpp.gtin, "04012345678901")
        XCTAssertEqual(dpp.serial, "SN1")
        XCTAssertEqual(dpp.expiry, "2026-12-31")
        XCTAssertEqual(dpp.originNumeric, "276")
        XCTAssertEqual(dpp.resolverHost, "id.gs1.org")

        guard case .gs1(let mixed) = ScanPayloadParser.parse("Https://id.gs1.org/01/09506000134352?17=261231") else {
            return XCTFail("Expected a GS1 Digital Link")
        }
        XCTAssertEqual(mixed.form, .digitalLink)
        XCTAssertEqual(mixed.elements.map(\.ai), ["01", "17"])

        // A `dpp` host is no marker, so without an origin this stays a
        // product code — read as a link, not as the AI "HT".
        guard case .gs1(let host) = ScanPayloadParser.parse("HTTPS://DPP.EXAMPLE.COM/01/04012345678901/21/SN1") else {
            return XCTFail("Expected a GS1 Digital Link")
        }
        XCTAssertEqual(host.form, .digitalLink)
        XCTAssertEqual(host.gtin, "04012345678901")
        XCTAssertEqual(host.serial, "SN1")
    }

    // R1-04 / R8-03: one host rule, the browser's host as Unicode.

    func testCredentialHostsAreTheBrowsersHost() {
        let cases: [(String, String)] = [
            ("münchen.de", "münchen.de"),
            ("bücher.example", "bücher.example"),
            ("[2001:db8::1]:8443", "2001:db8::1"),
            ("ｅｘａｍｐｌｅ.com", "example.com"),
            ("ex\u{200B}ample.com", "example.com"),
            ("Verifier.Example.ORG", "verifier.example.org"),
        ]
        for (written, shown) in cases {
            let vc = hostRequest("redirect_uri:https://\(written)/cb", "https://\(written)/post")
            XCTAssertEqual(rows(vc)["Verifier"], shown, written)
            XCTAssertEqual(rows(vc)["Answer goes to"], shown, written)
            XCTAssertEqual(vc?.counterpartyHost, shown, written)
            XCTAssertEqual(vc?.cautions, [approveOnlyYours], written)
        }
        // A backslash ends the host, as it does in a browser.
        let backslash = hostRequest("redirect_uri:https://verifier.example\\cb", "https://verifier.example\\post")
        XCTAssertEqual(rows(backslash)["Verifier"], "verifier.example")
        XCTAssertEqual(rows(backslash)["Answer goes to"], "verifier.example")
        // … a combining mark after it included: delimiters are found by byte.
        XCTAssertEqual(rows(hostRequest("redirect_uri:https://verifier.example\\\u{301}cb",
                                        "https://verifier.example/post"))["Verifier"], "verifier.example")
        // Look-alikes warn in any alphabet.
        for written in ["p\u{430}ypal.com", "\u{440}\u{430}\u{443}\u{440}\u{430}l.com"] {
            let vc = parse("openid4vp://?client_id=" + asciiAlnum("https://\(written)") + "&nonce=n-1")
            XCTAssertEqual(rows(vc)["Verifier"], written)
            XCTAssertEqual(vc?.cautions, [approveOnlyYours, typosquat], written)
        }
        guard case .digitalProductPassport(let dpp) =
                ScanPayloadParser.parse("https://dpp.bücher.de/01/04012345678901/21/SN1?17=261231&422=276") else {
            return XCTFail("Expected .digitalProductPassport")
        }
        XCTAssertEqual(dpp.resolverHost, "dpp.bücher.de")
    }

    func testAnAddressThatHidesItsHostIsNotNamed() {
        let unusual = ShownHost.unusual
        let backslash = hostRequest("redirect_uri:https://evil.example\\@verifier.gov/cb",
                                    "https://evil.example\\@verifier.gov/post")
        XCTAssertEqual(rows(backslash)["Verifier"], unusual)
        XCTAssertEqual(rows(backslash)["Answer goes to"], unusual)
        XCTAssertEqual(backslash?.cautions, [approveOnlyYours, ShownHost.hiddenHostCaution])
        XCTAssertEqual(backslash?.explanationPoints.last, "Verifier: \(unusual).")
        for written in ["https://paypal.com@evil.example/cb", "https://evil.example%2Fpaypal.com/cb",
                        "https://a b.example/cb", "https:///cb", "https://ev\u{202E}il.example/cb",
                        "https://evil\u{85}.example/cb", "https://evil.example\u{0}/cb", "https://[::1/cb",
                        "https://[::1]\u{301}:443/cb"] {
            let vc = hostRequest("redirect_uri:" + written, "https://verifier.example/post")
            XCTAssertEqual(rows(vc)["Verifier"], unusual, written)
            XCTAssertEqual(vc?.cautions.last, ShownHost.hiddenHostCaution, written)
        }
        // In a sentence, and for the other hosts a code names.
        let fetched = parse("openid-credential-offer://?credential_offer_uri=" + asciiAlnum("https://good.example@evil.example/o/1"))
        XCTAssertEqual(rows(fetched)["Offer"], "Your wallet fetches it from an unusual address (not shown)")
        XCTAssertEqual(fetched?.cautions.last, ShownHost.hiddenHostCaution)
        let signIn = offer(#"{"credential_issuer":"https://issuer.example","credential_configuration_ids":["x"],"#
            + #""grants":{"authorization_code":{"authorization_server":"https://a@b.example"}}}"#)
        XCTAssertEqual(rows(signIn)["Sign-in"], "You'll sign in at an unusual address (not shown)")
        let token = parse(b64(#"{"alg":"ES256","typ":"dc+sd-jwt"}"#) + "."
                          + b64(#"{"iss":"https://paypal.com@evil.example","vct":"urn:eudi:pid:1"}"#) + ".c2ln")
        XCTAssertEqual(rows(token)["Issuer"], unusual)
        XCTAssertEqual(token?.explanationPoints.first,
                       "A digital-identity credential issued by an unusual address (not shown).")
        XCTAssertEqual(token?.cautions.last, ShownHost.hiddenHostCaution)
        // The passport's resolver, both ways round.
        for raw in ["https://evil.example\\@id.gs1.org/01/09506000134352/10/L1?17=261130&422=276",
                    "https://id.gs1.org\\@evil.example/01/09506000134352/10/L1?17=261130&422=276"] {
            guard case .digitalProductPassport(let dpp) = ScanPayloadParser.parse(raw) else {
                return XCTFail("Expected .digitalProductPassport for \(raw)")
            }
            XCTAssertEqual(dpp.labelledFields, fields([
                ("Format", "GS1 Digital Product Passport carrier"),
                ("Product (GTIN)", "09506000134352"),
                ("Batch / lot", "L1"),
                ("Expiry", "2026-11-30"),
                ("Country of origin", "Germany (DEU)"),
                ("Passport hosted at", unusual),
                ("Read from", "the code itself — nothing was fetched"),
            ]), raw)
        }
    }

    // R1-02 / R8-01: one malformed parameter spoils only itself.

    private let lookalikeQuery = "client_id=" + "redirect_uri%3Ahttps%3A%2F%2Fpaypa1-verify.com%2Fcb"
        + "&response_uri=https%3A%2F%2Fpaypa1-verify.com%2Fpost&nonce=n-1&dcql_query="
        + "%7B%22credentials%22%3A%5B%7B%22id%22%3A%22pid%22%2C%22format%22%3A%22dc%2Bsd-jwt%22%2C"
        + "%22meta%22%3A%7B%22vct_values%22%3A%5B%22urn%3Aeudi%3Apid%3A1%22%5D%7D%7D%5D%7D"

    func testAStrayParameterDoesNotHideTheVerifier() {
        guard let control = parse("openid4vp://?" + lookalikeQuery) else { return }
        XCTAssertEqual(control.labelledFields, fields([
            ("Type", "Credential request"),
            ("Format", "dc+sd-jwt"),
            ("Asking for", pidName),
            ("Verifier", "paypa1-verify.com"),
            ("Answer goes to", "paypa1-verify.com"),
            ("Anti-replay", "Nonce present"),
        ]))
        XCTAssertEqual(control.cautions, [approveOnlyYours, typosquat])
        for suffix in ["&x=a b", "&x=café", "&x=50%", "&x=%", "&x=%zz", "&x=%FF", "&x=a|b",
                       #"&client_metadata={"client_name":"V"}"#] {
            let vc = parse("openid4vp://?" + lookalikeQuery + suffix)
            XCTAssertEqual(vc?.labelledFields, control.labelledFields, suffix)
            XCTAssertEqual(vc?.requested, control.requested, suffix)
            XCTAssertEqual(vc?.counterpartyHost, "paypa1-verify.com", suffix)
            XCTAssertEqual(vc?.cautions, control.cautions, suffix)
        }
        for variant in ["openid4vp://?" + lookalikeQuery + "&state=%zz", "openid4vp://?state=a b&" + lookalikeQuery] {
            let vc = parse(variant)
            XCTAssertEqual(rows(vc)["Verifier"], "paypa1-verify.com", variant)
            XCTAssertEqual(rows(vc)["Anti-replay"], "Nonce + state", variant)
            XCTAssertEqual(vc?.cautions, control.cautions, variant)
        }
        let scoped = parse("openid4vp://?" + lookalikeQuery + "&scope=openid pid")
        XCTAssertEqual(rows(scoped)["Asking for"], "\(pidName) + 2 more")
        XCTAssertEqual(rows(scoped)["Verifier"], "paypa1-verify.com")
        XCTAssertEqual(scoped?.cautions, control.cautions)
        // Encoded identifiers next to a raw JSON query.
        let rawJSON = parse("openid4vp://?client_id=redirect_uri%3Ahttps%3A%2F%2Fpaypa1-verify.com%2Fcb"
            + "&response_uri=https%3A%2F%2Fpaypa1-verify.com%2Fpost&nonce=n-1"
            + #"&dcql_query={"credentials":[{"id":"pid","format":"dc+sd-jwt","meta":{"vct_values":["urn:eudi:pid:1"]}}]}"#)
        XCTAssertEqual(rawJSON?.labelledFields, control.labelledFields)
        XCTAssertEqual(rawJSON?.cautions, control.cautions)
        // By reference, with a raw space elsewhere.
        let reference = parse("openid4vp://?client_id=redirect_uri%3Ahttps%3A%2F%2Fpaypa1-verify.com%2Fcb"
            + "&request_uri=https%3A%2F%2Fpaypa1-verify.com%2Frequest%2F1&x=a b")
        XCTAssertEqual(reference?.referenceHost, "paypa1-verify.com")
        XCTAssertEqual(rows(reference)["Request"], "Your wallet fetches it from paypa1-verify.com")
        XCTAssertEqual(reference?.cautions, [approveOnlyYours, typosquat])
    }

    func testAnOfferSurvivesAStrayParameter() {
        let grants = #""grants":{"urn:ietf:params:oauth:grant-type:pre-authorized_code":"#
            + #"{"pre-authorized_code":"SplxlOBeZQQYbYS6WxSbIA"}}"#
        let issuer = "openid-credential-offer://?credential_offer=" + alnum(#"{"credential_issuer":"https://issuer.example","#
            + #""credential_configuration_ids":["eu.europa.ec.eudi.pid_vc_sd_jwt"],"# + grants + "}")
        for suffix in ["", "&x=%", "&note=a b"] {
            let vc = parse(issuer + suffix)
            XCTAssertEqual(vc?.labelledFields, fields([
                ("Type", "Credential offer"),
                ("Offering", pidName),
                ("Issuer", "issuer.example"),
                ("Sign-in", "Not needed — pre-authorised by the issuer"),
                ("Transaction code", "Not required — whoever redeems the code gets the credential"),
            ]), suffix)
            XCTAssertEqual(vc?.cautions, [unsolicited, bearer], suffix)
        }
        let lookalike = parse("openid-credential-offer://?credential_offer=" + alnum(#"{"credential_issuer":"https://paypa1.com","#
            + #""credential_configuration_ids":["eu.europa.ec.eudi.pid_vc_sd_jwt"],"# + grants + "}") + "&note=a b")
        XCTAssertEqual(rows(lookalike)["Issuer"], "paypa1.com")
        XCTAssertEqual(lookalike?.preAuthorized, true)
        XCTAssertEqual(lookalike?.cautions, [unsolicited, bearer, typosquat])

        // What does not decode is kept as written — never dropped, never U+FFFD.
        let nonce = parse("openid4vp://?client_id=https%3A%2F%2Fverifier.example.org&nonce=%FF")
        XCTAssertEqual(nonce?.noncePresent, true)
        XCTAssertEqual(rows(nonce)["Anti-replay"], "Nonce present")
        let byReference = parse("openid-credential-offer://?credential_offer_uri=%96")
        XCTAssertEqual(byReference?.labelledFields, fields([
            ("Type", "Credential offer"),
            ("Offering", "Not in the code — your wallet fetches the details"),
            ("Issuer", "Not in the code"),
            ("Offer", "Your wallet fetches it from the issuer"),
        ]))
        XCTAssertEqual(rows(parse("openid4vp://?client_id=abc%zz&nonce=1"))["Verifier"], "abc%zz")
        // A fragment is no part of the query.
        let fragment = parse("openid4vp://?client_id=https%3A%2F%2Fverifier.example.org&nonce=1#frag")
        XCTAssertEqual(fragment?.noncePresent, true)
        XCTAssertFalse(fragment?.labelledFields.contains { $0.value.contains("frag") } ?? true)
    }

    // R1-03: a JSON document nested past the cap is refused, not recursed.

    private var deeplyNested: String {
        String(repeating: #"{"":"#, count: 511) + "1" + String(repeating: "}", count: 511)
    }

    func testDeepJSONCannotOverrunAnIntentsStack() async throws {
        let offerCode = "openid-credential-offer://?credential_offer=" + deeplyNested
        let requestCode = "openid4vp://?client_id=x&dcql_query=" + deeplyNested
        XCTAssertEqual(rows(parse(offerCode))["Offering"], "Not stated")
        XCTAssertEqual(rows(parse(offerCode))["Claims"], "Not decodable — possibly a newer format")
        XCTAssertEqual(rows(parse(requestCode))["Asking for"], "Not stated")
        // Shortcuts' "Explain Code" runs on a 512 KB pool thread …
        for raw in [offerCode, requestCode] {
            let intent = ExplainCodeIntent()
            intent.contents = raw
            _ = try await intent.perform()
        }
        // … and so does this, explicitly.
        let parsed = expectation(description: "parsed on a 512 KB stack")
        let inputs = [offerCode, requestCode]
        let thread = Thread {
            for raw in inputs { _ = ScanPayloadParser.parse(raw) }
            parsed.fulfill()
        }
        thread.stackSize = 512 * 1024
        thread.start()
        await fulfillment(of: [parsed], timeout: 30)
    }

    // R1-05: claim sets are UTF-8, and trimmed by one whitespace set.

    func testOnlyUTF8ClaimSetsAreRead() {
        let header = b64(#"{"alg":"ES256","typ":"dc+sd-jwt"}"#)
        let claims = #"{"iss":"https://issuer.example","vct":"urn:eudi:pid:1"}"#
        XCTAssertEqual(ScanPayloadParser.parse(header + "." + b64(claims) + ".c2ln").kindLabel, "Verifiable credential")
        for bytes in [utf16LE(claims), [0xFF, 0xFE] + utf16LE(claims), utf32LE(claims)] {
            XCTAssertEqual(ScanPayloadParser.parse(header + "." + base64URL(bytes) + ".c2ln").kindLabel, "Text")
        }
        let requestClaims = #"{"client_id":"https://good.example","nonce":"n-1"}"#
        let utf16Request = parse("openid4vp://?client_id=x&request=" + header + "." + base64URL(utf16LE(requestClaims)) + ".c2ln")
        XCTAssertEqual(rows(utf16Request)["Verifier"], "x")
        XCTAssertEqual(rows(utf16Request)["Anti-replay"], "Inside the signed request — not readable")
        let offerJSON = #"{"credential_issuer":"https://issuer.example","credential_configuration_ids":["eu.europa.ec.eudi.pid_vc_sd_jwt"]}"#
        XCTAssertEqual(parse("openid-credential-offer://?credential_offer=" + percentEncoded(utf16LE(offerJSON)))?.labelledFields,
                       fields([
                        ("Type", "Credential offer"),
                        ("Offering", "Not stated"),
                        ("Issuer", "Not stated"),
                        ("Claims", "Not decodable — possibly a newer format"),
                       ]))
        // U+001F is not whitespace to Swift, U+0085 is.
        let unitSeparator = parse("openid4vp://?client_id=x&request=" + header + ".%1F" + b64(requestClaims) + ".c2ln")
        XCTAssertEqual(rows(unitSeparator)["Anti-replay"], "Inside the signed request — not readable")
        let nextLine = parse("openid4vp://?client_id=x&request=" + header + ".%C2%85" + b64(requestClaims) + ".c2ln")
        XCTAssertEqual(rows(nextLine)["Verifier"], "good.example")
        XCTAssertEqual(rows(nextLine)["Anti-replay"], "Nonce present")
        let invoice = "<rsm:CrossIndustryInvoice><rsm:ExchangedDocument><ram:ID>INV-1</ram:ID></rsm:ExchangedDocument>"
            + "<ram:SellerTradeParty><ram:Name>\u{1C}ACME GmbH</ram:Name></ram:SellerTradeParty>"
            + "<ram:GrandTotalAmount>10.00</ram:GrandTotalAmount></rsm:CrossIndustryInvoice>"
        XCTAssertEqual(InvoiceParser.parse(invoice)?.sellerName, "\u{1C}ACME GmbH")
    }

    // R1-06: an issued / expiry date is a real instant or no row at all.

    func testCredentialDatesOutOfRangeAreLeftOut() {
        let header = b64(#"{"alg":"ES256","typ":"dc+sd-jwt"}"#)
        func token(_ value: String) -> VerifiableCredentialPayload? {
            parse(header + "." + b64(#"{"iss":"https://issuer.example","vct":"urn:eudi:pid:1","iat":"# + value
                                     + #","exp":"# + value + "}") + ".c2ln")
        }
        for value in ["1e300", "-1e300", "1e18", #""Infinity""#, #""NaN""#, #""nan""#, #""inf""#, "-1",
                      #""1e9""#, #"" 1767225600""#, #""1767225600.""#, "true", "253402300800"] {
            let vc = token(value)
            XCTAssertNotNil(vc, value)
            XCTAssertNil(vc?.issuedAt, value)
            XCTAssertNil(vc?.expiresAt, value)
            XCTAssertNil(rows(vc)["Issued"], value)
            XCTAssertNil(rows(vc)["Expires"], value)
        }
        let valid: [(String, TimeInterval)] = [
            ("1767225600", 1_767_225_600), (#""1767225600""#, 1_767_225_600), ("1767225600.5", 1_767_225_600.5),
            (#""1767225600.5""#, 1_767_225_600.5), ("0", 0), ("253402300799", 253_402_300_799),
        ]
        for (value, seconds) in valid {
            let vc = token(value)
            XCTAssertEqual(vc?.issuedAt?.timeIntervalSince1970, seconds, value)
            XCTAssertEqual(vc?.expiresAt?.timeIntervalSince1970, seconds, value)
            XCTAssertFalse(rows(vc)["Issued"]?.isEmpty ?? true, value)
            XCTAssertFalse(rows(vc)["Expires"]?.isEmpty ?? true, value)
        }
    }

    // R1-08: the e-invoice parser is CII-only, and its labels say so.

    func testInvoiceProfilesAreOnlyTheCIIOnes() {
        func standard(_ marker: String) -> String? {
            InvoiceParser.parse("<rsm:CrossIndustryInvoice><rsm:ExchangedDocument><ram:ID>INV-1</ram:ID>"
                + "</rsm:ExchangedDocument><ram:GrandTotalAmount>10.00</ram:GrandTotalAmount>\(marker)"
                + "</rsm:CrossIndustryInvoice>")?.standard
        }
        XCTAssertEqual(standard("<ram:Name>ZUGFeRD</ram:Name>"), "ZUGFeRD (EN 16931, Germany)")
        XCTAssertEqual(standard("<ram:Name>Factur-X</ram:Name>"), "Factur-X (EN 16931, France)")
        XCTAssertEqual(standard("<ram:Name>Peppol</ram:Name>"), "Electronic invoice (UN/CEFACT)")
        XCTAssertEqual(standard("<ram:Name>UBL</ram:Name>"), "Electronic invoice (UN/CEFACT)")
        XCTAssertEqual(standard("<ram:Name>en16931</ram:Name>"), "EN 16931 e-invoice")
        XCTAssertEqual(standard("<ram:Name>Whatever</ram:Name>"), "Electronic invoice (UN/CEFACT)")
        // A UBL invoice (Peppol BIS Billing 3.0) is not read at all.
        let ubl = #"<Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2" "#
            + #"xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">"#
            + "<cbc:CustomizationID>urn:cen.eu:en16931:2017#compliant#urn:fdc:peppol.eu:2017:poacc:billing:3.0"
            + "</cbc:CustomizationID><cbc:ID>INV-9</cbc:ID>"
            + #"<cbc:PayableAmount currencyID="EUR">125.00</cbc:PayableAmount></Invoice>"#
        XCTAssertEqual(ScanPayloadParser.parse(ubl).kindLabel, "Text")
    }

    // R3-07: the explanation names the claims a request asks for.

    func testRequestExplanationNamesTheClaimsAskedFor() {
        guard let vc = parse(dcqlRequest) else { return }
        XCTAssertEqual(vc.claimsByCredential, [
            "given name, family name, street address from \(pidName)",
            "given name, portrait from \(mdlName)",
        ])
        XCTAssertEqual(vc.biometricClaims, ["portrait"])
        XCTAssertEqual(vc.explanationPoints, [
            "A site is asking your digital-identity wallet to release attributes.",
            "Requested: given name, family name, street address from \(pidName); given name, portrait from \(mdlName).",
            "Verifier: client.example.org.",
        ])
        let explained = HeuristicExplainer.explain(raw: dcqlRequest, payload: ScanPayloadParser.parse(dcqlRequest))
        let text = ([explained.summary] + explained.keyPoints).joined(separator: " ")
        XCTAssertTrue(text.contains("street"), text)
        XCTAssertTrue(text.contains("portrait"), text)
        XCTAssertFalse(text.contains("birth date"), text)
        XCTAssertFalse(text.contains("nationality"), text)
        XCTAssertTrue(explained.cautions.contains(biometricCaution("portrait")))

        // Eight claims a credential and four credentials are named, the rest counted.
        let ten = (1...10).map { #"{"path":["c_\#($0)"]}"# }.joined(separator: ",")
        let dcql = #"{"credentials":[{"id":"alpha","format":"dc+sd-jwt","claims":["# + ten + "]},"
            + #"{"id":"beta","format":"dc+sd-jwt"},"#
            + #"{"id":"gamma","format":"mso_mdoc","claims":[{"path":["org.iso.18013.5.1","signature_usual_mark"]}]},"#
            + #"{"id":"delta","format":"dc+sd-jwt","claims":[{"path":["picture"]}]},"#
            + #"{"id":"epsilon","format":"dc+sd-jwt","claims":[{"path":["x"]}]}]}"#
        let capped = parse("openid4vp://?client_id=redirect_uri%3Ahttps%3A%2F%2Fv.example%2Fcb&nonce=1&dcql_query=" + alnum(dcql))
        XCTAssertEqual(capped?.claimsByCredential, [
            "c 1, c 2, c 3, c 4, c 5, c 6, c 7, c 8 + 2 more from alpha",
            "beta",
            "signature usual mark from gamma",
            "picture from delta",
            "+ 1 more",
        ])
        XCTAssertEqual(capped?.biometricClaims, ["signature usual mark", "picture"])
        XCTAssertEqual(capped?.cautions, [approveOnlyYours, biometricCaution("signature usual mark, picture")])
        // No claims at all: the credentials' names, as before.
        let unnamed = parse("openid4vp://?client_id=redirect_uri%3Ahttps%3A%2F%2Fv.example%2Fcb&nonce=1&dcql_query="
                            + alnum(#"{"credentials":[{"id":"pid","format":"dc+sd-jwt","meta":{"vct_values":["urn:eudi:pid:1"]}}]}"#))
        XCTAssertEqual(unnamed?.claimsByCredential, [])
        XCTAssertEqual(unnamed?.explanationPoints[1], "Requested: \(pidName).")
    }

    // S1: the country table is the whole ISO 3166-1 list.

    func testCountryTableIsTheWholeISOList() {
        XCTAssertEqual(ISOCountry.name(numeric: "032"), "Argentina (ARG)")
        XCTAssertEqual(ISOCountry.name(numeric: "608"), "Philippines (PHL)")
        XCTAssertEqual(ISOCountry.name(numeric: "818"), "Egypt (EGY)")
        XCTAssertEqual(ISOCountry.name(numeric: "158"), "Taiwan (TWN)")
        // The codes the first table mixed up, each where ISO puts it.
        let neighbours = [("528", "Netherlands (NLD)"), ("504", "Morocco (MAR)"), ("470", "Malta (MLT)"),
                          ("466", "Mali (MLI)"), ("600", "Paraguay (PRY)"), ("710", "South Africa (ZAF)"),
                          ("324", "Guinea (GIN)"), ("624", "Guinea-Bissau (GNB)")]
        for (code, name) in neighbours {
            XCTAssertEqual(ISOCountry.name(numeric: code), name, code)
        }
        XCTAssertEqual(ISOCountry.name(numeric: "384"), "Côte d’Ivoire (CIV)")
        XCTAssertEqual(ISOCountry.name(numeric: "156"), "China (CHN)")
        XCTAssertEqual(ISOCountry.name(numeric: "344"), "Hong Kong SAR China (HKG)")
        // All 249 current codes; withdrawn ones (East Germany, the two
        // Yemens, old Ethiopia and Sudan) and ICU's 983 for Kosovo are not.
        let named = (0...999).map { String(format: "%03d", $0) }.filter { ISOCountry.name(numeric: $0) != nil }
        XCTAssertEqual(named.count, 249)
        for withdrawn in ["230", "278", "280", "720", "736", "886", "983", "999"] {
            XCTAssertNil(ISOCountry.name(numeric: withdrawn), withdrawn)
        }
        guard case .digitalProductPassport(let dpp) =
                ScanPayloadParser.parse("(01)04012345678901(17)261231(10)LOT42(422)032(423)608818") else {
            return XCTFail("Expected .digitalProductPassport")
        }
        XCTAssertEqual(dpp.originDescription, "Argentina (ARG)")
        XCTAssertEqual(rows(dppPayload: dpp)["Country of initial processing"], "Philippines (PHL), Egypt (EGY)")
    }

    private func rows(dppPayload: DigitalProductPassportPayload) -> [String: String] {
        Dictionary(dppPayload.labelledFields.map { ($0.label, $0.value) }, uniquingKeysWith: { _, last in last })
    }

    // R1-07 and the corpus: every test-fixtures image decodes to the kind
    // its README promises. Vision cannot run in the Simulator ("Could not
    // create inference context"), so there CIDetector reads the 58 QR
    // fixtures and the EAN-13 and two PDF417 images are skipped; Vision
    // reads all 61 where it works, and the Android suite always does.

    func testEveryFixtureImageIsTheKindItsREADMESays() async throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test-fixtures")
        let readme = try String(contentsOf: directory.appendingPathComponent("README.md"), encoding: .utf8)
        var expected: [(String, String)] = []
        for line in readme.split(separator: "\n") where line.hasPrefix("| `") {
            let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard cells.count >= 2, var kind = cells.last else { continue }
            let file = cells[0].trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            // "re-classified to **Location** (geo)": the bold word is the kind.
            if let bold = kind.range(of: #"\*\*[^*]+\*\*"#, options: .regularExpression) {
                kind = kind[bold].replacingOccurrences(of: "**", with: "")
            }
            expected.append((file, kind))
        }
        XCTAssertEqual(expected.count, 61)
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        var skipped: [String] = []
        for (file, kind) in expected {
            let data = try Data(contentsOf: directory.appendingPathComponent(file))
            var code: (String, Symbology)?
            if let found = try? await ImageDecoder.decode(data: data).first {
                code = (found.value, found.symbology)
            } else if let image = CIImage(data: data),
                      let text = detector?.features(in: image).compactMap({ ($0 as? CIQRCodeFeature)?.messageString }).first {
                code = (text, .qr)
            }
            guard let decoded = code else {
                skipped.append(file)
                continue
            }
            let payload = ScanPayloadParser.parse(decoded.0, symbology: decoded.1)
            // A README note after the kind — "Merchant QR (sub-row …)" — is allowed.
            XCTAssertTrue(payload.kindLabel == kind || kind.hasPrefix(payload.kindLabel + " ("),
                          "\(file): \(payload.kindLabel), but the README says \(kind)")
            if file == "43-emvco-pix.png" {
                guard case .emvPayment(let emv) = payload else {
                    XCTFail("43-emvco-pix.png is not a merchant QR")
                    continue
                }
                XCTAssertTrue(emv.labelledFields.contains { $0.label == "Pix account (26)" })
            }
        }
        if skipped.count == expected.count {
            throw XCTSkip("Neither Vision nor CIDetector can decode images here.")
        }
        XCTAssertTrue(Set(skipped).isSubset(of: ["59-ean13.png", "60-aamva-driver-license.png", "61-iata-boarding-pass.png"]),
                      "Only the non-QR fixtures may go undecoded: \(skipped)")
    }
}

// MARK: - Safety, redaction and assistant parity (1.10)
//
// The same corpus and fixtures as the Android port's `QrRiskCorpusTest`,
// `SecretRedactionTest`, `ComposeRuleEngineTest` and the parity sections of
// `QrRiskAssessorTest`, `AssistantTest` and `TranslationKitTest` — character
// for character, with the same expected output — so a rule changed on one
// platform and not the other fails on both.

final class SafetyParityTests: XCTestCase {

    // MARK: Risk corpus

    /// Ordinary codes — popular sites, internationalised domains, Wi-Fi,
    /// payment and contact codes — must produce nothing at all, so the badge
    /// keeps its meaning; the classic tricks must produce the same finding
    /// codes at the same levels as on Android. Each entry is
    /// `level | code:severity, …` with the findings in report order.
    static let riskCorpus: [(String, String)] = [
        // Ordinary links
        ("https://www.google.com/search?q=weather+belgrade",
         "safe | "),
        ("https://www.youtube.com/watch?v=dQw4w9WgXcQ",
         "safe | "),
        ("https://youtu.be/dQw4w9WgXcQ",
         "safe | "),
        ("https://en.wikipedia.org/wiki/QR_code",
         "safe | "),
        ("https://www.amazon.co.uk/gp/help/customer/display.html",
         "safe | "),
        ("https://github.com/apple/swift",
         "safe | "),
        ("https://apps.apple.com/us/app/whatsapp-messenger/id310633997",
         "safe | "),
        ("https://play.google.com/store/apps/details?id=com.whatsapp",
         "safe | "),
        ("https://maps.google.com/?q=44.8125,20.4612",
         "safe | "),
        ("https://www.instagram.com/natgeo/",
         "safe | "),
        ("https://www.linkedin.com/company/microsoft/",
         "safe | "),
        ("https://www.booking.com/hotel/rs/example.html",
         "safe | "),
        ("https://wa.me/381641234567",
         "safe | "),
        ("https://t.me/durov",
         "safe | "),
        ("https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC",
         "safe | "),
        ("https://paypal.me/example",
         "safe | "),
        ("https://www.bbc.co.uk/news",
         "safe | "),
        ("https://www.ubereats.com/",
         "safe | "),
        ("https://www.telegraph.co.uk/news/",
         "safe | "),
        ("https://login.microsoftonline.com/",
         "safe | "),
        ("https://www.wish.com/",
         "safe | "),
        ("https://Google.com/",
         "safe | "),
        ("https://eBay.com/",
         "safe | "),
        ("https://www.dhl.com/de-de/home/tracking.html?tracking-id=00340434161094042557",
         "safe | "),
        ("https://example.com/disclaimer",
         "safe | "),
        ("https://example.net/01/04006000200007",
         "safe | "),
        // Internationalised domains
        ("https://m\u{00FC}nchen.de/",
         "safe | "),
        ("https://www.b\u{00FC}cher.de/",
         "safe | "),
        ("https://xn--mnchen-3ya.de/",
         "safe | "),
        ("https://www.xn--bcher-kva.de/",
         "safe | "),
        ("https://\u{043F}\u{0440}\u{0435}\u{0437}\u{0438}\u{0434}\u{0435}\u{043D}\u{0442}.\u{0440}\u{0444}/",
         "safe | "),
        ("https://\u{65E5}\u{672C}\u{8A9E}.jp/",
         "safe | "),
        // Ordinary non-links
        ("WIFI:T:WPA;S:CafeNet;P:coffee2026;H:false;;",
         "safe | "),
        ("WIFI:T:WPA;S:HiddenNet;P:secret123;H:true;;",
         "safe | "),
        ("BCD\n002\n1\nSCT\nBPOTBEB1\nRed Cross Belgium\nBE72000000001616\nEUR10.00\n\n\nDonation",
         "safe | "),
        ("00020101021226580014br.gov.bcb.pix0136123e4567-e89b-12d3-a456-426614174000520458125303986540512.505802BR5909ACME LTDA6009SAO PAULO62070503***6304BF76",
         "safe | "),
        ("BEGIN:VCARD\nVERSION:3.0\nFN:Ana Ivi\u{0107}\nTEL:+381641234567\nEMAIL:ana@example.com\nEND:VCARD",
         "safe | "),
        ("bitcoin:bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
         "safe | "),
        ("mailto:hello@example.com?subject=Hi",
         "safe | "),
        ("tel:+381641234567",
         "safe | "),
        ("geo:44.8125,20.4612",
         "safe | "),
        ("weixin://wxpay/bizpayurl?pr=abc123",
         "safe | "),
        ("Meeting point: main entrance, third floor, room 12",
         "safe | "),
        // Cautions by design
        ("WIFI:T:nopass;S:Cafe Guest;;",
         "caution | open-wifi:caution"),
        ("WIFI:S:Cafe Guest;P:;;",
         "caution | open-wifi:caution"),
        ("00020101021126580014br.gov.bcb.pix0136123e4567-e89b-12d3-a456-4266141740005204581253039865802BR5909ACME LTDA6009SAO PAULO62070503***63046BF3",
         "caution | static-payment-code:caution"),
        ("000201010211520458125303986540525.005802BR6009SAO PAULO630474A9",
         "caution | payment-no-merchant:caution, static-amount-poster:caution, static-payment-code:caution"),
        ("bitcoin:bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh?amount=0.01",
         "caution | crypto-amount-preset:caution"),
        ("otpauth://totp/ACME:alice@acme.com?secret=JBSWY3DPEHPK3PXP&issuer=ACME",
         "caution | otp-share-warning:caution"),
        // Tricks
        ("https://paypaI.com/signin",
         "danger | lookalike-domain:danger"),
        ("https://paypa1.com/",
         "danger | lookalike-domain:danger"),
        ("https://www.amaz0n.com/",
         "danger | lookalike-domain:danger"),
        ("https://gooogle.com/",
         "danger | lookalike-domain:danger"),
        ("https://paypal-secure-login.com/",
         "danger | lookalike-domain:danger"),
        ("https://xn--pple-43d.com/",
         "danger | mixed-script-host:danger, lookalike-domain:danger"),
        ("https://\u{0430}pple.com/",
         "danger | mixed-script-host:danger, lookalike-domain:danger"),
        ("https://xn--80ak6aa92e.com/",
         "danger | punycode-host:danger, lookalike-domain:danger"),
        ("https://p\u{00E1}ypal.com/",
         "danger | lookalike-domain:danger"),
        ("https://xn--zz9999999999.com/",
         "danger | punycode-host:danger"),
        ("https://user@evil.example/",
         "danger | credentials-in-url:danger"),
        ("https://paypal.com@evil.example/checkout",
         "danger | credentials-in-url:danger"),
        ("http://203.0.113.9/login",
         "caution | ip-literal-host:caution, plain-http:caution"),
        ("http://192.168.1.10/admin",
         "caution | ip-literal-host:note, plain-http:caution"),
        ("https://example.com:8888/",
         "caution | odd-port:caution"),
        ("https://trusted.example/go?url=https://evil.example/login",
         "caution | open-redirect:caution"),
        ("https://bit.ly/3xYzAbC",
         "caution | url-shortener:caution"),
        ("https://giveaway.top/claim",
         "caution | abuse-tld:caution, bait-keyword:caution"),
        ("https://a.b.c.d.example.com/",
         "caution | deep-subdomain:caution"),
        ("https://example.com/p?data=QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVo=",
         "caution | base64-payload:caution"),
        ("data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==",
         "danger | dangerous-scheme:danger"),
        ("javascript:alert(1)",
         "danger | dangerous-scheme:danger"),
        ("Scan this code to pay 39 EUR now. Questions? Contact us on Telegram t.me/support_pay",
         "caution | lure-text:caution"),
        ("nostr:nsec1qvz8cq6d8t0f0y3gqk0q0m3v9z2xk",
         "caution | secret-exposed:caution"),
        ("abandon ability able about above absent absorb abstract absurd abuse access accident",
         "danger | secret-exposed:danger"),
        // Links a browser repairs: no slashes or extra ones, backslashes,
        // line breaks — graded for where they really go
        ("https:paypa1.com/login",
         "danger | lookalike-domain:danger"),
        ("https:/paypa1.com/login",
         "danger | lookalike-domain:danger"),
        ("HTTPS:PAYPA1.COM",
         "danger | lookalike-domain:danger"),
        ("https:////paypa1.com/login",
         "danger | lookalike-domain:danger"),
        ("https:\\\\paypa1.com\\login",
         "danger | lookalike-domain:danger"),
        ("https://paypa1.com\n/login",
         "danger | lookalike-domain:danger"),
        ("http:accounts.google.com@evil.example/",
         "danger | credentials-in-url:danger, plain-http:caution"),
        ("https:///paypal.com@evil.example/",
         "danger | credentials-in-url:danger"),
        ("https://paypal.com @evil.example/login",
         "danger | credentials-in-url:danger"),
        ("https://paypal.com@\nevil.example/",
         "danger | credentials-in-url:danger"),
        ("http:203.0.113.9/login",
         "caution | ip-literal-host:caution, plain-http:caution"),
        // A backslash before the login's @ is graded the way iOS opens it
        ("https://paypal.com\\@evil.example/login",
         "danger | credentials-in-url:danger"),
        ("https://www.paypal.com\\@paypa1.com/signin",
         "danger | lookalike-domain:danger, credentials-in-url:danger"),
        ("https://google.com\\@203.0.113.9/",
         "danger | ip-literal-host:caution, credentials-in-url:danger"),
        // Brands that are everyday words
        ("https://www.big-apple-pizza.com/menu",
         "safe | "),
        ("https://www.ups-and-downs-cafe.com/menu",
         "safe | "),
        ("https://www.wise-owl-books.co.uk/",
         "safe | "),
        ("https://www.amazon-river-tours.com.br/",
         "safe | "),
        ("https://www.daily-telegram.com/",
         "safe | "),
        ("https://pop-ups-shop.com/",
         "safe | "),
        ("https://grown-ups-club.com/",
         "safe | "),
        ("https://apple-support-login.com/",
         "danger | lookalike-domain:danger"),
        ("https://ups-delivery.com/",
         "danger | lookalike-domain:danger"),
        // A brand's address in front of somebody else's domain, and the
        // brands added in 1.10
        ("https://paypal.com.secure-login.info/",
         "danger | lookalike-domain:danger"),
        ("https://apple.com-support.help/",
         "danger | lookalike-domain:danger"),
        ("https://www.paypal.com.account-security-check.net/signin",
         "danger | lookalike-domain:danger, deep-subdomain:caution"),
        ("https://microsoft.github.io/",
         "safe | "),
        ("https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ",
         "safe | "),
        ("https://youtube-premium-offer.com/",
         "danger | lookalike-domain:danger"),
        ("https://www.youtubee.com/watch?v=abc",
         "danger | lookalike-domain:danger"),
        ("https://linkedin-jobs-verify.com/",
         "danger | lookalike-domain:danger"),
        ("https://usps-redelivery-center.com/track",
         "danger | lookalike-domain:danger"),
        ("https://adobe-docsign-review.com/",
         "danger | lookalike-domain:danger"),
        // IPv4 hosts in the spellings browsers accept
        ("https://3627732046/login",
         "caution | ip-literal-host:caution"),
        ("https://0xd83ad60e/login",
         "caution | ip-literal-host:caution"),
        ("https://0330.072.0326.016/login",
         "caution | ip-literal-host:caution"),
        ("https://216.58.0xd6.14/",
         "caution | ip-literal-host:caution"),
        ("https://0xc0000201/login",
         "caution | ip-literal-host:caution"),
        ("http://3627732046/",
         "caution | ip-literal-host:caution, plain-http:caution"),
        ("https://0x7f.1/",
         "safe | ip-literal-host:note"),
        // Redirectors to another site
        ("https://www.google.com/url?q=https://evil.example/login&sa=D&source=editors",
         "caution | open-redirect:caution"),
        ("https://www.youtube.com/redirect?event=video_description&redir_token=QUFFLUhqa&q=https%3A%2F%2Fevil.example%2F",
         "caution | open-redirect:caution"),
        ("https://www.bing.com/ck/a?!&&p=abc123&u=a1aHR0cHM6Ly9ldmlsLmV4YW1wbGUvbG9naW4&ntb=1",
         "caution | open-redirect:caution"),
        ("https://duckduckgo.com/l/?uddg=https%3A%2F%2Fevil.example%2F",
         "caution | open-redirect:caution"),
        ("https://r.search.yahoo.com/_ylt=abc/RV=2/RE=1700000000/RO=10/RU=https%3a%2f%2fevil.example%2f/RK=2/RS=abc",
         "caution | open-redirect:caution"),
        ("https://www.google.com/amp/s/evil.example/login",
         "caution | open-redirect:caution"),
        ("https://accounts.google.com/ServiceLogin?continue=https://evil.example/",
         "caution | open-redirect:caution"),
        // Ordinary sign-in returns, deep links and government sites
        ("https://accounts.google.com/ServiceLogin?service=mail&continue=https://mail.google.com/mail/u/0/",
         "safe | "),
        ("https://www.facebook.com/login/?next=https%3A%2F%2Fwww.facebook.com%2Fgroups%2F123%2F",
         "safe | "),
        ("https://www.instagram.com/accounts/login/?next=https%3A%2F%2Fwww.instagram.com%2Fnatgeo%2F",
         "safe | "),
        ("https://www.linkedin.com/login?session_redirect=https%3A%2F%2Fwww.linkedin.com%2Ffeed%2F",
         "safe | "),
        ("https://www.reddit.com/login/?dest=https%3A%2F%2Fwww.reddit.com%2Fr%2Fpics%2F",
         "safe | "),
        ("https://www.amazon.com/ap/signin?openid.return_to=https%3A%2F%2Fwww.amazon.com%2F&openid.mode=checkid_setup",
         "safe | "),
        ("https://signin.ebay.com/ws/eBayISAPI.dll?SignIn&ru=https%3A%2F%2Fwww.ebay.com%2F",
         "safe | "),
        ("https://github.com/login?return_to=https%3A%2F%2Fgithub.com%2Fsettings%2Fprofile",
         "safe | "),
        ("https://example.com/?menu=lunch&img=https://cdn.example.com/a.png",
         "safe | "),
        ("https://www.amazon.com/progress-tracker/package/ref=ppx_yo_dt_b_track_package",
         "safe | "),
        ("https://www.paypal.com/invoice/p/#INV2-ABCD-1234",
         "safe | "),
        ("https://www.tax.service.gov.uk/",
         "safe | "),
        ("https://www.service.nsw.gov.au/",
         "safe | "),
        ("https://www.health.nsw.gov.au/",
         "safe | "),
        ("https://www.cl.cam.ac.uk/",
         "safe | "),
        ("https://www.city.shibuya.tokyo.jp/",
         "safe | "),
        ("https://www.receita.fazenda.gov.br/",
         "safe | "),
        ("https://my-bucket.s3.us-east-1.amazonaws.com/menu.pdf",
         "safe | "),
        ("https://maps.app.goo.gl/X8yZ3kq9WmLpT6Ra7",
         "safe | "),
        ("https://linktr.ee/selenagomez",
         "caution | url-shortener:caution"),
        ("market://details?id=com.whatsapp",
         "safe | store-link:note"),
        ("Questions about your booking? WhatsApp us on +34 600 123 456. Your card will not be blocked or charged until arrival.",
         "safe | "),
        // Seed phrases are BIP-39 words, however they are written down
        ("Welcome guests please enjoy your stay and visit our rooftop bar tonight",
         "safe | "),
        ("Love you forever happy anniversary from your family with all our hearts",
         "safe | "),
        ("Scan with your phone camera follow the steps shown below thank you",
         "safe | "),
        ("abandon\nability\nable\nabout\nabove\nabsent\nabsorb\nabstract\nabsurd\nabuse\naccess\naccident",
         "danger | secret-exposed:danger"),
        ("1. abandon 2. ability 3. able 4. about 5. above 6. absent 7. absorb 8. abstract 9. absurd 10. abuse 11. access 12. accident",
         "danger | secret-exposed:danger"),
        ("Seed: abandon ability able about above absent absorb abstract absurd abuse access accident",
         "danger | secret-exposed:danger"),
        ("abandon,ability,able,about,above,absent,absorb,abstract,absurd,abuse,access,accident",
         "danger | secret-exposed:danger"),
        ("5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ1jvhTVqvbTLvyTJ",
         "danger | secret-exposed:danger"),
        ("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318",
         "safe | "),
    ]

    func testRiskCorpusMatchesAndroid() {
        var mismatches: [String] = []
        for (raw, expected) in Self.riskCorpus {
            let report = QrRiskAssessor.assess(raw: raw, payload: ScanPayloadParser.parse(raw))
            let actual = "\(report.level) | " + report.findings.map { "\($0.code):\($0.severity)" }.joined(separator: ", ")
            if actual != expected { mismatches.append("\(raw)\n  expected: \(expected)\n  actual:   \(actual)") }
        }
        XCTAssertEqual(mismatches, [])
    }

    func testTheCorpusCoversOrdinaryCodesAndTricks() {
        XCTAssertGreaterThanOrEqual(Self.riskCorpus.count, 60)
        XCTAssertGreaterThanOrEqual(Self.riskCorpus.filter { $0.1 == "safe | " }.count, 40)
        XCTAssertGreaterThanOrEqual(Self.riskCorpus.filter { $0.1.hasPrefix("danger") }.count, 10)
    }

    // MARK: Targeted risk checks

    private func codes(_ raw: String) -> [String] {
        QrRiskAssessor.assess(raw: raw, payload: ScanPayloadParser.parse(raw)).findings.map(\.code)
    }

    func testOnlyWebLinksAreGradedAsWebAddresses() {
        // App-scheme rich links fall through to the scheme check: grading
        // them as web addresses invented findings on ordinary codes.
        for raw in ["weixin://wxpay/bizpayurl?pr=abc123", "alipays://platformapi/startapp?saId=10000007",
                    "matrix:u/alice:example.org"] {
            XCTAssertEqual(codes(raw), [], raw)
        }
        let ftp = "ftp://files.example/x"
        XCTAssertEqual(QrRiskAssessor.assess(raw: ftp, payload: .url(URL(string: ftp)!)).findings, [])
    }

    func testOpenWifiFiresForAMissingOrEmptyPasswordWithNoSecurity() {
        XCTAssertTrue(codes("WIFI:S:Cafe;P:;;").contains("open-wifi"))
        XCTAssertTrue(codes("WIFI:T:;S:Cafe;;").contains("open-wifi"))
        XCTAssertTrue(codes("WIFI:T:NONE;S:Cafe;;").contains("open-wifi"))
        // Declared WPA with the password left out is a broken code, not an open network.
        XCTAssertFalse(codes("WIFI:T:WPA;S:Cafe;P:;;").contains("open-wifi"))
        XCTAssertTrue(QrRiskAssessor.isOpenNetwork(password: nil, security: nil))
        XCTAssertTrue(QrRiskAssessor.isOpenNetwork(password: "", security: "nopass"))
        XCTAssertFalse(QrRiskAssessor.isOpenNetwork(password: "x", security: nil))
        XCTAssertFalse(QrRiskAssessor.isOpenNetwork(password: nil, security: "WPA"))
    }

    func testLookalikeHelperReadsLookAlikesNotRealWords() {
        for host in ["paypa1.com", "paypaI.com", "gooogle.com", "paypla.com", "rnicrosoft.com", "paypa1.co.uk",
                     "revolut-pay.example", "ups-delivery.com", "xn--80ak6aa92e.com", "\u{0430}pple.com"] {
            XCTAssertTrue(QrRiskAssessor.looksLookalike(host), host)
        }
        for host in ["Google.com", "ubereats.com", "telegraph.co.uk", "wish.com", "login.microsoftonline.com",
                     "s3.amazonaws.com", "groups.io", "startups.com", "revolt.chat", "example.com", "revolut.com"] {
            XCTAssertFalse(QrRiskAssessor.looksLookalike(host), host)
        }
    }

    func testRegistrableDomainOfAThreeLabelTwoPartSuffixHost() {
        XCTAssertEqual(QrRiskAssessor.registrableDomain("example.co.uk"), "example.co.uk")
        XCTAssertEqual(QrRiskAssessor.registrableDomain("bbc.co.uk"), "bbc.co.uk")
        XCTAssertEqual(QrRiskAssessor.registrableDomain("example.com"), "example.com")
    }

    func testPunycodeDecodesRFC3492Labels() {
        XCTAssertEqual(Punycode.decode("mnchen-3ya"), "m\u{00FC}nchen")
        XCTAssertEqual(Punycode.decode("bcher-kva"), "b\u{00FC}cher")
        XCTAssertEqual(Punycode.decode("80ak6aa92e"), "\u{0430}\u{0440}\u{0440}\u{04CF}\u{0435}")
        XCTAssertEqual(Punycode.decode("d1abbgf6aiiy"), "\u{043F}\u{0440}\u{0435}\u{0437}\u{0438}\u{0434}\u{0435}\u{043D}\u{0442}")
        XCTAssertEqual(Punycode.decode("wgv71a119e"), "\u{65E5}\u{672C}\u{8A9E}")
        XCTAssertNil(Punycode.decode("zz9999999999"))
    }

    func testTheHostIsTheOneAfterTheLogin() {
        // The look-alike sits in the login part; the real destination is evil.example.
        XCTAssertEqual(codes("https://\u{0430}pple.com@evil.example/"), ["credentials-in-url"])
        XCTAssertEqual(codes("https://user@paypa1.com:8443/"), ["lookalike-domain", "credentials-in-url"])
    }

    func testAnIPv6HostIsNamedWithoutItsBrackets() {
        let findings = QrRiskAssessor.assess(raw: "https://[2001:db8::1]/admin").findings
        XCTAssertEqual(findings.map(\.code), ["ip-literal-host"])
        XCTAssertTrue(findings.first?.detail.contains("straight to 2001:db8::1 with no domain") == true)
    }

    func testAPercentEncodedHostIsReadTheWayABrowserReadsIt() {
        XCTAssertEqual(codes("https://%70aypa1.com/"), ["lookalike-domain"])
    }

    func testPGPPrivateKeyBlockIsDanger() {
        let r = QrRiskAssessor.assess(raw: "-----BEGIN PGP PRIVATE KEY BLOCK-----\nlQOYBF\n-----END PGP PRIVATE KEY BLOCK-----")
        XCTAssertEqual(r.level, .danger)
        XCTAssertEqual(r.findings.map(\.code), ["secret-exposed"])
    }

    func testBaitWordsMatchWholeWordsOnly() {
        XCTAssertEqual(codes("https://example.com/claim-now"), ["bait-keyword"])
        XCTAssertEqual(codes("https://example.com/unlocked"), [])
        XCTAssertEqual(codes("https://example.com/disclaimer"), [])
    }

    // MARK: Redaction

    /// Every credential blanked with its field name kept, and ordinary prose
    /// ("Enter your password below", "pin the poster") left exactly as it was.
    /// Fake Slack credentials, assembled at runtime so that no token-shaped
    /// literal sits in the source: GitHub push protection rejects those.
    static let fakeSlackToken = "xox" + "b-123456789012-1234567890123-AbCdEfGhIjKlMnOpQrStUvWx"
    static let fakeSlackWebhook = "https://hooks.slack.com/services/" + "T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX"

    static let redactionFixtures: [(String, String)] = [
        ("WIFI:T:WPA;S:BlueHouse;P:hunter2hidden;H:false;;",
         "WIFI:T:WPA;S:BlueHouse;P:<redacted>;H:false;;"),
        ("WIFI:S:Cafe;T:WPA;P:pa\\;ss\\\\word;H:true;;",
         "WIFI:S:Cafe;T:WPA;P:<redacted>;H:true;;"),
        ("WIFI:P:firstfield;S:x;;",
         "WIFI:P:<redacted>;S:x;;"),
        ("wifi:s:Net;p:lowercase1;;",
         "wifi:s:Net;p:<redacted>;;"),
        ("otpauth://totp/ACME:alice@acme.com?secret=JBSWY3DPEHPK3PXP&issuer=ACME",
         "otpauth://totp/ACME:alice@acme.com?secret=<redacted>&issuer=ACME"),
        ("otpauth://totp/x?issuer=E&SECRET=jbswy3dpehpk3pxp%3D&digits=6",
         "otpauth://totp/x?issuer=E&SECRET=<redacted>&digits=6"),
        ("otpauth-migration://offline?data=CjEKCkhlbGxvId6tvu8SBUFsaWNlGgdFeGFtcGxlIAEoATACEAEYASAA%3D",
         "otpauth-migration://offline?data=<redacted>"),
        ("https://api.example.com/reset?token=abcdef123456&user=bob",
         "https://api.example.com/reset?token=<redacted>&user=bob"),
        ("https://example.com/cb?access_token=ya29.a0AfH6SMB&auth_token=Zx81kQ&next=1",
         "https://example.com/cb?access_token=<redacted>&auth_token=<redacted>&next=1"),
        ("x-api-key: AKIAIOSFODNN7EXAMPLE",
         "x-api-key: <redacted>"),
        ("client_secret=s3cr3tValue&grant_type=x",
         "client_secret=<redacted>&grant_type=x"),
        ("Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2lnbmF0dXJl",
         "Authorization: Bearer <redacted>"),
        ("password=correcthorsebattery",
         "password=<redacted>"),
        ("password: sunshine2026",
         "password: <redacted>"),
        ("pin = 4821",
         "pin = <redacted>"),
        ("The Wi-Fi password is espresso42, enjoy!",
         "The Wi-Fi password is <redacted> enjoy!"),
        ("Guest wifi password: espresso42 enjoy",
         "Guest wifi password: <redacted> enjoy"),
        ("Password is: Tr0ub4dor&3",
         "Password is: <redacted>"),
        ("PIN code: 1234",
         "PIN code: <redacted>"),
        ("PIN 4321 for the locker",
         "PIN <redacted> for the locker"),
        ("Locker passcode 0000",
         "Locker passcode <redacted>"),
        ("https://zoom.us/j/1234567890?pwd=AbCdEf123456",
         "https://zoom.us/j/1234567890?pwd=<redacted>"),
        ("user_password=hunter2&lang=en",
         "user_password=<redacted>&lang=en"),
        ("wifi password \"correct horse\" at the bar",
         "wifi password <redacted> at the bar"),
        ("NSEC1QQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQ and nsec1abcdefgh",
         "NSEC1<redacted> and nsec1<redacted>"),
        ("nostr:nsec1qvz8cq6d8t0f0y3gqk0q0m3v9z2xk",
         "nostr:nsec1<redacted>"),
        ("-----BEGIN RSA PRIVATE KEY-----\nMIIEow\n-----END RSA PRIVATE KEY-----",
         "-----BEGIN RSA PRIVATE KEY-----<redacted>"),
        ("-----BEGIN PGP PRIVATE KEY BLOCK-----\nlQOYBF\n-----END PGP PRIVATE KEY BLOCK-----",
         "-----BEGIN PGP PRIVATE KEY BLOCK-----<redacted>"),
        ("5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ1jvhTVqvbTLvyTJ",
         "<redacted>"),
        ("KwdMAjGmerYanjeui5SHS7JkmpZvVipYvB2LJGU1ZxJwYvP98617",
         "<redacted>"),
        ("abandon ability able about above absent absorb abstract absurd abuse access accident",
         "<seed phrase redacted>"),
        ("ABANDON ABILITY ABLE ABOUT ABOVE ABSENT ABSORB ABSTRACT ABSURD ABUSE ACCESS ACCIDENT",
         "<seed phrase redacted>"),
        ("abandon ability able about\nabove absent absorb abstract\nabsurd abuse access accident",
         "<seed phrase redacted>"),
        ("https://user:hunter2@evil.example/",
         "https://user:<redacted>@evil.example/"),
        ("ftp://anonymous:me@ftp.example/pub",
         "ftp://anonymous:<redacted>@ftp.example/pub"),
        ("https://paypal.com@evil.example/checkout",
         "https://paypal.com@evil.example/checkout"),
        ("https://example.com:8443/x",
         "https://example.com:8443/x"),
        ("Enter your password below to continue",
         "Enter your password below to continue"),
        ("Forgot your password? Reset it here",
         "Forgot your password? Reset it here"),
        ("Spin the wheel to win",
         "Spin the wheel to win"),
        ("Please pin the poster to the wall",
         "Please pin the poster to the wall"),
        ("PIN code required at checkout",
         "PIN code required at checkout"),
        ("Your password was changed yesterday",
         "Your password was changed yesterday"),
        ("Use a password manager",
         "Use a password manager"),
        ("Password protected PDF inside",
         "Password protected PDF inside"),
        ("The secret garden opens at 9",
         "The secret garden opens at 9"),
        ("A token of appreciation",
         "A token of appreciation"),
        ("Visit Pinterest for ideas",
         "Visit Pinterest for ideas"),
        ("http://example.com/menu Help: call us",
         "http://example.com/menu Help: call us"),
        ("-----BEGIN PUBLIC KEY-----\nMFkwEwYH\n-----END PUBLIC KEY-----",
         "-----BEGIN PUBLIC KEY-----\nMFkwEwYH\n-----END PUBLIC KEY-----"),
        ("bitcoin:bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh?amount=0.01",
         "bitcoin:bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh?amount=0.01"),
        ("1BoatSLRHtKNngkdXEeobR76b53LETtpyT",
         "1BoatSLRHtKNngkdXEeobR76b53LETtpyT"),
        ("abandon ability able about above absent absorb abstract absurd abuse access",
         "abandon ability able about above absent absorb abstract absurd abuse access"),
        ("BEGIN:VCARD\nVERSION:3.0\nFN:Ana Ivi\u{0107}\nTEL:+381641234567\nEND:VCARD",
         "BEGIN:VCARD\nVERSION:3.0\nFN:Ana Ivi\u{0107}\nTEL:+381641234567\nEND:VCARD"),
        ("MECARD:N:Ivi\u{0107},Ana;TEL:+381641234567;EMAIL:ana@example.com;;",
         "MECARD:N:Ivi\u{0107},Ana;TEL:+381641234567;EMAIL:ana@example.com;;"),
        ("Scan this code to pay 39 EUR now. Contact us on Telegram t.me/support_pay",
         "Scan this code to pay 39 EUR now. Contact us on Telegram t.me/support_pay"),
        ("Meeting point: main entrance, third floor, room 12",
         "Meeting point: main entrance, third floor, room 12"),
        // Bare service tokens keep only the prefix that names them
        ("ghp_1234567890abcdefghijklmnopqrstuvwxyzAB",
         "ghp_<redacted>"),
        ("github_pat_11ABCDEFG0123456789_abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOP",
         "github_pat_<redacted>"),
        ("sk-proj-AbCdEfGhIjKlMnOpQrStUvWxYz0123456789",
         "sk-proj-<redacted>"),
        ("sk_live_51HAbCdEfGhIjKlMnOpQrSt",
         "sk_live_<redacted>"),
        (fakeSlackToken,
         "xoxb-<redacted>"),
        ("AKIAIOSFODNN7EXAMPLE wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
         "AKIA<redacted> <redacted>"),
        ("aws_access_key_id=AKIAIOSFODNN7EXAMPLE",
         "aws_access_key_id=AKIA<redacted>"),
        (fakeSlackWebhook,
         "https://hooks.slack.com/services/<redacted>"),
        ("https://discord.com/api/webhooks/123456789012345678/abcdefGHIJKL-mnopQRSTuvwx",
         "https://discord.com/api/webhooks/<redacted>"),
        ("pass: Sunshine99",
         "pass: <redacted>"),
        ("Wi-Fi pass: Sunshine99",
         "Wi-Fi pass: <redacted>"),
        ("API key: sk-proj-AbCdEfGhIjKlMnOpQrStUvWxYz0123456789",
         "API key: <redacted>"),
        ("phonefactor://activate_account?code=123456789&url=https://mobileappcommunicator.auth.microsoft.com/activate/987654321/WUS",
         "phonefactor://activate_account?code=<redacted>&url=<redacted>"),
        ("Boarding passport: X1234567 at gate 12",
         "Boarding passport: X1234567 at gate 12"),
        // Seed phrases however they are written down; sentences that only
        // look like one pass through
        ("1. abandon 2. ability 3. able 4. about 5. above 6. absent 7. absorb 8. abstract 9. absurd 10. abuse 11. access 12. accident",
         "<seed phrase redacted>"),
        ("Seed: abandon ability able about above absent absorb abstract absurd abuse access accident",
         "<seed phrase redacted>"),
        ("abandon,ability,able,about,above,absent,absorb,abstract,absurd,abuse,access,accident",
         "<seed phrase redacted>"),
        ("Welcome guests please enjoy your stay and visit our rooftop bar tonight",
         "Welcome guests please enjoy your stay and visit our rooftop bar tonight"),
        ("Love you forever happy anniversary from your family with all our hearts",
         "Love you forever happy anniversary from your family with all our hearts"),
        ("Scan with your phone camera follow the steps shown below thank you",
         "Scan with your phone camera follow the steps shown below thank you"),
        // OpenID4VCI 1.0's own examples: an offer by value, percent-encoded;
        // the same offer as JSON; the authorization-code offer; the token
        // request. The tx_code object only describes the code and stays.
        ("openid-credential-offer://?credential_offer=%7B%22credential_issuer%22:%22https://credential-issuer.example.com%22,%22credential_configuration_ids%22:%5B%22org.iso.18013.5.1.mDL%22%5D,%22grants%22:%7B%22urn:ietf:params:oauth:grant-type:pre-authorized_code%22:%7B%22pre-authorized_code%22:%22oaKazRN8I0IbtZ0C7JuMn5%22,%22tx_code%22:%7B%22input_mode%22:%22text%22,%22description%22:%22Please%20enter%20the%20serial%20number%20of%20your%20physical%20drivers%20license%22%7D%7D%7D%7D",
         "openid-credential-offer://?credential_offer=%7B%22credential_issuer%22:%22https://credential-issuer.example.com%22,%22credential_configuration_ids%22:%5B%22org.iso.18013.5.1.mDL%22%5D,%22grants%22:%7B%22urn:ietf:params:oauth:grant-type:pre-authorized_code%22:%7B%22pre-authorized_code%22:%22<redacted>%22,%22tx_code%22:%7B%22input_mode%22:%22text%22,%22description%22:%22Please%20enter%20the%20serial%20number%20of%20your%20physical%20drivers%20license%22%7D%7D%7D%7D"),
        ("{\n  \"credential_issuer\": \"https://credential-issuer.example.com\",\n  \"credential_configuration_ids\": [\n    \"UniversityDegreeCredential\",\n    \"org.iso.18013.5.1.mDL\"\n  ],\n  \"grants\": {\n    \"urn:ietf:params:oauth:grant-type:pre-authorized_code\": {\n      \"pre-authorized_code\": \"oaKazRN8I0IbtZ0C7JuMn5\",\n      \"tx_code\": {\n        \"length\": 4,\n        \"input_mode\": \"numeric\",\n        \"description\": \"Please provide the one-time code that was sent via e-mail\"\n      }\n    }\n  }\n}",
         "{\n  \"credential_issuer\": \"https://credential-issuer.example.com\",\n  \"credential_configuration_ids\": [\n    \"UniversityDegreeCredential\",\n    \"org.iso.18013.5.1.mDL\"\n  ],\n  \"grants\": {\n    \"urn:ietf:params:oauth:grant-type:pre-authorized_code\": {\n      \"pre-authorized_code\": \"<redacted>\",\n      \"tx_code\": {\n        \"length\": 4,\n        \"input_mode\": \"numeric\",\n        \"description\": \"Please provide the one-time code that was sent via e-mail\"\n      }\n    }\n  }\n}"),
        ("{\"credential_issuer\": \"https://credential-issuer.example.com\", \"credential_configuration_ids\": [\"UniversityDegreeCredential\"], \"grants\": {\"authorization_code\": {\"issuer_state\": \"eyJhbGciOiJSU0Et...FYUaBy\"}}}",
         "{\"credential_issuer\": \"https://credential-issuer.example.com\", \"credential_configuration_ids\": [\"UniversityDegreeCredential\"], \"grants\": {\"authorization_code\": {\"issuer_state\": \"<redacted>\"}}}"),
        ("grant_type=urn:ietf:params:oauth:grant-type:pre-authorized_code&pre-authorized_code=SplxlOBeZQQYbYS6WxSbIA&tx_code=493536",
         "grant_type=urn:ietf:params:oauth:grant-type:pre-authorized_code&pre-authorized_code=<redacted>&tx_code=<redacted>"),
    ]

    func testRedactionMatchesAndroid() {
        var mismatches: [String] = []
        for (input, expected) in Self.redactionFixtures {
            let actual = SecretRedaction.redactForModel(input)
            if actual != expected { mismatches.append("\(input)\n  expected: \(expected)\n  actual:   \(actual)") }
        }
        XCTAssertEqual(mismatches, [])
    }

    func testRedactionPlaceholdersMatchAndroid() {
        XCTAssertEqual(SecretRedaction.placeholder, "<redacted>")
        XCTAssertEqual(SecretRedaction.blobPlaceholder, "<encoded-data omitted>")
        XCTAssertEqual(SecretRedaction.seedPhrasePlaceholder, "<seed phrase redacted>")
    }

    func testRedactionIsCappedAtTwoThousandCodePoints() {
        XCTAssertEqual(SecretRedaction.redactForModel(String(repeating: "scan this ", count: 600)).count, 2000)
        // Code points, as on Android, so both ports cut in the same place.
        let emoji = SecretRedaction.redactForModel(String(repeating: "\u{1F44D}\u{1F3FD}", count: 1500))
        XCTAssertEqual(emoji.unicodeScalars.count, 2000)
        // A long opaque blob is dropped before the cap applies.
        XCTAssertEqual(SecretRedaction.redactForModel(String(repeating: "a", count: 5000)), "<encoded-data omitted>")
    }

    // MARK: Compose

    /// `kind | key=value;… | text` (values sorted by key, `nil` when the
    /// engine declines).
    static let composeCases: [(String, String)] = [
        ("wifi network BlueHouse password hunter2 hidden",
         "wifi | hidden=true;password=hunter2;ssid=BlueHouse | "),
        ("url https://example.com/a",
         "url |  | https://example.com/a"),
        ("just some words",
         "nil |  | "),
        ("wifi BlueHouse password hunter2 hidden",
         "wifi | hidden=true;password=hunter2;ssid=BlueHouse | "),
        ("wifi network named Casa Verde password verde2026 wpa3",
         "wifi | password=verde2026;security=WPA3;ssid=Casa Verde | "),
        ("url https://example.com/menu",
         "url |  | https://example.com/menu"),
        ("make me a code for my coffee shop",
         "nil |  | "),
        ("wifi",
         "nil |  | "),
        ("something clever",
         "nil |  | "),
        ("Wi-Fi QR for guest network BlueHouse, password hunter2",
         "wifi | password=hunter2;ssid=BlueHouse | "),
        ("Guest wifi called Cafe Lumen with password espresso42",
         "wifi | password=espresso42;ssid=Cafe Lumen | "),
        ("make a wifi code for my network \"Home 5G\" with password abc12345",
         "wifi | password=abc12345;ssid=Home 5G | "),
        ("wifi Key West password sunset99",
         "wifi | password=sunset99;ssid=Key West | "),
        ("WiFi for BlueHouse pw hunter2",
         "wifi | password=hunter2;ssid=BlueHouse | "),
        ("Wi-Fi QR code for the guest network, name Guests, password abc12345",
         "wifi | password=abc12345;ssid=Guests | "),
        ("Create a QR code for Wi-Fi network Office-5G password Tr0ub4dor&3",
         "wifi | password=Tr0ub4dor&3;ssid=Office-5G | "),
        ("wifi network BlueHouse hidden wpa2 password hunter2",
         "wifi | hidden=true;password=hunter2;security=WPA2;ssid=BlueHouse | "),
        ("open wifi network named Garden",
         "wifi | security=NOPASS;ssid=Garden | "),
        ("wifi network Cafe.Net password is beans4all.",
         "wifi | password=beans4all;ssid=Cafe.Net | "),
        ("wifi Ana's network password \"correct horse\"",
         "wifi | password=correct horse;ssid=Ana's network | "),
        ("wifi password hunter2",
         "nil |  | "),
        ("vcard for Ana Ivi\u{0107} +381641234567 ana@example.com",
         "contact | email=ana@example.com;name=Ana Ivi\u{0107};phone=+381641234567 | "),
        ("contact card for Marko Petrovi\u{0107}, phone 064 123 4567, company Acme",
         "contact | name=Marko Petrovi\u{0107};org=Acme;phone=064 123 4567 | "),
        ("a QR for our website example.com/menu",
         "url |  | https://example.com/menu"),
        ("link to https://example.com/contact.",
         "url |  | https://example.com/contact"),
        ("text anything at all",
         "text |  | anything at all"),
        ("note: back in 5 minutes",
         "text |  | back in 5 minutes"),
        ("wifi Garden no password hidden",
         "wifi | hidden=true;security=NOPASS;ssid=Garden | "),
        ("Wi-Fi network name: Office 5G, password: Tr0ub4dor&3",
         "wifi | password=Tr0ub4dor&3;ssid=Office 5G | "),
        ("wifi\u{00A0}BlueHouse password\u{00A0}hunter2",
         "wifi | password=hunter2;ssid=BlueHouse | "),
        ("contact card for \u{017D}ana \u{0106}iri\u{0107}, phone +381 64 123 4567, email zana@example.com",
         "contact | email=zana@example.com;name=\u{017D}ana \u{0106}iri\u{0107};phone=+381 64 123 4567 | "),
        ("vcard for Jos\u{00E9} \u{00C1}lvarez 0612345678",
         "contact | name=Jos\u{00E9} \u{00C1}lvarez;phone=0612345678 | "),
        ("business card for Anna M\u{00FC}ller, works at Siemens AG, tel 089 1234567",
         "contact | name=Anna M\u{00FC}ller;org=Siemens AG;phone=089 1234567 | "),
        ("a QR for our website m\u{00FC}nchen.de",
         "url |  | https://m\u{00FC}nchen.de"),
        ("website: www.example.com/menu.",
         "url |  | https://www.example.com/menu"),
        ("message Hello there",
         "text |  | Hello there"),
        ("link for user@example.com",
         "nil |  | "),
        ("wifi Key West open network",
         "nil |  | "),
        ("WIFI password for Home: abc 123",
         "nil |  | "),
        ("contact for Ana",
         "contact | name=Ana | "),
        ("vcard",
         "nil |  | "),
        ("website example",
         "nil |  | "),
        ("url ftp://example.com",
         "nil |  | "),
        ("note:back soon",
         "nil |  | "),
        ("TEXT Hello",
         "text |  | Hello"),
        ("wifi \u{201C}Ana\u{2019}s Place\u{201D} pw \u{2018}s3cret\u{2019}",
         "wifi | password=s3cret;ssid=Ana\u{2019}s Place | "),
        ("ssid: Lab-5G, key: Lab$ecret!",
         "wifi | password=Lab$ecret!;ssid=Lab-5G | "),
    ]

    func testComposeMatchesAndroid() {
        var mismatches: [String] = []
        for (request, expected) in Self.composeCases {
            let actual: String
            if let r = HeuristicExplainer.compose(request: request) {
                let values = r.values.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ";")
                actual = "\(r.kind.rawValue) | \(values) | \(r.text)"
            } else {
                actual = "nil |  | "
            }
            if actual != expected { mismatches.append("\(request)\n  expected: \(expected)\n  actual:   \(actual)") }
        }
        XCTAssertEqual(mismatches, [])
    }

    // MARK: Built-in explainer

    private func explain(_ raw: String) -> AssistantExplanation {
        HeuristicExplainer.explain(raw: raw, payload: ScanPayloadParser.parse(raw))
    }

    func testASeedPhraseKeepsItsDangerCaution() {
        let seed = "abandon ability able about above absent absorb abstract absurd abuse access accident"
        let e = HeuristicExplainer.explain(raw: seed, payload: nil)
        XCTAssertTrue(e.cautions.contains { $0.contains("seed phrase") }, "\(e.cautions)")
        XCTAssertFalse(([e.headline, e.summary] + e.keyPoints).contains { $0.contains("abandon") })
    }

    func testANostrPrivateKeyIsNeverRepeated() {
        let e = explain("nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5")
        XCTAssertTrue(e.keyPoints.contains("A Nostr private key (nsec)."), "\(e.keyPoints)")
        XCTAssertFalse(([e.headline, e.summary] + e.keyPoints + e.cautions)
            .contains { $0.contains("vl029") || $0.contains("nlfe5") })
    }

    func testAnOpenNetworkIsExplainedAsOpenWhateverTheCodeLeftOut() {
        let open = "No password is needed \u{2014} the network is open."
        for raw in ["WIFI:S:Cafe;P:;;", "WIFI:T:nopass;S:Cafe;;", "WIFI:S:Cafe;;"] {
            let points = explain(raw).keyPoints
            XCTAssertTrue(points.contains("Security: None.") && points.contains(open), "\(raw): \(points)")
        }
        let wpa = explain("WIFI:T:WPA;S:Cafe;P:;;").keyPoints
        XCTAssertFalse(wpa.contains("Security: None.") || wpa.contains(open), "\(wpa)")
    }

    func testTextIsCountedInTheCharactersAPersonSees() {
        func first(_ text: String) -> String? {
            HeuristicExplainer.explain(raw: text, payload: .text(text)).keyPoints.first
        }
        XCTAssertEqual(first("\u{1F44D}\u{1F3FD}"), "Plain text, 1 character.")
        XCTAssertEqual(first("cafe\u{0301}"), "Plain text, 4 characters.")
        XCTAssertEqual(first("\u{1F1F7}\u{1F1F8} Belgrade"), "Plain text, 10 characters.")
        let sms = "SMSTO:+381641234567:\u{1F44B}\u{1F3FD}" + String(repeating: "x", count: 100)
        XCTAssertTrue(explain(sms).keyPoints.contains("Pre-filled text: \u{1F44B}\u{1F3FD}" + String(repeating: "x", count: 79) + "."))
    }

    func testAnInternationalisedLinkIsExplainedByTheNameItIsWrittenIn() {
        let e = explain("https://m\u{00FC}nchen.de/")
        XCTAssertTrue(e.keyPoints.contains("Opens m\u{00FC}nchen.de in your browser."), "\(e.keyPoints)")
        XCTAssertEqual(e.cautions, ["Check the spelling of the domain before you sign in or pay."])
    }

    // MARK: Translation catalog

    func testTranslationCatalogMatchesAndroid() {
        XCTAssertEqual(TranslationCatalog.languages.map { "\($0.identifier)=\($0.label)" }, [
            "en=English",
            "de=German",
            "fr=French",
            "es=Spanish",
            "it=Italian",
            "pt-BR=Portuguese (Brazil)",
            "nl=Dutch",
            "pl=Polish",
            "cs=Czech",
            "sk=Slovak",
            "sr-Latn=Serbian (Latin)",
            "hr=Croatian",
            "sl=Slovenian",
            "bs=Bosnian",
            "bg=Bulgarian",
            "ro=Romanian",
            "el=Greek",
            "hu=Hungarian",
            "ru=Russian",
            "uk=Ukrainian",
            "tr=Turkish",
            "ar=Arabic",
            "he=Hebrew",
            "hi=Hindi",
            "zh-Hans=Chinese (Simplified)",
            "ja=Japanese",
            "ko=Korean",
            "id=Indonesian",
            "th=Thai",
            "vi=Vietnamese",
        ])
    }

    // MARK: Links a browser repairs, and what iOS opens

    func testAContactCardLinkWithoutSlashesIsStillGated() throws {
        let card = "BEGIN:VCARD\nVERSION:3.0\nFN:Ana\nURL:https:paypa1.com/login\nEND:VCARD"
        guard case .contact(let contact) = ScanPayloadParser.parse(card) else { return XCTFail("not a contact card") }
        XCTAssertEqual(contact.urls, ["https:paypa1.com/login"])
        // What `openNestedLink` grades.
        let link = try XCTUnwrap(URL(string: contact.urls[0]))
        XCTAssertTrue(QrRiskAssessor.assess(raw: link.absoluteString).isBlocking)
    }

    func testAWebLinkWhoseHostCannotBeReadIsDanger() {
        let r = QrRiskAssessor.assess(raw: "https://pay pal.com/", payload: .url(URL(string: "https://pay%20pal.com/")!))
        XCTAssertEqual(r.findings.map(\.code), ["unreadable-address"])
        XCTAssertTrue(r.isBlocking)
        // Text has no Open button: nothing to warn about.
        XCTAssertEqual(QrRiskAssessor.assess(raw: "https://pay pal.com/", payload: .text("https://pay pal.com/")).findings, [])
    }

    func testWhatIOSOpensIsNeverGradedSaferThanTheScannedText() {
        for (raw, _) in Self.riskCorpus {
            guard case .url(let url) = ScanPayloadParser.parse(raw) else { continue }
            let opened = QrRiskAssessor.assess(raw: url.absoluteString).level
            XCTAssertLessThanOrEqual(opened, QrRiskAssessor.assess(raw: raw, payload: .url(url)).level, raw)
        }
    }

    func testTheExplainerNamesTheHostTheLinkReallyOpens() {
        for raw in ["https://paypal.com\\@evil.example/login", "https://www.paypal.com\\@paypa1.com/signin"] {
            let points = explain(raw).keyPoints
            XCTAssertFalse(points.contains { $0.hasPrefix("Opens paypal.com") || $0.hasPrefix("Opens www.paypal.com") },
                           "\(raw): \(points)")
        }
        XCTAssertTrue(explain("https://paypal.com\\@evil.example/login").keyPoints.contains("Opens evil.example in your browser."))
        XCTAssertTrue(explain("https:paypa1.com/login").keyPoints.contains("Opens paypa1.com in your browser."))
    }

    func testTheGatedLinkAlertNamesTheHostLowerCased() {
        let message = QrRiskAssessor.gatedLinkMessage(for: "https://paypaI.com/x")
        XCTAssertTrue(message.hasPrefix("Impersonates PayPal\n\n"), message)
        XCTAssertTrue(message.contains("paypai.com"), message)
        XCTAssertFalse(message.contains("paypaI"), message)
    }

    // MARK: IPv4 hosts

    func testIPv4HostsAreReadTheWayABrowserReadsThem() {
        let cases: [(String, String?)] = [
            ("3627732046", "216.58.204.78"), ("0xd83ad60e", "216.58.214.14"),
            ("0330.072.0326.016", "216.58.214.14"), ("216.58.0xd6.14", "216.58.214.14"),
            ("0x7f.1", "127.0.0.1"), ("127.1", "127.0.0.1"), ("192.168.1.10", "192.168.1.10"),
            ("1.2.3.4.", "1.2.3.4"), ("0x", "0.0.0.0"), ("4294967295", "255.255.255.255"),
            ("4294967296", nil), ("256.1.1.1", nil), ("1.2.3.4.5", nil), ("08.1.1.1", nil),
            ("1..2", nil), ("0x1g", nil), ("example.com", nil), ("", nil),
        ]
        for (host, address) in cases { XCTAssertEqual(QrRiskAssessor.ipv4Address(host), address, host) }
        let finding = QrRiskAssessor.assess(raw: "https://0x7f.1/").findings.first
        XCTAssertEqual(finding?.severity, .note)
        XCTAssertTrue(finding?.detail.contains("straight to 127.0.0.1 (written as 0x7f.1) with no domain") == true)
    }

    // MARK: Seed phrases and wallet keys

    func testTheEmbeddedWordlistIsBIP39English() {
        let words = SeedPhrase.englishWordlist
        XCTAssertEqual(words.count, 2048)
        XCTAssertEqual([words.first, words[1024], words.last], ["abandon", "length", "zoo"])
        // FNV-1a (64-bit) of bip-0039/english.txt from github.com/bitcoin/bips,
        // whose SHA-256 the Android port's test checks as well.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in (words.joined(separator: "\n") + "\n").utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        XCTAssertEqual(hash, 0x82b47707efb51238)
    }

    func testSeedPhrasesAreRecognisedHoweverTheyAreWrittenDown() {
        let words = SeedPhrase.englishWordlist
        for count in [12, 15, 18, 21, 24] {
            XCTAssertTrue(SeedPhrase.isMnemonic(words.prefix(count).joined(separator: " ")), "\(count) words")
        }
        for count in [11, 13, 14, 25] {
            XCTAssertFalse(SeedPhrase.isMnemonic(words.prefix(count).joined(separator: " ")), "\(count) words")
        }
        let twelve = Array(words.prefix(12))
        let numbered = twelve.indices.map { "\($0 + 1)) \(twelve[$0])" }.joined(separator: " ")
        let padded = twelve.indices.map { ($0 < 9 ? "0" : "") + "\($0 + 1):\(twelve[$0])" }.joined(separator: "\n")
        for written in [twelve.joined(separator: "\r\n"), numbered, padded, twelve.joined(separator: ", ").uppercased(),
                        "Recovery phrase:\n" + twelve.joined(separator: " "), "SECRET RECOVERY PHRASE: " + twelve.joined(separator: " ")] {
            XCTAssertTrue(SeedPhrase.isMnemonic(written), written)
        }
        for written in ["Notes: " + twelve.joined(separator: " "), twelve.joined(separator: "-"),
                        twelve.dropLast().joined(separator: " ") + " accidents"] {
            XCTAssertFalse(SeedPhrase.isMnemonic(written), written)
        }
    }

    func testAWalletImportKeyIsAPrivateKeyOnlyWhenItsChecksumHolds() {
        XCTAssertTrue(QrRiskAssessor.containsWIFKey("5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ1jvhTVqvbTLvyTJ"))
        XCTAssertTrue(QrRiskAssessor.containsWIFKey("Paper wallet: KwdMAjGmerYanjeui5SHS7JkmpZvVipYvB2LJGU1ZxJwYvP98617 (keep it safe)"))
        XCTAssertFalse(QrRiskAssessor.containsWIFKey("5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ1jvhTVqvbTLvyTK"))
        XCTAssertFalse(QrRiskAssessor.containsWIFKey("1BoatSLRHtKNngkdXEeobR76b53LETtpyT"))
        XCTAssertEqual(codes("KwdMAjGmerYanjeui5SHS7JkmpZvVipYvB2LJGU1ZxJwYvP98617"), ["secret-exposed"])
    }

    func testTheRedactionBlanksEverySeedPhraseTheSafetyCheckFlags() {
        for (raw, verdict) in Self.riskCorpus where verdict.contains("secret-exposed:danger") && SeedPhrase.isMnemonic(raw) {
            XCTAssertEqual(SecretRedaction.redactForModel(raw), SecretRedaction.seedPhrasePlaceholder, raw)
        }
    }

    func testTheListedSecretsNeverReachTheModel() {
        for (input, _) in Self.redactionFixtures {
            for secret in ["oaKazRN8I0IbtZ0C7JuMn5", "eyJhbGciOiJSU0Et", "SplxlOBeZQQYbYS6WxSbIA", "493536",
                           "1234567890abcdefghijklmnopqrstuvwxyzAB", "AbCdEfGhIjKlMnOpQrStUvWxYz0123456789",
                           "wJalrXUtnFEMI", "XXXXXXXXXXXXXXXXXXXXXXXX", "Sunshine99", "123456789&", "987654321"] {
                XCTAssertFalse(SecretRedaction.redactForModel(input).contains(secret), "\(input) leaks \(secret)")
            }
        }
    }

    // MARK: Language-model answers

    private static let modelDraft = ScanAssistant.ModelDraft(
        headline: "Model headline", summary: "What the model said.", keyPoints: ["A model point."])

    func testAModelAnswerKeepsTheRuleCautionsOnly() async {
        let raw = "WIFI:T:WPA;S:CafeNet;P:coffee2026;H:false;;"
        let fallback = explain(raw)
        let draft = Self.modelDraft
        let e = await ScanAssistant.explain(raw: raw, fallback: fallback, model: { _ in draft })
        XCTAssertEqual(e.source, .onDeviceModel)
        XCTAssertEqual([e.headline, e.summary], ["Model headline", "What the model said."])
        XCTAssertEqual(e.keyPoints, ["A model point."])
        XCTAssertEqual(e.cautions, fallback.cautions)
        XCTAssertFalse(e.cautions.isEmpty)
    }

    func testAModelThatAnswersInASecondIsUsed() async {
        XCTAssertEqual(ScanAssistant.modelDeadline, .seconds(10))
        let raw = "https://example.com/menu"
        let draft = Self.modelDraft
        let e = await ScanAssistant.explain(raw: raw, fallback: explain(raw), model: { _ in
            try? await Task.sleep(for: .seconds(1))
            return draft
        })
        XCTAssertEqual(e.source, .onDeviceModel)
    }

    func testAModelThatNeverAnswersFallsBackInTime() async {
        let raw = "https://example.com/menu"
        let fallback = explain(raw)
        let started = ContinuousClock.now
        let e = await ScanAssistant.explain(raw: raw, fallback: fallback, model: { _ in
            try? await Task.sleep(for: .seconds(3600))
            return nil
        }, deadline: .milliseconds(200))
        XCTAssertEqual(e, fallback)
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(5))
    }

    func testAModelThatIgnoresCancellationCannotHoldTheAnswer() async {
        let raw = "https://example.com/menu"
        let draft = Self.modelDraft
        let started = ContinuousClock.now
        let e = await ScanAssistant.explain(raw: raw, fallback: explain(raw), model: { _ in
            // A detached sleep never sees the cancellation: the call runs on.
            _ = await Task.detached { try? await Task.sleep(for: .seconds(3)) }.value
            return draft
        }, deadline: .milliseconds(200))
        XCTAssertEqual(e.source, .builtIn)
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(2))
    }

    func testCancellingTheRequestEndsTheWait() async {
        let raw = "https://example.com/menu"
        let fallback = explain(raw)
        let started = ContinuousClock.now
        let request = Task {
            await ScanAssistant.explain(raw: raw, fallback: fallback, model: { _ in
                try? await Task.sleep(for: .seconds(3600))
                return nil
            })
        }
        try? await Task.sleep(for: .milliseconds(100))
        request.cancel()
        let e = await request.value
        XCTAssertEqual(e, fallback)
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(5))
    }

    func testTheModelSeesAtMostAboutFiveHundredCharactersOfThePayload() {
        let raw = String(repeating: "menu item ", count: 300)
        let prompt = ScanAssistant.explainPrompt(raw: raw, fallback: explain(raw))
        let payloadLine = prompt.components(separatedBy: "\n").last ?? ""
        XCTAssertEqual(payloadLine.count, 501)
        XCTAssertTrue(payloadLine.hasSuffix("\u{2026}"))
    }

    // MARK: Translate target and row

    func testTheDeviceLanguageIsOneThisDeviceCanTranslateInto() {
        let unavailable: Set<String> = ["cs", "sk", "sr-Latn", "hr", "sl", "bs", "bg", "ro", "el", "hu"]
        let supported = TranslationCatalog.languages.filter { !unavailable.contains($0.identifier) }
        func resolved(_ preferred: [String]) -> String? {
            TranslationCatalog.deviceLanguage(preferred: preferred, supported: supported)?.identifier
        }
        XCTAssertEqual(resolved(["cs-CZ", "en-GB"]), "en")
        XCTAssertEqual(resolved(["cs-CZ", "de-DE"]), "de")
        XCTAssertEqual(resolved(["sr-Latn-RS", "en-US"]), "en")
        XCTAssertEqual(resolved(["bs-BA", "de-DE"]), "de")
        XCTAssertNil(resolved(["cs-CZ", "sv-SE"]))
        XCTAssertEqual(TranslationCatalog.deviceLanguage(preferred: ["cs-CZ"], supported: TranslationCatalog.languages)?.identifier, "cs")
        func label(_ preferred: [String]) -> String {
            TranslationCatalog.deviceLanguageLabel(preferred: preferred, supported: supported)
        }
        XCTAssertEqual(label(["cs-CZ", "en-GB"]), "Device language (English \u{2014} Czech isn't available)")
        XCTAssertEqual(label(["cs-CZ", "de-DE"]), "Device language (German \u{2014} Czech isn't available)")
        XCTAssertEqual(label(["sv-SE", "cs-CZ"]), "Device language (English \u{2014} Czech isn't available)")
        // The same lines as the Android test, whose ML Kit lacks these two too.
        XCTAssertEqual(label(["sr-Latn-RS", "en-US"]), "Device language (English \u{2014} Serbian (Latin) isn't available)")
        XCTAssertEqual(label(["bs-BA", "de-DE"]), "Device language (German \u{2014} Bosnian isn't available)")
        XCTAssertEqual(label(["sv-SE", "bs-BA"]), "Device language (English \u{2014} Bosnian isn't available)")
        XCTAssertEqual(label(["de-AT"]), "Device language (German)")
        XCTAssertEqual(label(["sv-SE"]), "Device language (English)")
    }

    func testTranslateIsOfferedForTheSameTextAsOnAndroid() {
        XCTAssertFalse(TranslationCatalog.isTranslatable(.text("\u{0E2A}\u{0E27}\u{0E31}\u{0E2A}\u{0E14}\u{0E35}\u{0E04}\u{0E23}\u{0E31}\u{0E1A}")))
        XCTAssertFalse(TranslationCatalog.isTranslatable(.text("\u{1F44D}\u{1F3FD}\u{1F44D}\u{1F3FD}")))
        XCTAssertFalse(TranslationCatalog.isTranslatable(.text("  short  \n")))
        XCTAssertTrue(TranslationCatalog.isTranslatable(.text("caf\u{00E9}s ok")))
        XCTAssertTrue(TranslationCatalog.isTranslatable(.text("Guten Tag")))
        XCTAssertTrue(TranslationCatalog.isTranslatable(.url(URL(string: "https://example.com/")!)))
        XCTAssertFalse(TranslationCatalog.isTranslatable(.email(address: "a@example.com", subject: "Hi", body: "")))
        XCTAssertTrue(TranslationCatalog.isTranslatable(.email(address: "a@example.com", subject: nil, body: "Hallo")))
    }
}

// MARK: - QR art studio (1.10)
//
// The same fixtures as the Android port's QRStyleTest and
// QRStyleScannabilityTest: the logo's cleared square for every version, the
// SVG's single `xlink:href`, the prepared logo's size, and every preset still
// decoding with and without a logo.

final class QRStudioTests: XCTestCase {

    /// Cleared side in modules for versions 1…40: the largest odd number
    /// ≤ min(⌊side × 0.22 × 1.12⌋, side − 18). Android's
    /// `logoLayoutClearsTheSameModulesAsIOSForEveryVersion` pins the same table.
    private let clearedModules = [
        3, 5, 7, 7, 9, 9, 11, 11, 13, 13, 15, 15, 17, 17, 17, 19, 19, 21, 21, 23,
        23, 25, 25, 27, 27, 29, 29, 31, 31, 33, 33, 35, 35, 37, 37, 39, 39, 41, 41, 43,
    ]

    private let payloads: [(String, String)] = [
        ("short URL", "https://nettrash.me/scan"),
        ("Wi-Fi", CodeComposer.wifi(ssid: "Guest Network", password: "correct horse battery staple",
                                    security: .wpa)),
        ("vCard", CodeComposer.vCard(fullName: "Jane Doe", phone: "+1 555 123 4567",
                                     email: "jane.doe@example.com", organization: "ACME Corporation",
                                     url: "https://example.com/jane")),
        ("300-char text", String(String(repeating: "The quick brown fox jumps over the lazy dog. ",
                                        count: 7).prefix(300))),
    ]

    func testLogoLayoutMatchesAndroidForEveryVersion() {
        for version in 1...40 {
            let side = 21 + 4 * (version - 1)
            let modules = CGFloat(clearedModules[version - 1])
            let origin = (CGFloat(side) - modules) / 2
            let layout = QRGeometry.logoLayout(side: side)
            XCTAssertEqual(layout.cleared, CGRect(x: origin, y: origin, width: modules, height: modules),
                           "v\(version)")
            // Never into the finders, separators, timing patterns or format
            // information: the first and last nine rows and columns.
            XCTAssertGreaterThanOrEqual(layout.cleared.minX, 9, "v\(version)")
            XCTAssertLessThanOrEqual(layout.cleared.maxX, CGFloat(side - 9), "v\(version)")
            XCTAssertLessThanOrEqual(modules * modules, 0.061 * CGFloat(side * side), "v\(version)")
            // The artwork is the cleared square inset by (w − w / 1.12) / 2.
            XCTAssertEqual(layout.artwork.minX, origin + (modules - modules / 1.12) / 2, accuracy: 1e-9)
            XCTAssertEqual(layout.artwork.width, modules / 1.12, accuracy: 1e-9, "v\(version)")
            XCTAssertEqual(layout.artwork.height, layout.artwork.width, accuracy: 1e-12, "v\(version)")
        }
        XCTAssertEqual(QRGeometry.logoLayout(side: 21).artwork.minX, 9.160714, accuracy: 1e-5)
        XCTAssertEqual(QRGeometry.logoLayout(side: 33).artwork.minX, 13.375, accuracy: 1e-9)
        XCTAssertEqual(QRGeometry.logoLayout(side: 33).artwork.width, 6.25, accuracy: 1e-9)
    }

    func testPassesLeaveTheModulesUnderTheLogoOut() throws {
        let matrix = try XCTUnwrap(CodeGenerator.qrModuleMatrix(for: "https://nettrash.me/scan",
                                                                errorCorrection: .high))
        let area = try XCTUnwrap(QRGeometry.symbolArea(of: matrix))
        let side = Int(area.width)
        var style = QRStyle()
        style.logo = logo()
        let withLogo = try XCTUnwrap(QRGeometry.passes(matrix: matrix, style: style))
        let plain = try XCTUnwrap(QRGeometry.passes(matrix: matrix, style: QRStyle()))
        let cleared = QRGeometry.logoLayout(side: side).cleared
        let eyes = QRGeometry.eyeRects(width: side, height: side)

        var underLogo = 0
        for y in 0..<side {
            for x in 0..<side where !QRGeometry.isInEye(x: x, y: y, eyes: eyes) {
                let centre = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                let dark = matrix[Int(area.minX) + x, Int(area.minY) + y]
                XCTAssertEqual(plain.ink.contains(centre), dark, "module \(x),\(y) without a logo")
                if cleared.contains(centre) {
                    underLogo += 1
                    XCTAssertFalse(withLogo.ink.contains(centre), "module \(x),\(y) under the logo")
                } else {
                    XCTAssertEqual(withLogo.ink.contains(centre), dark, "module \(x),\(y) beside the logo")
                }
            }
        }
        XCTAssertEqual(underLogo, Int(cleared.width * cleared.height))
    }

    func testStyledSVGInlinesTheLogoOnceUnderXlinkHref() throws {
        let matrix = try XCTUnwrap(CodeGenerator.qrModuleMatrix(for: "https://nettrash.me/scan",
                                                                errorCorrection: .high))
        let side = Int(try XCTUnwrap(QRGeometry.symbolArea(of: matrix)).width)
        var style = QRStyle()
        style.moduleShape = .rounded
        style.logo = solid(width: 1200, height: 600)    // past the 512-pixel cap
        let svg = QRSvg.svg(for: matrix, foreground: .black, background: .white, style: style)
        let a = QRGeometry.logoLayout(side: side).artwork

        XCTAssertEqual(svg.components(separatedBy: "base64,").count - 1, 1)
        XCTAssertTrue(svg.contains(
            #"<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" "#))
        XCTAssertFalse(svg.contains(" href="), "no SVG 2 duplicate of the artwork")
        XCTAssertFalse(svg.contains("<rect x="), "no backing patch")
        let image = #"<image x="\#(svgNumber(a.minX))" y="\#(svgNumber(a.minY))" "#
            + #"width="\#(svgNumber(a.width))" height="\#(svgNumber(a.height))" "#
            + #"preserveAspectRatio="xMidYMid meet" xlink:href="data:image/png;base64,"#
        XCTAssertTrue(svg.contains(image))
        // Inside the module-unit group, after the three passes.
        let imageAt = try XCTUnwrap(svg.range(of: "<image ")).lowerBound
        XCTAssertLessThan(try XCTUnwrap(svg.range(of: "<path ", options: .backwards)).lowerBound, imageAt)
        XCTAssertLessThan(imageAt, try XCTUnwrap(svg.range(of: "</g>")).lowerBound)

        let base64 = svg.components(separatedBy: "base64,")[1].prefix { $0 != "\"" }
        let png = try XCTUnwrap(UIImage(data: try XCTUnwrap(Data(base64Encoded: String(base64)))))
        XCTAssertEqual(png.size.width * png.scale, 512)
        XCTAssertEqual(png.size.height * png.scale, 256)

        style.logo = nil
        XCTAssertFalse(QRSvg.svg(for: matrix, foreground: .black, background: .white, style: style)
            .contains("xlink"))
    }

    func testPreparedLogoCapsTheLongSideLikeAndroid() {
        // Android `preparedLogoSize` on the same inputs.
        let photo = QRStyledRenderer.preparedLogo(solid(width: 4032, height: 3024))
        XCTAssertEqual(photo.size.width * photo.scale, 1024)
        XCTAssertEqual(photo.size.height * photo.scale, 768)
        let svgSized = QRStyledRenderer.preparedLogo(solid(width: 2048, height: 1023), maxPixels: 512)
        XCTAssertEqual(svgSized.size.width * svgSized.scale, 512)
        XCTAssertEqual(svgSized.size.height * svgSized.scale, 256)
        let small = solid(width: 800, height: 600)
        XCTAssertTrue(QRStyledRenderer.preparedLogo(small) === small, "already fits: untouched")
    }

    func testEveryPresetDecodesWithAndWithoutALogo() throws {
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                                options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        var failures: [String] = []
        var exempt: [String] = []
        var decoded = 0
        for studio in try studioCases() {
            guard let ci = CIImage(image: studio.image) else {
                failures.append("\(studio.label): rendered nothing")
                continue
            }
            let text = detector.features(in: ci)
                .compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
            if studio.style.isHardToScan(symbolSide: studio.side) {
                exempt.append("\(studio.label) (\(studio.side) modules)")
            } else if text == studio.content {
                decoded += 1
            } else {
                failures.append("\(studio.label) (\(studio.side) modules): read \(text ?? "nothing")")
            }
        }
        XCTAssertEqual(failures, [])
        // The dense dots, and Soft, Nature and Ink with the logo on the vCard and the
        // 300-character text: the cases the generator warns about. Android's
        // QRStyleScannabilityTest holds the same bound.
        XCTAssertLessThanOrEqual(exempt.count, 12, "\(exempt)")
        XCTAssertEqual(decoded + exempt.count, QRStyle.presets.count * 2 * payloads.count)
    }

    // MARK: Helpers

    /// Artwork with real contrast in it — a dark tile, a light disc, a
    /// coloured core, 3:2 — the Android test's logo.
    private func logo() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 90, height: 60), format: format).image { ctx in
            UIColor(red: 0x1A / 255.0, green: 0x1A / 255.0, blue: 0x2E / 255.0, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 90, height: 60))
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 21, y: 6, width: 48, height: 48))
            UIColor(red: 0xE9 / 255.0, green: 0x45 / 255.0, blue: 0x60 / 255.0, alpha: 1).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 33, y: 18, width: 24, height: 24))
        }
    }

    private func solid(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// The SVG export's number form: at most three decimals, no trailing zeros.
    private func svgNumber(_ value: CGFloat) -> String {
        let thousandths = Int((value * 1000).rounded())
        guard thousandths % 1000 != 0 else { return String(thousandths / 1000) }
        var fraction = String(thousandths % 1000)
        fraction = String(repeating: "0", count: 3 - fraction.count) + fraction
        while fraction.hasSuffix("0") { fraction.removeLast() }
        return "\(thousandths / 1000).\(fraction)"
    }

    // MARK: The import reader

    /// Every studio code the generator does not warn about must also decode with
    /// the reader Scan's own photo / file import uses — `ImageDecoder`, a default
    /// `VNDetectBarcodesRequest` — fed the PNG the studio shares and saves. It is
    /// far stricter than CIDetector or ZXing: shaped modules with a logo stopped
    /// reading from version 13 while both of those still decoded every case.
    /// Vision reads barcodes on Mac Catalyst and on a device but not in the
    /// Simulator, which fails the plain control code as well; there the test is
    /// skipped rather than passing without reading anything.
    func testEveryUnwarnedPresetDecodesWithTheImportReader() async throws {
        try await skipUnlessTheImportReaderReadsBarcodes()
        var failures: [String] = []
        var exempt: [String] = []
        var decoded = 0
        for studio in try studioCases() {
            if studio.style.isHardToScan(symbolSide: studio.side) {
                exempt.append("\(studio.label) (\(studio.side) modules)")
                continue
            }
            let png = try XCTUnwrap(studio.image.pngData(), studio.label)
            let values = (try? await ImageDecoder.decode(data: png))?.map(\.value) ?? []
            if !values.isEmpty, values.allSatisfy({ $0 == studio.content }) {
                decoded += 1
            } else {
                failures.append("\(studio.label) (\(studio.side) modules): read \(values)")
            }
        }
        XCTAssertEqual(failures, [])
        XCTAssertLessThanOrEqual(exempt.count, 12, "\(exempt)")
        XCTAssertEqual(decoded + exempt.count, QRStyle.presets.count * 2 * payloads.count)
    }

    /// The plain generator's own output must read, or the import reader cannot
    /// judge anything. Only the Simulator may fail it, and then the caller skips.
    private func skipUnlessTheImportReaderReadsBarcodes() async throws {
        let control = try XCTUnwrap(CodeGenerator.image(for: "https://nettrash.me/scan",
                                                        symbology: .qr, scale: 12))
        do {
            let codes = try await ImageDecoder.decode(data: try XCTUnwrap(control.pngData()))
            XCTAssertEqual(codes.map(\.value), ["https://nettrash.me/scan"], "the plain control code")
        } catch {
            #if targetEnvironment(simulator)
            throw XCTSkip("The Simulator's Vision reads no barcodes (\(error.localizedDescription)); "
                          + "this oracle runs on Mac Catalyst and on a device.")
            #else
            throw error
            #endif
        }
    }

    // MARK: Linear ink paths

    /// `QRGeometry.passes` appends one path per data module. Core Graphics'
    /// `addPath(_:transform:)` costs time in proportion to the path it appends
    /// *to*, which made that loop quadratic: about 3 s for a version-40 rounded
    /// code, on the main thread, on every preview refresh. Built linearly it takes
    /// about 10 ms. Measured as this thread's CPU time, best of three, so a busy
    /// machine cannot push the linear build past the bound; the quadratic one
    /// sits ten times above it.
    func testInkPathBuildsInLinearTime() throws {
        let matrix = try XCTUnwrap(CodeGenerator.qrModuleMatrix(
            for: String(repeating: "a", count: 1250), errorCorrection: .high))
        XCTAssertEqual(QRGeometry.symbolArea(of: matrix)?.width, 177, "version 40")
        var style = QRStyle()
        style.moduleShape = .rounded
        var best = TimeInterval.infinity
        for _ in 0..<3 where best >= 0.3 {
            let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            XCTAssertNotNil(QRGeometry.passes(matrix: matrix, style: style))
            best = min(best, TimeInterval(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start) / 1e9)
        }
        XCTAssertLessThan(best, 0.3, "QRGeometry.passes spent \(best) s of CPU on a version-40 rounded code")
    }

    /// The linear build must trace the very path the transforming append built —
    /// element for element, every non-square shape, at versions 10 and 40 — so
    /// the styled SVG export is unchanged too.
    func testInkPathMatchesTheTransformingAppendElementForElement() throws {
        for (version, length) in [(10, 110), (40, 1250)] {
            let matrix = try XCTUnwrap(CodeGenerator.qrModuleMatrix(
                for: String(repeating: "a", count: length), errorCorrection: .high))
            let area = try XCTUnwrap(QRGeometry.symbolArea(of: matrix))
            let side = Int(area.width)
            XCTAssertEqual(side, 17 + 4 * version)
            let eyes = QRGeometry.eyeRects(width: side, height: side)
            for shape in QRStyle.ModuleShape.allCases where shape != .square {
                var style = QRStyle()
                style.moduleShape = shape
                let label = "v\(version) \(shape)"
                let passes = try XCTUnwrap(QRGeometry.passes(matrix: matrix, style: style), label)

                // The old construction: every module through addPath(_:transform:).
                // One destination per row keeps it fast; what that call appends
                // does not depend on what the destination already holds.
                let reference = CGMutablePath()
                let module = QRGeometry.modulePath(shape: shape)
                for y in 0..<side {
                    let row = CGMutablePath()
                    for x in 0..<side where matrix[Int(area.minX) + x, Int(area.minY) + y]
                        && !QRGeometry.isInEye(x: x, y: y, eyes: eyes) {
                        row.addPath(module, transform: CGAffineTransform(translationX: CGFloat(x),
                                                                         y: CGFloat(y)))
                    }
                    reference.addPath(row)
                }
                for eye in eyes {
                    reference.addPath(QRGeometry.eyePieces(shape: style.eyeShape, eye: eye).ring)
                }

                let got = pathElements(passes.ink), want = pathElements(reference)
                XCTAssertEqual(got.count, want.count, label)
                let mismatches = zip(got, want).filter { !sameElement($0, $1, accuracy: 1e-12) }.count
                XCTAssertEqual(mismatches, 0, label)
                let svg = QRSvg.svg(for: matrix, foreground: .black, background: .white, style: style)
                XCTAssertTrue(svg.contains(
                    ##"<path fill="#000000" fill-rule="nonzero" d="\##(svgPathData(reference))"/>"##), label)
            }
        }
    }

    /// One rendered studio code of the scannability matrix.
    private struct StudioCase {
        let label: String
        let style: QRStyle
        let content: String
        let side: Int
        let image: UIImage
    }

    /// Every preset, with and without the test logo, over every payload: encoded
    /// at the level the generator uses (the style raising the default Medium) and
    /// rendered by the studio, as the preview and the shared PNG are.
    private func studioCases() throws -> [StudioCase] {
        var cases: [StudioCase] = []
        for preset in QRStyle.presets {
            for withLogo in [false, true] {
                var style = preset.style
                if withLogo { style.logo = logo() }
                for (name, content) in payloads {
                    let label = "\(preset.name)\(withLogo ? " + logo" : ""), \(name)"
                    let matrix = try XCTUnwrap(CodeGenerator.qrModuleMatrix(
                        for: content, errorCorrection: style.errorCorrection(raising: .medium)), label)
                    let side = Int(try XCTUnwrap(QRGeometry.symbolArea(of: matrix), label).width)
                    let image = try XCTUnwrap(QRStyledRenderer.image(matrix: matrix, style: style), label)
                    cases.append(StudioCase(label: label, style: style, content: content,
                                            side: side, image: image))
                }
            }
        }
        return cases
    }

    private func pathElements(_ path: CGPath) -> [(type: CGPathElementType, points: [CGPoint])] {
        var elements: [(type: CGPathElementType, points: [CGPoint])] = []
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            let count: Int
            switch element.type {
            case .moveToPoint, .addLineToPoint: count = 1
            case .addQuadCurveToPoint:          count = 2
            case .addCurveToPoint:              count = 3
            case .closeSubpath:                 count = 0
            @unknown default:                   count = 0
            }
            elements.append((element.type, (0..<count).map { element.points[$0] }))
        }
        return elements
    }

    private func sameElement(_ a: (type: CGPathElementType, points: [CGPoint]),
                             _ b: (type: CGPathElementType, points: [CGPoint]),
                             accuracy: CGFloat) -> Bool {
        guard a.type == b.type, a.points.count == b.points.count else { return false }
        for (p, q) in zip(a.points, b.points) {
            if abs(p.x - q.x) > accuracy || abs(p.y - q.y) > accuracy { return false }
        }
        return true
    }

    /// `QRSvg`'s path data form, for finding a path in the export verbatim.
    private func svgPathData(_ path: CGPath) -> String {
        var d = ""
        for element in pathElements(path) {
            let points = element.points.map { svgNumber($0.x) + "," + svgNumber($0.y) }
            switch element.type {
            case .moveToPoint:         d += "M" + points[0]
            case .addLineToPoint:      d += "L" + points[0]
            case .addQuadCurveToPoint: d += "Q" + points.joined(separator: " ")
            case .addCurveToPoint:     d += "C" + points.joined(separator: " ")
            case .closeSubpath:        d += "Z"
            @unknown default:          break
            }
        }
        return d
    }

    // MARK: Density warnings

    /// Which codes the generator warns about, by module shape, logo and symbol
    /// side ("X" = hard to scan), for every eye shape, flat or gradient. Android's
    /// `hardToScanThresholdsMatchIOS` pins the same table, so both ports warn on
    /// the same codes.
    func testHardToScanThresholdsMatchAndroid() {
        XCTAssertEqual(QRStyle.denseDotSymbolSide, 81)
        XCTAssertEqual(QRStyle.denseDotWithLogoSymbolSide, 57)
        XCTAssertEqual(QRStyle.nonSquareWithLogoSymbolSide, 65)
        let sides = [21, 53, 57, 61, 65, 77, 81, 177]
        let table: [(shape: QRStyle.ModuleShape, plain: String, withLogo: String)] = [
            (.square,  "........", "........"),
            (.rounded, "........", "....XXXX"),
            (.dot,     "......XX", "..XXXXXX"),
            (.leaf,    "........", "....XXXX"),
            (.bars,    "........", "....XXXX"),
        ]
        let artwork = logo()
        for row in table {
            for eye in QRStyle.EyeShape.allCases {
                for inks in [[UIColor.black], [UIColor.black, UIColor.blue]] {
                    var style = QRStyle()
                    style.moduleShape = row.shape
                    style.eyeShape = eye
                    style.inks = inks
                    let plain = sides.map { style.isHardToScan(symbolSide: $0) ? "X" : "." }.joined()
                    style.logo = artwork
                    let withLogo = sides.map { style.isHardToScan(symbolSide: $0) ? "X" : "." }.joined()
                    let label = "\(row.shape) modules, \(eye) eyes, \(inks.count) ink(s)"
                    XCTAssertEqual(plain, row.plain, label)
                    XCTAssertEqual(withLogo, row.withLogo, "\(label), logo")
                }
            }
        }
    }

    /// The words under the preview, pinned here and in Android's
    /// `scannabilityWarningsMatchIOS`. With a logo the advice narrows to square
    /// modules once every shaped module is past its threshold.
    func testScannabilityWarningsMatchAndroid() throws {
        let dots = "Dots get hard for cameras to read on a code this dense. "
            + "Square, rounded, leaf or bar modules scan more reliably."
        let dotsWithLogo = "Dots get hard for cameras to read on a code this dense with a logo. "
            + "Square, rounded, leaf or bar modules — or no logo — scan more reliably."
        let shaped = "Shaped modules with a logo get hard for cameras to read on a code this dense. "
            + "Square modules — or no logo — scan more reliably."
        var style = QRStyle()
        style.moduleShape = .dot
        XCTAssertNil(style.scannabilityWarning(symbolSide: 77))
        XCTAssertEqual(style.scannabilityWarning(symbolSide: 81), dots)
        style.logo = logo()
        XCTAssertNil(style.scannabilityWarning(symbolSide: 53))
        XCTAssertEqual(style.scannabilityWarning(symbolSide: 57), dotsWithLogo)
        XCTAssertEqual(style.scannabilityWarning(symbolSide: 61), dotsWithLogo)
        XCTAssertEqual(style.scannabilityWarning(symbolSide: 65), shaped)
        XCTAssertEqual(style.scannabilityWarning(symbolSide: 177), shaped)
        for shape in [QRStyle.ModuleShape.rounded, .leaf, .bars] {
            style.moduleShape = shape
            XCTAssertNil(style.scannabilityWarning(symbolSide: 61), "\(shape)")
            XCTAssertEqual(style.scannabilityWarning(symbolSide: 65), shaped, "\(shape)")
            style.logo = nil
            XCTAssertNil(style.scannabilityWarning(symbolSide: 177), "\(shape) without a logo")
            style.logo = logo()
        }
        // Classic with a logo never warns; every other preset with one does.
        for preset in QRStyle.presets {
            var styled = preset.style
            styled.logo = logo()
            XCTAssertEqual(styled.scannabilityWarning(symbolSide: 61),
                           preset.style.moduleShape == .dot ? dotsWithLogo : nil, preset.name)
            XCTAssertEqual(styled.scannabilityWarning(symbolSide: 65),
                           preset.id == "classic" ? nil : shaped, preset.name)
        }
    }

    // MARK: Preview failures

    /// A preview that cannot draw says why instead of asking for fields that are
    /// already filled in. Lengths sit on the same side of High's and Medium's
    /// capacity in both ports' encoders (Core Image: 1273 and 2331 bytes; ZXing,
    /// whose UTF-8 ECI header costs 12 bits: 1272 and 2330), so Android's
    /// `previewExplainsWhyItHasNoCode` uses the very same fixtures.
    func testPreviewExplainsWhyItHasNoCode() throws {
        func render(_ length: Int, _ style: QRStyle,
                    picked: QRErrorCorrection = .medium) -> GeneratorScreen.PreviewResult {
            GeneratorScreen.renderPreview(GeneratorScreen.PreviewRequest(
                content: String(repeating: "a", count: length), symbology: .qr,
                style: style, errorCorrection: picked))
        }
        /// Nil when nothing was drawn; `.some(nil)` for a plain code.
        func side(_ result: GeneratorScreen.PreviewResult) -> Int?? {
            if case .code(_, let styledSide) = result { return .some(styledSide) }
            return nil
        }
        func failure(_ result: GeneratorScreen.PreviewResult) -> PreviewFailure? {
            if case .unavailable(let failure) = result { return failure }
            return nil
        }
        var rounded = QRStyle()
        rounded.moduleShape = .rounded
        var ringEyes = QRStyle()
        ringEyes.eyeShape = .ring
        var withLogo = QRStyle()
        withLogo.logo = logo()
        var gradient = QRStyle()
        gradient.inks = [.black, .blue]

        // A shape, shaped eyes or a logo raise Medium to High, which holds less.
        XCTAssertEqual(side(render(1270, rounded)), .some(177))
        XCTAssertEqual(failure(render(1274, rounded)), .tooLongForStyle)
        XCTAssertEqual(failure(render(1274, ringEyes)), .tooLongForStyle)
        XCTAssertEqual(failure(render(1274, withLogo)), .tooLongForStyle)
        // The same content still fits a plain code, and a gradient alone raises
        // nothing.
        XCTAssertEqual(side(render(1274, .standard)), .some(nil))
        XCTAssertNotNil(side(render(1274, gradient)).flatMap { $0 }, "a styled code at Medium")
        // Too long at the user's own level is not the style's doing.
        XCTAssertEqual(failure(render(1274, rounded, picked: .high)), .tooLong(.qr))
        XCTAssertEqual(side(render(2328, .standard)), .some(nil))
        XCTAssertEqual(failure(render(2332, .standard)), .tooLong(.qr))
        XCTAssertEqual(failure(render(2332, gradient)), .tooLong(.qr))
        // ZXing sets Code 128 no length limit and Core Image one of 4096, so
        // only the decision is shared there, not an encoder fixture.
        XCTAssertEqual(PreviewFailure.reason(content: String(repeating: "a", count: 5000), symbology: .code128,
                                             style: .standard, requested: .medium), .tooLong(.code128))
        XCTAssertEqual(failure(render(0, rounded)), .empty)
        XCTAssertEqual(failure(GeneratorScreen.renderPreview(GeneratorScreen.PreviewRequest(
            content: "café", symbology: .code128, style: .standard, errorCorrection: .medium))), .notASCII)

        // The words, pinned on both ports.
        XCTAssertEqual(PreviewFailure.empty.message, "Fill in the fields above to see a preview.")
        XCTAssertEqual(PreviewFailure.tooLongForStyle.message,
                       "Too long for shaped modules, shaped eyes or a logo — they need High error correction. "
                       + "Use square modules and eyes without a logo, or shorten the content.")
        XCTAssertEqual(PreviewFailure.notASCII.message,
                       "Code 128 only holds plain ASCII text — no accents, emoji or other scripts.")
        XCTAssertEqual(GeneratableSymbology.allCases.map { PreviewFailure.tooLong($0).message }, [
            "This content is too long for a QR code.",
            "This content is too long for an Aztec code.",
            "This content is too long for a PDF417 code.",
            "This content is too long for a Code 128 code.",
        ])
    }

    /// The preview's request is its `.task(id:)`: equal inputs must compare
    /// equal, or the preview would redraw on every pass of the body, and any
    /// change to what the picture shows must not.
    func testPreviewRequestChangesExactlyWithThePicture() {
        let artwork = logo()
        let ink = QRStyle.presets.first { $0.id == "ink" }?.style ?? QRStyle()
        func request(_ content: String = "https://nettrash.me/scan",
                     symbology: GeneratableSymbology = .qr,
                     picked: QRErrorCorrection = .medium,
                     _ mutate: (inout QRStyle) -> Void = { _ in }) -> GeneratorScreen.PreviewRequest {
            var style = ink
            style.logo = artwork
            mutate(&style)
            return GeneratorScreen.PreviewRequest(content: content, symbology: symbology,
                                                  style: style, errorCorrection: picked)
        }
        XCTAssertEqual(request(), request())
        XCTAssertNotEqual(request(), request("https://nettrash.me/scan/"))
        XCTAssertNotEqual(request(), request(symbology: .aztec))
        XCTAssertNotEqual(request(), request(picked: .quartile))
        XCTAssertNotEqual(request(), request { $0.moduleShape = .dot })
        XCTAssertNotEqual(request(), request { $0.eyeShape = .circle })
        XCTAssertNotEqual(request(), request { $0.inks = [.black] })
        XCTAssertNotEqual(request(), request { $0.background = .yellow })
        XCTAssertNotEqual(request(), request { $0.logo = nil })
        XCTAssertNotEqual(request(), request { $0.logo = self.solid(width: 90, height: 60) })
    }
}

// MARK: - NFC codec parity with the Android port (1.10)
//
// One fixture set, byte for byte the one in the Android port's
// `NfcPayloadCodecTest` ("shared fixtures") — the two tables were generated
// together and change together — so a tag reads, and a request writes, the
// same on both apps. Smart Posters (NFC Forum Smart Poster RTD 1.0, with its own examples
// A.1 and A.2), nested messages every NDEF parser must reject, the URI prefix
// table, RTD Text in UTF-8 and UTF-16, Wi-Fi Simple Configuration tokens in
// both directions, vCards and other media types, absolute URIs, the records
// Scan skips, and messages of several records.

final class NFCTagCodecParityTests: XCTestCase {

    // MARK: Smart Posters and every other record a tag can hand back

    func testSharedReadFixtures() {
        for fixture in Self.readFixtures {
            guard let records = NDEFRecordCodec.records(inMessage: Data(hex: fixture.hex)) else {
                XCTFail("not one well-formed NDEF message: \(fixture.name)")
                continue
            }
            XCTAssertEqual(NDEFRecordCodec.readableString(in: records), fixture.expected, fixture.name)
        }
    }

    func testMalformedNestedMessagesAreRejected() {
        for fixture in Self.malformedNestedMessages {
            let nested = Data(hex: fixture.hex)
            XCTAssertNil(NDEFRecordCodec.records(inMessage: nested), fixture.name)
            // A poster carrying it reads as nothing, and nothing traps.
            let poster = NDEFRecordCodec.Record(format: 0x01, type: Data("Sp".utf8), payload: nested)
            XCTAssertNil(NDEFRecordCodec.smartPosterURI(in: poster), fixture.name)
            XCTAssertNil(NDEFRecordCodec.readableString(in: [poster]), fixture.name)
        }
    }

    func testSmartPosterExampleParsesRecordByRecord() {
        // Example A.2's nested message: a long-form (SR = 0) URI record, the
        // action, then titles in two languages. The titles are display text
        // and never the value.
        let nested = Data(hex: "81010000000E55016E66632D666F72756D2E6F7267 11030161637400"
            + " 1101125405656E2D555348656C6C6F2C20776F726C64 510113540266694D6F726A656E732C206D6161696C6D61")
        let expected: [NDEFRecordCodec.Record] = [
            Self.wellKnown("U", [0x01], "nfc-forum.org"),
            Self.wellKnown("act", [0x00], ""),
            Self.wellKnown("T", [0x05], "en-USHello, world"),
            Self.wellKnown("T", [0x02], "fiMorjens, maailma"),
        ]
        XCTAssertEqual(NDEFRecordCodec.records(inMessage: nested), expected)
        let poster = NDEFRecordCodec.Record(format: 0x01, type: Data("Sp".utf8), payload: nested)
        XCTAssertEqual(NDEFRecordCodec.smartPosterURI(in: poster), "http://www.nfc-forum.org")
        XCTAssertNil(NDEFRecordCodec.smartPosterURI(in: NDEFRecordCodec.uriRecord("https://nettrash.me")),
                     "only an Sp record is a poster")
    }

    func testChunkedRecordIsReassembled() {
        // Initial chunk (CF, TNF 0x01, "U"), a middle chunk and the
        // terminating one (TNF 0x06, no TYPE): one record, one payload.
        let records = NDEFRecordCodec.records(inMessage: Data(hex: "B1010955046E65747472617368 3600032E6D65 5600052F7363616E"))
        XCTAssertEqual(records, [Self.wellKnown("U", [0x04], "nettrash.me/scan")])
    }

    /// A well-known record whose payload is `head`, then `text` as UTF-8.
    private static func wellKnown(_ type: String, _ head: [UInt8], _ text: String) -> NDEFRecordCodec.Record {
        NDEFRecordCodec.Record(format: 0x01, type: Data(type.utf8), payload: Data(head + Array(text.utf8)))
    }

    func testRecordCountIsBounded() {
        /// A poster of `count` records: its URI ("https://x"), then
        /// well-known "x" records with no payload, the last one with ME.
        func poster(records count: Int) -> NDEFRecordCodec.Record {
            var nested: [UInt8] = [0x91, 0x01, 0x02, 0x55, 0x04, 0x78]
            for index in 1 ..< count {
                nested += [index == count - 1 ? 0x51 : 0x11, 0x01, 0x00, 0x78]
            }
            return .init(format: 0x01, type: Data("Sp".utf8), payload: Data(nested))
        }
        XCTAssertEqual(NDEFRecordCodec.maxMessageRecords, 255)
        XCTAssertEqual(NDEFRecordCodec.readableString(in: [poster(records: 255)]), "https://x")
        XCTAssertNil(NDEFRecordCodec.readableString(in: [poster(records: 256)]))
    }

    // MARK: Write side

    func testURIPrefixTableMatchesAndroid() {
        for fixture in Self.uriPrefixFixtures {
            let record = NDEFRecordCodec.uriRecord(fixture.uri)
            XCTAssertEqual(record.payload.first, fixture.code, fixture.uri)
            let prefixLength = NDEFRecordCodec.uriPrefixes[Int(fixture.code)].utf8.count
            XCTAssertEqual(Array(record.payload.dropFirst()), Array(fixture.uri.utf8.dropFirst(prefixLength)),
                           fixture.uri)
            XCTAssertEqual(NDEFRecordCodec.uriFromPayload(record.payload), fixture.uri, fixture.uri)
        }
        XCTAssertEqual(Set(Self.uriPrefixFixtures.map(\.code)), Set<UInt8>(0x00 ... 0x23),
                       "every identifier code is exercised")
    }

    func testWriteFixturesMatchAndroid() {
        for fixture in Self.writeFixtures {
            guard let kind = NFCTagPayloadKind(rawValue: fixture.kind),
                  let records = NDEFRecordCodec.records(for: NFCTagWriteRequest(kind: kind, value: fixture.value))
            else {
                XCTFail("nothing to write: \(fixture.name)")
                continue
            }
            let expected = NDEFRecordCodec.Record(format: fixture.format, type: Data(fixture.type.utf8),
                                                  payload: Data(hex: fixture.payload))
            XCTAssertEqual(records, [expected], fixture.name)
        }
    }

    func testKindInferenceAndTrimmingMatchAndroid() {
        // The same whitespace set on both ports: Swift's whitespacesAndNewlines
        // trims U+0085 and U+200B but not U+001C...U+001F.
        for fixture in Self.inferenceFixtures {
            let kind = NFCTagPayloadKind.inferred(from: fixture.value)
            XCTAssertEqual(kind.rawValue, fixture.kind, fixture.value.debugDescription)
            XCTAssertEqual(NFCTagWriteRequest(kind: kind, value: fixture.value).isValid, fixture.valid,
                           fixture.value.debugDescription)
        }
    }

    // MARK: Fixtures — row for row the ones in NfcPayloadCodecTest.kt; change both together

    static let readFixtures: [(name: String, hex: String, expected: String?)] = [
        ("Smart Poster RTD 1.0 example A.1: a simple URI", "D102125370D1010E55016E66632D666F72756D2E6F7267", "http://www.nfc-forum.org"),
        ("Smart Poster RTD 1.0 example A.2: long URI record, action, titles in en-US and fi", "D10249537081010000000E55016E66632D666F72756D2E6F7267110301616374001101125405656E2D555348656C6C6F2C20776F726C64510113540266694D6F726A656E732C206D6161696C6D61", "http://www.nfc-forum.org"),
        ("poster with titles first (one UTF-16), a URI with an ID, action, size, type and a long-form icon", "D1027253709101135402656E5363616E206279206E6574747261736811010D54826A61FEFF30B930AD30E330F3190111015531046E657474726173682E6D652F7363616E11030161637401110104730000100011010974746578742F68746D6C420900000008696D6167652F706E6789504E470D0A1A0A", "https://nettrash.me/scan"),
        ("poster whose URI record is chunked in three", "D1021B5370B1010955046E657474726173683600032E6D655600052F7363616E", "https://nettrash.me/scan"),
        ("poster followed by an Android application record", "9102125370D1010E55016E66632D666F72756D2E6F7267 540F10616E64726F69642E636F6D3A706B676D652E6E657474726173682E7363616E", "http://www.nfc-forum.org"),
        ("a poster overrides a URI record beside it (Smart Poster RTD 1.0 section 3.4)", "91010C55026578616D706C652E636F6D 5102155370D1011155046E657474726173682E6D652F7363616E", "https://nettrash.me/scan"),
        ("a text record before a poster still comes first", "9101085402656E68656C6C6F 5102125370D1010E55016E66632D666F72756D2E6F7267", "hello"),
        ("an unreadable poster does not hide the URI beside it", "91010C55046578616D706C652E636F6D 5102055370D101FF5504", "https://example.com"),
        ("two URI records in a poster: the first readable one", "D102145370910102557F7851010A5504622E6578616D706C65", "https://b.example"),
        ("a poster inside a poster is not followed", "D102175370D102125370D1010E55016E66632D666F72756D2E6F7267", nil),
        ("a poster with titles only", "D1021953709101075402656E5363616E51010A540264655363616E6E656E", nil),
        ("a poster with an empty payload", "D102005370", nil),
        ("URI 0x00: no prefix", "D1010E55006E657474726173682E6D652F78", "nettrash.me/x"),
        ("URI 0x02: https://www.", "D1010C55026E657474726173682E6D65", "https://www.nettrash.me"),
        ("URI 0x23: urn:nfc:, the last code", "D101055523736E3A31", "urn:nfc:sn:1"),
        ("URI 0x24: the first reserved code", "D10102552478", nil),
        ("URI 0xFF: reserved", "D1010255FF78", nil),
        ("URI: a prefix code and nothing else", "D101015504", "https://"),
        ("URI: empty payload", "D1010055", nil),
        ("URI: UTF-8 path kept as is", "D1010F55046578616D706C652E636F6D2FC3A4", "https://example.com/\u{E4}"),
        ("URI: an invalid UTF-8 byte", "D101025504FF", "https://\u{FFFD}"),
        ("Text: UTF-8, en", "D1010B5402656E5061737320233432", "Pass #42"),
        ("Text: UTF-8, five-byte language tag", "D101125405656E2D555348656C6C6F2C20776F726C64", "Hello, world"),
        ("Text: no language tag", "D10105540062617265", "bare"),
        ("Text: reserved status bit 6 set", "D101045442656E78", "x"),
        ("Text: UTF-16 big-endian, no BOM", "D101095482656E004800692713", "Hi\u{2713}"),
        ("Text: UTF-16 big-endian BOM", "D1010B5482656EFEFF004800692713", "Hi\u{2713}"),
        ("Text: UTF-16 little-endian BOM (what Core NFC writes)", "D1010B5482656EFFFE480069001327", "Hi\u{2713}"),
        ("Text: UTF-16 surrogate pair", "D101095482656EFFFE3DD800DE", "\u{1F600}"),
        ("Text: UTF-16 with an odd trailing byte", "D101065482656E004800", "H"),
        ("Text: UTF-16 unpaired high surrogate", "D101075482656ED8000041", "\u{FFFD}A"),
        ("Text: UTF-16 lone low surrogate", "D101075482656EDC000041", "\u{FFFD}A"),
        ("Text: UTF-16 high surrogate at the end", "D101075482656E0041D800", "A\u{FFFD}"),
        ("Text: UTF-16 high, high, low", "D101095482656ED800D800DC00", "\u{FFFD}\u{10000}"),
        ("Text: UTF-16 BOM and a lone byte", "D101065482656EFFFE48", nil),
        ("Text: language length past the end", "D10103543F656E", nil),
        ("Text: blank", "D101065402656E202020", nil),
        ("Text: only U+0085", "D101055402656EC285", nil),
        ("Text: only U+200B", "D101065402656EE2808B", nil),
        ("Text: only U+001D is not blank", "D101045402656E1D", "\u{1D}"),
        ("WSC: WPA2-Personal", "D217416170706C69636174696F6E2F766E642E7766612E777363104A000110100E002E1026000101104500054775657374100300020020100F000200081027000673336372657410200006FFFFFFFFFFFF1049000600372A000120", "WIFI:T:WPA;S:Guest;P:s3cret;;"),
        ("WSC: characters the WIFI: string escapes", "D217466170706C69636174696F6E2F766E642E7766612E777363104A000110100E003310260001011045000947756573743B4E6574100300020020100F0002000810270007733363723A657410200006FFFFFFFFFFFF1049000600372A000120", "WIFI:T:WPA;S:Guest\\;Net;P:s3cr\\:et;;"),
        ("WSC: open", "D2173A6170706C69636174696F6E2F766E642E7766612E777363104A000110100E002710260001011045000443616665100300020001100F000200011027000010200006FFFFFFFFFFFF1049000600372A000120", "WIFI:T:nopass;S:Cafe;;"),
        ("WSC: WPA and WPA2 mixed", "D217436170706C69636174696F6E2F766E642E7766612E777363104A000110100E00301026000101104500054D69786564100300020022100F0002000C10270008736563726574313210200006FFFFFFFFFFFF1049000600372A000120", "WIFI:T:WPA;S:Mixed;P:secret12;;"),
        ("WSC: shared key (WEP)", "D2173E6170706C69636174696F6E2F766E642E7766612E777363104A000110100E002B1026000101104500034F6C64100300020004100F0002000210270005313233343510200006FFFFFFFFFFFF1049000600372A000120", "WIFI:T:WEP;S:Old;P:12345;;"),
        ("WSC: WEP encryption on open authentication", "D2173E6170706C69636174696F6E2F766E642E7766612E777363104A000110100E002B1026000101104500034F6C64100300020001100F0002000210270005313233343510200006FFFFFFFFFFFF1049000600372A000120", "WIFI:T:WEP;S:Old;P:12345;;"),
        ("WSC: no authentication flags but a key", "D217416170706C69636174696F6E2F766E642E7766612E777363104A000110100E002E10260001011045000357686F100300020000100F0002000010270008736563726574313210200006FFFFFFFFFFFF1049000600372A000120", "WIFI:T:WPA;S:Who;P:secret12;;"),
        ("WSC: no authentication flags and no key", "D217396170706C69636174696F6E2F766E642E7766612E777363104A000110100E002610260001011045000357686F100300020000100F000200001027000010200006FFFFFFFFFFFF1049000600372A000120", "WIFI:T:nopass;S:Who;;"),
        ("WSC: WPA2-Personal with an empty key", "D2173B6170706C69636174696F6E2F766E642E7766612E777363104A000110100E00281026000101104500054E6F4B6579100300020020100F000200081027000010200006FFFFFFFFFFFF1049000600372A000120", "WIFI:T:WPA;S:NoKey;;"),
        ("WSC: WPA2-Enterprise", "D2173D6170706C69636174696F6E2F766E642E7766612E777363104A000110100E002A1026000101104500064F6666696365100300020010100F00020008102700017810200006FFFFFFFFFFFF1049000600372A000120", nil),
        ("WSC: media type in capitals", "D217414150504C49434154494F4E2F564E442E5746412E575343104A000110100E002E1026000101104500054775657374100300020020100F000200081027000673336372657410200006FFFFFFFFFFFF1049000600372A000120", "WIFI:T:WPA;S:Guest;P:s3cret;;"),
        ("WSC: a repeated SSID, the last one wins", "D2171D6170706C69636174696F6E2F766E642E7766612E777363100E0019104500054669727374104500065365636F6E64100300020001", "WIFI:T:nopass;S:Second;;"),
        ("WSC: an authentication attribute of the wrong length is ignored", "D2171E6170706C69636174696F6E2F766E642E7766612E777363100E001A104500034F646410030003002000102700087365637265743132", "WIFI:T:WPA;S:Odd;P:secret12;;"),
        ("WSC: truncated", "D217066170706C69636174696F6E2F766E642E7766612E777363100E00FF1045", nil),
        ("WSC: no credential", "D217056170706C69636174696F6E2F766E642E7766612E777363104A000110", nil),
        ("vCard: text/vcard", "D20A31746578742F7663617264424547494E3A56434152440D0A56455253494F4E3A332E300D0A464E3A416E6120497669C4870D0A454E443A5643415244", "BEGIN:VCARD\u{D}\u{A}VERSION:3.0\u{D}\u{A}FN:Ana Ivi\u{107}\u{D}\u{A}END:VCARD"),
        ("vCard: text/x-vcard", "D20C31746578742F782D7663617264424547494E3A56434152440D0A56455253494F4E3A332E300D0A464E3A416E6120497669C4870D0A454E443A5643415244", "BEGIN:VCARD\u{D}\u{A}VERSION:3.0\u{D}\u{A}FN:Ana Ivi\u{107}\u{D}\u{A}END:VCARD"),
        ("vCard: capitals and a parameter", "D21B31546578742F582D56436172643B20636861727365743D7574662D38424547494E3A56434152440D0A56455253494F4E3A332E300D0A464E3A416E6120497669C4870D0A454E443A5643415244", "BEGIN:VCARD\u{D}\u{A}VERSION:3.0\u{D}\u{A}FN:Ana Ivi\u{107}\u{D}\u{A}END:VCARD"),
        ("vCard: spaces and a tab around the type", "D2103120746578742F7663617264093B783D79424547494E3A56434152440D0A56455253494F4E3A332E300D0A464E3A416E6120497669C4870D0A454E443A5643415244", "BEGIN:VCARD\u{D}\u{A}VERSION:3.0\u{D}\u{A}FN:Ana Ivi\u{107}\u{D}\u{A}END:VCARD"),
        ("vCard: nothing before the semicolon", "D20B313B746578742F7663617264424547494E3A56434152440D0A56455253494F4E3A332E300D0A464E3A416E6120497669C4870D0A454E443A5643415244", nil),
        ("vCard: a newline is not optional whitespace", "D20B31746578742F76636172640A424547494E3A56434152440D0A56455253494F4E3A332E300D0A464E3A416E6120497669C4870D0A454E443A5643415244", nil),
        ("media: text/plain is skipped", "D20A05746578742F706C61696E68656C6C6F", nil),
        ("media: an image is skipped", "D20904696D6167652F706E6789504E47", nil),
        ("absolute URI in TYPE", "D3170068747470733A2F2F6E657474726173682E6D652F746167", "https://nettrash.me/tag"),
        ("absolute URI in the payload", "D3001A68747470733A2F2F6E657474726173682E6D652F6C6567616379", "https://nettrash.me/legacy"),
        ("absolute URI in both: TYPE wins", "D3121268747470733A2F2F612E6578616D706C652F68747470733A2F2F622E6578616D706C652F", "https://a.example/"),
        ("absolute URI with neither", "D30000", nil),
        ("the empty record", "D00000", nil),
        ("unknown TNF", "D5000568656C6C6F", nil),
        ("external type", "D40F10616E64726F69642E636F6D3A706B676D652E6E657474726173682E7363616E", nil),
        ("reserved TNF", "D7000568656C6C6F", nil),
        ("well-known type nobody defined", "D10205587868656C6C6F", nil),
        ("external record, then a URI", "940F10616E64726F69642E636F6D3A706B676D652E6E657474726173682E7363616E 51010C55046E657474726173682E6D65", "https://nettrash.me"),
        ("blank text, then text", "9101055402656E2020 5101095402656E757361626C65", "usable"),
        ("unknown, then a vCard, then a URI", "9500013F 120A31746578742F7663617264424547494E3A56434152440D0A56455253494F4E3A332E300D0A464E3A416E6120497669C4870D0A454E443A5643415244 51010C55046E657474726173682E6D65", "BEGIN:VCARD\u{D}\u{A}VERSION:3.0\u{D}\u{A}FN:Ana Ivi\u{107}\u{D}\u{A}END:VCARD"),
    ]

    static let malformedNestedMessages: [(name: String, hex: String)] = [
        ("empty", ""),
        ("a payload length past the end", "D1 01 FF 55 04"),
        ("a four-byte payload length of 2^32 - 1", "C1 01 FFFFFFFF 55 04 78"),
        ("a type length past the end", "D1 05 00 55"),
        ("an ID length past the end", "D9 01 00 05 55"),
        ("a header cut short", "91 01"),
        ("no MB on the first record", "51 01 02 55 04 78"),
        ("MB on a second record", "91 01 02 55 04 78 D1 01 02 55 04 79"),
        ("no ME before the end", "91 01 02 55 04 78"),
        ("a byte after ME", "D1 01 02 55 04 78 00"),
        ("ME on an initial chunk", "F1 01 02 55 04 78"),
        ("ME on a middle chunk", "B1 01 02 55 04 78 76 00 01 79 56 00 01 7A"),
        ("a later chunk that is not TNF 0x06", "B1 01 02 55 04 78 51 00 01 79"),
        ("TNF 0x06 outside a chunk", "D6 00 01 78"),
        ("a later chunk with a TYPE", "B1 01 02 55 04 78 56 01 01 55 79"),
        ("a later chunk with an ID length", "B1 01 02 55 04 78 5E 00 01 00 79"),
        ("an initial chunk without a TYPE", "B1 00 02 04 78 56 00 01 79"),
        ("an empty record with a payload", "D0 00 01 78"),
        ("an empty record with an ID", "D8 00 00 01 78"),
        ("an unknown record with a TYPE", "D5 01 01 55 78"),
        ("a reserved record with a TYPE", "D7 01 01 55 78"),
        ("MB on a middle chunk", "B1 01 02 55 04 78 B6 00 01 79 56 00 01 7A"),
    ]

    static let uriPrefixFixtures: [(uri: String, code: UInt8)] = [
        ("https://www.nettrash.me", 0x02),
        ("https://nettrash.me", 0x04),
        ("http://www.example.com", 0x01),
        ("http://example.com", 0x03),
        ("tel:+15551234", 0x05),
        ("mailto:a@b.c", 0x06),
        ("ftp://anonymous:anonymous@x", 0x07),
        ("ftp://ftp.x.org", 0x08),
        ("ftps://x", 0x09),
        ("sftp://x", 0x0A),
        ("smb://x", 0x0B),
        ("nfs://x", 0x0C),
        ("ftp://x.org", 0x0D),
        ("dav://x", 0x0E),
        ("news:x", 0x0F),
        ("telnet://x", 0x10),
        ("imap:x", 0x11),
        ("rtsp://x", 0x12),
        ("urn:x", 0x13),
        ("pop:x", 0x14),
        ("sip:x", 0x15),
        ("sips:x", 0x16),
        ("tftp:x", 0x17),
        ("btspp://x", 0x18),
        ("btl2cap://x", 0x19),
        ("btgoep://x", 0x1A),
        ("tcpobex://x", 0x1B),
        ("irdaobex://x", 0x1C),
        ("file:///x", 0x1D),
        ("urn:epc:id:x", 0x1E),
        ("urn:epc:tag:x", 0x1F),
        ("urn:epc:pat:x", 0x20),
        ("urn:epc:raw:x", 0x21),
        ("urn:epc:x", 0x22),
        ("urn:nfc:x", 0x23),
        ("ftp://ftp.", 0x08),
        ("HTTPS://X.ORG", 0x00),
        ("nettrash.me", 0x00),
        ("https:/x", 0x00),
        ("", 0x00),
    ]

    static let writeFixtures: [(name: String, kind: String, value: String, format: UInt8, type: String, payload: String)] = [
        ("a URL, abbreviated", "url", "https://www.nettrash.me/scan", 0x01, "U", "026E657474726173682E6D652F7363616E"),
        ("a URL, trimmed first", "url", "  https://nettrash.me \u{A}", 0x01, "U", "046E657474726173682E6D65"),
        ("a URL behind a zero-width space", "url", "\u{200B}https://nettrash.me", 0x01, "U", "046E657474726173682E6D65"),
        ("text, as UTF-8 with \"en\"", "text", "Pass #42 \u{2014} gate B", 0x01, "T", "02656E506173732023343220E2809420676174652042"),
        ("text keeps its spaces", "text", "  hi  ", 0x01, "T", "02656E202068692020"),
        ("a WPA network", "wifi", "WIFI:T:WPA;S:Guest;P:s3cret;;", 0x02, "application/vnd.wfa.wsc", "104A000110100E002E1026000101104500054775657374100300020020100F000200081027000673336372657410200006FFFFFFFFFFFF1049000600372A000120"),
        ("a WPA2 network with escapes", "wifi", "WIFI:T:WPA2;S:Guest\\;Net;P:s3cr\\:et;;", 0x02, "application/vnd.wfa.wsc", "104A000110100E003310260001011045000947756573743B4E6574100300020020100F0002000810270007733363723A657410200006FFFFFFFFFFFF1049000600372A000120"),
        ("an open network", "wifi", "WIFI:T:nopass;S:Cafe;;", 0x02, "application/vnd.wfa.wsc", "104A000110100E002710260001011045000443616665100300020001100F000200011027000010200006FFFFFFFFFFFF1049000600372A000120"),
        ("an open network drops a stray password", "wifi", "WIFI:T:nopass;S:Cafe;P:ignored;;", 0x02, "application/vnd.wfa.wsc", "104A000110100E002710260001011045000443616665100300020001100F000200011027000010200006FFFFFFFFFFFF1049000600372A000120"),
        ("no type and no password is open", "wifi", "WIFI:S:Cafe;;", 0x02, "application/vnd.wfa.wsc", "104A000110100E002710260001011045000443616665100300020001100F000200011027000010200006FFFFFFFFFFFF1049000600372A000120"),
        ("a WPA3 network stays text", "wifi", "WIFI:T:SAE;S:Home;P:longpassword;;", 0x01, "T", "02656E574946493A543A5341453B533A486F6D653B503A6C6F6E6770617373776F72643B3B"),
        ("a WEP network stays text", "wifi", "WIFI:T:WEP;S:Old;P:12345;;", 0x01, "T", "02656E574946493A543A5745503B533A4F6C643B503A31323334353B3B"),
        ("a Passpoint network stays text", "wifi", "WIFI:T:HS20;S:Air;P:x;;", 0x01, "T", "02656E574946493A543A485332303B533A4169723B503A783B3B"),
        ("a hidden network stays text", "wifi", "WIFI:T:WPA;S:Hid;P:longpassword;H:true;;", 0x01, "T", "02656E574946493A543A5750413B533A4869643B503A6C6F6E6770617373776F72643B483A747275653B3B"),
        ("a WPA without a password network stays text", "wifi", "WIFI:T:WPA;S:Net;;", 0x01, "T", "02656E574946493A543A5750413B533A4E65743B3B"),
        ("a no type with a password network stays text", "wifi", "WIFI:S:Net;P:secret12;;", 0x01, "T", "02656E574946493A533A4E65743B503A73656372657431323B3B"),
        ("a a 33-byte SSID network stays text", "wifi", "WIFI:T:WPA;S:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;P:secret12;;", 0x01, "T", "02656E574946493A543A5750413B533A7878787878787878787878787878787878787878787878787878787878787878783B503A73656372657431323B3B"),
        ("a a 65-byte key network stays text", "wifi", "WIFI:T:WPA;S:Net;P:kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk;;", 0x01, "T", "02656E574946493A543A5750413B533A4E65743B503A6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B3B3B"),
        ("a 32-byte SSID and a 64-byte key still fit", "wifi", "WIFI:T:WPA;S:ssssssssssssssssssssssssssssssss;P:kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk;;", 0x02, "application/vnd.wfa.wsc", "104A000110100E00831026000101104500207373737373737373737373737373737373737373737373737373737373737373100300020020100F00020008102700406B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B6B10200006FFFFFFFFFFFF1049000600372A000120"),
        ("a vCard", "contact", "BEGIN:VCARD\u{D}\u{A}VERSION:3.0\u{D}\u{A}FN:Ana Ivi\u{107}\u{D}\u{A}END:VCARD", 0x02, "text/vcard", "424547494E3A56434152440D0A56455253494F4E3A332E300D0A464E3A416E6120497669C4870D0A454E443A5643415244"),
        ("a vCard with a combining mark after BEGIN:VCARD", "contact", "BEGIN:VCARD\u{301}\u{D}\u{A}END:VCARD", 0x02, "text/vcard", "424547494E3A5643415244CC810D0A454E443A5643415244"),
        ("a MECARD stays text", "contact", "MECARD:N:Doe,Jane;;", 0x01, "T", "02656E4D45434152443A4E3A446F652C4A616E653B3B"),
    ]

    static let inferenceFixtures: [(value: String, kind: String, valid: Bool)] = [
        ("\u{200B}https://nettrash.me", "url", true),
        (" \u{9}\u{A}http://x ", "url", true),
        ("\u{85}WIFI:T:WPA;S:x;P:y;;", "wifi", true),
        ("\u{3000}begin:vcard\u{A}END:VCARD", "contact", true),
        ("\u{1D}https://nettrash.me", "text", true),
        ("\u{1F}BEGIN:VCARD\u{A}END:VCARD", "text", true),
        ("httpd is down", "text", true),
        ("mailto:hi@example.com", "url", true),
        ("\u{200B} \u{85}", "text", false),
        ("\u{1D}", "text", true),
        // The links besides the web's (`linkPrefixes`), in any case...
        ("tel:+15551234", "url", true),
        ("SMSTO:+15551234:Hi", "url", true),
        ("\u{A0}Geo:44.8125,20.4612", "url", true),
        ("Tel: +1 555 1234", "url", true),
        // ...and lookalikes, which stay text.
        ("telnet://x", "text", true),
        ("geology: rocks", "text", true),
        ("sms", "text", true),
        // A prefix is matched byte by byte, as Kotlin's startsWith matches
        // chars: a combining mark straight after it — on the colon, even —
        // doesn't hide it.
        ("tel:\u{301}5551234", "url", true),
        ("https://\u{301}x", "url", true),
        ("BEGIN:VCARD\u{301}\u{A}END:VCARD", "contact", true),
        // Nothing but whitespace can't be written, so the Write button is off.
        ("", "text", false),
        (" \u{A}\u{9}\u{3000}\u{2028}", "text", false),
    ]

    // MARK: Phone, email, SMS and map links

    func testLinksBecomeURIRecordsCoreNFCReadsBack() {
        XCTAssertEqual(NFCTagPayloadKind.linkPrefixes,
                       ["http://", "https://", "tel:", "mailto:", "sms:", "smsto:", "geo:"])
        for fixture in Self.linkFixtures {
            let kind = NFCTagPayloadKind.inferred(from: fixture.value)
            XCTAssertEqual(kind, .url, fixture.name)
            guard let records = NDEFRecordCodec.records(for: NFCTagWriteRequest(kind: kind, value: fixture.value))
            else {
                XCTFail("nothing to write: \(fixture.name)")
                continue
            }
            let payload = Data(hex: fixture.payload)
            XCTAssertEqual(records, [NDEFRecordCodec.Record(format: 0x01, type: Data("U".utf8), payload: payload)],
                           fixture.name)
            // Scan reads back exactly what a scan of the code gives...
            XCTAssertEqual(NDEFRecordCodec.readableString(in: records), fixture.uri, fixture.name)
            // ...and Core NFC's own reader hands an app the same URL: the URI
            // itself when it is ASCII, percent-encoded as `URL(string:)`
            // encodes it when it is not.
            let system = NFCNDEFPayload(format: .nfcWellKnown, type: Data("U".utf8), identifier: Data(),
                                        payload: payload).wellKnownTypeURIPayload()
            XCTAssertEqual(system, URL(string: fixture.uri), fixture.name)
            if fixture.uri.unicodeScalars.allSatisfy(\.isASCII) {
                XCTAssertEqual(system?.absoluteString, fixture.uri, fixture.name)
            }
        }
    }

    // MARK: An outcome belongs to the content it was for

    @MainActor
    func testEditingTheContentClearsTheLastOutcome() {
        let writer = NFCTagWriter()
        writer.contentDidChange()
        XCTAssertEqual(writer.status, .idle, "nothing to clear")
        for fixture in Self.outcomeFixtures {
            let request = NFCTagWriteRequest(kind: .inferred(from: fixture.value), value: fixture.value)
            // Content worth writing would start a real session on an iPhone;
            // the simulator has no NFC reader, and that is the outcome here.
            if request.isValid, NFCTagWriter.isSupported { continue }
            writer.write(request)
            XCTAssertEqual(writer.status, .failed(fixture.failure), fixture.value.debugDescription)
            writer.contentDidChange()
            XCTAssertEqual(writer.status, .idle, fixture.value.debugDescription)
        }
    }

    // Row for row the ones in NfcPayloadCodecTest.kt; change both together.

    static let linkFixtures: [(name: String, value: String, uri: String, payload: String)] = [
        ("a phone number: tel: is code 0x05", "tel:+15551234", "tel:+15551234", "052B3135353531323334"),
        ("an email: mailto: is code 0x06", "mailto:hi@example.com?subject=Hi%20there", "mailto:hi@example.com?subject=Hi%20there", "066869406578616D706C652E636F6D3F7375626A6563743D48692532307468657265"),
        ("an SMS: sms: has no code, so it is written whole", "sms:+15551234?body=Hi", "sms:+15551234?body=Hi", "00736D733A2B31353535313233343F626F64793D4869"),
        ("an SMS as smsto:, written whole", "smsto:+15551234:Hi", "smsto:+15551234:Hi", "00736D73746F3A2B31353535313233343A4869"),
        ("a place: geo: has no code, so it is written whole", "geo:44.8125,20.4612", "geo:44.8125,20.4612", "0067656F3A34342E383132352C32302E34363132"),
        ("a scheme in capitals is a link too, written as typed", "TEL:+15551234", "TEL:+15551234", "0054454C3A2B3135353531323334"),
        ("a scheme in mixed case, written as typed", "MailTo:hi@example.com", "MailTo:hi@example.com", "004D61696C546F3A6869406578616D706C652E636F6D"),
        ("trimmed, like a web link", " \u{A}geo:0,0?q=Belgrade\u{9} ", "geo:0,0?q=Belgrade", "0067656F3A302C303F713D42656C6772616465"),
        ("a combining mark straight after the colon", "tel:\u{301}5551234", "tel:\u{301}5551234", "05CC8135353531323334"),
    ]

    static let outcomeFixtures: [(value: String, failure: String)] = [
        (" \u{A}", "Nothing to write yet — fill in the content first."),
        ("tel:+15551234", "This device can't write NFC tags."),
    ]
}

// MARK: - Scanner and quick entry (1.10)
//
// Bulk capture outliving mode switches, the Start Scanning intent's mode
// write and camera request, and the mode hints. The Android port's
// `BulkScanSessionTest`, `ScanModeHintsTest`, `ScanEntryDispatcherTest` and
// `ScannerRevealCameraTest` run the same cases on the same inputs.

// For the in-memory store the Bulk "Save all to History" tests write to.
// Declared here, beside the one class that uses it.
import CoreData

final class ScannerQuickEntryTests: XCTestCase {

    @MainActor
    private func code(_ value: String) -> ScannedCode {
        ScannedCode(value: value, symbology: .qr, avType: "org.iso.QRCode",
                    timestamp: Date(timeIntervalSince1970: 1_700_000_000), previewRect: nil)
    }

    @MainActor
    func testBulkListSurvivesLeavingAndReenteringBulk() {
        let session = BulkScanSession()
        session.start()
        XCTAssertTrue(session.ingest(code("A")))
        XCTAssertTrue(session.ingest(code("B")))
        XCTAssertFalse(session.ingest(code("A")))

        // Codes, Live Text, another tab or the background: paused, kept.
        session.stop()
        XCTAssertFalse(session.isRunning)
        XCTAssertFalse(session.ingest(code("C")), "a paused capture collects nothing")
        XCTAssertEqual(session.entries.map(\.value), ["A", "B"])

        // Back in Bulk: the same list, and the counter shows it.
        session.start()
        XCTAssertTrue(session.isRunning)
        XCTAssertEqual(session.count, 2)
        XCTAssertEqual(session.entries.map(\.sightings), [2, 1])
        XCTAssertFalse(session.ingest(code("B")), "kept entries still dedupe")
        XCTAssertTrue(session.ingest(code("C")))
        XCTAssertEqual(session.entries.map(\.value), ["A", "B", "C"])
        XCTAssertEqual(session.entries.map(\.sightings), [2, 2, 1])
    }

    @MainActor
    func testOnlyClearEmptiesTheBulkList() {
        let session = BulkScanSession()
        session.start()
        session.ingest(code("A"))
        session.start()
        for _ in 0..<3 {
            session.stop()
            session.start()
        }
        XCTAssertEqual(session.entries.map(\.value), ["A"], "pausing and resuming never drops the list")

        session.reset()
        XCTAssertTrue(session.isEmpty)
        XCTAssertTrue(session.isRunning, "Clear empties the list without stopping the capture")
        XCTAssertTrue(session.ingest(code("A")), "a cleared value is new again")

        session.stop()
        session.reset()
        XCTAssertTrue(session.isEmpty)
        XCTAssertFalse(session.isRunning, "Clear while paused stays paused")
    }

    func testScanModeStoredValuesAreTheSharedKeys() {
        // Android's `ScanModePreference.key`, in the same order.
        XCTAssertEqual(ScanMode.allCases.map(\.storedValue), ["codes", "text", "bulk"])
        XCTAssertEqual(ScanMode.allCases.map(\.label), ["Codes", "Live Text", "Bulk"])
        for mode in ScanMode.allCases {
            XCTAssertEqual(ScanMode(storedValue: mode.storedValue), mode)
            XCTAssertEqual(ScanMode(storedValue: mode.label), mode, "an unreleased build stored labels")
        }
        XCTAssertEqual(ScanMode(storedValue: ""), .codes)
        XCTAssertEqual(ScanMode(storedValue: "Text"), .codes)
        XCTAssertEqual(ScanMode(storedValue: "BULK"), .codes)
    }

    func testStoreWritesTheScanTabKey() throws {
        let suite = "ScannerQuickEntryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for mode in ScanMode.allCases {
            ScanMode.store(mode, in: defaults)
            let stored = defaults.string(forKey: ScanSettingsKey.scanMode)
            XCTAssertEqual(stored, mode.storedValue)
            XCTAssertEqual(ScanMode(storedValue: stored ?? ""), mode)
        }
    }

    @MainActor
    func testStartScanningMapsEveryOptionExplicitly() {
        let pairs: [(ScanModeOption, ScanMode)] = [(.codes, .codes), (.text, .text), (.bulk, .bulk)]
        XCTAssertEqual(ScanModeOption.allCases.count, pairs.count)
        // Saved shortcuts hold these; they are Shortcuts' business, not the
        // Scan tab's stored key.
        XCTAssertEqual(pairs.map(\.0.rawValue), ["codes", "text", "bulk"])
        for (option, mode) in pairs {
            XCTAssertEqual(option.scanMode, mode)
            XCTAssertEqual(StartScanningIntent.resolvedMode(for: option, isAvailable: { _ in true }), mode)
        }
        // Where VisionKit can't run, Live Text opens Codes; nothing else moves.
        let noLiveText: @MainActor (ScanMode) -> Bool = { $0 != .text }
        XCTAssertEqual(StartScanningIntent.resolvedMode(for: .text, isAvailable: noLiveText), .codes)
        XCTAssertEqual(StartScanningIntent.resolvedMode(for: .codes, isAvailable: noLiveText), .codes)
        XCTAssertEqual(StartScanningIntent.resolvedMode(for: .bulk, isAvailable: noLiveText), .bulk)
    }

    @MainActor
    func testEveryScannerRequestIsAChange() {
        let router = ScanIntentRouter.shared
        let before = router.scannerRequests
        router.showScanner()
        router.showScanner()
        XCTAssertEqual(router.scannerRequests, before + 2, "asking twice in a row registers twice")
    }

    func testModeHintsSayWhatThisPlatformDoes() {
        // Live Text: VisionKit's highlighted blocks open the card (Copy /
        // Share / Translate), and the shutter freezes a frame for word
        // selection with the system menu.
        XCTAssertEqual(ScanMode.text.footnote,
                       "Tap highlighted text to copy, share or translate it, or freeze the frame to select words. A single code is read straight away; with several, tap one.")
        XCTAssertFalse(ScanMode.text.footnote.localizedCaseInsensitiveContains("look up"),
                       "the live card offers no Look Up")
        // Shared with Android word for word.
        XCTAssertTrue(ScanMode.text.footnote.hasSuffix(" A single code is read straight away; with several, tap one."))
        XCTAssertEqual(ScanMode.codes.footnote, "Point at a barcode or QR to decode it.")
        XCTAssertEqual(ScanMode.bulk.footnote, "Keep scanning: every distinct code is collected and counted.")
    }

    // MARK: Save all, the CSV exports, Live Text copy and Explain Code

    /// A throwaway in-memory store on the app's own model (a second copy of
    /// the model would have two entities claim `ScanRecord`). The caller
    /// keeps the container alive while it uses the context.
    @MainActor
    private func inMemoryStore(readOnly: Bool = false) throws -> NSPersistentContainer {
        let model = PersistenceController.shared.container.managedObjectModel
        let container = NSPersistentContainer(name: "ScannerQuickEntryTests", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.isReadOnly = readOnly
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        return container
    }

    /// The records of an RFC 4180 file — the reading side of `HistoryCSV`,
    /// for round trips: CRLF ends a record only outside quotes, and "" inside
    /// them is one quote.
    private static func csvRecords(_ text: String) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false
        var scalars = Array(text.unicodeScalars)[...]
        while let scalar = scalars.popFirst() {
            if inQuotes {
                if scalar != "\"" {
                    field.append(scalar)
                } else if scalars.first == "\"" {
                    scalars.removeFirst()
                    field.append(scalar)
                } else {
                    inQuotes = false
                }
            } else if scalar == "\"" {
                inQuotes = true
            } else if scalar == "," {
                record.append(String(field))
                field = String.UnicodeScalarView()
            } else if scalar == "\r", scalars.first == "\n" {
                scalars.removeFirst()
                record.append(String(field))
                field = String.UnicodeScalarView()
                records.append(record)
                record = []
            } else {
                field.append(scalar)
            }
        }
        if !field.isEmpty || !record.isEmpty {
            record.append(String(field))
            records.append(record)
        }
        return records
    }

    @MainActor
    func testSaveAllWritesEachBulkEntryOnce() throws {
        let store = try inMemoryStore()
        let context = store.viewContext
        let session = BulkScanSession()
        XCTAssertFalse(session.hasUnsavedEntries, "an empty list has nothing to save")
        XCTAssertEqual(try session.saveUnsaved(into: context), 0)

        session.start()
        session.ingest(code("A"))
        session.ingest(code("B"))
        XCTAssertTrue(session.hasUnsavedEntries)
        XCTAssertEqual(try session.saveUnsaved(into: context), 2, "the sheet reports 2 saved to History")
        XCTAssertEqual(session.entries.map(\.isSaved), [true, true])
        XCTAssertFalse(session.hasUnsavedEntries, "Save all is disabled once every entry is saved")

        // More sightings, a pause and a second Save all write nothing.
        session.ingest(code("A"))
        session.stop()
        session.start()
        XCTAssertFalse(session.hasUnsavedEntries)
        XCTAssertEqual(try session.saveUnsaved(into: context), 0)

        // A new code turns Save all back on, and only that code is written.
        session.ingest(code("C"))
        XCTAssertEqual(session.unsavedEntries.map(\.value), ["C"])
        XCTAssertEqual(try session.saveUnsaved(into: context), 1)
        XCTAssertEqual(session.entries.map(\.sightings), [2, 1, 1], "saving leaves the list as it was")

        let request: NSFetchRequest<ScanRecord> = ScanRecord.fetchRequest()
        let saved = try context.fetch(request)
        XCTAssertEqual(saved.compactMap(\.value).sorted(), ["A", "B", "C"], "each code once")
        XCTAssertEqual(Set(saved.compactMap(\.notes)), ["Bulk capture"])
        XCTAssertEqual(Set(saved.compactMap(\.symbology)), ["QR"])
        XCTAssertEqual(Set(saved.compactMap(\.timestamp)), [Date(timeIntervalSince1970: 1_700_000_000)],
                       "a record is dated by the code's first sighting")

        // Clear starts a new capture: the same code is new again.
        session.reset()
        session.ingest(code("A"))
        XCTAssertEqual(session.unsavedEntries.map(\.value), ["A"])
    }

    @MainActor
    func testAFailedSaveAllLeavesNothingBehind() throws {
        let store = try inMemoryStore(readOnly: true)
        let context = store.viewContext
        let session = BulkScanSession()
        session.start()
        session.ingest(code("A"))
        XCTAssertThrowsError(try session.saveUnsaved(into: context))
        XCTAssertTrue(context.insertedObjects.isEmpty,
                      "no insert waits in the context for the next save of anything else")
        XCTAssertEqual(session.unsavedEntries.map(\.value), ["A"], "still unsaved, so a retry writes it")
    }

    @MainActor
    func testBulkCSVRevisionFollowsWhatTheCSVShows() throws {
        let store = try inMemoryStore()
        let session = BulkScanSession()
        session.start()
        var revision = session.csvRevision
        var csv = session.csvLines()
        func assertCSVChanged(_ why: String, line: UInt = #line) {
            XCTAssertNotEqual(session.csvRevision, revision, why, line: line)
            XCTAssertNotEqual(session.csvLines(), csv, why, line: line)
            revision = session.csvRevision
            csv = session.csvLines()
        }
        func assertCSVUnchanged(_ why: String, line: UInt = #line) {
            XCTAssertEqual(session.csvRevision, revision, why, line: line)
            XCTAssertEqual(session.csvLines(), csv, why, line: line)
        }

        session.ingest(code("A"))
        assertCSVChanged("a new code")
        session.ingest(code("A"))
        assertCSVChanged("another sighting: the count of entries is the same, the sightings column is not")
        session.ingest(code("B"))
        assertCSVChanged("a second code")
        try session.saveUnsaved(into: store.viewContext)
        assertCSVUnchanged("the CSV doesn't show what is saved, so an exported file stays good")
        session.stop()
        session.ingest(code("A"))
        assertCSVUnchanged("a paused capture changes nothing")
        session.start()
        session.remove(at: IndexSet(integer: 0))
        assertCSVChanged("a swipe-delete")
        session.remove(try XCTUnwrap(session.entries.first))
        assertCSVChanged("a removal by entry")
        session.ingest(code("C"))
        assertCSVChanged("a new code")
        session.reset()
        assertCSVChanged("Clear")
    }

    func testCSVFieldQuotesByScalarNotCharacter() {
        // "\r\n" is one Character, equal to neither "\r" nor "\n"; a comma or
        // a quote followed by a combining mark is one Character too.
        XCTAssertEqual(HistoryCSV.csvField("a\r\nb"), "\"a\r\nb\"")
        XCTAssertEqual(HistoryCSV.csvField("a,\u{301}b"), "\"a,\u{301}b\"")
        XCTAssertEqual(HistoryCSV.csvField("say \"\u{301}hi"), "\"say \"\"\u{301}hi\"")
        XCTAssertEqual(HistoryCSV.csvField("a\nb"), "\"a\nb\"")
        XCTAssertEqual(HistoryCSV.csvField("a\rb"), "\"a\rb\"")
        XCTAssertEqual(HistoryCSV.csvField("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(HistoryCSV.csvField("plain"), "plain")
        XCTAssertEqual(HistoryCSV.csvField(""), "")
    }

    @MainActor
    func testCSVNeutralisesFormulaCells() {
        // A leading = + - @ tab or CR gets an apostrophe, before quoting. The
        // Android port's `HistoryCsv` test runs the same inputs.
        XCTAssertEqual(HistoryCSV.csvField("=1+2"), "'=1+2")
        XCTAssertEqual(HistoryCSV.csvField("+15551234"), "'+15551234")
        XCTAssertEqual(HistoryCSV.csvField("-5"), "'-5")
        XCTAssertEqual(HistoryCSV.csvField("@SUM(A1:A2)"), "'@SUM(A1:A2)")
        XCTAssertEqual(HistoryCSV.csvField("\t=1+2"), "'\t=1+2")
        XCTAssertEqual(HistoryCSV.csvField("\r=1+2"), "\"'\r=1+2\"")
        XCTAssertEqual(HistoryCSV.csvField("=\u{301}1"), "'=\u{301}1", "a combining mark doesn't hide it")
        // OWASP's example, and a link a spreadsheet would make clickable.
        XCTAssertEqual(HistoryCSV.csvField("=1+2\";=1+2"), "\"'=1+2\"\";=1+2\"")
        XCTAssertEqual(HistoryCSV.csvField("=HYPERLINK(\"https://evil.example\",\"Open\")"),
                       "\"'=HYPERLINK(\"\"https://evil.example\"\",\"\"Open\"\")\"")
        // Only the first character counts, and only those six: a line feed
        // just forces quoting.
        XCTAssertEqual(HistoryCSV.csvField("a=b"), "a=b")
        XCTAssertEqual(HistoryCSV.csvField(" =1+2"), " =1+2")
        XCTAssertEqual(HistoryCSV.csvField("\n=1+2"), "\"\n=1+2\"")
        XCTAssertEqual(HistoryCSV.csvField("1-2"), "1-2")

        // The Bulk export goes through the same escape.
        let session = BulkScanSession()
        session.start()
        session.ingest(code("=cmd|' /C calc'!A0"))
        let lines = session.csvLines()
        XCTAssertEqual(lines.count, 2)
        guard let row = lines.dropFirst().first else { return }
        XCTAssertTrue(row.hasPrefix("'=cmd|' /C calc'!A0,QR,"), row)
        XCTAssertTrue(row.hasSuffix(",1,2023-11-14T22:13:20.000Z"), row)
    }

    @MainActor
    func testBulkCSVKeepsACRLFValueInOneRecord() throws {
        // Scan's own generator writes vCards with CRLF, as RFC 6350 does; EPC
        // payment codes may use CRLF too.
        let vCard = CodeComposer.vCard(fullName: "Ana", phone: "+15551234")
        XCTAssertTrue(vCard.contains("\r\n"))
        let epc = "BCD\r\n002\r\n1\r\nSCT\r\nBFSWDE33BER\r\nWikimedia Foerdergesellschaft\r\nDE33100205000001194700\r\nEUR123.45\r\n\r\n\r\nSpende"
        let session = BulkScanSession()
        session.start()
        session.ingest(code(vCard))
        session.ingest(code(epc))
        let lines = session.csvLines()
        XCTAssertEqual(lines.count, 3)
        guard lines.count == 3 else { return }
        XCTAssertTrue(lines[1].hasPrefix("\"BEGIN:VCARD\r\n"), lines[1])
        XCTAssertTrue(lines[1].hasSuffix("END:VCARD\",QR,Contact,1,2023-11-14T22:13:20.000Z"), lines[1])
        XCTAssertTrue(lines[2].hasPrefix("\"BCD\r\n002\r\n"), lines[2])

        // The shared file: one CRLF outside quotes per record, and the values
        // read back as scanned.
        let written = try String(contentsOf: try HistoryCSV.writeBulk(lines: lines), encoding: .utf8)
        let records = Self.csvRecords(written)
        XCTAssertEqual(records.count, session.count + 1, "the header and one record per entry")
        XCTAssertEqual(records.map(\.count), [5, 5, 5])
        XCTAssertEqual(records.dropFirst().map { $0[0] }, [vCard, epc])
    }

    @MainActor
    func testHistoryCSVQuotesCRLFAndNeutralisesFormulas() throws {
        let store = try inMemoryStore()
        let vCard = CodeComposer.vCard(fullName: "Ana", phone: "+15551234")
        let formula = "=HYPERLINK(\"https://evil.example\",\"Open\")"
        var rows: [ScanRecord] = []
        for (value, notes) in [(vCard, "Met at \"Expo\""), (formula, "@team")] {
            let record = ScanRecord(context: store.viewContext)
            record.id = UUID()
            record.value = value
            record.symbology = "QR"
            record.timestamp = Date(timeIntervalSince1970: 1_700_000_000)
            record.notes = notes
            rows.append(record)
        }
        let written = try String(contentsOf: try HistoryCSV.write(rows), encoding: .utf8)
        XCTAssertEqual(written,
                       "timestamp,symbology,value,notes,favourite\r\n"
                       + "2023-11-14T22:13:20.000Z,QR,\"\(vCard)\",\"Met at \"\"Expo\"\"\",0\r\n"
                       + "2023-11-14T22:13:20.000Z,QR,\"'=HYPERLINK(\"\"https://evil.example\"\",\"\"Open\"\")\",'@team,0\r\n")
        let records = Self.csvRecords(written)
        XCTAssertEqual(records.map(\.count), [5, 5, 5], "the header and one five-field record per row")
        guard records.count == 3, records.allSatisfy({ $0.count == 5 }) else { return }
        XCTAssertEqual(records[1][2], vCard)
        XCTAssertEqual(records[2][2], "'" + formula)
    }

    func testCameraPurposeStringCoversLiveText() throws {
        let purpose = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String)
        // The Android port's camera rationale says the same, word for word.
        XCTAssertEqual(purpose, "Scan uses the camera to read barcodes and QR codes and, in Live Text mode, printed text. Frames are processed on this device and are not saved.")
        XCTAssertTrue(purpose.contains("printed text"))
    }

    @MainActor
    func testFrozenFrameHintSaysLookUpAndTranslateAreAppleServices() {
        let hint = FrozenFrameTextView.selectionHint
        XCTAssertFalse(hint.localizedCaseInsensitiveContains("copy, look up or translate"),
                       "the menu's Look Up and Translate are not Scan's on-device features")
        XCTAssertTrue(hint.contains("Look Up and Translate in that menu are iOS services that may send the selection to Apple"))
        XCTAssertTrue(hint.contains("Scan's on-device Translate"), "and it points at the one that is")
    }

    /// Shortcuts runs Explain Code off the main thread, where a pool thread's
    /// stack is about 512 KB and a deeply nested credential once overran it.
    /// `perform()` parses on the main actor, so the same code is explained.
    func testExplainCodeIntentExplainsADeeplyNestedCredentialOffer() async throws {
        // The built-in explainer, so the answer doesn't depend on the model.
        let key = ScanSettingsKey.assistantEnabled
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(false, forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        let depth = 511
        let nested = String(repeating: "{\"\":", count: depth) + "1" + String(repeating: "}", count: depth)
        let intent = ExplainCodeIntent()
        intent.contents = "openid-credential-offer://?credential_offer=" + nested
        let result = try await intent.perform()
        let explanation = try XCTUnwrap(result.value)
        XCTAssertTrue(explanation.hasSuffix(AssistantExplanation.Source.builtIn.rawValue), explanation)
    }
}
