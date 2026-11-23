//
//  ScanIntents.swift
//  Scan
//
//  App Intents (1.10): the surface Shortcuts, Siri, Spotlight and the Action
//  button use to reach Scan without going through its screens. They are
//  declared in the app target itself, so there is no extension to keep in
//  step: every intent runs in-process against the same parser, history
//  store, generator and on-device assistant the buttons use — which is also
//  what keeps them inside the privacy promise. Nothing here makes a network
//  request, and nothing a code contains is sent anywhere.
//
//  The set is small on purpose. An intent is a promise to someone who is
//  not looking at the screen, so each one does one complete job:
//
//    Start Scanning    opens the camera, in Codes, Live Text or Bulk mode
//    Explain Code      the "Explain this code" answer, as text
//    Generate Code     a QR / Aztec / PDF417 / Code 128 image
//    Copy Recent Scan  the newest History entry, on the clipboard
//
//  Three traps worth knowing before editing anything here. All of them end
//  the same way — the app builds, and every action silently disappears from
//  Shortcuts, Siri and Spotlight — so check the built app still contains
//  `Metadata.appintents/extract.actionsdata` after any change:
//
//  - Every App Shortcut phrase must contain `\(.applicationName)`. A phrase
//    without it makes the build's App Intents metadata extraction fail, and
//    the target then exports no metadata at all.
//  - The app target has to build with `LM_SKIP_METADATA_EXTRACTION = NO`.
//    The project sets YES so the extension and test targets, which have no
//    intents, build without a "metadata extraction skipped" warning; the app
//    target must override it, or the extraction never runs.
//  - Titles, descriptions and display representations are read at build
//    time by that same extraction, so they have to stay compile-time
//    literals — no computed strings, no shared constants.
//

import AppIntents
import CoreData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Start Scanning

/// Brings Scan to the front on the camera. The cheapest thing an intent can
/// do, and the one people actually say out loud ("scan a code with Scan").
struct StartScanningIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Scanning"
    // Typed as the optional the protocol declares: a non-optional
    // `IntentDescription` compiles cleanly but does not satisfy the
    // requirement, so the system would see no description at all.
    static let description: IntentDescription? = IntentDescription(
        "Opens Scan on the camera, ready to read a barcode or QR code, read printed text with Live Text, or collect a whole batch of codes in Bulk mode.",
        searchKeywords: ["barcode", "QR code", "camera", "scanner"])
    /// The whole job is the camera on screen, so the app comes forward
    /// before `perform()` runs.
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Mode",
               description: "Codes reads barcodes and QR codes, Live Text reads printed text, and Bulk keeps collecting every distinct code it sees.",
               default: .codes)
    var mode: ScanModeOption

    static var parameterSummary: some ParameterSummary {
        Summary("Start scanning in \(\.$mode) mode")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let requested = mode.scanMode
        let resolved = Self.resolvedMode(for: mode, isAvailable: ScanMode.isAvailable)
        // Through `ScanMode`'s own stored key — the one the Scan tab's
        // `@AppStorage` reads — so an already running camera switches mode
        // live, and this enum's raw values never reach UserDefaults.
        ScanMode.store(resolved)
        // Brings the Scan tab forward and clears whatever covers its camera.
        ScanIntentRouter.shared.showScanner()

        if Platform.isVisionOS {
            // Vision Pro does not give apps its cameras, so the Scan tab is
            // the import screen there.
            return .result(dialog: "Vision Pro doesn't share its cameras with apps, so pick a photo or PDF that contains the code.")
        }
        if resolved != requested {
            return .result(dialog: "Live Text isn't available on this device, so Scan opened in Codes mode.")
        }
        // The footnote the Scan tab shows under the mode picker, so Siri and
        // the screen say the same thing.
        return .result(dialog: "\(resolved.footnote)")
    }

    /// The mode Start Scanning opens. Live Text needs VisionKit's scanner,
    /// which Mac Catalyst, Vision Pro and older hardware do not have, and
    /// storing a mode the Scan tab cannot show would leave its mode menu
    /// with nothing selected — so it falls back to Codes, and `perform()`
    /// says so rather than pretend.
    @MainActor
    static func resolvedMode(for option: ScanModeOption,
                             isAvailable: @MainActor (ScanMode) -> Bool) -> ScanMode {
        let requested = option.scanMode
        return isAvailable(requested) ? requested : .codes
    }
}

