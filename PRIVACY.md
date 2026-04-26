# Privacy Policy

**Effective date:** 26 April 2026
**Applies to:** Scan — the iOS app published by nettrash, available on
the App Store. This policy is versioned alongside the app's source
code; the most recent commit on `main` is authoritative.

## TL;DR

Scan **does not collect, transmit, sell, or share any personal
data**. It contains no analytics, no advertising SDKs, no third-party
trackers, and no remote servers operated by us. Everything you scan,
generate, or save stays on your device — and, if you're signed in to
iCloud, in *your own* private iCloud database.

If that already answers your question, you don't need to read the rest.

## What we collect

**Nothing.** Scan does not transmit any data about you to us or to any
third party. There is no account to create, no email to register, and
no telemetry pinging home from the app.

We have no servers in this picture. The app's network access is
limited to the URL schemes you explicitly trigger by tapping a smart
action — for example, opening a scanned `https://` URL in Safari, an
`upi://pay` URI in your installed UPI app, or a SEPA verification
URL on the issuing tax authority's site. In every such case, the
network request goes from *your device* directly to *that
destination* — Scan is not in the loop.

## Data stored on your device

Scan keeps a single local database — your **scan history** — using
Apple's Core Data with `NSPersistentCloudKitContainer`:

- Each entry records the decoded value, the symbology, a timestamp,
  and any notes you choose to attach.
- The database lives in the app's sandbox directory on your device.
- If you're signed in to iCloud and have *Scan* enabled in
  *Settings → \[Your Name\] → iCloud → Apps Using iCloud*, the
  database is mirrored to **your own** private iCloud database via
  CloudKit. Apple stores it; we never see it.
- Deleting a scan from the History tab removes it from the local
  database and the iCloud mirror.
- Deleting the app removes the local database. To remove the iCloud
  copy, sign in at `iCloud.com → Account → Manage iCloud Storage` or
  delete the app's data from *Settings → \[Your Name\] → iCloud →
  Manage Account Storage*.

We have no access to this database under any circumstance.

## Permissions Scan asks for, and what each one is used for

| Permission | Used for | Scope |
| --- | --- | --- |
| **Camera** (`NSCameraUsageDescription`) | Live barcode and QR-code scanning. | Frames are decoded on-device by Apple's AVFoundation; nothing is recorded or transmitted. |
| **Photo Library — add only** (`NSPhotoLibraryAddUsageDescription`) | Saving codes you generate to your Photos library. | Write-only — the app cannot read existing photos. |
| **Contacts** (`NSContactsUsageDescription`) | "Add to Contacts" when you scan a vCard / MECARD QR. | Mediated by the system "New Contact" sheet that you must tap *Done* on; Scan does not read your address book. |
| **Calendars — write only** (`NSCalendarsWriteOnlyAccessUsageDescription` / `NSCalendarsUsageDescription`) | "Add to Calendar" when you scan an iCalendar QR. | Mediated by the system "Add Event" sheet on iOS 17+ via write-only access; Scan does not read your existing events. |

Every privileged action is gated on a system-supplied edit-and-save
sheet that you control. If you cancel that sheet, nothing is saved.

## Third-party services

**None.** Scan ships with zero third-party SDKs, frameworks, or
libraries beyond what Apple itself provides as part of iOS. There are
no analytics tools (Firebase, Mixpanel, Sentry, etc.), no advertising
SDKs (AdMob, Meta, etc.), no crash reporters that phone home, and no
attribution providers. The only external network connections are the
ones *you* initiate — tapping "Open in Safari" on a scanned URL, for
example.

## Tracking

Scan does not "track" you in the sense Apple's *App Tracking
Transparency* framework defines: it does not link any data collected
in the app with data from other apps, websites, or offline sources to
build a user profile, and it does not share any data with data
brokers. Scan therefore does not present an ATT prompt and is
declared with **Data Not Collected** on its App Store privacy
nutrition label.

## Children's privacy

Scan is rated **4+** and is suitable for all ages. We do not
knowingly collect personal information from children, because we do
not collect personal information from anyone.

## International data transfers

Because Scan does not transmit personal data anywhere, there are no
cross-border transfers to disclose under the GDPR, UK GDPR, CCPA,
LGPD, or similar regimes. Your scan history's iCloud mirror is
governed by Apple's iCloud privacy terms, not ours.

## Your rights

Because we hold no data about you:

- There is **no record to access** under GDPR Article 15 / CCPA
  "right to know".
- There is **no record to delete** under GDPR Article 17 / CCPA
  "right to delete" (the local + iCloud database is yours alone — see
  the deletion steps above).
- There is **no record to correct** under GDPR Article 16.
- There is **nothing being sold or shared** under CCPA / CPRA, so no
  opt-out is required.

If you'd like confirmation in writing that we hold no data about you,
email the address below and we will reply.

## Changes to this policy

If a future version of Scan ever changes any of the above — adds
analytics, integrates a third-party SDK, transmits data off-device,
or requests new permissions — this document will be updated *in the
same release* and the **Effective date** at the top will be bumped.
The full history of this file is visible in the project's `git log`
on GitHub: <https://github.com/nettrash/Scan/commits/main/PRIVACY.md>.

## Contact

For privacy questions, please email **nettrash@nettrash.me**.
