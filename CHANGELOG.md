# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

`CFBundleVersion` (build number) is set automatically at build time from
`git rev-list --count HEAD`, so a separate "build number" entry per release
is not required — it is whatever the commit count was when the build was cut.

## [Unreleased]

This is the work that will become **1.0.0** once tagged. Until then, every
commit on `main` produces a fresh dev build whose `CFBundleVersion` matches
the commit count.

### Added

#### App shell

- Replaced the default Xcode SwiftUI + Core Data template with a real
  three-tab app: **Scan**, **Generate**, **History**.
- App icon is a real, scannable QR code pointing to
  `https://nettrash.me`, framed by amber viewfinder corner brackets on a
  navy gradient. Verified pixel-accurate against the canonical encoding.
- Auto-incrementing build number via a `PBXShellScriptBuildPhase` that
  rewrites `CFBundleVersion` in the bundle (and dSYM) Info.plist using
  `git rev-list --count HEAD`. Skips silently with a warning if git isn't
  available.

#### Live camera scanner

- `ScannerScreen` + `CameraScannerView` (`UIViewControllerRepresentable`
  wrapping `AVCaptureSession` + `AVCaptureMetadataOutput`).
- Symbologies: QR, Aztec, PDF417, Data Matrix, EAN-8, EAN-13, UPC-E,
  Code 39 (and mod-43 checksum), Code 93, Code 128, ITF-14, Interleaved 2
  of 5, Codabar, GS1 DataBar variants where the device supports them.
- Camera-permission flow with descriptive failure messaging.
- Torch toggle.
- Accent-coloured viewfinder corner brackets (no decorative outline —
  scan area is implied by the brackets).
- Result-debouncing so repeated reads of the same code in quick
  succession don't spam the result sheet.

#### Image import (still scans)

- Import from **Photo Library** (`PhotosPicker`) and **Files**
  (`fileImporter`).
- `ImageDecoder` runs `VNDetectBarcodesRequest` on a background queue;
  surfaces decoded codes through the same result sheet as live scans.
- Vision-symbology mapping into the app's `Symbology` enum, including
  microQR / microPDF417 / GS1 DataBar variants.
- Decoding spinner; pauses the live session while reading.

#### Smart payload decomposition

`ScanPayload` is parsed from the decoded string and rendered as
labelled, copyable fields. Recognised:

- **URLs** (`http` / `https`)
- **Email** (`mailto:` with subject/body params)
- **Phone** (`tel:`)
- **SMS / SMSTO** (`sms:`, `smsto:NUMBER:BODY`)
- **Wi-Fi** (`WIFI:T:…;S:…;P:…;H:…;;`) with backslash-escape support
- **Geolocation** (`geo:lat,lon?q=…`)
- **vCard 3.0** and **MECARD** contacts
- **iCalendar VEVENT** with RFC-5545 line-folding, UTC / TZID / all-day
  date forms, escape-sequence unescaping, `mailto:` stripped from organizer
- **One-time-password URIs** (`otpauth://`)
- **EAN-8 / EAN-13 / UPC-E / ITF-14** product codes (driven by
  symbology, not text content)
- **Cryptocurrency** wallet URIs:
  - Bitcoin (BIP-21)
  - Ethereum (EIP-681 with `@chainId`)
  - Litecoin, Bitcoin Cash, Dogecoin, Monero, Cardano, Solana
  - Lightning (BOLT-11)
