# App Store Review — App Review Information Note

Scan is a barcode and QR-code reader / generator. No accounts, no sign-in, no telemetry, no third-party SDKs. This submission is 1.10.

DESTINATIONS

Single iOS target, four destinations: iPhone, iPad, Mac (Catalyst, macOS 26+), Apple Vision Pro (Designed for iPad). Same bundle ID (me.nettrash.Scan) — please review as one app. Mac uses the built-in webcam or any Continuity Camera. On Vision Pro the live camera is unavailable by design (Apple does not expose Vision Pro's world cameras to third-party apps); the Scan tab opens to "Choose from Photos / Choose from Files". Designed-for-iPad-on-Mac is opted out (SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO) — Catalyst is the canonical Mac experience.

WHAT'S NEW IN 1.10

• "What is this code?" — a plain-language explanation of a scanned code. Uses the on-device Apple Intelligence model (FoundationModels SystemLanguageModel; never Private Cloud Compute) where available, otherwise Scan's built-in rules. Credentials are blanked before anything reaches the model. "Describe the code" on the Generate tab fills the form from a sentence the same way.
• QR safety check — every code is graded before an action is offered (look-alike domains, address-bar tricks, risky links, preset payment amounts, two codes in one frame…). A dangerous link offers "Copy link" instead of Open until the user chooses "I understand — open anyway". Pure on-device string analysis; no reputation service.
• Scan modes: Codes, Live Text (VisionKit DataScannerViewController + ImageAnalysisInteraction on a frozen frame) and Bulk (collects distinct codes, saves them to History or exports CSV).
• On-device translation with Apple's Translation framework (language packs downloaded by iOS after its own consent sheet).
• NFC read and write on iPhone (CoreNFC NFCNDEFReaderSession; sessions start only from a button).
• Decoding of digital-ID codes (ISO 18013-5 mdoc engagement QR, OpenID4VP requests, OpenID4VCI offers, SD-JWT VCs), EN 16931 CII e-invoices, GS1 Digital Product Passports and FIDO passkey QR codes. All decode-only: Scan never answers an identity request, fetches a request URI, completes a passkey sign-in or verifies signatures.
• QR styles (module / eye shapes, gradients, logo, presets; PNG / SVG / PDF keep the style).
• App Shortcuts (App Intents): Start Scanning, Explain Code, Generate Code, Copy Recent Scan (requires the device to be unlocked).
• Settings → Insights: switches for the assistant and the safety check, and the translation language.

TESTING TIPS

• Real device for the camera, Live Text and NFC — the iOS Simulator has no camera and no NFC. Photo Library / Files import works in the Simulator with a saved QR screenshot.
• Live Text: iPhone or iPad with a supported camera. Tap a highlighted text block for Copy / Share / Translate; tap the frame button ("Select words in this frame") to select single words.
• NFC: iPhone with any writable NDEF tag (e.g. NTAG213/215). Scan tab → "Read an NFC tag"; Generate tab → "Write to NFC tag".
• Apple Intelligence is optional: on a device without it (or with it switched off) "What is this code?" answers from Scan's built-in explainer.
• Shortcuts: e.g. "Scan a code with Scan", "Copy my last scan from Scan".
• Translation: the first translation into a new language shows iOS's own download sheet.
• Suggested payloads: any https URL, a look-alike URL such as https://paypaI.com/login (shows the safety warning), Wi-Fi QR, vCard, iCalendar VEVENT, EAN-13, EPC SEPA QR, plus an image or PDF shared via the Share Sheet (covers the extension end-to-end).

PERMISSIONS

Camera (NSCameraUsageDescription) — live scanning and Live Text, on-device; frames are not saved. NFC (NFCReaderUsageDescription, new in 1.10) — only after the user taps Read / Write; iPhone only. Photo Library Add-Only — Save to Photos in Generate. Contacts — only on "Add to Contacts"; CNContactViewController mediates. Calendar write-only on iOS 17+ — only on "Add to Calendar"; EKEventEditViewController mediates. PhotosPicker is out-of-process and needs no permission.

ENTITLEMENTS

associated-domains: applinks:nettrash.me + webcredentials:nettrash.me. iCloud-services: CloudKit on iCloud.me.nettrash.Scan (private user database). NFC Tag Reading (new in 1.10): com.apple.developer.nfc.readersession.formats = [TAG], iOS only. Mac Catalyst signs with Scan-macCatalyst.entitlements — the same keys minus NFC — plus the sandbox keys app-sandbox + device.camera + network.client + files.user-selected.read-only + personal-information.photos-library (iOS ignores these keys at runtime). Privacy manifest: PrivacyInfo.xcprivacy (no tracking, no collected data; UserDefaults CA92.1).

SHARE EXTENSION

Second target ScanShareExtension (me.nettrash.Scan.ScanShareExtension) — com.apple.share-services. Activation: max 10 images, max 10 PDFs. Decoding is in-process and on-device. "Open in Scan" hands off via the custom scheme me.nettrash.scan:// registered in the main app.

SENSITIVE PAYLOAD TYPES

Identity codes (mdoc engagement, OpenID4VP / OpenID4VCI, SD-JWT VC, DigiD / EUDI flows) — decoded to labelled fields with cautions. NO hand-off, NO request fetch, NO verification, NO claim storage; tokens, keys and pre-authorised codes are never displayed. Passkey QR (FIDO:/) — informational; the one-time secret is never displayed and only the system camera can complete the sign-in. Crypto and stablecoin URIs — parse, present labelled fields, hand off to the user's wallet via URI scheme. NO transactions, NO key custody. Payment QRs (SEPA / Swiss / UPI / IPS / SPD / Pay by Square / Bezahlcode / EMVCo / Swish / Vipps / MobilePay / Bizum / iDEAL) — same pattern; NO transaction initiation. E-invoices — summary fields only. AAMVA driver licences — parsed locally to labelled fields. Loyalty cards — local Core Data metadata; NOT Apple Wallet integration.

PRIVACY

No data collection, no analytics, no advertising, no third-party trackers. All decoding, the safety check and the explanations run on-device. iCloud history mirroring uses the user's own private CloudKit container. Apple system services used: on-device Apple Intelligence, Apple Translation (language packs via iOS), and the standard Live Text menu (its Look Up / Translate are iOS features).

LINKS

Privacy: https://nettrash.me/appstore/scan/privacy.html
Support: https://nettrash.me/appstore/scan/support.html
Source:  https://github.com/nettrash/Scan

CONTACT

nettrash@nettrash.me
