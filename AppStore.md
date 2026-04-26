# App Store submission copy

Drop-in text for the **Scan** App Store Connect listing. Each section
below maps to a specific field in App Store Connect; character limits
are noted in parentheses and verified against the copy.

---

## App Name (max 30)

```
Scan: QR & Barcode Reader
```

(25 characters.)

---

## Subtitle (max 30)

```
Smart QR & barcode toolkit
```

(26 characters.)

---

## Promotional Text (max 170)

This is the only field you can update without re-submitting a build, so
treat it as the editable hero line. Suggested copy:

```
Decode QR codes and barcodes into structured fields you can copy or act
on instantly. Recognises 30+ payment, contact, calendar, and crypto
formats.
```

(159 characters.)

---

## Description (max 4 000)

```
Most QR scanners just show you the text inside a code. Scan understands
what the text means — and lets you act on it with one tap.

WHAT SCAN DECOMPOSES INTO FIELDS

• Web — URLs, email, phone, SMS, geolocation
• Connectivity — Wi-Fi credentials with copyable password
• Contacts — vCard / MECARD with one-tap "Add to Contacts"
• Calendar — iCalendar events with one-tap "Add to Calendar"
• Bank payments — SEPA Credit Transfer (EPC / GiroCode), Swiss
  QR-bill, Czech SPD (Spayd), Slovak Pay by Square, Russian
  unified payment (ST00012), EMVCo Merchant QR with deep
  decoding for Pix, PayNow, PromptPay, UPI-via-EMVCo, CoDi,
  DuitNow, QRIS, FPS, NAPAS, NETS
• Mobile pay — Indian UPI, Swish (Sweden), Vipps (Norway),
  MobilePay (Denmark / Finland), Bizum (Spain), iDEAL
  (Netherlands), Bezahlcode (Germany), Serbian NBS IPS
  (Prenesi)
• Receipts — Russian FNS retail receipts, Serbian SUF fiscal
  receipts
• Crypto — Bitcoin, Ethereum (with chain ID), Litecoin,
  Bitcoin Cash, Dogecoin, Monero, Cardano, Solana, plus
  Lightning Network invoices

EVERY FIELD IS COPYABLE

A scanned bank QR doesn't dump a wall of text. It shows the IBAN, the
beneficiary, the amount, the reference, the purpose code — each as its
own row with a tap-to-copy button. Perfect for pasting into your
banking app.

SMART ACTIONS

• A URL opens in Safari
• A contact pre-fills the system "New Contact" form
• A calendar event pre-fills the system "Add Event" sheet
• A crypto address hands off to your installed wallet
• A receipt opens the official verification page
• A location opens in Maps

GENERATE CODES TOO

Build QR, Aztec, PDF417, or Code 128 codes from plain text, URLs,
contacts (full vCard 3.0 with name + phone + email + organisation +
website), or Wi-Fi credentials (with WPA / WEP / open + hidden
network support). Live preview, share via the system sheet, save to
Photos, or copy both the image and the encoded string to the clipboard.

LIVE CAMERA OR FROM A PICTURE

Scan with the camera or import an image from Photos or the Files app.
Every symbology AVFoundation recognises is supported, plus a few
extras Vision adds: QR (and microQR), Aztec, PDF417 (and microPDF417),
Data Matrix, EAN-8, EAN-13, UPC-E, Code 39, Code 93, Code 128, ITF-14,
Interleaved 2 of 5, Codabar, and the GS1 DataBar family.

PRIVACY-FIRST BY DESIGN

Scan never reads your address book, your calendar, or your photo
library. Every privileged action is mediated by a system "edit and
save" sheet that you control. Photo-library writes use the
least-privilege "add only" permission; calendar writes use iOS 17's
write-only access scope. No ads, no analytics, no account, no
third-party SDKs, no tracking. Your scan history stays on your
devices.

iCLOUD SYNC

Saved scans sync across your iPhone and iPad through your private
iCloud account. Search the history, edit notes per scan, delete what
you don't need.

BUILT FOR iOS 26

Native SwiftUI throughout, with Liquid Glass on the standard
containers. Universal app for iPhone and iPad.
```

(~2 700 characters of the 4 000 budget — leaves room for marketing
tweaks, regional callouts, or future features without trimming.)

