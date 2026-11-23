//
//  AssistantView.swift
//  Scan
//
//  UI for the on-device helpers: "What is this code?", "Translate", and the
//  Generate tab's "describe the code" box. All of them are lazy — nothing
//  runs until asked — and all of them say which engine answered, because
//  "the AI did it" is not a useful answer when the model was not even on the
//  device.
//
//  These views sit inside `Form` rows, where SwiftUI fires every
//  default-styled button in a row on any tap; each button that shares a row
//  with another is `.borderless` for that reason.
//

import SwiftUI
import UIKit
#if canImport(Translation)
import Translation
#endif

// MARK: - Explain

struct AssistantExplainButton: View {
    let raw: String
    let payload: ScanPayload

    /// The request and its answer, held by the row's state: the answer
    /// survives the row scrolling out of sight, and a request still running
    /// when the result sheet goes away is cancelled with it.
    @State private var request = ExplainRequest()

    var body: some View {
        if let explanation = request.explanation {
            ExplainCard(explanation: explanation)
        } else {
            Button {
                request.start(raw: raw, payload: payload)
            } label: {
                Label(request.isWorking ? "Thinking on the device…" : "What is this code?",
                      systemImage: "sparkles")
            }
            .disabled(request.isWorking)
        }
    }
}

/// One "What is this code?" request. The task holds it only weakly, so when
/// SwiftUI lets go of the row's state — the sheet was dismissed — the
/// request is released and its deinit cancels the work, instead of an
/// abandoned model call queueing in front of the next code's explanation.
@Observable
private final class ExplainRequest {
    private(set) var explanation: AssistantExplanation?
    private(set) var isWorking = false
    @ObservationIgnored private var task: Task<Void, Never>?

    @MainActor
    func start(raw: String, payload: ScanPayload) {
        guard !isWorking, explanation == nil else { return }
        isWorking = true
        task = Task { [weak self] in
            let answer = await ScanAssistant.explain(raw: raw, payload: payload)
            self?.finish(with: answer)
        }
    }

    @MainActor
    private func finish(with answer: AssistantExplanation) {
        explanation = answer
        isWorking = false
    }

    deinit { task?.cancel() }
}

