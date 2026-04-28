# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

`CFBundleVersion` (build number) is the value of `CURRENT_PROJECT_VERSION`
in the project file and is now auto-incremented by the app target's
build-phase script via `agvtool next-version -all`.

## [Unreleased]

_(nothing yet)_

## [1.1.0] — 2026-04-28

Public release on the App Store: <https://apps.apple.com/us/app/nettrash-scan/id6763932723>.

### App Store

- **Listed publicly.** Bundle ID `me.nettrash.Scan`, App Store ID `6763932723`. The README, the nettrash.me homepage, and the new App-Store tab on the personal site all link to the listing.
- **App Review Information note.** New `AppStoreReviewNotes.md` at the repo root holds the verbatim text we paste into App Store Connect's *App Review Information → Notes* field on every submission. Walks the reviewer through the testing flow (real device vs Simulator), suggested payload fixtures, what each `NSxxxUsageDescription` is for, and links to the privacy policy + source.
- **Privacy policy now hosted at** <https://nettrash.me/appstore/scan/privacy.html>. Same content as `PRIVACY.md`; the markdown stays canonical, the HTML mirror is generated and copied into `dist/` by Trunk on every nettrash.me deploy.

### Marketing version

- Bumped to **1.1** across all six `MARKETING_VERSION` build configurations (Debug + Release × app + tests + UI tests). `CURRENT_PROJECT_VERSION` continues to auto-increment via the `agvtool bump` scheme post-action.

### App icon refresh

- Yellow corner brackets removed; the QR motif is now scaled to ~70 % of the canvas (was ~40 %) on the same deep-blue radial gradient. The icon now reads as a *scanner* at a glance instead of getting lost in dock / Spotlight thumbnails. Generated via `outputs/make_ios_scan_icon.py` so future tweaks are reproducible.

### Generator-tab UX

- **Tap-outside-to-dismiss the keyboard.** Three layered ways to put the keyboard away: an interactive scroll-dismiss (drag down anywhere in the form, matches Mail / Notes), a `simultaneousGesture` tap-anywhere fallback that doesn't steal taps from the toggles / pickers / buttons, and a *Done* keyboard toolbar accessory that appears whenever a field is editing.

### New payload types — Pass 1 (lightweight recognitions)

- **Magnet URIs** (`magnet:?xt=urn:btih:…&dn=…&xl=…&tr=…`). Surface info-hash, display name, exact length, tracker list. "Open in torrent client" smart action.
- **Rich URLs** — recognises specific HTTP(S) URLs and offers the right smart action instead of a generic "Open in Safari":
  - WhatsApp click-to-chat (`wa.me/<phone>?text=…`, `api.whatsapp.com/send?phone=…`)
  - Telegram (`t.me/<target>`)
  - Apple Wallet `.pkpass`
  - App Store / Google Play store-listing URLs (extract App ID / package name)
  - YouTube watch / `youtu.be` short / Shorts URLs (extract video ID)
  - Spotify, Apple Music
- **Maps URLs (Google + Apple) re-classify to `.geo`** when coordinates can be pulled out, so the user gets the same "Open in Maps" smart action as a `geo:` payload.
- **vCard 4.0** transparently supported — the existing parser doesn't gate on `VERSION:`, both 3.0 and 4.0 line shapes go through the same handler.
- **More crypto chains.** `Crypto.Chain` gained XRP / Ripple, Stellar, Cosmos, LNURL, Lightning Address. Schemes recognised: `xrp://`, `xrpl://`, `ripple://`, `stellar:`, `web+stellar:`, `cosmos:`.
- **Bare crypto address detection.** Strings without a scheme but matching well-known address formats are now classified as `.crypto`: legacy + bech32 Bitcoin, Ethereum `0x…`, XRP `r…`, Stellar `G…`, Cosmos `cosmos1…`, bare bolt11 invoices (`lnbc…` / `lntb…`), LNURL bech32 (`LNURL1…`).

