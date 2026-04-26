# Scan

![build](https://github.com/nettrash/Scan/actions/workflows/ios.yml/badge.svg)

An iOS app for reading and generating 1D and 2D barcodes. Built in SwiftUI on top of AVFoundation, Vision, and Core Image — no third-party dependencies. The point of the app is not just to *decode* a code, but to *understand* what's in it: scan a Wi-Fi QR and we'll show the SSID and offer to open Wi-Fi Settings; scan a SEPA invoice and we'll surface the IBAN, beneficiary, and amount as separate copyable rows; scan a Russian receipt and we'll show the fiscal markers; and so on.

## Features

### Scanning

- Live-camera scanning of every symbology AVFoundation supports natively: **QR**, **Aztec**, **PDF417**, **Data Matrix**, **EAN-8 / EAN-13**, **UPC-E**, **Code 39** (with mod-43 checksum), **Code 93**, **Code 128**, **ITF-14**, **Interleaved 2 of 5**, **Codabar**, and **GS1 DataBar**.
- Import an image from the **Photo Library** or **Files**; decoded with `VNDetectBarcodesRequest`, which adds a few formats Vision recognises (microQR, microPDF417) on top.
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
| Authentication | `otpauth://` |
| Retail | EAN-8 / EAN-13 / UPC-E / ITF-14 product codes |
| Cryptocurrency | Bitcoin (BIP-21), Ethereum (EIP-681 with chain ID), Litecoin, Bitcoin Cash, Dogecoin, Monero, Cardano, Solana, Lightning (BOLT-11) |
| Bank payments | EPC SEPA Payment QR / GiroCode (EU), Swiss QR-bill (SPC), Czech SPD (Spayd), Slovak Pay by Square (recognition only — decoding needs LZMA), Russian unified payment (ST00012 / ST00011), EMVCo Merchant QR with nested-template drilling for Pix, PayNow, PromptPay, CoDi, UPI-via-EMVCo, DuitNow, QRIS, FPS, NAPAS, NETS and friends, Indian UPI (`upi://pay`), Bezahlcode (German legacy `bank://` / `bezahlcode://`), Serbian NBS IPS QR (Prenesi — PR / PT / PK) |
| Mobile-payment apps | Swish (Sweden, base64-JSON-encoded `swish://`), Vipps (Norway), MobilePay (Denmark / Finland), Bizum (Spain), iDEAL (Netherlands) |
| Receipts | Russian FNS retail receipt, Serbian SUF fiscal receipt |

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
- **Russian FNS receipt** — Date in the user's timezone, amount, fiscal markers (FN / FD / FPD), receipt type (Sale / Refund / Expense / Expense refund).
- All payloads — Copy raw / Share via system share sheet.

### Generation

A dedicated **Generate** tab builds 1D / 2D codes from structured input via Core Image filters:

- **Inputs** — Text, URL, Contact (emits well-formed vCard 3.0), Wi-Fi (emits the standard `WIFI:` payload with proper escaping).
- **Symbologies** — QR, Aztec, PDF417, Code 128.
- **Outputs** — Share via system sheet, Save to Photos (with `NSPhotoLibraryAddUsageDescription`), Copy image *and* encoded string to the pasteboard.
- Live preview that re-renders on every keystroke; integer-scaled rendering for crisp module edges.

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
- **Devices**: iPhone and iPad (universal — `TARGETED_DEVICE_FAMILY = "1,2"`).

## Privacy

The app declares the following usage descriptions:

| Key | Used for |
| --- | --- |
| `NSCameraUsageDescription` | Live barcode scanning |
| `NSPhotoLibraryAddUsageDescription` | Saving generated codes to Photos |
| `NSContactsUsageDescription` | Add-to-Contacts UI when a vCard is scanned |
| `NSCalendarsUsageDescription` | Add-to-Calendar (iOS 16) |
| `NSCalendarsWriteOnlyAccessUsageDescription` | Add-to-Calendar (iOS 17+, write-only) |

The app never reads the user's address book, calendar, or photo library — every privileged action is mediated by a system-supplied edit-and-save UI.

## Building

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

Parser tests (`ScanTests/ScanTests.swift`) cover real-world payloads for every format the app claims to decompose — vCard, Wi-Fi, geo, mailto, sms, EPC, Russian unified payment + FNS, EMVCo, Bitcoin / Ethereum / Lightning, Swiss QR-bill, iCalendar (UTC and all-day), Serbian SUF / IPS, and round-trip checks for the composers. Run with ⌘U in Xcode or:

```sh
xcodebuild test -scheme Scan -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Project structure

```
Scan/
├─ ScanApp.swift                  app entry point
├─ ContentView.swift               TabView root (Scan / Generate / History)
├─ Persistence.swift               Core Data + CloudKit container
│
├─ ScannerScreen.swift             camera + photo / file import + result sheet
├─ CameraScannerView.swift         AVCaptureSession wrapper
├─ ImageDecoder.swift              VNDetectBarcodesRequest decoder
│
├─ GeneratorScreen.swift           text / URL / contact / wifi → code
├─ CodeGenerator.swift             Core Image filter wrappers
├─ CodeComposer.swift              vCard / Wi-Fi composers
│
├─ HistoryScreen.swift             searchable Core Data list
├─ ScanDetailView.swift            per-record detail + actions
├─ PayloadActionsView.swift        smart actions + LabelledFieldsList
│
├─ Symbology.swift                 AVFoundation + Vision symbology mapping
├─ ScanPayload.swift               payload enum + master parser
├─ BankPaymentPayloads.swift       EPC, Swiss, Russian, FNS, EMVCo (with nested drilling), Serbian
├─ RegionalPaymentPayloads.swift   UPI, Czech SPD, Pay by Square, Bezahlcode, Swish, Vipps, MobilePay, Bizum, iDEAL
├─ CryptoPayload.swift             BIP-21 / EIP-681 / BOLT-11 parser
├─ CalendarPayload.swift           RFC 5545 VEVENT parser
│
└─ Scan.xcdatamodeld               ScanRecord (id, value, symbology, timestamp, notes)
```

## Roadmap

Things that have been considered and could land if there's demand:

- Switch the live scanner to VisionKit's `DataScannerViewController` for built-in viewfinder UI, region-of-interest, and live highlight of recognised codes.
- Translation framework integration on iOS 18+ — "Translate" smart action for text / URL / contact payloads.
- Real decoding of Slovak Pay by Square payloads — would need an LZMA Swift package (e.g. `SWCompression`) since iOS doesn't ship LZMA natively. Today we recognise the format and let the user route the raw token to a banking app via Share / Copy.
- Localised field labels (currently English even for the Russian, Serbian, and Czech formats).
- Boarding-pass (BCBP), AAMVA driver's-licence, GS1 Application Identifier decoders.

## License

To be added — please drop a `LICENSE` file into the repo root.
