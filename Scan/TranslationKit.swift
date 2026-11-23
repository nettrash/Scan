//
//  TranslationKit.swift
//  Scan
//
//  On-device translation for scanned text — menus, signs, foreign payment
//  instructions.
//
//  Built on Apple's `Translation` framework, which translates with the
//  system's on-device models. No text ever leaves the phone, which is the
//  whole reason this is the API we use: translating a scanned code through a
//  web service would mean shipping the user's surroundings to a third party.
//  The one thing that can be fetched is a *language pack*, by the system and
//  only after the user agrees in the system's own sheet — which is why the
//  result sheet translates through SwiftUI's `.translationTask` (the only
//  sanctioned way to show that consent) and the UI-less entry point below
//  works with installed packs only.
//
//  The catalog is the list both ports share; what the device can actually
//  produce comes from `LanguageAvailability` (`TranslationTargets`), so
//  Settings never offers a language that can only fail, and the "device
//  language" default skips one this device cannot produce — Apple's
//  Translation does not cover the whole catalog (no Czech, for one).
//

import Foundation
import NaturalLanguage
import Observation
#if canImport(Translation)
import Translation
#endif

/// One selectable language in the translate UI.
struct TranslateLanguage: Identifiable, Hashable {
    let identifier: String      // BCP-47, e.g. "sr-Latn"
    let label: String           // display name in English, like the rest of the UI

    var id: String { identifier }

    var localeLanguage: Locale.Language { Locale.Language(identifier: identifier) }
}

enum TranslationCatalog {

    /// The stored Settings value meaning "whatever language the phone is in".
    static let systemTag = "system"

    /// The target when nothing else matches.
    static let english = TranslateLanguage(identifier: "en", label: "English")

    /// Languages a barcode scanner realistically meets — including the app's
    /// own regional formats (Serbian, Czech, Slovak, Russian, German). Shared
    /// with the Android port; `ScanTranslator.supportedTargets()` narrows it
    /// to what this device's translation models can produce.
    static let languages: [TranslateLanguage] = [
        .init(identifier: "en",      label: "English"),
        .init(identifier: "de",      label: "German"),
        .init(identifier: "fr",      label: "French"),
        .init(identifier: "es",      label: "Spanish"),
        .init(identifier: "it",      label: "Italian"),
        .init(identifier: "pt-BR",   label: "Portuguese (Brazil)"),
        .init(identifier: "nl",      label: "Dutch"),
        .init(identifier: "pl",      label: "Polish"),
        .init(identifier: "cs",      label: "Czech"),
        .init(identifier: "sk",      label: "Slovak"),
        .init(identifier: "sr-Latn", label: "Serbian (Latin)"),
        .init(identifier: "hr",      label: "Croatian"),
        .init(identifier: "sl",      label: "Slovenian"),
        .init(identifier: "bs",      label: "Bosnian"),
        .init(identifier: "bg",      label: "Bulgarian"),
        .init(identifier: "ro",      label: "Romanian"),
        .init(identifier: "el",      label: "Greek"),
        .init(identifier: "hu",      label: "Hungarian"),
        .init(identifier: "ru",      label: "Russian"),
        .init(identifier: "uk",      label: "Ukrainian"),
        .init(identifier: "tr",      label: "Turkish"),
        .init(identifier: "ar",      label: "Arabic"),
        .init(identifier: "he",      label: "Hebrew"),
        .init(identifier: "hi",      label: "Hindi"),
        .init(identifier: "zh-Hans", label: "Chinese (Simplified)"),
        .init(identifier: "ja",      label: "Japanese"),
        .init(identifier: "ko",      label: "Korean"),
        .init(identifier: "id",      label: "Indonesian"),
        .init(identifier: "th",      label: "Thai"),
        .init(identifier: "vi",      label: "Vietnamese"),
    ]

    /// The language the user reads, used as the default target: the first of
    /// `preferred` (most preferred first) that is in the catalog and among
    /// `supported`, what this device can translate into — the whole catalog
    /// until the system has said. This walks `Locale.preferredLanguages`
    /// rather than reading `Locale.current`: Scan ships in English only, so
    /// `Locale.current` reports English even for someone whose phone is in
    /// German — exactly the person who wants a German translation. Nil when
    /// none of them qualifies; the caller falls back to English.
    static func deviceLanguage(preferred: [String] = Locale.preferredLanguages,
                               supported: [TranslateLanguage]? = nil) -> TranslateLanguage? {
        let candidates = supported ?? languages
        for identifier in preferred {
            if let entry = entry(for: Locale.Language(identifier: identifier)), candidates.contains(entry) {
                return entry
            }
        }
        return nil
    }

