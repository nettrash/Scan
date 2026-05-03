# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

`CFBundleVersion` (build number) is the value of `CURRENT_PROJECT_VERSION`
in the project file and is now auto-incremented by the app target's
build-phase script via `agvtool next-version -all`.

## [Unreleased]

_(nothing yet)_

## [1.8] — 2026-05-02

Mac Catalyst + visionOS targets.

### Mac Catalyst

The `Scan` target's build settings gained `SUPPORTS_MACCATALYST = YES` and `MACOSX_DEPLOYMENT_TARGET = 14.0` (Sonoma) across both the project-level and per-target configurations — Debug + Release for the `Scan` app, the `ScanShareExtension` app-extension, and both test targets. `DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER = NO` keeps the Mac build under the same `me.nettrash.Scan` bundle ID so the iCloud container, App Store listing, and Universal Link's `apple-app-site-association` `appIDs` entry all carry over without a second App ID.

The Catalyst destination needs no platform-specific Swift shims:
- `UIApplication.shared.open(_:)` works as-is for the `mailto:` / `tel:` / `geo:` / `wallet:` smart actions; macOS 14 routes them to the system handler.
- `UIPinchGestureRecognizer` on the camera preview works against trackpad pinch and Magic-Mouse gestures.
- `windowScene` lookups in the Share Extension and Universal Link arrival path resolve to the host `UIWindowScene` Catalyst synthesises for the Mac window.
- `AVCaptureDevice.default(for: .video)` returns the Mac's built-in camera or any connected Continuity Camera; if the device is unsuitable (no camera at all, or permission denied) the existing failure-banner UX takes over.

`Scan.entitlements` gained five App Sandbox entitlements that Mac Catalyst requires for the corresponding capabilities — `com.apple.security.app-sandbox`, `com.apple.security.device.camera`, `com.apple.security.network.client`, `com.apple.security.files.user-selected.read-only`, and `com.apple.security.personal-information.photos-library`. iOS ignores the `com.apple.security.*` namespace at runtime, so a single shared entitlements file covers both destinations. Without `device.camera` in particular, `AVCaptureDevice.default(for: .video)` returns nil on Catalyst even when `NSCameraUsageDescription` is set — the iOS-only entitlement is invisible to the macOS sandbox.

`updatePreviewOrientation()` in `CameraScannerView` early-returns with `videoRotationAngle = 0` when `Platform.isMacCatalyst` is true. Catalyst windows always report `effectiveGeometry.interfaceOrientation = .portrait` regardless of the actual window shape, so the iPhone-style portrait→90° rotation map would tilt the Mac preview by 90°. Forcing 0° lets the webcam's native landscape frame pass through, and `videoGravity = .resizeAspectFill` aspect-fills it into whatever shape the user has resized the window to.

### Designed-for-iPad-on-Mac destination — opted out

`SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO` is set on every build configuration that has `SUPPORTS_MACCATALYST = YES`. The default for iOS 14+ SDKs is `YES`, which auto-enrolls every iPad app in the "iPad apps on Apple Silicon Mac" availability bucket. Two reasons for opting out: (1) the runtime layers its own opaque orientation transform on top of any `AVCaptureConnection.videoRotationAngle` we set, so the camera preview can't be reliably uprighted from inside the iOS app — empirically every value on the 90°-step grid produced a different wrong-orientation result; and (2) the Mac App Store auto-prefers Catalyst over Designed-for-iPad-on-Mac when both are present in the same submission, so end users were never going to see the iPad-on-Mac build anyway. Removing the destination gets rid of a broken-in-development build path without affecting anything users would have actually run.

### visionOS (Designed for iPad) — library + image import

`SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = YES` enables the Vision Pro destination. Apple does NOT expose Vision Pro's world cameras to third-party apps under standard App Store distribution — `com.apple.developer.arkit.main-camera-access.allow` is gated on an enterprise developer agreement and a managed-device deployment, neither of which applies to Scan — so the live-camera path is unreachable on visionOS by design. Rather than ship the Scan tab with a permanent "no camera available" failure banner, 1.8 detects the host platform at runtime and presents a different layout there.

