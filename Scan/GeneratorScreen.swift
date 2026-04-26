//
//  GeneratorScreen.swift
//  Scan
//
//  Lets the user construct a 1D / 2D code from text, a URL, a contact, or
//  Wi-Fi credentials. Live preview, share sheet, save-to-Photos, and copy
//  buttons.
//

import SwiftUI
import UIKit
import Photos

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

    // MARK: - UX state

    @State private var showShare = false
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
        return CodeGenerator.image(for: encodedString, symbology: symbology, scale: 12)
    }

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
        .sheet(isPresented: $showShare) {
            if let img = generatedImage {
                ShareSheet(items: [img])
            }
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

    // MARK: - Action row (Share / Save / Copy)

    @ViewBuilder
    private func actionsRow(image: UIImage) -> some View {
        Button {
            showShare = true
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
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

    // MARK: - Helpers

    private func copyToClipboard(image: UIImage) {
        // Put both representations on the pasteboard explicitly so the user
        // can paste the image *or* the encoded string depending on the
        // destination app.
        UIPasteboard.general.setObjects([image, encodedString as NSString])
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        copiedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copiedFlash = false }
    }

    private func saveToPhotos(image: UIImage) {
        // Use the modern PHPhotoLibrary API so we can request *add-only*
        // permission specifically (NSPhotoLibraryAddUsageDescription).
        let proceed = {
            PHPhotoLibrary.shared().performChanges({
                // The request registers itself with the surrounding change
                // block; the returned object is intentionally unused.
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
