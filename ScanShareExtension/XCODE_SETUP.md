# Share Extension — Xcode setup notes

This folder contains the source files for `ScanShareExtension`. The
`Scan.xcodeproj` has been edited to add the matching native target,
build configurations, and embed phase. If any of that pbxproj surgery
didn't fully take (Xcode is finicky about target wiring, especially
across iOS / Xcode releases), the recovery is straightforward — see
"Manual setup" below.

## What's in this folder

| File                       | Role                                                                  |
| -------------------------- | --------------------------------------------------------------------- |
| `Info.plist`               | Activation rule (image + PDF, max 10 items), principal class binding. |
| `ShareViewController.swift`| UIKit bridge — extracts `NSItemProvider`s and hosts the SwiftUI view. |
| `ShareView.swift`          | SwiftUI surface: loading / list / detail; copy + open-in-Scan.        |

The extension shares parser sources with the main `Scan` target via
**dual file membership**, not a separate framework — every Swift
source under `Scan/` that the parser pipeline depends on
(`Symbology.swift`, `ScanPayload.swift`, `ImageDecoder.swift`, all
the per-payload parsers under `BankPaymentPayloads.swift` etc.) is
listed in *both* targets' Sources build phases. No extra framework
target was added; for ~12 small files this is simpler.

## Capabilities

The extension target inherits the App ID prefix from the main app and
needs **no entitlements of its own**. CloudKit, App Groups, and
Universal-Links entitlements all live on the main app and the
extension reaches the main app via the existing `https://nettrash.me/scan/<base64url-payload>` deep link, so no shared App Group is required for v1.

## Manual setup (if the pbxproj edits didn't take)

Symptoms that something didn't take:
- Build fails with `Cannot find 'ShareViewController' in scope`.
- The Xcode target picker shows two `Scan` targets but no
  `ScanShareExtension`.
- `xcodebuild -list` doesn't show the extension target.

Recovery — three minutes in Xcode:

1. **File → New → Target → Share Extension**. Name it
   `ScanShareExtension`. Set the Bundle Identifier to
   `me.nettrash.Scan.ScanShareExtension`.
2. Xcode will scaffold a new `ScanShareExtension/` folder with its
   own `ShareViewController` template. **Delete** Xcode's stub files
   and **add** the three files in this folder (`Info.plist`,
   `ShareViewController.swift`, `ShareView.swift`) to the new target
   via *File → Add Files to "Scan"…*.
3. Set the target's **Info.plist file** build setting to
   `ScanShareExtension/Info.plist`.
4. In the project navigator, select each of the parser sources
   listed below, open the File Inspector, and tick the
   `ScanShareExtension` target's "Target Membership" checkbox in
   addition to `Scan`:
   - `ScannedCode.swift`     ← the value type the decoder + view return.
   - `Symbology.swift`
   - `ScanPayload.swift`
   - `ImageDecoder.swift`
   - `BankPaymentPayloads.swift`
   - `CryptoPayload.swift`
   - `CalendarPayload.swift`
   - `RegionalPaymentPayloads.swift`
   - `MagnetPayload.swift`
   - `RichURLPayload.swift`
   - `GS1Payload.swift`
   - `BoardingPassPayload.swift`
   - `DrivingLicensePayload.swift`

   `CameraScannerView.swift` is **deliberately not** dual-membered —
   it pulls in `AVCaptureSession` and the live-preview UIKit hosting,
   neither of which a share extension can use. `ScannedCode.swift`
   was extracted from `CameraScannerView.swift` for exactly this
   reason: so the extension can import the value type without the
   camera plumbing.
5. Build. Run on a device. Share an image from Photos → "Scan"
   should appear.

## Why no App Group?

The Share Extension never directly writes to the main app's Core
Data store. Instead it offers an **"Open in Scan"** button that
mints an `https://nettrash.me/scan/<base64url-payload>` URL and
asks the system to open it — which lands on the main app's
Universal-Link handler (wired up in 1.5) and shows the result
sheet there. No shared container needed.

If we ever want the extension to *save* directly to History
without a hand-off, that's the point at which we'd need an App
Group + an `applicationGroupIdentifier`-based persistent store
URL, plus a CloudKit container ID on the extension as well. For
v1 the deep-link hand-off is enough.

## Memory

The extension is hard-capped at ~120 MB on most devices. The
`NSExtensionActivationSupportsImageWithMaxCount` /
`SupportsFileWithMaxCount` of 10 in `Info.plist` is the user-facing
limit; the decoder additionally streams via `loadDataRepresentation`
rather than `NSItemProvider.loadItem(forTypeIdentifier:)` to avoid
materialising every shared file's bytes simultaneously when the user
shares a 50-image batch through some other channel.