- New `Scan/Scan/Platform.swift` exposes `Platform.isVisionOS` (`ProcessInfo.processInfo.isiOSAppOnVisionOS`) and `Platform.isMacCatalyst` (`ProcessInfo.processInfo.isMacCatalystApp`). Centralising the predicates keeps platform branches readable and gives the codebase a single place to update if Apple ever opens up the world camera.
- `ScannerScreen` branches its body: iPhone / iPad / Mac Catalyst keep the existing edge-to-edge `cameraScannerLayout` ZStack; visionOS gets a new `visionOSImportLayout` that leads with two large "Choose from Photos" / "Choose from Files" buttons, a clear one-paragraph explanation of why there's no live scanner, and a footnote about the cross-device iCloud library + Generate tab. Critically, the visionOS branch never instantiates `CameraScannerView`, so no `AVCaptureSession` is started and no permission prompt fires.
- `.fileImporter` now advertises both `.image` and `.pdf` content types — a regression catch from 1.6, when the PDF decoder was added but the importer's allowed-types list wasn't updated. Important on visionOS, where Files is the natural source for screenshots-of-receipts and saved tickets.

### Same library on every device

iCloud sync was already wired up in 1.5 via `NSPersistentCloudKitContainer` + the `iCloud.me.nettrash.Scan` container declared in `Scan.entitlements`. With the new Mac Catalyst and visionOS destinations, the existing replication path means a Wi-Fi QR scanned on the iPhone shows up in the Mac and Vision Pro History tabs without any new code — the iCloud token surface in the Settings tab is unchanged.

### What's New

`WhatsNew.swift` updated to `version = "1.8"` with four rows: "Now on Mac" (Catalyst), "On Vision Pro: library + image import" (the honest framing of what visionOS users get), "Same library, every device" (cross-device iCloud), and a roll-up entry summarising 1.2 → 1.7 for users coming directly from 1.1 / 1.0 on a freshly-installed Mac or Vision Pro build. The auto-presentation logic in `ContentView` is unchanged from 1.2 — `@AppStorage(ScanSettingsKey.lastSeenVersion)` gates the sheet so existing users who already saw 1.7 will see the 1.8 sheet exactly once.

### Marketing version

`MARKETING_VERSION` bumped to `1.8` across all eight `XCBuildConfiguration` entries (Debug + Release × `Scan` app + `ScanShareExtension` + `ScanTests` + `ScanUITests`). `CURRENT_PROJECT_VERSION` continues to auto-increment via the post-action `agvtool bump`.

## [1.7] — 2026-05-01

Camera UX: pinch-to-zoom + centred-frame scanning.

### Pinch-to-zoom

`ScannerViewController` now installs a `UIPinchGestureRecognizer` on its host view. Each gesture frame multiplies the camera's *current* `videoZoomFactor` by `recognizer.scale` and re-applies, clamped to `[device.minAvailableVideoZoomFactor, min(device.maxAvailableVideoZoomFactor, 8.0)]`. The 8× cap is a quality floor — beyond that you're amplifying noise, not gaining detail. `device.lockForConfiguration()` is best-effort; if another thread holds the lock we skip a frame and pick up the next one (zoom is naturally interpolated by AVFoundation either way).

A new `pinchStartZoom` private field captures the zoom at gesture start so a single pinch is monotonic — without it, multiplying `device.videoZoomFactor` by every incremental `recognizer.scale` would drift exponentially.

### Region-of-interest cropping

`AVCaptureMetadataOutput.rectOfInterest` is now set to a centred 78 % × 78 % rect of the preview layer, mapped through `previewLayer.metadataOutputRectConverted(fromLayerRect:)` to AV's normalised (0..1, top-left-origin) coordinate space. AVFoundation server-side filters out codes whose bounds don't intersect — saves recogniser cycles and stops a stray code at the edge of the frame from competing with the one the user is centring on.

