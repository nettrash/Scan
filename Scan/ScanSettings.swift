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
    /// 1.10 — the on-device assistant (Explain + "describe the code"). On by
    /// default (`ScanAssistant.defaultEnabled`); off hides both and keeps the
    /// language model out of everything else.
    static let assistantEnabled  = "settings.assistantEnabled"
    /// 1.10 — the QR safety inspector. Some users find the warnings noisy;
    /// switching them off hides the banner, never the raw payload.
    static let riskChecksEnabled = "settings.riskChecksEnabled"
    /// 1.10 — which camera mode the Scan tab opens in: codes, live text,
    /// or bulk capture. Stored as `ScanMode.storedValue` ("codes" / "text" /
    /// "bulk", the Android port's keys) and read back with
    /// `ScanMode(storedValue:)`.
    static let scanMode          = "settings.scanMode"
    /// 1.10 — target language for the Translate action: a BCP-47 tag from
    /// `TranslationCatalog.languages`, or `TranslationCatalog.systemTag`
    /// ("system") for the device language.
    static let translateLanguage = "settings.translateLanguage"
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
    @AppStorage(ScanSettingsKey.assistantEnabled)  private var assistantEnabled: Bool  = ScanAssistant.defaultEnabled
    @AppStorage(ScanSettingsKey.riskChecksEnabled) private var riskChecksEnabled: Bool = true
    @AppStorage(ScanSettingsKey.translateLanguage) private var translateLanguage: String = TranslationCatalog.systemTag

    /// Catalog languages this device can translate into, once the system has
    /// answered; until then (and if it never lists any) the whole catalog.
    @State private var translateTargets: [TranslateLanguage]?

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

    /// One honest line about which assistant engine this device will use.
    /// Reading the availability here keeps the line live: the system model
    /// is observable, so the text changes when its download finishes.
    private var assistantStatusLine: String {
        guard assistantEnabled else {
            return "The assistant is off, so results show no \u{201C}What is this code?\u{201D} button."
        }
        switch AssistantAvailability.current() {
        case .ready:
            return "Explain uses Apple Intelligence on this device."
        case .needsSetup(let reason):
            return "Explain uses Apple Intelligence once it is ready (\(reason)); until then the built-in explainer answers."
        case .unavailable:
            return "Explain uses the built-in explainer on this device."
        }
    }

    /// "Scan's own": the system's Look Up and Translate menu on selected
    /// Live Text is iOS's, not Scan's, and may use Apple's servers.
    private var insightsFooter: String {
        var text = "\(assistantStatusLine) Scan's own safety check, explanations"
        if ScanTranslator.isSupportedHere {
            text += " and translations run entirely on this device and never upload what you scan. A translation language may need a one-time download, which the system asks you about first."
        } else {
            text += " run entirely on this device and never upload what you scan."
        }
        return text
    }

    /// The picker's languages: what this device can produce, plus the
    /// current choice even if it is not among them, so the picker never
    /// holds a selection it has no row for.
    private var translatePickerLanguages: [TranslateLanguage] {
        var list = translateTargets ?? TranslationCatalog.languages
        if translateLanguage != TranslationCatalog.systemTag,
           !list.contains(where: { $0.identifier == translateLanguage }),
           let chosen = TranslationCatalog.languages.first(where: { $0.identifier == translateLanguage }) {
            list.append(chosen)
        }
        return list
    }

    private var deviceLanguageLabel: String {
        TranslationCatalog.deviceLanguageLabel(supported: translateTargets)
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
                Toggle(isOn: $assistantEnabled) {
                    Label("On-device assistant", systemImage: "sparkles")
                }
                Toggle(isOn: $riskChecksEnabled) {
                    Label("QR safety check", systemImage: "checkmark.shield")
                }
                if ScanTranslator.isSupportedHere {
                    Picker(selection: $translateLanguage) {
                        Text(deviceLanguageLabel).tag(TranslationCatalog.systemTag)
                        ForEach(translatePickerLanguages) { language in
                            Text(language.label).tag(language.identifier)
                        }
                    } label: {
                        Label("Translate to", systemImage: "globe")
                    }
                }
            } header: {
                Text("Insights")
            } footer: {
                Text(insightsFooter)
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
        .task { await loadTranslateTargets() }
    }

    /// Asks the system which catalog languages it can translate into, through
    /// the cache the Translate rows share. Only the question goes to the
    /// system — nothing the user scanned is in it.
    private func loadTranslateTargets() async {
        translateTargets = await TranslationTargets.shared.load()
    }
}

#if DEBUG
struct SettingsScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { SettingsScreen() }
    }
}
#endif
