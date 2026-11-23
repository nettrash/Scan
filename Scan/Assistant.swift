//
//  Assistant.swift
//  Scan
//
//  The "explain this code" and "describe the code" helpers, run entirely on
//  the device.
//
//  Scan's whole product promise is that nothing you scan leaves the phone,
//  so the assistant has to honour that: it is built on Apple's on-device
//  `FoundationModels` (`SystemLanguageModel.default`, Apple Intelligence),
//  and when that model is not present — older hardware, Apple Intelligence
//  turned off, model still downloading — it falls back to a deterministic
//  explainer assembled from the parser's own metadata. Either way there is
//  no network call, no API key, no account, and nothing to leak. The
//  framework's Private Cloud Compute model is deliberately never used: it
//  runs on Apple's servers, and a scanned payload must not go there.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Model

/// What the assistant says about a code. Plain value type so the heuristic
/// fallback and the model-produced answer share one UI.
struct AssistantExplanation: Equatable {
    var headline: String
    var summary: String
    var keyPoints: [String]
    var cautions: [String]
    /// Which engine produced this — surfaced in the UI so the user knows
    /// whether they got the language model or the built-in explainer.
    var source: Source

    enum Source: String, Equatable {
        case onDeviceModel = "Apple Intelligence (on device)"
        case builtIn       = "Built-in explainer"
    }
}

enum AssistantAvailability: Equatable {
    /// The on-device model is ready to answer.
    case ready
    /// The model exists on this device but is not usable yet; `reason` is
    /// what the user can do about it, phrased to follow "once it is ready".
    case needsSetup(reason: String)
    /// No on-device model on this hardware / OS — the built-in explainer
    /// still works, so the feature is never hidden entirely.
    case unavailable

    /// What this device can do right now. Cheap and synchronous, so the
    /// Settings status line can call it while rendering; the system model is
    /// `Observable`, so a view that reads this updates when the model
    /// finishes downloading.
    static func current() -> AssistantAvailability {
        #if canImport(FoundationModels)
        // `Availability` is frozen; `UnavailableReason` is not, so the final
        // `.unavailable` arm catches any reason a later OS adds.
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ready
        case .unavailable(.deviceNotEligible):
            // No model on this hardware: that is "built-in explainer", not
            // something the user can set up.
            return .unavailable
        case .unavailable(.appleIntelligenceNotEnabled):
            return .needsSetup(reason: "turn on Apple Intelligence in Settings")
        case .unavailable(.modelNotReady):
            return .needsSetup(reason: "the model is still downloading")
        case .unavailable:
            return .needsSetup(reason: "Apple Intelligence is still setting up")
        }
        #else
        return .unavailable
        #endif
    }
}

// MARK: - Assistant

enum ScanAssistant {

    /// The Settings → Insights default. On, like the safety check: both
    /// engines are local, so there is no consent question to answer first,
    /// and the Android port defaults the same way.
    static let defaultEnabled = true

    /// The user's Settings → Insights switch. Off hides the Explain button
    /// and the "describe the code" box, and keeps the language model out of
    /// everything else (a Shortcut still gets the built-in explainer).
    static var isEnabled: Bool {
        let key = ScanSettingsKey.assistantEnabled
        if UserDefaults.standard.object(forKey: key) == nil { return defaultEnabled }
        return UserDefaults.standard.bool(forKey: key)
    }

    /// How long a language-model answer may take before the built-in one is
    /// shown instead. A runaway generation once kept "Thinking on the
    /// device…" up for four minutes; the built-in answer is ready at once.
    static let modelDeadline: Duration = .seconds(10)

    /// Explain a decoded code in plain language. Never throws: the worst
    /// case is the built-in explainer.
    static func explain(raw: String, payload: ScanPayload?) async -> AssistantExplanation {
        let parsed = payload ?? ScanPayloadParser.parse(raw)
        let fallback = HeuristicExplainer.explain(raw: raw, payload: parsed)
        guard isEnabled, AssistantAvailability.current() == .ready else { return fallback }
        #if canImport(FoundationModels)
        return await explain(raw: raw, fallback: fallback, model: { await appleIntelligenceExplanation($0) })
        #else
        return fallback
        #endif
    }