`applyRectOfInterest()` runs:
- on every successful `viewDidLayoutSubviews` (rotation / split-screen / window resize all re-derive the rect),
- in `buildSession()` once the preview layer is ready (initial setup),
- with explicit clamping to `[0, 1]` because `metadataOutputRectConverted` can return briefly out-of-range values during layout transitions.

The 78 % factor is sized to be *slightly larger* than the SwiftUI reticle (260 × 260 pt) on a typical phone, so anything visually inside the corner brackets is also inside the ROI — there's no "I framed the code in the reticle but it's not detecting" gotcha.

## [1.6] — 2026-05-01

Share-to-Scan + PDF support.

### Share Extension (new target)

- New `ScanShareExtension` app-extension target wired into `Scan.xcodeproj`. Scan now shows up in the iOS share sheet for images and PDFs; the result + actions render *inline* without leaving the source app.
- `ScanShareExtension/Info.plist` declares `com.apple.share-services` as the extension point, with `NSExtensionActivationSupportsImageWithMaxCount = 10` and `NSExtensionActivationSupportsFileWithMaxCount = 10` — the share sheet only offers Scan when the source provides at least one image or PDF, capped at 10 items per share to stay inside the share-extension memory budget (~120 MB on most devices).
- `ShareViewController.swift` is the UIKit bridge — extracts every `NSItemProvider` matching the image / PDF type IDs and hands them to a `UIHostingController`-wrapped SwiftUI view.
- `ShareView.swift` runs through three states: Loading (decoding), Ready (renders single-result detail or a list when ≥ 2 codes), Failed (no decodable barcodes). Each result row offers Copy and "Open in Scan", the latter handing off via the existing `https://nettrash.me/scan/<base64url-payload>` Universal Link wired up in 1.5 — no shared App Group required for v1.
- Parser sources are dual-membered between the main `Scan` target and the extension via additional PBXBuildFile entries pointing at the same fileRefs. Twelve files cross over: `Symbology`, `ScanPayload`, `ImageDecoder`, and the per-payload parsers under `BankPaymentPayloads` / `CryptoPayload` / `CalendarPayload` / `RegionalPaymentPayloads` / `MagnetPayload` / `RichURLPayload` / `GS1Payload` / `BoardingPassPayload` / `DrivingLicensePayload`. No new framework target — for ~12 small files this is simpler than introducing one.
- `XCODE_SETUP.md` in the extension folder documents the manual recovery if any of the pbxproj surgery needs touching up in Xcode.

### PDF support

- `ImageDecoder.decode(pdfData:)` walks every page of a `PDFDocument` via PDFKit, rasterises each at 2× the page's natural point size, and runs the existing Vision path on the resulting bitmap. Boarding-pass PDFKit-flipped coordinate space is handled with an explicit `translateBy` + `scaleBy(1, -1)` so the page draws the right way up.
- `ImageDecoder.decode(url:)` now auto-routes `.pdf` URLs to the PDF path so the in-app Files importer also benefits.
- `ImageDecoder.decodeBatch(urls:)` and `decodeBatch(items:)` aggregate decoded codes across N inputs (mixed images + PDFs) with `Set`-based dedup on `value`. The Share Extension uses `decodeBatch(items:)` to avoid file-system round-trips.

### Generator (no changes; just version bump)

The earlier 1.5 bug fixes (Form gesture intercept, strict same-value dedupe, banner ✕ button) all carry forward.

## [1.5] — 2026-05-01

Architectural pass — Universal Links + iCloud sync surface.

### Universal Links

- New `Scan/Scan/DeepLink.swift` decodes `https://nettrash.me/scan/<base64url-payload>` URLs back into the original payload string. URL-safe base64 (`-_`, no padding) keeps the path round-trippable for arbitrary binary payloads (vCards with newlines, EMVCo merchant blobs with `&` and `=`, …) while staying short enough for the URL to be shareable.
- `DeepLinkDispatcher` (singleton, `ObservableObject`) is the bridge between `ScanApp.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` / `.onOpenURL(...)` and the SwiftUI tree. The single-slot `pending` value survives a cold-start race where `ContentView` may not yet be in the hierarchy when the link fires.
- `DeepLinkResultSheet` re-uses the existing `PayloadActionsView` so the displayed fields and smart actions match a freshly-scanned code exactly. The only difference is a single "Save to History" button instead of the camera path's notes flow — deep-link arrivals are typically one-offs.
- New `Scan/Scan/Scan.entitlements` declares `applinks:nettrash.me` and `webcredentials:nettrash.me` in `com.apple.developer.associated-domains`. Wired into both Debug and Release build configs via `CODE_SIGN_ENTITLEMENTS = Scan/Scan.entitlements;`.