- **Bank payments**:
  - **EPC SEPA Payment QR** (GiroCode) — line-based, v001 / v002
  - **Swiss QR-bill (SPC)** — full address-block parsing (S / K),
    creditor + ultimate creditor + ultimate debtor, QRR / SCOR / NON
    reference types
  - **Czech SPD (Spayd)** — asterisk-delimited `SPD*1.0*ACC:…*AM:…*…*`;
    surfaces IBAN, amount + currency, recipient, message, due date,
    variable / constant / specific symbols (`X-VS` / `X-KS` / `X-SS`),
    with `+`-to-space decoding per SPD escaping rules
  - **Slovak Pay by Square** — recognised heuristically (header prefix
    plus all-base32hex check); decoding requires LZMA which iOS doesn't
    ship, so the result sheet labels the format and offers Copy / Share
    so the raw token can be passed to a banking app
  - **Russian unified payment** (`ST00012` / `ST00011`) — pipe-separated
    fields with friendly English labels for the well-known keys; `Sum`
    converted from kopecks to rubles
  - **EMVCo Merchant QR** — top-level TLV walker plus recursive drilling
    into Tag 62 (Additional Data: Bill number / Mobile number / Store
    label / Reference label / Customer label / Terminal label / Purpose
    of transaction) and Tags 02–51 (Merchant Account Information).
    Recognises 14 known scheme GUIDs and renames the parent row by
    scheme: **Pix**, **PayNow**, **NETS**, **PromptPay**, **CoDi**,
    **UPI**, **FPS** (Hong Kong), **DuitNow** (Malaysia), **QRIS**
    (Indonesia), **NAPAS** (Vietnam), and friends. Sub-fields render with
    a "↳" marker for individual tap-to-copy. 28-currency ISO 4217
    numeric→alpha mapping; static / dynamic initiation-method labels.
  - **Indian UPI** (`upi://pay`) — VPA, payee name, amount + currency
    (defaults INR), note, merchant code, transaction ID, and reference
    URL all surfaced as labelled fields
  - **Bezahlcode** (German legacy `bank://` / `bezahlcode://`) — full
    field mapping (beneficiary, IBAN, BIC, amount, currency, purpose,
    creditor / mandate IDs)
  - **Serbian NBS IPS QR** (Prenesi) — `K:value | …` format with
    PR / PT / PK kind labels, percent-decoded recipient names, validates
    required K / R / V fields
- **Mobile-payment apps** (regional URI schemes):
  - **Swish** (Sweden, `swish://payment?data=<base64-JSON>`) —
    base64-decoded JSON exposes payee, amount, message, currency
  - **Vipps** (Norway, `vipps://`) — phone number, amount, message,
    merchant ID, order text
  - **MobilePay** (Denmark / Finland, `mobilepay://`) — phone, amount,
    comment, locked-amount flag
  - **Bizum** (Spain, `bizum://`) — phone, amount, concept
  - **iDEAL** (Netherlands, `ideal://`) — IBAN, amount, beneficiary,
    description, reference
- **Receipts**:
  - **Russian FNS retail receipt** — Europe/Moscow timestamp parsed to a
    `Date`, sale / refund / expense / expense-refund classification
  - **Serbian SUF fiscal receipt** — recognised by `suf.purs.gov.rs`
    host (exact match or proper subdomain — lookalike domains rejected);
    "Verify Receipt" action opens the official PURS verification page

#### Smart actions per payload

- **URL** → Open in Safari.
- **Email / Phone / SMS** → Compose / Call / Send via the right system app.
- **Wi-Fi** → Show details, copy password, open Wi-Fi Settings.
- **Location** → Open in Maps.
- **Contact** → **Add to Contacts** via `CNContactViewController` with a
  `CNContactViewControllerDelegate` coordinator (Done / Cancel dismiss
  the sheet correctly).
- **Calendar** → **Add to Calendar** via `EKEventEditViewController`,
  using `requestWriteOnlyAccessToEvents` on iOS 17+ and `requestAccess(to:.event)`
  on iOS 16. Denial alert directs the user to Settings.
- **Crypto** → Open in Wallet (iOS picks an installed wallet via the URI
  scheme).
- **UPI** → Open in UPI app (handed off via `upi:` scheme so iOS picks
  an installed UPI app — PhonePe, GPay, Paytm, BHIM…).
- **Mobile-payment apps** (Swish / Vipps / MobilePay / Bizum / iDEAL) →
  Open in *<scheme>* via the registered URI scheme.
- **Product code** → Look up via web search.
- **Serbian SUF** → Verify Receipt (opens PURS site).
- All payloads → global Copy + Share buttons; per-field tap-to-copy on
  bank / receipt / crypto / Serbian / Czech / UPI / calendar payloads.

