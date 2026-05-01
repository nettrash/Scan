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
import Combine
import CoreData
import AVFoundation
import UIKit
import PhotosUI
import UniformTypeIdentifiers

struct ScannerScreen: View {
    @Environment(\.managedObjectContext) private var viewContext

    // User preferences (Settings tab)
    @AppStorage(ScanSettingsKey.hapticOnScan)   private var hapticOnScan: Bool   = true
    @AppStorage(ScanSettingsKey.soundOnScan)    private var soundOnScan: Bool    = false
    @AppStorage(ScanSettingsKey.continuousScan) private var continuousScan: Bool = false

    // Scanner state
    @State private var torchOn = false
    /// In continuous-scan mode, the most recent value that was
    /// auto-saved. Used to drive a small banner so the user has
    /// confirmation that something *was* recognised — and a tap
    /// target if they want to open the result sheet for it.
    @State private var lastContinuousScan: ScannedCode?
    /// The code currently displayed in the result sheet. Bound to
    /// `.sheet(item:)` so SwiftUI presents/dismisses atomically — no
    /// race between the dismiss animation and a fresh scan of the same
    /// payload (which previously could leave the sheet empty).
    @State private var sheetCode: ScannedCode?
    @State private var failureReason: String?
    @State private var lastValue: String?
    @State private var lastValueAt: Date = .distantPast
    /// The value we last took action on (saved to history in
    /// continuous-scan mode, or presented in the sheet in normal
    /// mode). Reset by the reticle watchdog when the camera frame
    /// has been empty for the grace period — i.e. when the user
    /// has visibly moved the camera off the code. This is what
    /// stops the same code being saved over and over while it sits
    /// in view; the older 1.5 s time window kept resetting and
    /// re-firing every dedupeWindow seconds.
    @State private var lastHandledValue: String?
    /// The most recent detected code's rectangle, in CameraScannerView's
    /// coordinate space. `nil` falls back to a centred default-size reticle.
    @State private var detectedRect: CGRect?
    /// Wall-clock time of the last successful metadata detection. Used by
    /// the watchdog timer to decide when to release the corner reticle
    /// back to its default centred position once no codes are visible.
    @State private var lastDetectionAt: Date = .distantPast
    /// When the camera reports more than one code in a frame, we
    /// store them here and render a chooser overlay instead of
    /// immediately presenting the result sheet. Cleared as soon as
    /// the user taps a chip, the user dismisses the chooser, or the
    /// frame goes back to having ≤ 1 code.
    @State private var multiCodeChoices: [ScannedCode] = []

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
                onScanBatch: handleScanBatch,
                onFailure: { failureReason = $0 },
                // Keep the live preview running while the result sheet is
                // up — only pause when we're actively decoding a still
                // image (otherwise the preview would freeze on top of the
                // imported-image progress indicator). Sheet-level dedupe
                // is handled by `lastValue` / `lastValueAt`.
                isPaused: isDecoding,
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