    /// The model half of `explain`, with the model passed in so a test can
    /// stand in for it. The model gets `modelDeadline`; its words replace the
    /// built-in headline, summary and key points, but the cautions stay the
    /// built-in ones — the tested safety rules, not something the model
    /// imagined about an ordinary code.
    static func explain(raw: String, fallback: AssistantExplanation, model: @escaping ExplainModel,
                        deadline: Duration = modelDeadline) async -> AssistantExplanation {
        let prompt = explainPrompt(raw: raw, fallback: fallback)
        guard let draft = await answer(within: deadline, { await model(prompt) }) else { return fallback }
        let summary = trimmed(draft.summary, limit: 700)
        guard isUsable(summary) else { return fallback }
        let headline = trimmed(draft.headline, limit: 80)
        let points = draft.keyPoints.map { trimmed($0, limit: 160) }.filter(isUsable).prefix(6)
        return AssistantExplanation(
            headline: isUsable(headline) ? headline : fallback.headline,
            summary: summary,
            keyPoints: points.isEmpty ? fallback.keyPoints : Array(points),
            cautions: fallback.cautions,
            source: .onDeviceModel)
    }

    /// Turn a sentence typed into the Generate tab into a filled-in form.
    /// Nil when neither engine understood it, so the form stays as the user
    /// left it rather than guessing.
    static func compose(request: String) async -> ComposeResult? {
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        #if canImport(FoundationModels)
        if isEnabled, AssistantAvailability.current() == .ready,
           let composed = await answer(within: modelDeadline, { await modelCompose(request: trimmed) }) {
            return composed
        }
        #endif
        return HeuristicExplainer.compose(request: trimmed)
    }

    // MARK: Model seam

    /// A language model as `explain` sees it: the prompt in, a draft out,
    /// nil for no answer. Apple Intelligence in the app; a stand-in in tests.
    typealias ExplainModel = @Sendable (String) async -> ModelDraft?

    /// What a model wrote about a code, before Scan's own checks.
    struct ModelDraft: Equatable, Sendable {
        var headline: String
        var summary: String
        var keyPoints: [String]
    }

    /// The prompt: what the parser already established, then the payload
    /// with every credential blanked, cut to about 500 characters — the
    /// parser's facts already carry what matters, and a long payload only
    /// gives a small model more to wander through. The parser's facts keep
    /// a small model from mistaking a payment string for prose.
    static func explainPrompt(raw: String, fallback: AssistantExplanation) -> String {
        var lines = ["Scan's parser recognised this as: \(fallback.headline)."]
        if !fallback.keyPoints.isEmpty {
            lines.append("Facts the parser read from it:")
            lines += fallback.keyPoints.map { "- " + SecretRedaction.redactForModel($0) }
        }
        lines.append("The scanned payload, with credentials removed:")
        lines.append(trimmed(SecretRedaction.redactForModel(raw), limit: 500))
        return lines.joined(separator: "\n")
    }