/// The Scan tab's three modes as Shortcuts and Siri see them. Kept separate
/// from `ScanMode` because an `AppEnum`'s titles must be compile-time literals
/// for the metadata extraction, and its raw values are stored in people's
/// saved shortcuts — they must not change when an in-app label does. Those
/// raw values belong to Shortcuts alone: the app maps each case to a
/// `ScanMode` explicitly (`scanMode`) and persists that.
enum ScanModeOption: String, AppEnum {
    case codes
    case text
    case bulk

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Scan Mode"
    // Titles match the Scan tab's mode menu; the symbols are `ScanMode.symbol`
    // spelled out, because a literal is the only thing the extraction reads.
    static let caseDisplayRepresentations: [ScanModeOption: DisplayRepresentation] = [
        .codes: DisplayRepresentation(title: "Codes",
                                      image: .init(systemName: "qrcode.viewfinder"),
                                      synonyms: ["Barcode", "QR Code"]),
        .text: DisplayRepresentation(title: "Live Text",
                                     image: .init(systemName: "text.viewfinder"),
                                     synonyms: ["Text"]),
        .bulk: DisplayRepresentation(title: "Bulk",
                                     image: .init(systemName: "square.stack.3d.down.right.fill"),
                                     synonyms: ["Batch"]),
    ]

    var scanMode: ScanMode {
        switch self {
        case .codes: return .codes
        case .text:  return .text
        case .bulk:  return .bulk
        }
    }
}

/// Hands Start Scanning's "show the camera" to the views that can hide it:
/// `ContentView` takes down whatever any tab presented over the window and
/// selects the Scan tab, and `ScannerScreen` takes down its result sheet,
/// the bulk list, the Files picker, the recognised-text card and a frozen
/// frame — the intent's job is a live viewfinder, not a sheet over one.
///
/// The same shape as `DeepLinkDispatcher`, for the same reason: on a cold
/// launch the intent can run before `ContentView` is in the hierarchy, so the
/// request lives in a singleton the view observes rather than in the
/// environment. A counter rather than a flag, so asking twice in a row still
/// registers as a change — and a non-zero count tells a view that appears
/// afterwards that this launch came from the intent.
@MainActor
final class ScanIntentRouter: ObservableObject {
    static let shared = ScanIntentRouter()
    private init() {}

    @Published private(set) var scannerRequests = 0

    func showScanner() {
        scannerRequests += 1
    }
}

// MARK: - Explain Code

/// "Explain this code" as a Shortcuts step: the decoded text in, the
/// assistant's plain-language answer out. Same engine as the button on a
/// result — Apple's on-device model where there is one, the built-in
/// explainer everywhere else — so the answer never leaves the device.
struct ExplainCodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Explain Code"
    static let description: IntentDescription? = IntentDescription(
        "Explains in plain language what a QR code or barcode contains and what scanning it would do. Runs entirely on this device.",
        searchKeywords: ["what is this code", "QR code", "barcode", "safety"],
        resultValueName: "Explanation")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Code Contents",
               description: "The text the QR code or barcode decoded to.",
               // A payload is not prose: smart quotes, autocorrect or an
               // automatic capital would change what is being explained.
               inputOptions: String.IntentInputOptions(keyboardType: .default,
                                                       capitalizationType: .none,
                                                       multiline: true,
                                                       autocorrect: false,
                                                       smartQuotes: false,
                                                       smartDashes: false),
               requestValueDialog: "What does the code say?")
    var contents: String

    static var parameterSummary: some ParameterSummary {
        Summary("Explain \(\.$contents)")
    }

    // Main actor, as Copy Recent Scan: the parse can recurse deep into a
    // credential's nested JSON, and the main thread has the deep stack — a
    // Swift-concurrency pool thread has about 512 KB, which such a code
    // overran.
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let raw = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            throw $contents.needsValueError("What does the code say?")
        }
        let explanation = await ScanAssistant.explain(raw: raw,
                                                      payload: ScanPayloadParser.parse(raw))
        return .result(value: Self.transcript(of: explanation),
                       dialog: "\(Self.spoken(explanation))")
    }

    /// The returned text: everything the in-app explanation card shows, in
    /// the same order, ending with which engine answered.
    private static func transcript(of explanation: AssistantExplanation) -> String {
        var sections = ["\(explanation.headline)\n\(explanation.summary)"]
        if !explanation.keyPoints.isEmpty {
            sections.append(explanation.keyPoints.map { "• \($0)" }.joined(separator: "\n"))
        }
        if !explanation.cautions.isEmpty {
            sections.append(explanation.cautions.map { "Caution: \($0)" }.joined(separator: "\n"))
        }
        sections.append(explanation.source.rawValue)
        return sections.joined(separator: "\n\n")
    }

    /// What Siri says: the headline, the summary, and every caution — a
    /// warning is the one part a listener must not miss.
    private static func spoken(_ explanation: AssistantExplanation) -> String {
        ([sentence(explanation.headline), explanation.summary] + explanation.cautions)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func sentence(_ text: String) -> String {
        guard let last = text.last, !".!?…".contains(last) else { return text }
        return text + "."
    }
}