    /// The Settings value resolved to a language: "system" (or anything no
    /// longer in the catalog) means the device language, then English.
    static func language(forStored stored: String, supported: [TranslateLanguage]? = nil) -> TranslateLanguage {
        if stored != systemTag, let chosen = languages.first(where: { $0.identifier == stored }) {
            return chosen
        }
        return deviceLanguage(supported: supported) ?? english
    }

    /// Settings' name for the "system" choice: "Device language (German)",
    /// or, when the phone's own language is one this device cannot translate
    /// into, what is used instead and why — "Device language (English —
    /// Czech isn't available)". The Android port words it the same.
    static func deviceLanguageLabel(preferred: [String] = Locale.preferredLanguages,
                                    supported: [TranslateLanguage]?) -> String {
        let resolved = deviceLanguage(preferred: preferred, supported: supported) ?? english
        let first = preferred.lazy.compactMap { entry(for: Locale.Language(identifier: $0)) }.first
        if let first, first != resolved {
            return "Device language (\(resolved.label) \u{2014} \(first.label) isn't available)"
        }
        return "Device language (\(resolved.label))"
    }

    /// Free-text-ish payloads are the ones where a translation actually
    /// helps — a menu, a sign, a foreign payment reference. Text needs eight
    /// characters as a person counts them (a Swift `Character`), past white
    /// space; the Android port counts the same way.
    static func isTranslatable(_ payload: ScanPayload) -> Bool {
        switch payload {
        case .text(let t):           return t.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8
        case .url, .richURL:         return true
        case .email(_, _, let body): return body?.isEmpty == false
        default:                     return false
        }
    }

    /// The catalog entry for a system language: same script and region when
    /// the entry names one, otherwise the same language at all ("pt-PT"
    /// reads Brazilian Portuguese rather than falling back to English).
    static func entry(for language: Locale.Language) -> TranslateLanguage? {
        languages.first { matches($0, language) }
            ?? languages.first { $0.localeLanguage.languageCode == language.languageCode }
    }

    /// Whether a system language (e.g. one `LanguageAvailability` lists) is
    /// the catalog entry: same language, same script when the entry names
    /// one (zh-Hans ≠ zh-Hant), same region when both name one.
    static func matches(_ entry: TranslateLanguage, _ language: Locale.Language) -> Bool {
        let wanted = entry.localeLanguage
        guard let code = wanted.languageCode, code == language.languageCode else { return false }
        if let script = wanted.script, script != likelyScript(of: language) { return false }
        if let region = wanted.region, let other = language.region, region != other { return false }
        return true
    }

    /// Same language and script, whatever the region — "en-GB" text does not
    /// need translating into "en".
    static func isSameLanguage(_ a: Locale.Language, _ b: Locale.Language) -> Bool {
        a.languageCode != nil && a.languageCode == b.languageCode
            && likelyScript(of: a) == likelyScript(of: b)
    }

    /// The language `text` is written in, when NaturalLanguage is reasonably
    /// sure. Nil for text too short or too mixed to call — the translation
    /// session then identifies the language itself.
    static func detectedLanguage(of text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let best = recognizer.languageHypotheses(withMaximum: 1).max(by: { $0.value < $1.value }),
              best.key != .undetermined, best.value >= 0.5 else { return nil }
        return Locale.Language(identifier: best.key.rawValue)
    }

    /// "zh" is written in Hans and "sr" in Cyrl unless they say otherwise.
    private static func likelyScript(of language: Locale.Language) -> Locale.Script? {
        language.script ?? Locale.Language(identifier: language.maximalIdentifier).script
    }
}

/// The catalog languages this device can translate into, asked of the
/// system once per launch and shared by Settings and every Translate row.
/// Only the question goes to the system — nothing the user scanned is in it.
@MainActor @Observable
final class TranslationTargets {
    static let shared = TranslationTargets()

    /// Nil until the system has answered, and when it lists none.
    private(set) var supported: [TranslateLanguage]?
    private var loading: Task<[TranslateLanguage]?, Never>?