### iCloud sync (now actually syncing)

- The same entitlements file declares `com.apple.developer.icloud-services = [CloudKit]` and `com.apple.developer.icloud-container-identifiers = [iCloud.me.nettrash.Scan]`. `Persistence.swift` already used `NSPersistentCloudKitContainer`, but without the entitlements the container ran in local-only mode. With these in place, history rows now replicate to the user's iCloud account when they're signed in at the system level.
- New "Sync" section in the Settings tab. Reads `FileManager.default.ubiquityIdentityToken` to surface a `Signed in` / `Signed out` label and an explanatory line directing the user to Settings → iCloud when off.

### Server-side

- `nettrash.me/frontend/assets/.well-known/apple-app-site-association` lists the `appIDs` (`V4WM2SJ8Q9.me.nettrash.Scan`) and the `/scan/*` path scope.
- `nginx.conf` adds a `location ^~ /.well-known/` block serving the file as `application/json` with `Cache-Control: no-store` and `try_files $uri =404` (no SPA fallback). The verifier insists on a hard 404 for missing files, not the SPA shell.
- `frontend/index.html` gets a new `<link data-trunk rel="copy-dir" href="assets/.well-known">` so Trunk copies the directory verbatim into `dist/`.

## [1.4] — 2026-05-01

Payload-recognition pass — four new flavours.

### Wi-Fi: WPA3 + Passpoint

- `CodeComposer.WifiSecurity` gains `.wpa3` (`SAE`) and `.passpoint` (`HS20`) cases. The display labels are now friendly ("WPA / WPA2", "WPA3 (SAE)", "Passpoint (HS20)") rather than the raw `T:` token.
- `PayloadActionsView`'s `.wifi` case routes the raw `security` string through a new `friendlyWifiSecurity(_:)` helper. Unknown tokens still pass through verbatim so a future security flavour shows *something* in the result sheet rather than nothing.
- Passpoint payloads now surface an explicit caveat ("install the profile manually") because iOS doesn't expose a programmatic Passpoint provisioning API.

### Crypto: USDC / USDT / DAI

- `CryptoPayload.Token { symbol, contract, chain }` is the new home for ERC-20 / TRC-20 / SPL token context. `labelledFields` leads with "USDC on Ethereum" + the contract address when a token is recognised, instead of dumping the contract as the destination.
- New `CryptoPayload.Chain.tron` plus `tron:` / `tronlink:` schemes recognised, with a strict 34-char base58 regex for bare Tron addresses (`T…`) — checked before Bitcoin's regex so the legacy-Bitcoin pattern doesn't swallow them.
- `CryptoURIParser.parse` now handles three transfer shapes:
  - **EIP-681 ERC-20** (`ethereum:CONTRACT@1/transfer?address=RECIPIENT&uint256=AMOUNT`) — recognised when the path's function segment is `/transfer`. Path's "address" is the *contract*, recipient is in the query, amount comes from `uint256=`.
  - **Solana Pay SPL** (`solana:RECIPIENT?spl-token=MINT&amount=…`) — recipient stays in the path, mint comes from the query.
  - **TRC-20** (`tron:CONTRACT?address=RECIPIENT` or `tron:RECIPIENT?contract=…`) — both shapes handled.
- Built-in `knownTokens` registry covers USDC, USDT, DAI on Ethereum; USDT, USDC on Tron; USDC, USDT on Solana. Lookups are case-insensitive (lowercased keys) so checksum / base58 casing variations resolve cleanly. Unknown contracts still surface a generic `ERC-20` / `TRC-20` / `SPL` token tag with the contract baked in.
- `parseBare` enriches `0x…` and `T…` matches with token registry lookup, so a scan of just a stablecoin contract address still surfaces the symbol.

