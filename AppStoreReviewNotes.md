# App Store Review — App Review Information Note

Scan is a barcode and QR-code reader / generator. No accounts, no sign-in, no telemetry. Last approved release was 1.1.0; this submission is 1.8.

DESTINATIONS

Single iOS target, four destinations: iPhone, iPad, Mac (Catalyst, macOS 14+), Apple Vision Pro (Designed for iPad). Same bundle ID (me.nettrash.Scan) — please review as one app. Mac uses the built-in webcam or any Continuity Camera. On Vision Pro the live camera is unavailable by design (Apple does not expose Vision Pro's world cameras to third-party apps); Platform.isVisionOS short-circuits AVCaptureSession and the Scan tab opens to "Choose from Photos / Choose from Files". Designed-for-iPad-on-Mac is opted out (SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO) — Catalyst is the canonical Mac experience.

WHAT'S NEW SINCE 1.1.0

Mac Catalyst + visionOS (1.8). Pinch-to-zoom + ROI camera crop (1.7). Share-to-Scan extension + PDFKit decoding (1.6). Universal Links + iCloud-synced history via NSPersistentCloudKitContainer (1.5). New payloads — WPA3 / Passpoint, USDC / USDT / DAI stablecoins, DigiD / EUDI / OpenID4VC identity flows, loyalty cards (1.4). Generator gains custom colours with WCAG contrast, error-correction picker, logo embedding, SVG / PDF export, multi-code disambiguation (1.3). Settings tab + History favourites + CSV export + What's-New sheet (1.2).

TESTING TIPS

• Real device only — the iOS Simulator has no camera. Photo Library import works in the Simulator if you pre-save a QR screenshot.
• Mac Catalyst: Continuity Camera shows up as a selectable video device.
• Vision Pro: the absent live scanner is by design — pick a saved QR from Photos to exercise the still-image path.
• Suggested payloads: any https URL, Wi-Fi QR, vCard, iCalendar VEVENT, EAN-13, EPC SEPA QR, plus an image or PDF shared via the Share Sheet (covers the extension end-to-end).

PERMISSIONS (unchanged since 1.1.0)

Camera (NSCameraUsageDescription) — live scanning, on-device. Photo Library Add-Only — Save to Photos in Generate. Contacts — only on "Add to Contacts"; CNContactViewController mediates. Calendar write-only on iOS 17+ — only on "Add to Calendar"; EKEventEditViewController mediates. PhotosPicker is out-of-process and needs no permission.

ENTITLEMENTS

associated-domains: applinks:nettrash.me + webcredentials:nettrash.me. iCloud-services: CloudKit on iCloud.me.nettrash.Scan (private user database). Mac Catalyst sandbox: app-sandbox + device.camera + network.client + files.user-selected.read-only + personal-information.photos-library (iOS ignores these keys at runtime).

SHARE EXTENSION

Second target ScanShareExtension (me.nettrash.Scan.ScanShareExtension) — com.apple.share-services. Activation: max 10 images, max 10 PDFs. Decoding is in-process and on-device. "Open in Scan" hands off via the custom scheme me.nettrash.scan:// registered in the main app.

SENSITIVE PAYLOAD TYPES

Identity flows (DigiD / EUDI / OpenID4VC) — recognise URL pattern, warn the user, route to browser. NO verification, NO claim storage. Crypto and stablecoin URIs — parse, present labelled fields, hand off to the user's wallet via URI scheme. NO transactions, NO key custody. Payment QRs (SEPA / Swiss / UPI / IPS / SPD / Pay by Square / Bezahlcode / EMVCo / Swish / Vipps / MobilePay / Bizum / iDEAL) — same pattern; NO transaction initiation. AAMVA driver licences — parsed locally to labelled fields. Loyalty cards — local Core Data metadata; NOT Apple Wallet integration.

PRIVACY

No data collection, no analytics, no advertising, no third-party trackers. All decoding is on-device. iCloud history mirroring uses the user's own private CloudKit container.

LINKS

Privacy: https://nettrash.me/appstore/scan/privacy.html
Support: https://nettrash.me/appstore/scan/support.html
Source:  https://github.com/nettrash/Scan

CONTACT

nettrash@nettrash.me