### New payload types — Pass 2 (full spec-driven parsers)

- **GS1 Application Identifier.** Three forms supported: parens (`(01)09506000134352(17)201225(10)ABC123`), GS1 Digital Link (`https://example.com/01/<gtin>/10/<batch>?…`), and FNC1-separated (the GS character `0x1D` between elements). Registry of ~40 common AIs with friendly names + length info; date AIs (11 / 12 / 13 / 15 / 16 / 17) render as `YYYY-MM-DD`. Smart action: GTIN web lookup.
- **IATA Bar Coded Boarding Pass (RP 1740c, version M).** Surfaces format code, leg count, passenger name, e-ticket flag, plus the 60-char mandatory leg's PNR / from / to / carrier / flight number / Julian date / cabin / seat / sequence / status. Multi-leg conditional sections vary too much across carriers to parse reliably without per-airline rules; the leg count is reported so the user knows there's more.
- **AAMVA driver's licence (PDF417).** US / Canada DLs. Header parsing extracts the 6-digit IIN; the registry maps ~50 IINs to friendly jurisdiction names (every US state + DC, every Canadian province). Element-ID walker pulls `DCS` / `DAC` / `DAD` (names), `DAQ` (licence number), `DBA` / `DBB` / `DBD` (expiry / DOB / issued — auto-detects MM/DD/YYYY vs YYYY/MM/DD), `DBC` (sex), `DAG` / `DAI` / `DAJ` / `DAK` (address). Element extractor only accepts triplets that follow a record terminator, so letter-triples inside other values don't false-match.

### Tests

- 38 new tests across the parser suite, taking the count from 38 → 90.
  - Pass 1: 20 tests — magnet, rich URLs, Maps→Geo re-classification, new chains, bare addresses, vCard 4.0.
  - Pass 2: 7 tests — GS1 (parens / Digital Link / FNC1), BCBP (positive + reject), AAMVA (positive + reject).
  - Fixed `testParsesSwissQRBill` — fixture was off by one blank line in the unused-ultimate-creditor block, which had been silently failing because of the next item.
- **Bug-fix: `testParsesICalendarAllDayEvent` was outside the `ScanTests` class.** A stray `}` ended the class one line too early, leaving the function as a free top-level function that XCTest never discovered and never ran. Restored to its proper place. As a result the existing all-day VEVENT test now actually executes.

## [1.0.0] — 2026-04-26

First public release. The notes below cover the development work that became 1.0.0.

### Added

#### App shell

- Replaced the default Xcode SwiftUI + Core Data template with a real
  three-tab app: **Scan**, **Generate**, **History**.
- App icon is a real, scannable QR code pointing to
  `https://nettrash.me`, framed by amber viewfinder corner brackets on a
  navy gradient. Verified pixel-accurate against the canonical encoding.
