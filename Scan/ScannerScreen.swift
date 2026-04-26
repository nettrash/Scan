//
//  ScannerScreen.swift
//  Scan
//
//  Live-camera scanning screen. Hosts CameraScannerView, debounces results,
//  shows a result sheet, and persists scans to Core Data. Also lets the
//  user import an image from the photo library or Files and decode it
//  with Vision.
//

import SwiftUI
import CoreData
import AVFoundation
import UIKit
import PhotosUI
import UniformTypeIdentifiers

struct ScannerScreen: View {
    @Environment(\.managedObjectContext) private var viewContext

    // Scanner state
    @State private var torchOn = false
    @State private var lastScan: ScannedCode?
    @State private var showResult = false
    @State private var failureReason: String?
    @State private var lastValue: String?
    @State private var lastValueAt: Date = .distantPast
    /// The most recent detected code's rectangle, in CameraScannerView's
    /// coordinate space. `nil` falls back to a centred default-size reticle.
    @State private var detectedRect: CGRect?

    // Image-import state
    @State private var photoItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var isDecoding = false
    @State private var importErrorMessage: String?
    @State private var showImportError = false

    private let dedupeWindow: TimeInterval = 1.5

    var body: some View {
        ZStack {
            CameraScannerView(
                onScan: handleScan,
                onFailure: { failureReason = $0 },
                isPaused: showResult || isDecoding,
                isTorchOn: torchOn
            )
            .ignoresSafeArea()

            // Reticle: snaps to the detected code's bounds when the camera
            // sees one, otherwise centres a default-size square as a hint
            // of where to point the lens. The animation gives the user
            // visible confirmation that a code was just recognised.
            GeometryReader { geo in
                let defaultSize: CGFloat = 260
                let rect = detectedRect ?? CGRect(
                    x: (geo.size.width - defaultSize) / 2,
                    y: (geo.size.height - defaultSize) / 2 - 80,
                    width: defaultSize,
                    height: defaultSize
                )
                ReticleView()
                    .frame(width: max(rect.width, 80),
                           height: max(rect.height, 80))
                    .position(x: rect.midX, y: rect.midY)
                    .animation(.spring(response: 0.28, dampingFraction: 0.78),
                               value: detectedRect)
            }
            .ignoresSafeArea()

            VStack {
                Spacer()
                HStack {
                    importMenu
                        .padding(.leading, 24)
                    Spacer()
                    Button {
                        torchOn.toggle()
                    } label: {
                        Image(systemName: torchOn ? "bolt.fill" : "bolt.slash.fill")
                            .font(.title2)
                            .padding(14)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel(torchOn ? "Turn flashlight off" : "Turn flashlight on")
                    .padding(.trailing, 24)
                }
                .padding(.bottom, 32)
            }

            if isDecoding {
                ProgressView("Reading image…")
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            if let failureReason {
                VStack {
                    Spacer()
                    Text(failureReason)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding()
                    Spacer().frame(height: 100)
                }
                .transition(.opacity)
            }
        }
        .navigationTitle("Scan")
        .navigationBarTitleDisplayMode(.inline)
        .photosPicker(
            isPresented: $showPhotoPickerInternal,
            selection: $photoItem,
            matching: .images
        )
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let first = urls.first {
                    Task { await handlePickedFile(first) }
                }
            case .failure(let err):
                presentImportError(err.localizedDescription)
            }
        }
        .onValueChange(of: photoItem) { newItem in
            guard let newItem else { return }
            Task { await handlePickedPhoto(newItem) }
        }
        .alert("Import failed", isPresented: $showImportError, presenting: importErrorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { msg in
            Text(msg)
        }
        .sheet(isPresented: $showResult, onDismiss: {
            lastScan = nil
            // Reset the reticle to its default centred position so the
            // next scan starts from a neutral hint.
            detectedRect = nil
        }) {
            if let lastScan {
                ScanResultSheet(
                    scan: lastScan,
                    onSave: { notes in saveScan(lastScan, notes: notes) },
                    onDismiss: { showResult = false }
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Import menu

    @State private var showPhotoPickerInternal = false

    private var importMenu: some View {
        Menu {
            Button {
                showPhotoPickerInternal = true
            } label: {
                Label("Photo Library", systemImage: "photo.on.rectangle")
            }
            Button {
                showFileImporter = true
            } label: {
                Label("Files", systemImage: "folder")
            }
        } label: {
            Image(systemName: "photo")
                .font(.title2)
                .padding(14)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel("Import from image")
    }

    // MARK: - Live scan handling

    private func handleScan(_ code: ScannedCode) {
        // Snap the reticle to the detected code's bounds. We do this even
        // on a debounced repeat so the reticle keeps tracking the code if
        // it moves while the result sheet is still about to appear.
        if let rect = code.previewRect {
            detectedRect = rect
        }
        // Debounce duplicate decodes from the same code in quick succession.
        let now = Date()
        if code.value == lastValue, now.timeIntervalSince(lastValueAt) < dedupeWindow {
            return
        }
        lastValue = code.value
        lastValueAt = now
        lastScan = code
        showResult = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: - Image import handling

    @MainActor
    private func handlePickedPhoto(_ item: PhotosPickerItem) async {
        isDecoding = true
        defer {
            isDecoding = false
            photoItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                presentImportError("Couldn't read the selected photo.")
                return
            }
            let codes = try await ImageDecoder.decode(data: data)
            presentDecoded(codes)
        } catch let e as ImageDecoder.DecodeError {
            presentImportError(e.localizedDescription)
        } catch {
            presentImportError(error.localizedDescription)
        }
    }

    @MainActor
    private func handlePickedFile(_ url: URL) async {
        isDecoding = true
        defer { isDecoding = false }
        do {
            let codes = try await ImageDecoder.decode(url: url)
            presentDecoded(codes)
        } catch let e as ImageDecoder.DecodeError {
            presentImportError(e.localizedDescription)
        } catch {
            presentImportError(error.localizedDescription)
        }
    }

    @MainActor
    private func presentDecoded(_ codes: [ScannedCode]) {
        guard let first = codes.first else {
            presentImportError("No barcodes were found in that image.")
            return
        }
        lastScan = first
        // Don't apply the live-scan debounce to imports.
        lastValue = first.value
        lastValueAt = Date()
        showResult = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Safe to call from any context — schedules itself onto the main actor.
    private func presentImportError(_ message: String) {
        Task { @MainActor in
            importErrorMessage = message
            showImportError = true
        }
    }

    // MARK: - Persistence

    private func saveScan(_ code: ScannedCode, notes: String?) {
        let record = ScanRecord(context: viewContext)
        record.id = UUID()
        record.value = code.value
        record.symbology = code.symbology.displayName
        record.timestamp = code.timestamp
        record.notes = notes?.isEmpty == false ? notes : nil
        do {
            try viewContext.save()
        } catch {
            print("Save failed: \(error)")
        }
    }
}

// MARK: - Reticle

private struct ReticleView: View {
    var body: some View {
        GeometryReader { geo in
            // Scale the corner-bracket size to ~18 % of the shorter
            // dimension, clamped between 20 and 48 pt. This way the
            // brackets stay readable when the reticle wraps a small
            // detected code and don't look comical when it's full-size.
            let minDim = min(geo.size.width, geo.size.height)
            let cornerSize = max(20, min(48, minDim * 0.18))
            let lineWidth = max(3, min(6, minDim * 0.025))
            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    Corner()
                        .stroke(Color.accentColor,
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .frame(width: cornerSize, height: cornerSize)
                        .rotationEffect(.degrees(Double(i) * 90))
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: cornerAlignment(for: i))
                }
            }
        }
    }

    private func cornerAlignment(for i: Int) -> Alignment {
        switch i {
        case 0: return .topLeading
        case 1: return .topTrailing
        case 2: return .bottomTrailing
        default: return .bottomLeading
        }
    }
}

private struct Corner: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + rect.width, y: rect.minY))
        return p
    }
}

// MARK: - Result sheet

private struct ScanResultSheet: View {
    let scan: ScannedCode
    let onSave: (String?) -> Void
    let onDismiss: () -> Void

    @State private var notes: String = ""
    @State private var saved = false

    private var payload: ScanPayload {
        ScanPayloadParser.parse(scan.value, symbology: scan.symbology)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(payload.kindLabel)
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                        Spacer()
                        Text(scan.symbology.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(scan.value)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }

                PayloadActionsView(payload: payload, raw: scan.value)

                Section("Notes (optional)") {
                    TextField("Add a note", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle("Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saved ? "Saved" : "Save") {
                        onSave(notes)
                        saved = true
                    }
                    .disabled(saved)
                }
            }
        }
    }
}