// MARK: - Generate Code

/// "Make a QR code for …" — renders the code with the same Core Image
/// generator and settings as the Generate tab's plain preview, and hands it
/// back as a PNG a shortcut can save, share or drop into a document.
struct GenerateCodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Generate Code"
    static let description: IntentDescription? = IntentDescription(
        "Makes a QR, Aztec, PDF417 or Code 128 image from text or a link, on this device.",
        searchKeywords: ["QR code", "barcode", "make", "create"],
        resultValueName: "Code Image")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Contents",
               description: "The text or link the code should hold.",
               inputOptions: String.IntentInputOptions(keyboardType: .default,
                                                       capitalizationType: .none,
                                                       multiline: true,
                                                       autocorrect: false,
                                                       smartQuotes: false,
                                                       smartDashes: false),
               requestValueDialog: "What should the code contain?")
    var contents: String

    @Parameter(title: "Symbology", default: .qr)
    var symbology: CodeSymbologyOption

    static var parameterSummary: some ParameterSummary {
        Summary("Generate \(\.$symbology) for \(\.$contents)")
    }

    // Main actor because the Siri snippet is a SwiftUI view; the render
    // itself is a few milliseconds of Core Image.
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog & ShowsSnippetView {
        // Surrounding whitespace is never what a shortcut means to encode —
        // a trailing newline from "Get Clipboard" would otherwise end up
        // inside the code.
        let text = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw $contents.needsValueError("What should the code contain?")
        }
        let target = symbology.generatable
        // Core Image fills Code 128 from ASCII only; refuse up front rather
        // than hand back a barcode that does not say what was asked.
        if target == .code128, !text.allSatisfy(\.isASCII) {
            throw ScanIntentError.code128NeedsASCII
        }
        guard let image = CodeGenerator.image(for: text, symbology: target, scale: 12),
              let png = image.pngData() else {
            throw ScanIntentError.doesNotFit(symbology)
        }
        let file = IntentFile(data: png, filename: symbology.filename, type: .png)
        // The dialog names the symbology, never the contents: Siri reads it
        // aloud, and the contents may be a Wi-Fi password.
        return .result(value: file,
                       dialog: "Here's your \(symbology.noun).",
                       view: GeneratedCodeSnippet(image: image))
    }
}

/// The symbologies Scan can generate, as Shortcuts sees them. Titles match
/// the Generate tab's picker (`GeneratableSymbology.rawValue`).
enum CodeSymbologyOption: String, AppEnum {
    case qr
    case aztec
    case pdf417
    case code128

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Symbology"
    static let caseDisplayRepresentations: [CodeSymbologyOption: DisplayRepresentation] = [
        .qr: DisplayRepresentation(title: "QR", synonyms: ["QR Code"]),
        .aztec: "Aztec",
        .pdf417: "PDF417",
        .code128: DisplayRepresentation(title: "Code 128", synonyms: ["Barcode"]),
    ]

    var generatable: GeneratableSymbology {
        switch self {
        case .qr:      return .qr
        case .aztec:   return .aztec
        case .pdf417:  return .pdf417
        case .code128: return .code128
        }
    }

    /// What the dialog and errors call the result.
    var noun: String {
        switch self {
        case .qr:      return "QR code"
        case .aztec:   return "Aztec code"
        case .pdf417:  return "PDF417 code"
        case .code128: return "Code 128 barcode"
        }
    }

