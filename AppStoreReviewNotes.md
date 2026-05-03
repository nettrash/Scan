# App Store Review — App Review Information Note

The text below is what goes verbatim into the *App Review Information → Notes* field in App Store Connect for every Scan submission. Update only when something user-facing changes (new permission, new URL host, new system intent, etc.).

---

Scan is a barcode and QR-code reader / generator. No account, sign-in, or onboarding — the Scan tab opens on launch and the camera starts decoding immediately after the camera-permission prompt.

DESTINATIONS

Scan ships a single iOS app target that runs on iPhone, iPad, Mac (via Mac Catalyst), and Apple Vision Pro (via Designed for iPad). The bundle ID is identical across all four destinations (`me.nettrash.Scan`); please review them as one app rather than as separate submissions.

• iPhone / iPad — primary destination. Live AVFoundation scanner + image import.
• Mac (Mac Catalyst, macOS 14 Sonoma or later) — uses the Mac's built-in webcam or any Continuity Camera for the live scanner. The same Photo Library / Files import paths work via the macOS file pickers. The smart-action handlers (`mailto:`, `tel:`, `geo:`, etc.) route through the macOS system handler.
• Apple Vision Pro (Designed for iPad) — Apple does not expose Vision Pro's world cameras to third-party apps under standard App Store distribution, so the live-scanner path is intentionally not present on visionOS. The Scan tab opens directly to a "Choose from Photos / Choose from Files" landing surface (with a one-paragraph explanation of why), and `Platform.isVisionOS` short-circuits the `AVCaptureSession` setup so no camera-permission prompt appears either. The Generate tab and the iCloud-synced History tab work exactly as on iPhone.

Note: the "iPad app on Apple Silicon Mac" (Designed-for-iPad-on-Mac) destination is intentionally opted out of via `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO`. Mac Catalyst is the canonical Mac experience for Scan; iPad-on-Mac would only have served as a fallback if Catalyst wasn't shipped, and the Mac App Store auto-prefers Catalyst when both are in the same submission anyway.

The same iCloud-synced scan history follows the user across all four destinations via the existing `iCloud.me.nettrash.Scan` private CloudKit container.

TESTING TIPS

• Test on a real device. The iOS Simulator doesn't expose a working camera, so the live scanner can't be exercised there. The "Photo Library" button in the Scan tab toolbar works in the Simulator if you save a QR screenshot to Photos first — that path uses Vision's `VNDetectBarcodesRequest` against a still image and exercises the same parser pipeline as the live scanner.
• On Mac Catalyst, Continuity Camera (an iPhone within Bluetooth range) shows up as a selectable video device — handy if the test machine is a Mac without an internal camera. Note the App Sandbox `com.apple.security.device.camera` entitlement is set in `Scan.entitlements` so the macOS camera permission prompt fires on first use.
• On Vision Pro, the Scan tab's primary call-to-action is "Choose from Photos" / "Choose from Files" by design — please don't flag the absence of the live scanner as a bug. Pick a saved QR screenshot from Photos to exercise the still-image decoder, which uses the same `VNDetectBarcodesRequest` pipeline as the iPhone build. The Generate tab is fully functional and is the recommended exercise for live-output review on visionOS.
• Suggested payloads to exercise the smart result-sheet actions:
  – any https:// URL → "Open in Safari"
  – a Wi-Fi QR (printed in any router manual) → shows SSID, copies password, opens Wi-Fi Settings
  – a vCard or MECARD → "Add to Contacts" opens the system "New Contact" sheet
  – an iCalendar VEVENT QR → "Add to Calendar" opens the system event editor
  – an EAN-13 barcode on any product → product lookup
  – an EPC SEPA Payment QR (a.k.a. GiroCode) → IBAN, beneficiary, amount as separate copyable fields
• The Generate tab builds QR / Aztec / PDF417 / Code 128 codes from text, URL, contact, or Wi-Fi credentials, with Save to Photos / Share / Copy actions.

PERMISSIONS

• Camera (NSCameraUsageDescription) — required for the Scan tab; used only for on-device decoding via AVFoundation. Frames are never recorded or transmitted.
• Photo Library — add only (NSPhotoLibraryAddUsageDescription) — for the "Save to Photos" action in the Generate tab. Write-only; the app cannot read existing photos.
• Contacts (NSContactsUsageDescription) — only when the user taps "Add to Contacts" on a scanned vCard / MECARD. The system-supplied CNContactViewController mediates the save.
• Calendar — write-only on iOS 17+ (NSCalendarsWriteOnlyAccessUsageDescription) — only when the user taps "Add to Calendar" on a scanned iCalendar event. The system-supplied EKEventEditViewController mediates the save.

PRIVACY

Scan does not collect, transmit, or share any data. The barcode model runs entirely on-device via AVFoundation and Vision. There are no third-party SDKs, no analytics, no advertising, no trackers. Optional iCloud sync of the local scan history uses the user's own private CloudKit container — Apple stores it, the developer never sees it.

LINKS

Privacy policy: https://nettrash.me/appstore/scan/privacy.html
Source code:    https://github.com/nettrash/Scan

CONTACT

nettrash@nettrash.me