private struct ExplainCard: View {
    let explanation: AssistantExplanation
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(.tint)
                Text(explanation.headline).font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }
            Text(explanation.summary)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            if !explanation.keyPoints.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(explanation.keyPoints.enumerated()), id: \.offset) { _, point in
                        // Wrapped, never cut to one line with "…": the
                        // points are what the card is for.
                        Label(point, systemImage: "circle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            ForEach(Array(explanation.cautions.enumerated()), id: \.offset) { _, caution in
                Label(caution, systemImage: "exclamationmark.shield")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text(explanation.source.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(copied ? "Copied" : "Copy") {
                    UIPasteboard.general.string =
                        "\(explanation.headline)\n\(explanation.summary)"
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        copied = false
                    }
                }
                .font(.caption2)
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Translate

/// Translate action + the result, as one row. The target is the Settings →
/// Insights language (the device language unless the user picked another),
/// like the Android port. Renders nothing where translation is unavailable
/// — a build without the framework, or the iPad app on Vision Pro.
struct TranslateRow: View {
    let text: String

    var body: some View {
        #if canImport(Translation)
        if ScanTranslator.isSupportedHere {
            TranslateRowContent(text: text)
        }
        #else
        EmptyView()
        #endif
    }
}

#if canImport(Translation)

private struct TranslateRowContent: View {
    let text: String

    @AppStorage(ScanSettingsKey.translateLanguage) private var storedLanguage = TranslationCatalog.systemTag
    /// Setting this (or invalidating it) runs `.translationTask` below. The
    /// session it hands over may download a missing language pack, and the
    /// system asks the user before it does.
    @State private var configuration: TranslationSession.Configuration?
    @State private var isWorking = false
    @State private var translation: String?
    @State private var errorText: String?

    /// "Device language" resolves against what this device can translate
    /// into, so a Czech phone's default is its next language or English —
    /// Apple's Translation has no Czech to translate into.
    private var target: TranslateLanguage {
        TranslationCatalog.language(forStored: storedLanguage, supported: TranslationTargets.shared.supported)
    }
    private var source: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "globe").foregroundStyle(.tint)
                Button(isWorking ? "Translating to \(target.label)…" : "Translate to \(target.label)") {
                    Task { await start() }
                }
                .buttonStyle(.borderless)
                .disabled(isWorking || source.isEmpty)
                Spacer(minLength: 0)
                if isWorking { ProgressView().controlSize(.small) }
            }

            if let translation {
                TranslationResultView(translation: translation)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .translationTask(configuration) { session in
            await translate(using: session)
        }
        .task { await TranslationTargets.shared.load() }
        .alert("Translation unavailable",
               isPresented: Binding(
                   get: { errorText != nil },
                   set: { if !$0 { errorText = nil } }),
               presenting: errorText) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    /// Checks what can be checked up front — the text is not already in the
    /// target language, the pair exists at all — then hands over to the
    /// system session.
    private func start() async {
        guard !isWorking, !source.isEmpty else { return }
        translation = nil
        // A tap before the system has listed its languages: ask now, so the
        // device-language default is one this device can produce.
        if storedLanguage == TranslationCatalog.systemTag, TranslationTargets.shared.supported == nil {
            isWorking = true
            await TranslationTargets.shared.load()
            isWorking = false
        }
        let target = self.target
        let targetLanguage = target.localeLanguage
        let detected = TranslationCatalog.detectedLanguage(of: source)
        if let detected, TranslationCatalog.isSameLanguage(detected, targetLanguage) {
            errorText = "This text is already in \(target.label)."
            return
        }
        isWorking = true
        if await ScanTranslator.status(of: source, from: detected, to: targetLanguage) == .unsupported {
            isWorking = false
            errorText = ScanTranslator.Failure.notAvailable.errorDescription
            return
        }
        let next = TranslationSession.Configuration(source: detected, target: targetLanguage)
        if configuration == next {
            configuration?.invalidate()
        } else {
            configuration = next
        }
    }

    private func translate(using session: TranslationSession) async {
        // `.translationTask` also re-runs when the row scrolls back into
        // view; only a tap on Translate (which sets `isWorking`) translates.
        guard isWorking else { return }
        defer { isWorking = false }
        do {
            let output = try await session.translate(source).targetText
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !output.isEmpty else {
                errorText = ScanTranslator.Failure.nothingToTranslate.errorDescription
                return
            }
            translation = output
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch is CancellationError {
            // The row went away mid-translation; there is nobody to tell.
        } catch {
            errorText = ScanTranslator.message(for: error)
        }
    }
}

#endif

/// The translated text, rendered under the fields it came from.
struct TranslationResultView: View {
    let translation: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Translation", systemImage: "globe")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(copied ? "Copied" : "Copy") {
                    UIPasteboard.general.string = translation
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        copied = false
                    }
                }
                .font(.caption2)
                .buttonStyle(.borderless)
            }
            Text(translation)
                .font(.footnote)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(.quaternary.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Describe the code (Generate tab)

/// The Generate tab's "describe the code" box: a sentence in, a filled-in
/// form out. A `Section`, so it drops straight into the Generate `Form`;
/// the form applies the result through `onResult` (`ComposeResult`
/// documents the field names). Hidden when the assistant is switched off in
/// Settings → Insights.
struct AssistantComposeBox: View {
    /// Receives a request one of the engines understood, and answers whether
    /// the form could use it — an empty answer gets the same "couldn't tell"
    /// note as no answer at all, as on Android.
    let onResult: @MainActor (ComposeResult) -> Bool

    @AppStorage(ScanSettingsKey.assistantEnabled) private var assistantEnabled = ScanAssistant.defaultEnabled
    @State private var request = ""
    @State private var isWorking = false
    @State private var note: String?

    private var trimmedRequest: String {
        request.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        if assistantEnabled {
            Section {
                TextField("Wi-Fi for network BlueHouse, password hunter2",
                          text: $request, axis: .vertical)
                    .lineLimit(1...3)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button {
                    Task { await run() }
                } label: {
                    Label(isWorking ? "Filling in the form…" : "Fill in the form",
                          systemImage: "sparkles")
                }
                .disabled(isWorking || trimmedRequest.isEmpty)
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Describe the code")
            } footer: {
                Text("Understood on this device — nothing you type is sent anywhere. Check the filled-in fields before you share the code.")
            }
        }
    }

    private func run() async {
        guard !isWorking, !trimmedRequest.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        guard let result = await ScanAssistant.compose(request: trimmedRequest),
              onResult(result) else {
            note = "Scan couldn't tell what to build from that. Start with the kind of code: \u{201C}wifi …\u{201D}, \u{201C}contact for …\u{201D}, a link, or \u{201C}text …\u{201D}."
            return
        }
        note = result.source == .onDeviceModel
            ? "Filled in by Apple Intelligence on this device."
            : "Filled in by the built-in assistant."
    }
}