### Digital identity: DigiD + EUDI + OpenID4VC

- `RichURLPayload.Kind.digitalIdentity` is the new tag. Detection lives in `RichURLParser.digitalIdentityPayload(...)`, conservative on purpose so that arbitrary `https://example.com/login` doesn't get mis-flagged. Triggers on:
  - DigiD hosts (`*.digid.nl`, `mijn.digid.nl`)
  - EUDI Wallet hosts (`*.eudiw.dev`, `*.eu-digital-identity-wallet.eu`, `ec.europa.eu` paths containing "eudi")
  - Path-level OpenID4VC markers (`openid-credential-offer`, `openid4vp`, `/oidvp/`, or an `authorize` endpoint with `response_type=vp_token` / `client_id_scheme`).
- The result sheet renders an orange `exclamationmark.shield` warning above the action button: "Identity flow — only continue if you started this login yourself." This makes the impersonation vector (a stranger's QR trying to log *you* into *their* session) hard to miss.
- New `Continue in browser` action label + `person.text.rectangle` icon. History row icon also updated to match.

### Loyalty cards

- New "Save as loyalty card" affordance on `.productCode` payloads. The user is prompted for a merchant name (Tesco, IKEA, …) and the row is persisted directly via `@Environment(\.managedObjectContext)` with `notes = "Loyalty: <merchant>"`, `symbology = "Loyalty"`, and `isFavorite = true`. The favourite flag pins it to the top of History; the merchant tag makes the search field find it instantly.
- Apple Wallet / PassKit integration is *deliberately* not done client-side: a real `.pkpass` requires server-side signing with a Wallet certificate, which isn't viable for an offline app. The favourited History row is the pragmatic equivalent.

## [1.3] — 2026-05-01

Generator + scanner UX pass.

### Generator

- **Foreground / background colour pickers** in `GeneratorScreen.swift`. Live preview re-renders on every change. WCAG relative-luminance contrast ratio is computed locally and the screen surfaces a warning when the chosen pair drops below 3:1 — the practical floor for reliable scanning.
- **QR error-correction picker** (L / M / Q / H) exposed alongside the colour controls, with the level forced to `H` whenever a logo is set so callers don't have to remember.
- **Logo embedding** for QR via `PhotosPicker` + a centred `~22 %`-of-canvas composite with a white rounded "punch" behind the logo. Punch is forced white regardless of the user's background colour, so the finder pattern keeps maximum contrast.
- **SVG and PDF exports** — new `QRSvg.swift`. SVG is run-length-encoded per row (so a typical 33-module QR emits ~120 `<rect>`s instead of ~600). PDF is drawn via `UIGraphicsPDFRenderer` for true vector output that prints cleanly at any size. Both exports honour the user's foreground / background colours and ride through the existing share-sheet pipeline (the new `ShareItems` wrapper handles three different export targets behind one `.sheet(item:)` binding).
- **Reset-to-default** button on the Style section so a user that messed with colours can get back to plain black-on-white in one tap.
- `CodeGenerator.swift` reworked: now takes `foreground`, `background`, `errorCorrection`, and `logo` parameters. Recolouring goes through `CIFilter.falseColor` *before* rasterisation so module edges stay crisp. New `qrModuleMatrix(for:)` helper exposes the unscaled QR module bitmap for vector exporters to consume without re-encoding.

### Scanner

- **Multi-code disambiguation.** `CameraScannerView.swift` now emits the full array of recognised codes (deduped on `value` with order preserved) via a new `onScanBatch` callback. `ScannerScreen.swift` renders numbered chips at each code's bounding rect when more than one is in frame, with a translucent backdrop and a "Multiple codes — tap one" banner. Tapping a chip routes through the normal scan pipeline (haptic / sound / continuous-scan / save). Single-code framing keeps the existing direct-to-sheet path.
- The reticle continues to track the *largest* detected rect during multi-code framing, so the user has a clear primary anchor while still seeing all alternatives.

## [1.2] — 2026-05-01

Polish + History pass on top of 1.1's payload coverage. `MARKETING_VERSION` bumped to `1.2` across all six configurations (Debug + Release × app + tests + UI tests). `CURRENT_PROJECT_VERSION` continues to auto-increment via the `agvtool bump` scheme post-action.

### Scanner UX

- **Live preview no longer freezes when a code is recognised.** The result sheet now slides up over a still-running camera feed instead of pausing the `AVCaptureSession`. Sheet-level dedupe (`lastValue` + `lastValueAt`) keeps re-detections of the same payload from re-presenting the sheet, so the user can keep the phone steady or flip to a different code without having to tap to "resume". The session is still paused while a still image from Photos / Files is being decoded — that path needs the recogniser's full attention and the preview would otherwise sit behind the progress indicator.
- **Corner reticle releases back to its default centred position when no codes are visible.** The reticle previously stayed locked on the last detection forever, which read as "stuck" once the code left the frame. A 0.5 s grace-period watchdog (`reticleResetGrace`) now clears `detectedRect` when the camera hasn't reported a recognised code for a short while, and `handleScan` updates the reticle on every detection — including dedupe-suppressed ones — so the brackets stay locked while the user is still pointing at a code, not just on the first frame.

### Settings tab (new)

- New `SettingsScreen.swift` and a fourth tab on `ContentView`. Three `@AppStorage`-backed toggles, all centralised in `ScanSettingsKey`:
  - **Haptic on scan** (default ON) — gates `UINotificationFeedbackGenerator().notificationOccurred(.success)` in the scanner path.
  - **Sound on scan** (default OFF) — `AudioToolbox` plays `SystemSoundID 1057` ("Tink") through `ScanSound.playScanned()`.
  - **Continuous scanning** (default OFF) — described below.
- "Test feedback" button fires both feedback channels at once so users can compare them before deciding which to leave on.
- About block surfaces the marketing version + build, plus links to the GitHub source and privacy policy.

### Continuous-scanning mode (new)

When `continuousScan` is on, recognised codes save straight to History instead of presenting the result sheet, and an inline banner shows the latest auto-saved value. Tap the banner to open the result sheet manually for that scan. Image-import path (Photos / Files) deliberately ignores the toggle — those are explicit one-off operations and benefit from the standard sheet acknowledgement.

### History favourites + CSV export (new)

- **Core Data model bumped to v2** (`Scan 2.xcdatamodel`). New attribute `isFavorite: Bool` (optional, scalar, default `NO`). Lightweight migration runs automatically — a 1.1 user's existing scans materialise as un-favourited and the iCloud-backed CKContainer accepts the schema change without requiring a reset.
- **Star a scan to pin it.** Leading swipe action on each row, plus a yellow "Favourites only" filter chip in the toolbar. The Core Data fetch sorts on `(isFavorite DESC, timestamp DESC)` so favourites bubble to the top globally.
- **Export to CSV.** New toolbar menu with two entries — *Visible* (respects the search + favourites filter) and *All* (the full list). `HistoryCSV.swift` writes RFC 4180-compliant output (CRLF, double-quote-escaping where needed) with columns `timestamp,symbology,value,notes,favourite`. The file is handed to a UIKit-bridged `UIActivityViewController` so the user can drop it into Files, AirDrop, e-mail, etc.

### What's-New sheet (new)

`WhatsNewSheet.swift` ships the per-version highlights as a literal `[WhatsNewItem]` array. `ContentView` checks `@AppStorage(ScanSettingsKey.lastSeenVersion)` against `CFBundleShortVersionString` on every launch — if they differ *and* the running build matches the bundled `WhatsNew.version`, the sheet auto-presents. Dismissal stamps the storage so it doesn't re-present on subsequent launches; build/version mismatches silently catch the storage up so the next legitimate version bump shows correctly.

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
  MECARD, EAN-13, EPC, EMVCo (top-level +
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