    /// Asks the system, once; later calls wait for that answer.
    @discardableResult
    func load() async -> [TranslateLanguage]? {
        if let supported { return supported }
        #if canImport(Translation)
        guard ScanTranslator.isSupportedHere else { return nil }
        let request = loading ?? Task {
            let targets = await ScanTranslator.supportedTargets()
            return targets.isEmpty ? nil : targets
        }
        loading = request
        supported = await request.value
        return supported
        #else
        return nil
        #endif
    }
}

// MARK: - Translator

enum ScanTranslator {

    enum Failure: LocalizedError {
        case notAvailable
        case needsDownload(String)
        case unknownSourceLanguage
        case nothingToTranslate

        var errorDescription: String? {
            switch self {
            case .notAvailable:
                return "This language pair isn't available on this device yet."
            case .needsDownload(let language):
                return "The \(language) language pack isn't downloaded yet. Translate any scanned text to \(language) once in Scan, and accept the download the system offers."
            case .unknownSourceLanguage:
                return "Scan couldn't tell which language this text is in."
            case .nothingToTranslate:
                return "Nothing to translate."
            }
        }
    }

    /// Whether this build and device offer translation at all. Apple marks
    /// the framework unavailable on visionOS, so the iPad app running on
    /// Vision Pro hides the row instead of showing a control that can only
    /// fail.
    @MainActor
    static var isSupportedHere: Bool {
        #if canImport(Translation)
        return !Platform.isVisionOS
        #else
        return false
        #endif
    }

    /// Translate `text` on device without any UI — for Shortcuts and other
    /// headless callers. `source` is the language the text is in; pass nil
    /// to detect it. Only installed language packs are used: downloading one
    /// needs the user's consent in a system sheet, which only a view can show
    /// (see `TranslateRow`), so a missing pack throws `.needsDownload`.
    static func translate(_ text: String,
                          from source: TranslateLanguage?,
                          to target: TranslateLanguage) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        #if canImport(Translation)
        let targetLanguage = target.localeLanguage
        guard let sourceLanguage = source?.localeLanguage
                ?? TranslationCatalog.detectedLanguage(of: trimmed) else {
            throw Failure.unknownSourceLanguage
        }
        // Already in the target language: the text is its own translation.
        if TranslationCatalog.isSameLanguage(sourceLanguage, targetLanguage) { return trimmed }

        let status = await LanguageAvailability().status(from: sourceLanguage, to: targetLanguage)
        if status == .supported { throw Failure.needsDownload(target.label) }
        guard status == .installed else { throw Failure.notAvailable }

        let session = TranslationSession(installedSource: sourceLanguage, target: targetLanguage)
        let translated = try await session.translate(trimmed).targetText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translated.isEmpty else { throw Failure.nothingToTranslate }
        return translated
        #else
        throw Failure.notAvailable
        #endif
    }

    #if canImport(Translation)
    /// How close translating `text` from `source` (nil: detect it) into
    /// `target` is to possible. Nil when the system could not say — usually
    /// because it could not identify the language — so the caller lets the
    /// session try and report the precise reason.
    static func status(of text: String,
                       from source: Locale.Language?,
                       to target: Locale.Language) async -> LanguageAvailability.Status? {
        let availability = LanguageAvailability()
        if let source { return await availability.status(from: source, to: target) }
        return try? await availability.status(for: text, to: target)
    }

    /// Catalog languages this device's translation models can produce.
    static func supportedTargets() async -> [TranslateLanguage] {
        let supported = await LanguageAvailability().supportedLanguages
        return TranslationCatalog.languages.filter { entry in
            supported.contains { TranslationCatalog.matches(entry, $0) }
        }
    }

    /// What to tell the user about an error a translation session threw.
    static func message(for error: Error) -> String {
        if let failure = error as? Failure { return failure.errorDescription ?? failure.localizedDescription }
        switch error {
        case Translation.TranslationError.unableToIdentifyLanguage:
            return Failure.unknownSourceLanguage.errorDescription ?? ""
        case Translation.TranslationError.unsupportedSourceLanguage,
             Translation.TranslationError.unsupportedTargetLanguage,
             Translation.TranslationError.unsupportedLanguagePairing:
            return Failure.notAvailable.errorDescription ?? ""
        case Translation.TranslationError.nothingToTranslate:
            return Failure.nothingToTranslate.errorDescription ?? ""
        default:
            return error.localizedDescription
        }
    }
    #endif
}
