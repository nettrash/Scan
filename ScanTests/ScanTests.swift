//
//  ScanTests.swift
//  ScanTests
//
//  Created by nettrash on 16/09/2023.
//

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
        let raw = "M1NETTRASH/IVAN       EABC123 LHRJFKBA  0175020M013D0028 100"
        XCTAssertEqual(raw.count, 60, "Test fixture must be exactly 60 chars")
        let p = ScanPayloadParser.parse(raw)
        guard case .boardingPass(let bp) = p else {
            return XCTFail("Expected .boardingPass, got \(p)")
        }
        XCTAssertEqual(bp.formatCode, "M")
        XCTAssertEqual(bp.numberOfLegs, 1)
        XCTAssertEqual(bp.passengerName, "NETTRASH/IVAN")
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
        let raw = "X1NETTRASH/IVAN       EABC123 LHRJFKBA  0175020M013D0028 100"
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
}