#### Generation

- New **Generate** tab in the TabView.
- Inputs: **Text**, **URL**, **Contact**, **Wi-Fi**.
- Symbologies: **QR** (correction level M), **Aztec**, **PDF417**, **Code 128**.
- Outputs: **Share** (system sheet), **Save to Photos** (uses
  `PHPhotoLibrary.requestAuthorization(for: .addOnly)` for least
  privilege), **Copy** (puts both image and encoded string on
  `UIPasteboard` via `setObjects`).
- Composers:
  - vCard 3.0 with CRLF line endings, `FN`/`N` split, and proper
    text-value escaping.
  - WIFI: payload with backslash-escaped special chars; password field
    omitted when "None" security is selected.
- Live preview that re-renders on every keystroke; integer-scaled
  rendering for crisp module edges; multi-line-content warning when
  Code 128 is paired with content that contains newlines.

#### History

- `ScanRecord` Core Data entity (id, value, symbology, timestamp,
  notes) replacing the template's stub `Item` entity.
- `NSPersistentCloudKitContainer` so saved scans sync across the user's
  iCloud devices.
- Searchable list with relative timestamps and a payload-kind SF Symbol
  per row.
- Empty state via a `ContentUnavailableView` (with an iOS 16 fallback).
- Per-record detail screen with editable notes, smart actions, share,
  delete.

#### Permissions / Info.plist

- `NSCameraUsageDescription` for the live scanner.
- `NSPhotoLibraryAddUsageDescription` for Save-to-Photos in the
  generator.
- `NSContactsUsageDescription` for Add-to-Contacts.
- `NSCalendarsUsageDescription` and `NSCalendarsWriteOnlyAccessUsageDescription`
  for Add-to-Calendar.
- All keys also mirrored as `INFOPLIST_KEY_*` build settings, since the
  project uses `GENERATE_INFOPLIST_FILE = YES`.

#### Tests

- `ScanTests` covers parser fidelity for every recognised format —
  URL, mailto, tel, smsto, geo, Wi-Fi (with escape sequences), vCard,
  MECARD, EAN-13, EPC, Russian ST00012, Russian FNS, EMVCo (top-level +
  the nested-template drill into a Pix merchant-account block),
  Bitcoin, Ethereum (with chain ID), Lightning, Swiss QR-bill, iCalendar
  (UTC and all-day), Serbian SUF, NBS IPS, UPI (and a UPI-without-payee
  rejection), Czech SPD with `+`-encoded message, Pay by Square
  recognition + lookalike rejection, Bezahlcode, Swish (with constructed
  base64-JSON fixture), and Vipps — plus round-trip tests for the
  vCard and Wi-Fi composers.

#### CI

- GitHub Actions workflow updated with `fetch-depth: 0` so the build-
  number script's `git rev-list --count` returns the real commit count.

### Changed

- `Scan.xcdatamodel` — `Item` → `ScanRecord`. Schema-incompatible: any
  existing simulator install must be deleted before re-running.
- The viewfinder reticle is corner-bracket-only now — the previous
  white rounded-square outline was removed in favour of a single,
  scanner-iconic look (matches the app icon).
- `.calendar` payload changed from `case calendar(String)` to
  `case calendar(CalendarPayload)` so the iCalendar fields are exposed
  to the UI directly.

### Removed

- The Xcode template's "Add Item" / `Item` flow.
- The decorative rounded-square outline on the scanner reticle.

### Notes

- The current marketing version is `1.0` (in `MARKETING_VERSION`); the
  first tagged release will be **`1.0.0`** and this section will be
  promoted accordingly. Until then, treat every build as a development
  build.
- Privacy posture: the app never reads the user's address book,
  calendar, or photo library. All privileged actions are mediated by a
  system-supplied edit-and-save UI; for Photos save the request is
  scoped to `addOnly`; for Calendar on iOS 17+ to write-only.

[Unreleased]: https://github.com/nettrash/Scan/compare/HEAD...main
