//
//  ScanSettings.swift
//  Scan
//
//  Centralised storage of user-tunable preferences. The app exposes them
//  through a Settings tab; the keys live here so the views that *consume*
//  them (ScannerScreen, ContentView's What's-New gate, …) can read the
//  same `@AppStorage` slot from anywhere without typo'd string keys.
//
//  The defaults are deliberately conservative: the app behaves the same
//  for a freshly upgraded user as before this screen existed.
//

import SwiftUI
import AVFoundation

enum ScanSettingsKey {
    static let hapticOnScan      = "settings.hapticOnScan"
    static let soundOnScan       = "settings.soundOnScan"
    static let continuousScan    = "settings.continuousScan"
    static let lastSeenVersion   = "settings.lastSeenVersion"
}

// MARK: - Audible-feedback helper

/// Plays a short system "scanned" sound effect. Uses `AudioToolbox`
/// directly so we don't pull in `AVAudioPlayer` lifecycle plumbing —
/// the caller fires-and-forgets and the system handles mixing /
/// duck-with-music itself.
enum ScanSound {
    /// `1057` is the system "Tink" sound — short, neutral, designed
    /// for UI feedback. If a future iOS release renumbers it (it
    /// hasn't since iOS 4), a silent play is the worst case.
    private static let scannedSoundID: SystemSoundID = 1057

    static func playScanned() {
        AudioServicesPlaySystemSound(scannedSoundID)
    }
}

// MARK: - Settings screen

struct SettingsScreen: View {
    @AppStorage(ScanSettingsKey.hapticOnScan)   private var hapticOnScan: Bool   = true
    @AppStorage(ScanSettingsKey.soundOnScan)    private var soundOnScan: Bool    = false
    @AppStorage(ScanSettingsKey.continuousScan) private var continuousScan: Bool = false

    /// Whether the user is currently signed into iCloud at the system
    /// level. `ubiquityIdentityToken` returning non-nil is the
    /// canonical Apple-recommended check — the token's value is
    /// opaque and only useful for equality, but presence ⇒ "signed
    /// in to *some* iCloud account on this device".
    ///
    /// We don't check whether *our* CloudKit container is reachable —
    /// that would require an async `CKContainer.accountStatus` call,
    /// and a Settings row that reads "checking…" half the time is
    /// strictly worse than a row that reads "signed in" or
    /// "signed out" instantly.
    private var iCloudIsActive: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private var iCloudStatusLabel: String {
        iCloudIsActive ? "Signed in" : "Signed out"
    }

    /// Cached marketing version pulled from `Info.plist`. Falls back to
    /// the empty string if the key is missing — should never happen in a
    /// shipping build, but `?? ""` keeps SwiftUI from crashing previews.
    private var versionString: String {
        let dict = Bundle.main.infoDictionary
        let marketing = dict?["CFBundleShortVersionString"] as? String ?? ""
        let build     = dict?["CFBundleVersion"] as? String ?? ""
        if marketing.isEmpty && build.isEmpty { return "—" }
        return "\(marketing) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $hapticOnScan) {
                    Label("Haptic on scan", systemImage: "iphone.radiowaves.left.and.right")
                }
                Toggle(isOn: $soundOnScan) {
                    Label("Sound on scan", systemImage: "speaker.wave.2.fill")
                }
                Toggle(isOn: $continuousScan) {
                    Label("Continuous scanning", systemImage: "viewfinder.rectangular")
                }
            } header: {
                Text("Feedback")
            } footer: {
                Text("Continuous scanning suppresses the result sheet — recognised codes save straight to History and a banner shows the latest one. Tap the banner to open it.")
            }

            Section {
                Button {
                    ScanSound.playScanned()
                    if hapticOnScan {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                } label: {
                    Label("Test feedback", systemImage: "play.circle")
                }
            } footer: {
                Text("Plays the scan sound (if enabled) and fires the success haptic, so you can compare the two.")
            }

            Section {
                LabeledContent("iCloud sync") {
                    Text(iCloudStatusLabel)
                        .foregroundStyle(iCloudIsActive ? .green : .secondary)
                }
                if !iCloudIsActive {
                    Text("Sign in to iCloud in Settings → [Your Name] → iCloud and turn on iCloud Drive to sync your scan history across devices.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Sync")
            } footer: {
                Text("Scan history is stored locally and replicated through your iCloud account via Apple's CloudKit. Nothing leaves the device when iCloud is off; nothing leaves the user's iCloud silo when it's on.")
            }

            Section {
                LabeledContent("Version", value: versionString)
                Link("Source on GitHub", destination: URL(string: "https://github.com/nettrash/Scan")!)
                Link("Privacy policy",   destination: URL(string: "https://nettrash.me/appstore/scan/privacy.html")!)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
struct SettingsScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { SettingsScreen() }
    }
}
#endif