    /// `work`'s answer, or nil once `limit` has passed — whichever comes
    /// first. The loser is cancelled but never waited for, so a model call
    /// that ignores cancellation cannot hold the caller past the deadline;
    /// cancelling the caller (the result sheet went away) ends the wait too.
    static func answer<T: Sendable>(within limit: Duration,
                                    _ work: @escaping @Sendable () async -> T?) async -> T? {
        let race = FirstAnswer<T>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                race.wait(continuation)
                race.track(Task { race.settle(await work()) })
                race.track(Task {
                    try? await Task.sleep(for: limit)
                    race.settle(nil)
                })
            }
        } onCancel: {
            race.settle(nil)
        }
    }

    // MARK: Output hygiene

    private static func trimmed(_ text: String, limit: Int) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.count <= limit ? cleaned : String(cleaned.prefix(limit)) + "…"
    }

    /// A model line that only parrots a redaction marker says nothing.
    private static func isUsable(_ line: String) -> Bool {
        !line.isEmpty
            && !line.contains(SecretRedaction.placeholder)
            && !line.contains(SecretRedaction.blobPlaceholder)
            && !line.contains(SecretRedaction.seedPhrasePlaceholder)
    }

    /// The model is told to copy names, passwords and links verbatim; this
    /// holds it to that. A value is kept only if it occurs in the request,
    /// and it is returned as the request spells it — an SSID or a password
    /// with one letter's case changed would build a code that does not work.
    private static func verbatim(_ value: String, in request: String) -> String? {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty,
              let range = request.range(of: candidate, options: [.caseInsensitive]) else { return nil }
        return String(request[range])
    }

    /// A link the request spelled with or without its scheme.
    private static func verbatimLink(_ value: String, in request: String) -> String? {
        if let exact = verbatim(value, in: request), exact.contains("://") { return exact }
        var bare = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for scheme in ["https://", "http://"] where bare.lowercased().hasPrefix(scheme) {
            bare = String(bare.dropFirst(scheme.count))
        }
        guard bare.contains("."), let written = verbatim(bare, in: request) else { return nil }
        return "https://" + written
    }
}

/// The race behind `ScanAssistant.answer(within:_:)`: the first of the work,
/// the timer and a cancellation to settle resumes the caller, once, and
/// cancels the rest.
private final class FirstAnswer<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?
    private var settled = false
    private var tasks: [Task<Void, Never>] = []

    /// Parks the caller — or resumes it at once when a cancellation got
    /// here first.
    func wait(_ continuation: CheckedContinuation<T?, Never>) {
        let alreadySettled = lock.withLock {
            if !settled { self.continuation = continuation }
            return settled
        }
        if alreadySettled { continuation.resume(returning: nil) }
    }

    func track(_ task: Task<Void, Never>) {
        let alreadySettled = lock.withLock {
            if !settled { tasks.append(task) }
            return settled
        }
        if alreadySettled { task.cancel() }
    }

    func settle(_ value: T?) {
        let (waiting, running): (CheckedContinuation<T?, Never>?, [Task<Void, Never>]) = lock.withLock {
            guard !settled else { return (nil, []) }
            settled = true
            defer { continuation = nil; tasks = [] }
            return (continuation, tasks)
        }
        running.forEach { $0.cancel() }
        waiting?.resume(returning: value)
    }
}

// MARK: - Apple Intelligence

#if canImport(FoundationModels)

extension ScanAssistant {

    private static let explainInstructions = """
        You explain what a scanned QR code or barcode is to an ordinary person. \
        Use only the facts you are given: the payload and what Scan's parser \
        recognised in it. Be concrete and brief. Never invent data that is not \
        there, never tell the person to visit a website or contact anyone, and \
        never repeat anything shown as <redacted>.
        """

    private static let composeInstructions = """
        You fill in the form for a QR code from a short request. Pick the kind \
        that matches what the person asked for. Copy network names, passwords, \
        names, phone numbers, email addresses and links exactly as the request \
        writes them, keeping their capitalisation. Leave a field empty when the \
        request does not give it; never make one up.
        """

