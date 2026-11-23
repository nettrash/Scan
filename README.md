# Scan

[![build](https://github.com/nettrash/Scan/actions/workflows/ios.yml/badge.svg)](https://github.com/nettrash/Scan/actions/workflows/ios.yml)
[![App Store](https://img.shields.io/badge/App_Store-Download-0D96F6?logo=apple&logoColor=white)](https://apps.apple.com/us/app/nettrash-scan/id6763932723)

An iOS app for reading and generating 1D and 2D barcodes. Built in SwiftUI on top of AVFoundation, Vision, and Core Image — no third-party dependencies. The point of the app is not just to *decode* a code, but to *understand* what's in it: scan a Wi-Fi QR and we'll show the SSID and offer to open Wi-Fi Settings; scan a SEPA invoice and we'll surface the IBAN, beneficiary, and amount as separate copyable rows; scan a fiscal receipt and we'll show the fiscal markers; and so on.

📱 **Available on the App Store:** <https://apps.apple.com/us/app/nettrash-scan/id6763932723> — bundle ID `me.nettrash.Scan`, App Store ID `6763932723`. Use that link to install on a real iPhone or iPad. Source-built copies via Xcode are still recommended for testing local changes.

## Features

### Scanning

- Three scanner modes, remembered between launches:
  - **Codes** — live-camera scanning of every symbology AVFoundation supports natively: **QR**, **Aztec**, **PDF417**, **Data Matrix**, **EAN-8 / EAN-13**, **UPC-E**, **Code 39** (with mod-43 checksum), **Code 93**, **Code 128**, **ITF-14**, **Interleaved 2 of 5**, **Codabar**, and **GS1 DataBar**.
  - **Live Text** — VisionKit's `DataScannerViewController` reads text and codes together: tap a highlighted block for a card with Copy, Share and on-device Translate, or freeze the frame ("Select words in this frame") for word-by-word selection with the system menu via `ImageAnalysisInteraction` — that menu's Look Up and Translate are iOS services that may use Apple's servers. A single code in view opens once per stay in the frame; with several, tap one. iPhone and iPad with a supported camera only — hidden on Mac, Vision Pro and the Simulator, and falls back to Codes when the camera is unavailable.
  - **Bulk** — keeps scanning instead of stopping at the first hit, deduplicating by value and counting sightings (up to 500 codes, in memory only). The list survives mode and tab switches until Clear; "Save all to History" writes only codes not saved yet; "Export CSV" shares `value,symbology,kind,sightings,first_seen`. Built for a pallet of parcels.
- Import an image from the **Photo Library** or **Files**; decoded with `VNDetectBarcodesRequest`, which adds a few formats Vision recognises (microQR, microPDF417) on top.
- **NFC** (iPhone) — "Read an NFC tag" reads a tag's first readable record (text, URI, Smart Poster, Wi-Fi configuration, vCard) into the normal result sheet. Sessions start only from that button; there is no background reading.
- Torch toggle, accent-coloured viewfinder corner brackets, debounced result presentation.

### Smart payload decomposition

The decoded string is parsed and rendered as structured fields with per-row tap-to-copy. Recognised formats:

| Domain | Formats |
| --- | --- |
| Web / messaging | URL, `mailto:`, `tel:`, `sms:` / `smsto:` |
| Connectivity | `WIFI:` (SSID + password + security) |
| Geolocation | `geo:` |
| Identity | vCard (3.0), MECARD |
| Calendar | iCalendar VEVENT (line-folded, UTC / TZID / all-day dates) |
| Authentication | `otpauth://`, FIDO cross-device passkey QR (`FIDO:/`, CTAP 2.2 hybrid transport) |
| Retail | EAN-8 / EAN-13 / UPC-E / ITF-14 product codes |
| Cryptocurrency | Bitcoin (BIP-21), Ethereum (EIP-681 with chain ID), Litecoin, Bitcoin Cash, Dogecoin, Monero, Cardano, Solana, Lightning (BOLT-11) |
| Bank payments | EPC SEPA Payment QR / GiroCode (EU), Swiss QR-bill (SPC), Czech SPD (Spayd), Slovak Pay by Square (recognition only — decoding needs LZMA), EMVCo Merchant QR with nested-template drilling for Pix, PayNow, PromptPay, CoDi, UPI-via-EMVCo, DuitNow, QRIS, FPS, NAPAS, NETS and friends, Indian UPI (`upi://pay`), Bezahlcode (German legacy `bank://` / `bezahlcode://`), Serbian NBS IPS QR (Prenesi — PR / PT / PK) |
| Mobile-payment apps | Swish (Sweden, base64-JSON-encoded `swish://`), Vipps (Norway), MobilePay (Denmark / Finland), Bizum (Spain), iDEAL (Netherlands) |
| Receipts | Serbian SUF fiscal receipt |
| Digital identity | ISO/IEC 18013-5 `mdoc:` device-engagement QR (mDL, EU PID and other mdocs) and the second-edition reader QR, ISO/IEC 18013-7 `mdoc://` — connection details only; OpenID4VP 1.0 / HAIP presentation requests (`openid4vp://`, `eudi-openid4vp://`, `mdoc-openid4vp://`, `haip-vp://`, …) incl. DCQL; OpenID4VCI 1.0 credential offers; SD-JWT verifiable credentials and presentations. Decode only — no hand-off, no `request_uri` fetch, no signature verification |
| Documents | EN 16931 e-invoice summary in UN/CEFACT CII syntax (ZUGFeRD / Factur-X / XRechnung CII) — raw XML or base64 carrier |
| Product data | GS1 Application Identifiers (parens, FNC1 and Digital Link forms), incl. **Digital Product Passports** — a Digital Link with a `dpp` path segment or query key: product, batch, serial, dates, countries of origin / processing (AIs 422–426), resolver host (shown, never contacted) and every other element |

### Smart actions

Per payload type:

- **URL** — Open in Safari.
- **Email / Phone / SMS** — Compose / Call / Send via the right system app.
- **Wi-Fi** — Show network details, copy password, open Wi-Fi Settings.
- **Location** — Open in Maps.
- **Contact** — Add to Contacts via `CNContactViewController` (delegate-driven save / cancel).
- **Calendar** — Add to Calendar via `EKEventEditViewController` with iOS 17+ write-only access (full-access fallback on iOS 16).
- **Crypto** — Open in Wallet (iOS picks an installed wallet via the URI scheme).
- **Bank payments** — Per-field copy (IBAN, amount, recipient, reference, INN, KPP, KBK, OKTMO, Czech variable / constant / specific symbols, …). Currency mapped via ISO 4217 numeric → alpha for EMVCo. Nested EMVCo templates render with a "↳" marker so individual sub-fields (Pix key, PayNow merchant ID, PromptPay phone, etc.) are individually copyable.
- **UPI** — Open in UPI app (iOS picks an installed UPI app — PhonePe, GPay, Paytm, BHIM…).
- **Mobile-payment apps** — Open in *<scheme>* via the registered URI scheme.
- **Serbian SUF receipt** — Open the official PURS verification page.
- **Passkey (`FIDO:/`)** — decodes the hybrid-transport blob (purpose, generated time, tunnel-server count) with a phishing caution. Informational only: the QR secret is never shown, and only the system camera can complete the sign-in.
- **All payloads — QR safety check.** Before any action is offered, the code is assessed on the device: punycode and mixed-alphabet hosts, brand look-alikes (homoglyphs such as `paypaI.com`, a brand pasted in front of someone else's domain), `user@host` and backslash address-bar tricks, raw and numeric IP hosts, odd ports, open redirects, URL shorteners, plain HTTP, abuse-heavy TLDs, oversized or encoded links, bait wording, dangerous schemes, exposed secrets (private / WIF keys, BIP-39 seed phrases), 2FA enrolment codes, open Wi-Fi, payment codes with no payee or a preset amount, static posters, and more than one code in the frame. Findings are graded note / caution / danger and each one explains itself. An ordinary link — internationalised domains included — produces no findings at all, which is what keeps the badge meaningful. A `danger` code's Open button becomes "Copy link" until "I understand — open anyway". No reputation service is ever contacted.
- **All payloads — "What is this code?"** On-device explanation via Apple FoundationModels (`SystemLanguageModel`, never Private Cloud Compute) where Apple Intelligence is available, and from a deterministic rule engine everywhere else. Credentials are redacted before a payload reaches the model, a model answer is length-capped with a 10-second deadline, and the cautions shown are always the rule engine's. The assistant and the safety check are on by default and can be switched off in Settings → Insights, which also reports which engine the current device uses.
- **Text / URL / e-mail — Translate** via Apple's `Translation` framework into Settings → Insights → "Translate to" (default: the first preferred language the device can translate into, else English). Missing language packs are downloaded by iOS after its own consent sheet; the text is never uploaded. Not on Vision Pro.
- All payloads — Copy raw / Share via system share sheet.

### Generation

A dedicated **Generate** tab builds 1D / 2D codes from structured input via Core Image filters:

- **Inputs** — Text, URL, Contact (emits well-formed vCard 3.0), Wi-Fi (emits the standard `WIFI:` payload with proper escaping).
- **Symbologies** — QR, Aztec, PDF417, Code 128.
- **Outputs** — Share via system sheet, Save to Photos (with `NSPhotoLibraryAddUsageDescription`), Copy image *and* encoded string to the pasteboard.
- Live preview that re-renders on every keystroke; integer-scaled rendering for crisp module edges.
- **Styling** — module shapes (Square, Rounded, Dots, Leaves, Bars), eye shapes (Square, Rounded, Circle, Ring), solid or two-colour gradient ink, a logo, and presets (Classic, Soft, Dots, Nature, Ink, Sunset). Core Image's 1-module border is trimmed and a 4-module quiet zone drawn, the finder eyes keep their 1:1:3:1:1 profile, shapes and logos raise error correction to High, a logo clears a whole-module square sized so the code still decodes, and there are warnings for low contrast and for dense codes that cameras struggle with. The preview renders off the main thread. SVG / PDF / PNG all honour the style; an unstyled code is byte-for-byte unchanged.
- **Write to NFC** (iPhone) — web, phone, e-mail, SMS and map links as URI records, WPA/WPA2/open Wi-Fi as a Wi-Fi configuration record, contacts as vCards, anything else as text, after a writable/capacity check.
- **Describe the code** — a sentence ("Wi-Fi for network BlueHouse, password hunter2") fills the form in, on-device: Apple Intelligence first where available (a value is kept only if it appears verbatim in the sentence), then the rule engine.

### Shortcuts and Siri

App Intents with an `AppShortcutsProvider` (no setup needed): **Start Scanning** (Codes / Live Text / Bulk — reveals the camera, closing whatever covers it), **Explain Code**, **Generate Code** (QR, Aztec, PDF417, Code 128 → image) and **Copy Recent Scan** (requires the device to be unlocked). Siri never reads a scanned code's contents aloud for Copy Recent Scan or Generate Code. App Intents metadata is exported for the app target (`LM_SKIP_METADATA_EXTRACTION = NO`; the project-level `YES` keeps the share extension and tests warning-free).

### History

- Saved scans persist to **Core Data + CloudKit** (`NSPersistentCloudKitContainer`) and sync across the user's devices.
- Searchable list with relative timestamps and a payload-kind icon.
- Per-record detail screen with editable notes, smart actions, and delete.

### App icon

The icon is a real, scannable QR code that decodes to `https://nettrash.me`, framed by amber viewfinder corner brackets on a navy gradient. Not decorative — every module matches the canonical encoding, so pointing the app's own scanner at the icon actually works.

### Build numbering

`CFBundleVersion` comes from `CURRENT_PROJECT_VERSION` in the project file, and the `Scan` shared scheme has a **post-build action** that runs `agvtool bump` after every successful build:

```
cd "${PROJECT_DIR}" ; agvtool bump
```

`agvtool bump` (alias for `next-version -all`) rewrites `CURRENT_PROJECT_VERSION` directly in `project.pbxproj` thanks to the `VERSIONING_SYSTEM = "apple-generic"` build setting. Because it's a scheme post-action — not a build-phase script — it runs *outside* the User Script Sandbox, so Xcode's default `ENABLE_USER_SCRIPT_SANDBOXING = YES` doesn't block it. Same mechanism the sibling Geo app uses, ported here.

## Requirements

- **Deployment target**: iOS 26.0+ uniformly across the project root, the app target, and both test targets. (Bumping the test targets in step with the app target matters: `@testable import Scan` brings the iOS-26-built module into the test bundle, so a lower test deployment fails to link.)
- **Xcode**: 26+ (uses the iOS 26 SDK and the Liquid Glass design system).
- **Devices**: iPhone and iPad (universal — `TARGETED_DEVICE_FAMILY = "1,2"`), Mac (Catalyst) and Vision Pro (Designed for iPad). Feature availability: iPhone — everything; iPad — everything except NFC; Mac — no Live Text, no NFC; Vision Pro — no live camera (image / PDF import only), no Live Text, NFC or Translate.

## Privacy

The app declares the following usage descriptions:

| Key | Used for |
| --- | --- |
| `NSCameraUsageDescription` | Live barcode scanning and Live Text (frames processed on the device, never saved) |
| `NFCReaderUsageDescription` | Reading and writing NFC tags, only after you tap Read / Write (iPhone; NFC Tag Reading capability, entitlement `TAG`) |
| `NSPhotoLibraryAddUsageDescription` | Saving generated codes to Photos |
| `NSContactsUsageDescription` | Add-to-Contacts UI when a vCard is scanned |
| `NSCalendarsUsageDescription` | Add-to-Calendar (iOS 16) |
| `NSCalendarsWriteOnlyAccessUsageDescription` | Add-to-Calendar (iOS 17+, write-only) |

The app never reads the user's address book, calendar, or photo library — every privileged action is mediated by a system-supplied edit-and-save UI.

The app ships a `PrivacyInfo.xcprivacy` (no tracking, no collected data; UserDefaults with reason `CA92.1`). Explanations, the safety check, Live Text recognition and translation run on the device; the only new downloads are iOS-managed translation language packs, which the system asks about first. Mac Catalyst signs with `Scan-macCatalyst.entitlements` — the iOS entitlements minus NFC.

## Installing

If you just want to use the app, install it from the App Store — it's free, ad-free, and tracker-free:

> **App Store:** <https://apps.apple.com/us/app/nettrash-scan/id6763932723>

The store listing is the right answer for end users, and is also the binary under "App Review Information" notes during App Store Connect submissions. Bundle ID `me.nettrash.Scan`, App Store ID `6763932723`.

## Building

To build from source (recommended for testing local changes):

```sh
git clone https://github.com/nettrash/Scan.git
cd Scan
open Scan.xcodeproj
```

CI runs on the `macos-26` GitHub-hosted runner (Xcode 26 / iOS 26 SDK — required by the deployment target) via the workflow at `.github/workflows/ios.yml`. The workflow resolves whatever iPhone simulator the runner happens to ship with for the day, then runs `build-for-testing` followed by `test-without-building`. Equivalent locally:

```sh
xcodebuild test \
  -scheme Scan \
  -project Scan.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  CODE_SIGNING_ALLOWED=NO
```

## Testing

Parser tests (`ScanTests/ScanTests.swift`) cover real-world payloads for every format the app claims to decompose — vCard, Wi-Fi, geo, mailto, sms, EPC, EMVCo, Bitcoin / Ethereum / Lightning, Swiss QR-bill, iCalendar (UTC and all-day), Serbian SUF / IPS, and round-trip checks for the composers. Run with ⌘U in Xcode or:

```sh
xcodebuild test -scheme Scan -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Project structure

```
Scan/
├─ ScanApp.swift                  app entry point
├─ ContentView.swift               TabView root (Scan / Generate / History / Settings)
├─ Persistence.swift               Core Data + CloudKit container
│
├─ ScannerScreen.swift             camera + photo / file import + result sheet + mode picker
├─ CameraScannerView.swift         AVCaptureSession wrapper (Codes / Bulk)
├─ VisionTextScanner.swift         VisionKit DataScanner wrapper (Live Text)
├─ ScanMode.swift                  scan modes + BulkScanSession dedupe accumulator
├─ ImageDecoder.swift              VNDetectBarcodesRequest decoder
├─ NFCTagWriter.swift              CoreNFC read / write
│
├─ GeneratorScreen.swift           text / URL / contact / wifi → code
├─ CodeGenerator.swift             Core Image filter wrappers
├─ CodeComposer.swift              vCard / Wi-Fi composers
├─ QRStyle.swift                   module / eye shapes, gradients, presets
│
├─ QrRisk.swift                    anti-quishing assessment
├─ QrRiskView.swift                risk banner UI
├─ Assistant.swift                 on-device explanation session
├─ HeuristicExplainer.swift        deterministic explainer + compose fallback
├─ SecretRedaction.swift           credential blanking before the model sees a payload
├─ TranslationKit.swift            on-device translation
├─ ScanIntents.swift               App Intents + AppShortcutsProvider
│
├─ HistoryScreen.swift             searchable Core Data list
├─ ScanDetailView.swift            per-record detail + actions
├─ PayloadActionsView.swift        smart actions + LabelledFieldsList
│
├─ Symbology.swift                 AVFoundation + Vision symbology mapping
├─ ScanPayload.swift               payload enum + master parser
├─ BankPaymentPayloads.swift       EPC, Swiss, EMVCo (with nested drilling), Serbian
├─ RegionalPaymentPayloads.swift   UPI, Czech SPD, Pay by Square, Bezahlcode, Swish, Vipps, MobilePay, Bizum, iDEAL
├─ CryptoPayload.swift             BIP-21 / EIP-681 / BOLT-11 parser
├─ CalendarPayload.swift           RFC 5545 VEVENT parser
├─ CBORReader.swift                shared CBOR decoder (passkey + mdoc), 64-level cap
├─ IdentityPayload.swift           ISO 18013-5/-7 mdoc engagement QR + PayloadCodec
├─ VerifiableCredentialPayload.swift  OpenID4VP / OpenID4VCI / HAIP / SD-JWT VC
├─ InvoicePayload.swift            EN 16931 CII (ZUGFeRD / Factur-X / XRechnung) summary
├─ DigitalProductPassport.swift    GS1 Digital Link product passport + ISO 3166 table
│
└─ Scan.xcdatamodeld               ScanRecord (id, value, symbology, timestamp, notes)
```

## Roadmap

Things that have been considered and could land if there's demand:

- Real decoding of Slovak Pay by Square payloads — would need an LZMA Swift package (e.g. `SWCompression`) since iOS doesn't ship LZMA natively. Today we recognise the format and let the user route the raw token to a banking app via Share / Copy.
- Localised field labels (currently English even for the Serbian and Czech formats).
- Signature verification for SD-JWT / mdoc credentials — deliberately not done: we decode to inform, and verifying would imply we vouched for the document.

## License

To be added — please drop a `LICENSE` file into the repo root.