---

## Keywords (max 100, comma-separated, no spaces around commas)

```
qr,barcode,scanner,scan,wifi,vcard,payment,sepa,iban,upi,upc,ean,code128,pdf417,generator,crypto
```

(96 characters.)

Notes on this set:

- Apple's keyword field already adds the App Name, Subtitle, and category
  to the search index for free, so don't repeat words from those fields here.
- Comma-separated, no spaces — spaces waste characters.
- Keywords are matched as exact substrings, so include both "qr" and
  "barcode" rather than "qrcode".
- "code128" rather than "code 128" because the field strips spaces but
  matches exact tokens.

---

## What's New in This Version (max 4 000)

For the **1.0** initial submission:

```
Scan launches on iOS 26 with Liquid Glass.

WHAT'S INSIDE:

• Live-camera scanning of every common 1D and 2D symbology — QR,
  Aztec, PDF417, Data Matrix, EAN, UPC, Code 39 / 93 / 128, ITF,
  Codabar, GS1 DataBar.

• Import from Photos or Files: scan codes already in your library
  or shared with you.

• Smart payload decomposition for 30+ formats — SEPA / EPC, Swiss
  QR-bill, Czech SPD, Slovak Pay by Square, Russian unified
  payment (ST00012), EMVCo Merchant QR (with deep decoding for
  Pix, PayNow, PromptPay, UPI, CoDi, DuitNow, QRIS, NETS, FPS,
  NAPAS), Indian UPI, Serbian NBS IPS, Bezahlcode, Swish, Vipps,
  MobilePay, Bizum, iDEAL, plus Wi-Fi, vCard, iCalendar, geo, OTP,
  product codes, and Bitcoin / Ethereum / Lightning + 6 more
  cryptocurrencies.

• Per-field tap-to-copy and one-tap smart actions: Add to Contacts,
  Add to Calendar, Open in Wallet, Verify Receipt, Open in Maps.

• Generate QR / Aztec / PDF417 / Code 128 from text, URLs, contacts,
  or Wi-Fi.

• Searchable scan history that syncs through your private iCloud
  account.

• Privacy-first: no ads, no tracking, no account, no third-party
  SDKs.
```

(~1 050 characters.)

---

## Support URL (required)

Pick one and paste into App Store Connect:

- `https://nettrash.me/scan/support` — if you want a dedicated page on
  your existing site.
- `https://github.com/nettrash/Scan/issues` — if you're happy directing
  users to GitHub Issues.

A bare email-only "support" page is acceptable; Apple just needs a
reachable destination.

---

## Marketing URL (optional)

```
https://nettrash.me/scan
```

If you don't have a marketing page, leave this field blank — it's
optional.

---

## Privacy Policy URL (required)

You'll need a privacy policy. Given the app collects nothing, the
policy can be very short. A skeleton:

> Scan does not collect, transmit, or sell any personal data. It does
> not use third-party SDKs or analytics. Camera, Photos, Contacts,
> and Calendar access are used only for the in-app actions you trigger
> explicitly, and never leave your device. Scan history is stored on
> your device and synced through your private iCloud account.

Host it at `https://nettrash.me/scan/privacy` (or anywhere reachable)
and paste the URL into App Store Connect.

---

## Suggested category

Primary: **Utilities**
Secondary: **Productivity**

Both are accurate; Utilities is the better primary because Scan's
function (camera-based code reading) is the textbook utility-app shape.

---

## Age rating

The app contains no objectionable content. The standard 4+ rating
applies. You'll be asked about Unrestricted Web Access — answer **No**;
even though scanned URLs can open in Safari, the *app itself* doesn't
embed a browser.

---

## Screenshot suggestions

Apple requires screenshots at multiple iPhone and iPad sizes. Five
suggested shots, in order:

1. **Hero — live scanner with corner brackets framing a QR.** Caption:
   "Scan any QR or barcode."
2. **Result sheet for a SEPA QR.** Caption: "Every field, individually
   copyable."
3. **Add-to-Contacts flow from a vCard.** Caption: "One tap to save."
4. **Generator screen with a freshly-rendered QR.** Caption: "Build
   your own codes too."
5. **History tab.** Caption: "Search your scans, sync via iCloud."
