//
//  GeneratorScreen.swift
//  Scan
//
//  Lets the user construct a 1D / 2D code from text, a URL, a contact, or
//  Wi-Fi credentials. Live preview, share sheet, save-to-Photos, copy.
//
//  In 1.3 the screen also exposes:
//   - foreground / background colour pickers (with a contrast warning),
//   - a logo image picker (QR only),
//   - SVG / PDF export alongside the existing PNG share path.
//
//  In 1.10 the QR art studio joins them (`QRStyle`): module and eye shapes,
//  an optional second ink for a gradient, and presets. A style that costs
//  module area raises the error correction by itself, and the preview, the
//  PNG, the SVG and the PDF all draw the same styled code. With no shape,
//  gradient or logo chosen, every output is exactly what it was before.
//

import SwiftUI
import UIKit
import Photos
import PhotosUI

struct GeneratorScreen: View {

    // MARK: - Form selection

    enum InputKind: String, CaseIterable, Identifiable {
        case text    = "Text"
        case url     = "URL"
        case contact = "Contact"
        case wifi    = "Wi-Fi"
        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .text:    return "text.alignleft"
            case .url:     return "link"
            case .contact: return "person.crop.circle"
            case .wifi:    return "wifi"
            }
        }
    }

    @State private var inputKind: InputKind = .text
    @State private var symbology: GeneratableSymbology = .qr

    // MARK: - Per-input fields

    @State private var textInput: String = ""
    @State private var urlInput: String  = "https://"

    @State private var contactName: String  = ""
    @State private var contactPhone: String = ""
    @State private var contactEmail: String = ""
    @State private var contactOrg: String   = ""
    @State private var contactURL: String   = ""

    @State private var wifiSSID: String     = ""
    @State private var wifiPassword: String = ""
    @State private var wifiSecurity: CodeComposer.WifiSecurity = .wpa
    @State private var wifiHidden: Bool     = false

    // MARK: - Style

    @State private var foregroundColor: Color = .black
    @State private var backgroundColor: Color = .white
    @State private var qrErrorCorrection: QRErrorCorrection = .medium
    @State private var logoItem: PhotosPickerItem?
    @State private var logoImage: UIImage?
    // 1.10 — QR art studio. Shapes and the optional second ink; colours
    // and error correction keep their existing state above.
    @State private var moduleShape: QRStyle.ModuleShape = .square
    @State private var eyeShape: QRStyle.EyeShape = .square
    @State private var usesSecondInk = false
    /// A fixed sRGB blue (the Android port's default too), not `.blue`:
    /// SwiftUI's blue adapts to Dark Mode, which would make the same
    /// settings print a different code depending on the phone's appearance.
    @State private var secondInk = Color(red: 0, green: 0, blue: 1)
    @State private var presetID = "classic"
    /// NFC tag writing. A session is single-use, so this object is the only
    /// place the live session lives.
    @StateObject private var nfc = NFCTagWriter()

    // MARK: - UX state

    @State private var shareItems: ShareItems?
    @State private var copiedFlash = false
    @State private var savedFlash = false
    @State private var saveError: String?

    // MARK: - Derived values

    /// The encoded-string form of the current input — what we feed into
    /// CodeGenerator.
    private var encodedString: String {
        switch inputKind {
        case .text:
            return textInput
        case .url:
            return urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        case .contact:
            // If there's nothing to put in the contact, return "" so we
            // don't generate a degenerate vCard.
            let pieces = [contactName, contactPhone, contactEmail, contactOrg, contactURL]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard pieces.contains(where: { !$0.isEmpty }) else { return "" }
            return CodeComposer.vCard(
                fullName: contactName,
                phone: contactPhone,
                email: contactEmail,
                organization: contactOrg,
                url: contactURL
            )
        case .wifi:
            let ssid = wifiSSID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ssid.isEmpty else { return "" }
            return CodeComposer.wifi(
                ssid: ssid,
                password: wifiPassword,
                security: wifiSecurity,
                hidden: wifiHidden
            )
        }
    }

    /// The style the preview and every export use. Colours and the logo come
    /// from the existing pickers; shapes from the studio rows.
    private var activeStyle: QRStyle {
        var style = QRStyle()
        style.moduleShape = symbology == .qr ? moduleShape : .square
        style.eyeShape = symbology == .qr ? eyeShape : .square
        style.background = UIColor(backgroundColor)
        style.inks = [UIColor(foregroundColor)]
        if usesSecondInk, symbology == .qr { style.inks.append(UIColor(secondInk)) }
        style.logo = symbology.supportsLogo ? logoImage : nil
        return style
    }

    /// Error correction every QR output is encoded at. Non-square modules,
    /// shaped eyes and inset artwork cost module area, so they buy back
    /// redundancy automatically; the user's pick is raised, never lowered.
    private var effectiveErrorCorrection: QRErrorCorrection {
        previewRequest.effectiveErrorCorrection
    }

    private var isStyled: Bool {
        previewRequest.isStyled
    }

    // MARK: - Preview

    /// Everything the preview picture depends on, and nothing else, so the
    /// Preview section redraws exactly when the picture would change.
    struct PreviewRequest: Equatable {
        let content: String
        let symbology: GeneratableSymbology
        let style: QRStyle
        /// The user's own pick; the style may raise it.
        let errorCorrection: QRErrorCorrection

        /// Only a QR with something for the studio to draw takes the styled path.
        var isStyled: Bool { symbology == .qr && !style.isPlain }

        /// The level every QR output is encoded at: the user's pick, raised —
        /// never lowered — to High when the style needs it.
        var effectiveErrorCorrection: QRErrorCorrection {
            symbology == .qr ? style.errorCorrection(raising: errorCorrection) : errorCorrection
        }
    }

    /// What the Preview section shows for one request.
    enum PreviewResult {
        /// The code. A styled QR also reports its modules per side, because
        /// that decides whether its shapes still scan reliably; nil for the
        /// plain path.
        case code(UIImage, styledSide: Int?)
        /// No code, and why not.
        case unavailable(PreviewFailure)
    }

    /// Draws `request`, away from the main actor: a dense styled code takes a
    /// few hundred milliseconds to draw, which must never stall typing or a
    /// colour-picker drag.
    nonisolated static func renderPreview(_ request: PreviewRequest) -> PreviewResult {
        guard !request.content.isEmpty else { return .unavailable(.empty) }
        if request.isStyled,
           let matrix = CodeGenerator.qrModuleMatrix(for: request.content,
                                                     errorCorrection: request.effectiveErrorCorrection) {
            if let image = QRStyledRenderer.image(matrix: matrix, style: request.style) {
                return .code(image, styledSide: QRGeometry.symbolArea(of: matrix).map { Int($0.width) })
            }
        } else if let image = CodeGenerator.image(
            for: request.content,
            symbology: request.symbology,
            scale: 12,
            foreground: request.style.primaryInk,
            background: request.style.background,
            errorCorrection: request.effectiveErrorCorrection,
            logo: request.style.logo
        ) {
            return .code(image, styledSide: nil)
        }
        return .unavailable(PreviewFailure.reason(content: request.content,
                                                  symbology: request.symbology,
                                                  style: request.style,
                                                  requested: request.errorCorrection))
    }

    private var previewRequest: PreviewRequest {
        PreviewRequest(content: encodedString, symbology: symbology, style: activeStyle,
                       errorCorrection: qrErrorCorrection)
    }

    /// The last preview drawn, with the request it was drawn for. It stays on
    /// screen while a newer request draws.
    private struct ShownPreview {
        let request: PreviewRequest
        let result: PreviewResult
    }

    @State private var shownPreview: ShownPreview?

    /// Draws `request` off the main actor and shows it. Every change to the
    /// request restarts this (`.task(id:)`), so the short sleep lets a burst
    /// of edits — typing, a colour-picker drag — draw only its last state.
    /// With nothing on screen yet there is nothing to wait for.
    private func refreshPreview(for request: PreviewRequest) async {
        guard !request.content.isEmpty else {
            shownPreview = nil
            return
        }
        if shownPreview != nil {
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
        }
        let result = await Task.detached(priority: .userInitiated) {
            GeneratorScreen.renderPreview(request)
        }.value
        guard !Task.isCancelled else { return }
        shownPreview = ShownPreview(request: request, result: result)
    }

    /// Relative luminance contrast ratio per WCAG. Values in [1, 21];
    /// QR scanners typically need ≥ 3 for reliable decoding (the
    /// scanner threshold logic is more lenient than human readability,
    /// but going below 3 gets noticeably hit-and-miss, so that's our
    /// warning floor). With a gradient every ink is measured against the
    /// background and the worst is reported: a wash is only as legible as
    /// its palest end.
    private var contrastRatio: Double {
        let background = relativeLuminance(of: activeStyle.background)
        let ratios = activeStyle.inks.map { ink -> Double in
            let l1 = relativeLuminance(of: ink)
            let lighter = max(l1, background)
            let darker  = min(l1, background)
            return (lighter + 0.05) / (darker + 0.05)
        }
        return ratios.min() ?? 21
    }

    private var contrastIsSafe: Bool { contrastRatio >= 3.0 }

    // MARK: - Body

    var body: some View {
        Form {
            // "Describe the code": a sentence in, a filled-in form out. The
            // box hides itself when the assistant is off in Settings →
            // Insights. Above the type picker, as on Android, because the
            // sentence also picks the type.
            AssistantComposeBox(onResult: applyComposed)

            Section {
                Picker("Type", selection: $inputKind) {
                    ForEach(InputKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            }

            inputSection

            Section("Symbology") {
                Picker("Symbology", selection: $symbology) {
                    ForEach(GeneratableSymbology.allCases) { sym in
                        Text(sym.rawValue).tag(sym)
                    }
                }
                .pickerStyle(.menu)

                if symbology == .code128 && encodedString.contains("\n") {
                    Label(
                        "Code 128 is a 1D format and can't encode multi-line content reliably.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }
            }

            styleSection

            nfcSection

            if symbology.supportsLogo {
                logoSection
            }

            Section("Preview") {
                let request = previewRequest
                if request.content.isEmpty {
                    Text(PreviewFailure.empty.message)
                        .foregroundStyle(.secondary)
                } else if let shown = shownPreview {
                    switch shown.result {
                    case .code(let img, let styledSide):
                        VStack(spacing: 12) {
                            Image(uiImage: img)
                                // Plain codes are pure module squares and stay
                                // crisp with nearest-neighbour; a styled code
                                // has antialiased curves that would alias.
                                .interpolation(styledSide == nil ? .none : .high)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 280)
                                .padding(8)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(.secondary.opacity(0.2))
                                )
                                .accessibilityLabel("Generated \(shown.request.symbology.rawValue) code")

                            if !contrastIsSafe {
                                Label(
                                    "Contrast \(String(format: "%.1f", contrastRatio)):1 is below the safe threshold (3:1). Some scanners will struggle.",
                                    systemImage: "exclamationmark.triangle"
                                )
                                .font(.footnote)
                                .foregroundStyle(.orange)
                            }

                            // Shaped modules run out of margin on dense codes —
                            // dots soonest, all of them sooner with a logo
                            // (`QRStyle.isHardToScan`): say so rather than let
                            // the user print a code their own camera may not
                            // read.
                            if let side = styledSide,
                               let warning = shown.request.style.scannabilityWarning(symbolSide: side) {
                                Label(warning, systemImage: "exclamationmark.triangle")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        // The last picture stays up while a newer one draws,
                        // but nothing shares, saves or copies it once it no
                        // longer matches the form.
                        Group {
                            actionsRow(image: img)
                        }
                        .disabled(shown.request != request)
                    case .unavailable(let failure):
                        Text(failure.message)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
        }
        // Off the main actor and debounced (`refreshPreview`): drawing a
        // dense styled code must not stall the form on every keystroke.
        .task(id: previewRequest) { [request = previewRequest] in
            await refreshPreview(for: request)
        }
        // An NFC outcome belongs to the content it was for: editing the form
        // clears "Tag written" (or a failure). On the Form, not in the lazy
        // NFC section, so it fires while that section is scrolled away.
        .onValueChange(of: encodedString) { _ in nfc.contentDidChange() }
        .navigationTitle("Generate")
        // `.scrollDismissesKeyboard(.interactively)` already
        // covers drag-to-dismiss; the keyboard's `Done` toolbar
        // button below covers explicit dismiss. The earlier
        // `.simultaneousGesture(TapGesture()...)` had to be
        // removed — iOS 26 routes its tap through the Button hit
        // path, intercepting *every* Button tap inside the Form
        // (Choose logo, Share PNG, Share SVG, Share PDF, …).
        // SwiftUI Buttons inside a Form already cooperate with
        // scroll-dismiss-keyboard; we don't need a redundant tap
        // recogniser layered on top.
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissKeyboard() }
            }
        }
        // Logo picker is now driven by the `PhotosPicker` *view* in
        // `logoSection` rather than an `.photosPicker(isPresented:)`
        // modifier — the modifier-based variant silently did nothing
        // when stacked alongside `.sheet(item:)` and `.alert(...)`.
        .onValueChange(of: logoItem) { newItem in
            guard let newItem else { logoImage = nil; return }
            Task {
                guard let data = try? await newItem.loadTransferable(type: Data.self) else { return }
                // Decode and shrink off the main actor: a camera-roll photo
                // is 12 MP, and the preview redraws the logo on every edit
                // (and the SVG export inlines it).
                let prepared = await Task.detached(priority: .userInitiated) {
                    UIImage(data: data).map { QRStyledRenderer.preparedLogo($0) }
                }.value
                // A slow load for an earlier pick must not replace a newer one.
                guard let prepared, logoItem == newItem else { return }
                logoImage = prepared
            }
        }
        .sheet(item: $shareItems) { wrapped in
            ShareSheet(items: wrapped.items)
        }
        .alert("Couldn't save",
               isPresented: Binding(
                   get: { saveError != nil },
                   set: { if !$0 { saveError = nil } }
               ),
               presenting: saveError) { _ in
            Button("OK", role: .cancel) {}
        } message: { msg in
            Text(msg)
        }
    }

    /// Resigns whatever's currently first responder.
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    // MARK: - Describe the code

    /// Copies a "describe the code" result onto the form and switches to its
    /// type. False when the result carries nothing the form can use, so the
    /// box says it did not understand instead of claiming it filled anything.
    /// Same mapping as the Android port's `ComposeFormFill`: fields the
    /// request did not give are cleared rather than left over from an
    /// earlier code — except the Wi-Fi security, which keeps the form's
    /// choice when the request does not name one.
    private func applyComposed(_ result: ComposeResult) -> Bool {
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch result.kind {
        case .wifi:
            guard let ssid = result.value("ssid") else { return false }
            inputKind = .wifi
            wifiSSID = ssid
            wifiPassword = result.value("password") ?? ""
            if let tag = result.wifiSecurityTag,
               let security = CodeComposer.WifiSecurity(rawValue: tag) {
                wifiSecurity = security
            }
            wifiHidden = result.isHiddenNetwork
        case .contact:
            let name = result.value("name") ?? ""
            let phone = result.value("phone") ?? ""
            let email = result.value("email") ?? ""
            let organization = result.value("org") ?? ""
            guard !(name.isEmpty && phone.isEmpty && email.isEmpty && organization.isEmpty) else {
                return false
            }
            inputKind = .contact
            contactName = name
            contactPhone = phone
            contactEmail = email
            contactOrg = organization
            contactURL = ""
        case .url:
            guard !text.isEmpty else { return false }
            inputKind = .url
            urlInput = text
        case .text, .email, .phone, .payment, .product:
            // The Generate tab has no form for the last four; neither engine
            // produces them today, and if one ever does its literal text is
            // still the code the user asked for.
            guard !text.isEmpty else { return false }
            inputKind = .text
            textInput = text
        }
        return true
    }

    // MARK: - Input forms (per kind)

    @ViewBuilder
    private var inputSection: some View {
        switch inputKind {
        case .text:
            Section("Text") {
                TextField("Anything you want to encode", text: $textInput, axis: .vertical)
                    .lineLimit(2...8)
                    .textInputAutocapitalization(.sentences)
            }

        case .url:
            Section("URL") {
                TextField("https://example.com", text: $urlInput)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

        case .contact:
            Section("Contact") {
                TextField("Full name", text: $contactName)
                    .textContentType(.name)
                TextField("Phone", text: $contactPhone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                TextField("Email", text: $contactEmail)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Organization (optional)", text: $contactOrg)
                    .textContentType(.organizationName)
                TextField("Website (optional)", text: $contactURL)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

        case .wifi:
            Section("Wi-Fi") {
                TextField("Network name (SSID)", text: $wifiSSID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if wifiSecurity != .open {
                    SecureField("Password", text: $wifiPassword)
                        .textContentType(.password)
                }
                Picker("Security", selection: $wifiSecurity) {
                    ForEach(CodeComposer.WifiSecurity.allCases) { sec in
                        Text(sec.displayName).tag(sec)
                    }
                }
                Toggle("Hidden network", isOn: $wifiHidden)
            }
        }
    }

    // MARK: - Style section

    @ViewBuilder
    private var styleSection: some View {
        Section {
            ColorPicker("Foreground", selection: $foregroundColor, supportsOpacity: false)
            ColorPicker("Background", selection: $backgroundColor, supportsOpacity: false)
            if symbology == .qr {
                Picker("Error correction", selection: $qrErrorCorrection) {
                    ForEach(QRErrorCorrection.allCases) { lvl in
                        Text(lvl.displayName).tag(lvl)
                    }
                }
                .pickerStyle(.menu)

                // Say so when the studio overrode the user's choice — the
                // picker still shows what they asked for.
                if effectiveErrorCorrection != qrErrorCorrection {
                    Label(
                        "Shapes and artwork raise error correction to \(effectiveErrorCorrection.displayName) automatically — that redundancy is what pays for them.",
                        systemImage: "shield.lefthalf.filled"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            if symbology == .qr {
                Picker("Preset", selection: $presetID) {
                    ForEach(QRStyle.presets) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }
                .pickerStyle(.menu)

                Picker("Modules", selection: $moduleShape) {
                    ForEach(QRStyle.ModuleShape.allCases) { shape in
                        Text(shape.label).tag(shape)
                    }
                }
                .pickerStyle(.menu)

                Picker("Eyes", selection: $eyeShape) {
                    ForEach(QRStyle.EyeShape.allCases) { shape in
                        Text(shape.label).tag(shape)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Gradient ink", isOn: $usesSecondInk)
                if usesSecondInk {
                    ColorPicker("Second ink", selection: $secondInk, supportsOpacity: false)
                }

                if let preset = QRStyle.presets.first(where: { $0.id == presetID }) {
                    Button {
                        apply(preset)
                    } label: {
                        Label("Apply “\(preset.name)”", systemImage: "paintbrush.pointed")
                            .font(.footnote)
                    }
                }
            }

            HStack {
                Button {
                    foregroundColor = .black
                    backgroundColor = .white
                    moduleShape = .square
                    eyeShape = .square
                    usesSecondInk = false
                    presetID = "classic"
                } label: {
                    Label("Reset to black on white", systemImage: "arrow.uturn.backward")
                        .font(.footnote)
                }
                Spacer()
            }
        } header: {
            Text("Style")
        } footer: {
            if symbology == .qr {
                Text("Shapes and artwork raise error correction to High automatically — that redundancy is what pays for them. Aim for a contrast ratio of at least 3:1 for every ink.")
            } else {
                Text("Colour customisation works on every supported symbology. Aim for a contrast ratio of at least 3:1.")
            }
        }
    }

    /// Apply a studio preset: shapes *and* inks, background included — a
    /// preset is a whole look, and the Android port applies it the same way.
    /// Shapes alone can still be changed afterwards with the rows above.
    private func apply(_ preset: QRStyle.Preset) {
        moduleShape = preset.style.moduleShape
        eyeShape = preset.style.eyeShape
        usesSecondInk = preset.style.inks.count > 1
        if let first = preset.style.inks.first {
            foregroundColor = Color(uiColor: first)
        }
        if preset.style.inks.count > 1, let second = preset.style.inks.last {
            secondInk = Color(uiColor: second)
        }
        backgroundColor = Color(uiColor: preset.style.background)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: - NFC section

    /// Write whatever the form currently encodes onto a writable NDEF tag.
    /// Same string as the code, so the tag and the QR stay interchangeable.
    @ViewBuilder
    private var nfcSection: some View {
        if NFCTagWriter.isSupported {
            // What a tap writes, so the button is off whenever the write would
            // be refused — blank or whitespace-only content included, trimmed
            // by the same rule as on Android.
            let request = NFCTagWriteRequest(kind: .inferred(from: encodedString), value: encodedString)
            Section {
                Button {
                    nfc.write(request)
                } label: {
                    Label("Write to NFC tag", systemImage: "wave.3.right")
                }
                .disabled(!request.isValid)

                switch nfc.status {
                case .scanning:
                    Label("Hold your iPhone near a writable tag…", systemImage: "hourglass")
                        .font(.footnote).foregroundStyle(.secondary)
                case .writing:
                    Label("Writing…", systemImage: "hourglass")
                        .font(.footnote).foregroundStyle(.secondary)
                case .wrote(let message):
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.footnote).foregroundStyle(.green)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.orange)
                case .idle:
                    EmptyView()
                }
            } header: {
                Text("NFC")
            } footer: {
                // Only http(s), tel, mailto, sms, smsto and geo links become
                // URI records (`NFCTagPayloadKind.linkPrefixes`), only open
                // and WPA/WPA2 networks a Wi-Fi token, only vCards a contact
                // card (`NDEFRecordCodec.records(for:)`). And a tap alone
                // doesn't do what a scan would — an iPhone ignores Wi-Fi,
                // contact and text tags, and `smsto:` and `geo:` links — so
                // the promise is about Scan.
                Text("Writes the same content to a writable NFC tag — a web, phone, email, SMS or map link, a Wi-Fi network or a contact card in its own NFC format, anything else (WPA3, WEP and hidden Wi-Fi included) as text — so reading the tag in Scan gives the same result as scanning the code.")
            }
        }
    }

    // MARK: - Logo section

    @ViewBuilder
    private var logoSection: some View {
        Section {
            HStack(spacing: 14) {
                if let logoImage {
                    Image(uiImage: logoImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.secondary.opacity(0.3))
                        )
                } else {
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundStyle(.secondary)
                        .frame(width: 48, height: 48)
                        .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(logoImage == nil ? "No logo" : "Logo set")
                        .font(.body)
                    Text(logoImage == nil
                         ? "Add an image to embed at the centre of the QR."
                         : "QR will use High error correction to keep it scannable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            // Use PhotosPicker as a *view*, not the modifier-based
            // .photosPicker(isPresented:). The previous setup had a
            // Button → flip @State Bool → .photosPicker(isPresented:)
            // dance, which silently did nothing — the picker was
            // never actually attached to the right level of the
            // view hierarchy when the Bool flipped, presumably
            // because of the multiple-modal-modifier stack on this
            // Form (.sheet for share, .alert for save errors,
            // .photosPicker for logo). The view-based variant is
            // self-contained: it *is* the tappable label, and the
            // picker presents itself when tapped.
            PhotosPicker(
                selection: $logoItem,
                matching: .images,
                preferredItemEncoding: .compatible
            ) {
                Label(
                    logoImage == nil ? "Choose logo…" : "Change logo…",
                    systemImage: "photo.badge.plus"
                )
            }
            if logoImage != nil {
                Button(role: .destructive) {
                    logoItem = nil
                    logoImage = nil
                } label: {
                    Label("Remove", systemImage: "xmark.circle")
                }
            }
        } header: {
            Text("Logo")
        } footer: {
            Text("Logos sit at about 22% of the code's width on a patch of the background colour — well within what High error correction can recover.")
        }
    }

    // MARK: - Action row (Share / Save / Copy / Vector)

    @ViewBuilder
    private func actionsRow(image: UIImage) -> some View {
        Button {
            shareItems = ShareItems(items: [image])
        } label: {
            Label("Share PNG", systemImage: "square.and.arrow.up")
        }

        if symbology == .qr {
            Button {
                exportSVG()
            } label: {
                Label("Share SVG", systemImage: "doc.richtext")
            }

            Button {
                exportPDF()
            } label: {
                Label("Share PDF", systemImage: "doc.fill")
            }
        }

        Button {
            saveToPhotos(image: image)
        } label: {
            Label(savedFlash ? "Saved to Photos" : "Save to Photos",
                  systemImage: savedFlash ? "checkmark" : "square.and.arrow.down")
        }
        .disabled(savedFlash)

        Button {
            copyToClipboard(image: image)
        } label: {
            Label(copiedFlash ? "Copied" : "Copy",
                  systemImage: copiedFlash ? "checkmark" : "doc.on.doc")
        }
        .disabled(copiedFlash)
    }

    // MARK: - Vector export

    /// The module grid the vector exports draw: encoded once, at the level
    /// the preview used, so the SVG / PDF is the same code as the PNG.
    private var exportMatrix: CodeGenerator.ModuleMatrix? {
        CodeGenerator.qrModuleMatrix(for: encodedString, errorCorrection: effectiveErrorCorrection)
    }

    /// Nil for a plain code, which keeps the exports' original output.
    private var exportStyle: QRStyle? { isStyled ? activeStyle : nil }

    private func exportSVG() {
        guard let matrix = exportMatrix else {
            saveError = "Couldn't build a vector for this content."
            return
        }
        let svg = QRSvg.svg(
            for: matrix,
            foreground: UIColor(foregroundColor),
            background: UIColor(backgroundColor),
            style: exportStyle
        )
        do {
            let url = try QRSvg.writeSVG(svg)
            shareItems = ShareItems(items: [url])
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func exportPDF() {
        guard let matrix = exportMatrix else {
            saveError = "Couldn't build a vector for this content."
            return
        }
        let data = QRSvg.pdfData(
            for: matrix,
            foreground: UIColor(foregroundColor),
            background: UIColor(backgroundColor),
            style: exportStyle
        )
        do {
            let url = try QRSvg.writePDF(data)
            shareItems = ShareItems(items: [url])
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func copyToClipboard(image: UIImage) {
        UIPasteboard.general.setObjects([image, encodedString as NSString])
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        copiedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copiedFlash = false }
    }

    private func saveToPhotos(image: UIImage) {
        let proceed = {
            PHPhotoLibrary.shared().performChanges({
                _ = PHAssetCreationRequest.creationRequestForAsset(from: image)
            }, completionHandler: { success, error in
                Task { @MainActor in
                    if success {
                        savedFlash = true
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { savedFlash = false }
                    } else {
                        saveError = error?.localizedDescription ?? "The image couldn't be saved."
                    }
                }
            })
        }

        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            proceed()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                if newStatus == .authorized || newStatus == .limited {
                    proceed()
                } else {
                    Task { @MainActor in
                        saveError = "Allow Photos access in Settings to save generated codes."
                    }
                }
            }
        default:
            saveError = "Allow Photos access in Settings to save generated codes."
        }
    }
}

// MARK: - Helpers (luminance, share-items wrapper)

/// Wraps an array of share-sheet items so it can drive `.sheet(item:)`.
/// We use this rather than three separate `@State` flags for PNG /
/// SVG / PDF — one binding, three call sites, one share-sheet
/// presentation lifecycle.
private struct ShareItems: Identifiable {
    let id = UUID()
    let items: [Any]
}

private func relativeLuminance(of color: UIColor) -> Double {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return 0 }
    func c(_ v: CGFloat) -> Double {
        let v = Double(v)
        return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * c(r) + 0.7152 * c(g) + 0.0722 * c(b)
}