            // Continuous-scan mode: render the last auto-saved code as a
            // dismissible banner near the top so the user has feedback
            // and a tap-target to open the sheet on demand. Hidden when
            // the toggle is off or no scan yet. The trailing ✕ button
            // is the user's explicit "I'm done with this one — show
            // me the next" gesture; tapping it releases the
            // same-value dedupe lock so the next sight of any code
            // (including the one just dismissed) registers as a
            // fresh scan.
            if continuousScan, let last = lastContinuousScan {
                VStack {
                    HStack(spacing: 0) {
                        Button {
                            sheetCode = last
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Saved")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    Text(last.value)
                                        .font(.subheadline.monospaced())
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .foregroundStyle(.primary)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.leading, 14)
                            .padding(.vertical, 10)
                            .padding(.trailing, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation {
                                lastContinuousScan = nil
                            }
                            // Release the dedupe so the next sight of
                            // any code — including this one — counts.
                            lastHandledValue = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss saved-scan banner")
                    }
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
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

            // Multi-code chooser. Each detected code gets a numbered
            // chip rendered roughly over its bounding rect so the
            // user can match what's on screen to which option to act
            // on. Tapping a chip routes through the normal scan
            // pipeline.
            if !multiCodeChoices.isEmpty {
                multiCodeOverlay
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
        .sheet(item: $sheetCode, onDismiss: {
            // Sheet dismissal — by tap-Done, swipe-down, or tap-outside —
            // releases the same-value dedupe lock. The next time the
            // user points at the same code, it'll re-present.
            lastHandledValue = nil
        }) { scan in
            ScanResultSheet(
                scan: scan,
                onSave: { notes in saveScan(scan, notes: notes) },
                onDismiss: {
                    sheetCode = nil
                    lastHandledValue = nil
                }
            )
            .presentationDetents([.medium, .large])
        }
        // Watchdog: if the camera hasn't reported a recognised code for a
        // short grace period, release the corner reticle back to its
        // centred default position so the brackets don't appear "stuck"
        // on a code that has since left the frame.
        //
        // NOTE: deliberately does *not* clear `lastHandledValue` —
        // the value-equality dedupe in `handleScan` is now strict.
        // Once a value has been handled, the only way to re-handle it
        // is to dismiss the result sheet (sheet mode) or the
        // continuous-scan banner (continuous mode). Pointing the
        // camera at the same code twice with a "look-away" in between
        // is no longer enough — the user has to explicitly say
        // "I'm done with this scan" first. This is what the user
        // asked for: literal same-value avoidance.
        .onReceive(reticleTimer) { _ in
            guard detectedRect != nil else { return }
            if Date().timeIntervalSince(lastDetectionAt) > reticleResetGrace {
                detectedRect = nil
            }
        }
    }

    // MARK: - Reticle watchdog

    /// How long the corner reticle stays locked on the last detection
    /// after the camera stops seeing any code. Long enough to ride out
    /// brief recogniser stutters, short enough to feel responsive when
    /// the code actually leaves the frame.
    private let reticleResetGrace: TimeInterval = 0.5

    /// Drives the watchdog above. `.common` keeps it firing while the
    /// user is interacting (otherwise it would pause during scrolls).
    private var reticleTimer: Publishers.Autoconnect<Timer.TimerPublisher> {
        Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()
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
        let now = Date()
        // Always refresh the reticle and the watchdog timestamp, even if
        // the value is a duplicate that the dedupe will swallow. This
        // keeps the corner brackets locked onto a code that's still
        // being held in front of the camera, instead of snapping back
        // to the centred default while the user lingers on the
        // result sheet.
        lastDetectionAt = now
        if let rect = code.previewRect {
            detectedRect = rect
        }
        // Primary dedupe: don't re-handle the *same value* until the
        // camera has visibly moved off the code (the watchdog clears
        // `lastHandledValue` on grace-period frame-emptiness). This
        // is what stops a single code held in view from being saved
        // every 1.5 s in continuous mode or re-popping the sheet
        // each time the time window expired.
        if let last = lastHandledValue, last == code.value {
            return
        }
        // Secondary safety net: a transient flip "code A → code B → code A"
        // (oscillating recogniser) would otherwise keep re-saving once
        // per pair of frames. Keep the original 1.5 s time-window
        // dedupe as a guard for that pathology.
        if code.value == lastValue, now.timeIntervalSince(lastValueAt) < dedupeWindow {
            return
        }
        lastValue = code.value
        lastValueAt = now
        lastHandledValue = code.value
        emitScanFeedback()
        if continuousScan {
            // Persist directly, surface a banner, and stay in the
            // camera — no sheet. Power-user "warehouse / event
            // check-in" flow.
            saveScan(code, notes: nil)
            withAnimation { lastContinuousScan = code }
        } else {
            sheetCode = code
        }
    }

    /// Overlay rendered on top of the camera preview when more than
    /// one code is in frame. Numbered chips at each code's `previewRect`,
    /// plus a translucent "Pick a code" banner at the top. Tapping a
    /// chip routes through the normal scan pipeline.
    @ViewBuilder
    private var multiCodeOverlay: some View {
        ZStack {
            // Dimmed backdrop helps the chips stand out against a
            // busy real-world scene without obscuring the camera.
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture {
                    // Tapping outside any chip dismisses the chooser
                    // — useful when the user changes their mind and
                    // wants to point the camera elsewhere.
                    multiCodeChoices = []
                }

            VStack {
                Label("Multiple codes — tap one", systemImage: "square.stack.3d.up")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 12)
                Spacer()
            }

            // Each chip positioned at its bounding-rect centre. A
            // GeometryReader is overkill — the rects are already in
            // CameraScannerView's coordinate space which matches
            // ours since both fill the screen edge-to-edge.
            ForEach(Array(multiCodeChoices.enumerated()), id: \.element.id) { (idx, code) in
                let rect = code.previewRect ?? CGRect(x: 100, y: 100 + CGFloat(idx) * 80,
                                                       width: 60, height: 60)
                Button {
                    selectFromChoices(code)
                } label: {
                    Text("\(idx + 1)")
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                        .shadow(radius: 3)
                }
                .accessibilityLabel("Pick code \(idx + 1): \(code.value)")
                .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    /// Called from `CameraScannerView.onScanBatch` whenever a frame
    /// contains *any* recognised codes. When count == 1 the
    /// single-code `onScan` path has already fired (handled in
    /// CameraScannerView's coordinator), so we just clear the
    /// chooser overlay. When count > 1 we drop into the chooser.
    private func handleScanBatch(_ codes: [ScannedCode]) {
        if codes.count > 1 {
            // Don't present a result sheet — let the user pick.
            // Suppress the haptic / sound here as well; firing once
            // per batch + once again after pick would feel chatty.
            multiCodeChoices = codes
            // Refresh the watchdog so the corner reticle still
            // tracks *something* — pick the largest rect, which is
            // typically the closest code.
            lastDetectionAt = Date()
            if let widest = codes.compactMap(\.previewRect).max(by: { $0.width < $1.width }) {
                detectedRect = widest
            }
        } else if !multiCodeChoices.isEmpty {
            multiCodeChoices = []
        }
    }

    /// User picked one of the multi-code chips. Clears the chooser
    /// and routes through the normal `handleScan` path so dedupe,
    /// continuous-scan, feedback, and history-save all stay
    /// consistent.
    private func selectFromChoices(_ code: ScannedCode) {
        multiCodeChoices = []
        // Bypass *both* dedupe gates — the user explicitly tapped
        // this one, even if it was previously handled.
        lastValue = nil
        lastHandledValue = nil
        handleScan(code)
    }

    /// Centralised so both live and continuous-scan paths trigger
    /// haptic + sound under the same gating. Cheap to instantiate the
    /// generator on each call; system caches the underlying engine.
    private func emitScanFeedback() {
        if hapticOnScan {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        if soundOnScan {
            ScanSound.playScanned()
        }
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
        // Don't apply the live-scan debounce to imports — the user
        // intentionally chose this image, so we always present the
        // sheet (even when continuous-scan mode is on for the camera
        // path). Feedback still respects the user's prefs.
        lastValue = first.value
        lastValueAt = Date()
        sheetCode = first
        emitScanFeedback()
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