    var filename: String {
        switch self {
        case .qr:      return "QR Code.png"
        case .aztec:   return "Aztec Code.png"
        case .pdf417:  return "PDF417.png"
        case .code128: return "Code 128.png"
        }
    }
}

/// What Siri shows under a generated code: the image itself, on white and at
/// a size another phone can scan straight off the screen. Nearest-neighbour
/// scaling, as in the Generate tab, so module edges stay sharp.
private struct GeneratedCodeSnippet: View {
    let image: UIImage

    var body: some View {
        Image(uiImage: image)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 240, maxHeight: 240)
            .padding(12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding()
            .accessibilityLabel("Generated code")
    }
}

// MARK: - Copy Recent Scan

/// The newest History entry, copied to the clipboard — what "the code I just
/// scanned" means in practice — and also returned, so a shortcut can pass it
/// on without touching the clipboard at all.
struct CopyRecentScanIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy Recent Scan"
    static let description: IntentDescription? = IntentDescription(
        "Copies the most recent code in your Scan history to the clipboard.",
        searchKeywords: ["last scan", "history", "clipboard"],
        resultValueName: "Recent Scan")
    static let supportedModes: IntentModes = .background
    /// History holds Wi-Fi passwords, 2FA enrolments and boarding passes; a
    /// locked phone must not hand them to whoever is holding it.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    // Main actor because it reads through the view context, which is a
    // main-queue context — the same store and context History lists from.
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let request: NSFetchRequest<ScanRecord> = ScanRecord.fetchRequest()
        request.predicate = NSPredicate(format: "value != nil AND value != %@", "")
        // Newest by scan time, deliberately ignoring History's favourites-
        // first order: "recent" means recent.
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ScanRecord.timestamp, ascending: false)]
        request.fetchLimit = 1
        let context = PersistenceController.shared.container.viewContext
        guard let record = try context.fetch(request).first, let value = record.value else {
            throw ScanIntentError.historyEmpty
        }
        UIPasteboard.general.string = value
        let symbology = Symbology(rawValue: record.symbology ?? "") ?? .unknown
        let kind = ScanPayloadParser.parse(value, symbology: symbology).kindLabel
        // Names the kind, never the contents: Siri reads the dialog aloud,
        // and the newest scan may well be a password.
        return .result(value: value, dialog: "Copied your most recent scan (\(kind)).")
    }
}

// MARK: - Errors

/// Failures worth explaining. Shortcuts and Siri show
/// `localizedStringResource` as the error text, so each case says what went
/// wrong and what to do instead.
enum ScanIntentError: Error, CustomLocalizedStringResourceConvertible {
    case historyEmpty
    case code128NeedsASCII
    case doesNotFit(CodeSymbologyOption)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .historyEmpty:
            return "There's nothing in your Scan history yet."
        case .code128NeedsASCII:
            return "Code 128 can only hold plain ASCII text. Choose QR for anything else."
        case .doesNotFit(let symbology):
            return "Couldn't fit that into one \(symbology.noun) — it's probably too long."
        }
    }
}

// MARK: - App Shortcuts

/// The phrases Siri and Spotlight offer with no setup. Every phrase names
/// `\(.applicationName)` — see the file header for why that is not optional.
/// "Scan a code" and "Generate a code" are also the Android port's launcher
/// shortcut labels; keep the two in step.
struct ScanAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartScanningIntent(),
            phrases: [
                "Scan a code with \(.applicationName)",
                "Start scanning with \(.applicationName)",
                "Start a \(\.$mode) scan in \(.applicationName)",
            ],
            shortTitle: "Scan a code",
            systemImageName: "qrcode.viewfinder")
        AppShortcut(
            intent: ExplainCodeIntent(),
            phrases: [
                "Explain a code with \(.applicationName)",
                "What is this code in \(.applicationName)",
            ],
            shortTitle: "Explain a code",
            systemImageName: "sparkles")
        AppShortcut(
            intent: GenerateCodeIntent(),
            phrases: [
                "Make a QR code with \(.applicationName)",
                "Generate a code with \(.applicationName)",
            ],
            shortTitle: "Generate a code",
            systemImageName: "qrcode")
        AppShortcut(
            intent: CopyRecentScanIntent(),
            phrases: [
                "Copy my last scan from \(.applicationName)",
                "Copy the latest \(.applicationName) scan",
            ],
            shortTitle: "Copy last scan",
            systemImageName: "doc.on.doc")
    }
}
