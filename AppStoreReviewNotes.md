# App Store Review — App Review Information Note

The text below is what goes verbatim into the *App Review Information → Notes* field in App Store Connect for every Scan submission. Update only when something user-facing changes (new permission, new URL host, new system intent, etc.).

---

Scan is a barcode and QR-code reader / generator. No account, sign-in, or onboarding — the Scan tab opens on launch and the camera starts decoding immediately after the camera-permission prompt.

TESTING TIPS

• Test on a real device. The iOS Simulator doesn't expose a working camera, so the live scanner can't be exercised there. The "Photo Library" button in the Scan tab toolbar works in the Simulator if you save a QR screenshot to Photos first — that path uses Vision's `VNDetectBarcodesRequest` against a still image and exercises the same parser pipeline as the live scanner.
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