    /// Apple Intelligence as an `ExplainModel`. One fresh session per
    /// question: nothing from an earlier code is in the transcript when the
    /// next one is explained. The answer is capped at 400 tokens — a
    /// headline, a few sentences and short points fit well inside that, and
    /// a credential request once ran on for minutes without a cap.
    fileprivate static func appleIntelligenceExplanation(_ prompt: String) async -> ModelDraft? {
        let session = LanguageModelSession(instructions: explainInstructions)
        guard let content = try? await session.respond(
            to: prompt,
            generating: ModelExplanation.self,
            options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 400)).content else { return nil }
        return ModelDraft(headline: content.headline, summary: content.summary, keyPoints: content.keyPoints)
    }

    /// The request is the user's own typing — it has to reach the model for
    /// the model to copy the password out of it — and it goes to the local
    /// model only, in a session that is thrown away afterwards. The form is
    /// capped at 300 tokens, and `compose` gives it `modelDeadline`.
    fileprivate static func modelCompose(request: String) async -> ComposeResult? {
        let session = LanguageModelSession(instructions: composeInstructions)
        guard let form = try? await session.respond(
            to: "Build a code for: \(request)",
            generating: ModelComposeForm.self,
            options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 300)).content,
              let kind = ComposeKind(rawValue: form.kind.lowercased()) else { return nil }

        var values: [String: String] = [:]
        switch kind {
        case .wifi:
            values["ssid"] = verbatim(form.ssid, in: request)
            values["password"] = verbatim(form.password, in: request)
            switch form.security {
            case "WPA", "WPA3", "WEP": values["security"] = form.security
            case "none":               values["security"] = "NOPASS"
            default:                   break
            }
            if form.hidden, request.range(of: "hidden", options: .caseInsensitive) != nil {
                values["hidden"] = "true"
            }
            guard values["ssid"] != nil else { return nil }
            return ComposeResult(kind: .wifi, values: values, text: "", source: .onDeviceModel)

        case .contact:
            values["name"] = verbatim(form.name, in: request)
            values["phone"] = verbatim(form.phone, in: request)
            values["email"] = verbatim(form.email, in: request)
            values["org"] = verbatim(form.organization, in: request)
            guard !values.isEmpty else { return nil }
            return ComposeResult(kind: .contact, values: values, text: "", source: .onDeviceModel)

        case .url:
            guard let link = verbatimLink(form.text, in: request) else { return nil }
            return ComposeResult(kind: .url, values: [:], text: link, source: .onDeviceModel)

        case .text:
            guard let text = verbatim(form.text, in: request) else { return nil }
            return ComposeResult(kind: .text, values: [:], text: text, source: .onDeviceModel)

        case .email, .phone, .payment, .product:
            // Not offered to the model (see `ModelComposeForm.kind`).
            return nil
        }
    }
}

// MARK: Generable shapes

@Generable
struct ModelExplanation {
    @Guide(description: "At most six words naming the code, e.g. 'Wi-Fi login for a home router'")
    var headline: String
    @Guide(description: "Two or three plain sentences saying what this code does when scanned")
    var summary: String
    @Guide(description: "Short facts taken only from the payload and the parser's facts",
           .maximumCount(5))
    var keyPoints: [String]
}

/// One flat form rather than free-form name/value pairs: a small model fills
/// named fields far more reliably than it invents matching keys. `kind` only
/// offers what the Generate tab can build.
@Generable
struct ModelComposeForm {
    @Guide(description: "wifi for a Wi-Fi login, contact for a person or business card, url for a web link, text for anything else",
           .anyOf(["text", "url", "wifi", "contact"]))
    var kind: String
    @Guide(description: "The Wi-Fi network name exactly as written, or empty")
    var ssid: String
    @Guide(description: "The Wi-Fi password exactly as written, or empty")
    var password: String
    @Guide(description: "The Wi-Fi security the request names; unspecified when it does not say",
           .anyOf(["unspecified", "WPA", "WPA3", "WEP", "none"]))
    var security: String
    @Guide(description: "True only when the request says the network is hidden")
    var hidden: Bool
    @Guide(description: "The contact's full name exactly as written, or empty")
    var name: String
    @Guide(description: "The contact's phone number exactly as written, or empty")
    var phone: String
    @Guide(description: "The contact's email address exactly as written, or empty")
    var email: String
    @Guide(description: "The contact's company or organisation exactly as written, or empty")
    var organization: String
    @Guide(description: "For url: the link. For text: the exact text to put in the code. Otherwise empty")
    var text: String
}

#endif