- Build number (`CFBundleVersion`) auto-increments via a **scheme
  post-action** on the `Scan` shared scheme that runs
  `cd "${PROJECT_DIR}" ; agvtool bump` after every successful build.
  `agvtool bump` (alias for `next-version -all`) rewrites
  `CURRENT_PROJECT_VERSION` in `project.pbxproj` directly — no
  build-phase script and so no User Script Sandbox to fight.
  Same mechanism the sibling `Geo` app uses; ported wholesale.

  Earlier iterations tried two other approaches that didn't survive
  contact with reality: a `PBXShellScriptBuildPhase` deriving the
  build number from `git rev-list --count HEAD` (Xcode 14+'s default
  `ENABLE_USER_SCRIPT_SANDBOXING = YES` blocks the script from
  reading `.git/`, so it printed "Could not determine git commit
  count" and left the version unchanged); and pure manual bumping
  via *Editor → Increase Build Number* (worked but easy to forget).
  The post-action approach is sandbox-friendly and runs automatically.

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

- GitHub Actions workflow uses the default shallow checkout — no longer
  needs `fetch-depth: 0` since the build-phase git script is gone.
- Pinned the runner to `macos-26` so we get Xcode 26 and the iOS 26 SDK
  (the app target's deployment target requires both). `macos-latest`
  still aliases to macos-15 / Xcode 16 at the time of writing.
- Added `LD_RUNPATH_SEARCH_PATHS` to all four test-target configurations
  (`ScanTests` + `ScanUITests` Debug + Release). The original Xcode 14
  template left this off the test targets; Xcode 26's explicit Swift
  module-build pipeline trips over it and fails the
  `SwiftExplicitDependencyGeneratePcm` step for the XCTest /
  XCUIAutomation precompiled modules.
- Switched CI from the split `build-for-testing` / `test-without-building`
  pair to a single combined `xcodebuild test` call. Xcode 26 has a known
  issue where the split form interacts badly with explicit module
  precompilation; the combined form is what Xcode itself runs when
  you press ⌘U and is the supported path.
- CI now writes `build/TestResults.xcresult` and uploads it as an
  artifact on failure, so the next time CI breaks the diagnostic data
  is one click away in the GitHub Actions run summary.
- Replaced the brittle "find any project / find any scheme" path
  detection with explicit `-project Scan.xcodeproj -scheme Scan`. The
  workflow now also resolves whatever iPhone iOS-runtime simulator the
  runner ships with for the day, instead of relying on a hardcoded
  device name.
- Workflow now runs the test suite (`build-for-testing` →
  `test-without-building`), not just `build`. Bumped
  `actions/checkout@v3` → `@v4` since v3 is deprecated.
- Committed a shared scheme at
  `Scan.xcodeproj/xcshareddata/xcschemes/Scan.xcscheme` so xcodebuild
  doesn't have to autocreate one on each fresh checkout. ScanUITests
  is included in the scheme but `skipped="YES"` by default — it's the
  template's launch-only smoke test and adds little value while costing
  CI time.

### Changed

- Restored automatic build-number incrementing for the app target using a
  `PBXShellScriptBuildPhase` that runs `agvtool next-version -all` during
  build/install actions (previews are skipped). This keeps the flow automatic
  without relying on `.git` commit counting.
- **Deployment target raised to iOS 26.0** uniformly across the
  project root, the `Scan` app target, and the `ScanTests` /
  `ScanUITests` targets — all four `IPHONEOS_DEPLOYMENT_TARGET`
  configurations now read `26.0`. Lets the app use AVFoundation's
  `videoRotationAngle` API directly,
  `UIWindowScene.effectiveGeometry.interfaceOrientation`,
  `requestWriteOnlyAccessToEvents` without an iOS 16 fallback,
  `ContentUnavailableView` and the modern two-arg
  `onChange(of:_:)` natively, and picks up Liquid Glass automatically
  on the standard SwiftUI containers. As a side-effect, all of the
  iOS 16 / 17 / 25 deprecation warnings the build was carrying are
  gone, and the `obsoleted:`-annotated legacy fallback helpers were
  deleted. Bumping the test targets *together with* the app target
  was necessary because `@testable import Scan` pulls the whole iOS
  26-built module into the test bundle — leaving the test target at
  iOS 16.4 caused `SwiftDriver ScanTests` to fail at link time on CI.
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
- All iOS 16 / 17 / 25 fallback paths in `CameraScannerView`,
  `PayloadActionsView`, and `HistoryScreen` that the deployment-target
  bump made obsolete: the legacy `applyLegacyVideoOrientation` and
  `legacySceneInterfaceOrientation` helpers, the iOS 16
  `requestAccess(to:.event)` branch in `requestCalendarAccess`, the
  iOS 16 manual `VStack` fallback inside `ContentUnavailableViewCompat`,
  and the `if #available(iOS 17.0, *)` branch inside `onValueChange`.
  All call sites still work — the wrappers stayed in place for
  readability but now just delegate to the native iOS 17+ APIs.

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
