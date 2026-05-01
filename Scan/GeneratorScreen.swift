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

    private var generatedImage: UIImage? {
        guard !encodedString.isEmpty else { return nil }
        return CodeGenerator.image(
            for: encodedString,
            symbology: symbology,
            scale: 12,
            foreground: UIColor(foregroundColor),
            background: UIColor(backgroundColor),
            errorCorrection: qrErrorCorrection,
            logo: symbology.supportsLogo ? logoImage : nil
        )
    }

    /// Relative luminance contrast ratio per WCAG. Values in [1, 21];
    /// QR scanners typically need ≥ 3 for reliable decoding (the
    /// scanner threshold logic is more lenient than human readability,
    /// but going below 3 gets noticeably hit-and-miss, so that's our
    /// warning floor).
    private var contrastRatio: Double {
        let l1 = relativeLuminance(of: UIColor(foregroundColor))
        let l2 = relativeLuminance(of: UIColor(backgroundColor))
        let lighter = max(l1, l2)
        let darker  = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private var contrastIsSafe: Bool { contrastRatio >= 3.0 }

    // MARK: - Body

    var body: some View {
        Form {
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

            if symbology.supportsLogo {
                logoSection
            }

            Section("Preview") {
                if let img = generatedImage {
                    VStack(spacing: 12) {
                        Image(uiImage: img)
                            .interpolation(.none)
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
                            .accessibilityLabel("Generated \(symbology.rawValue) code")

                        if !contrastIsSafe {
                            Label(
                                "Contrast \(String(format: "%.1f", contrastRatio)):1 is below the safe threshold (3:1). Some scanners will struggle.",
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    actionsRow(image: img)
                } else {
                    Text("Fill in the fields above to see a preview.")
                        .foregroundStyle(.secondary)
                }
            }
        }
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
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await MainActor.run { logoImage = img }
                }
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
            }
            HStack {
                Button {
                    foregroundColor = .black
                    backgroundColor = .white
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
                Text("Error correction is auto-set to High whenever a logo is added — keep it on Medium for the smallest QR otherwise.")
            } else {
                Text("Colour customisation works on every supported symbology. Aim for a contrast ratio of at least 3:1.")
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
            Text("Logos are placed at ~22% of the QR canvas with a white punch behind them — well within the 30% recovery margin of High error correction.")
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

    private func exportSVG() {
        guard let matrix = CodeGenerator.qrModuleMatrix(
            for: encodedString,
            errorCorrection: logoImage == nil ? qrErrorCorrection : .high
        ) else {
            saveError = "Couldn't build a vector for this content."
            return
        }
        let svg = QRSvg.svg(
            for: matrix,
            foreground: UIColor(foregroundColor),
            background: UIColor(backgroundColor)
        )
        do {
            let url = try QRSvg.writeSVG(svg)
            shareItems = ShareItems(items: [url])
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func exportPDF() {
        guard let matrix = CodeGenerator.qrModuleMatrix(
            for: encodedString,
            errorCorrection: logoImage == nil ? qrErrorCorrection : .high
        ) else {
            saveError = "Couldn't build a vector for this content."
            return
        }
        let data = QRSvg.pdfData(
            for: matrix,
            foreground: UIColor(foregroundColor),
            background: UIColor(backgroundColor)
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
