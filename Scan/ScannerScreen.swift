//
//  ScannerScreen.swift
//  Scan
//
//  Live-camera scanning screen. Hosts the camera for the current scan mode
//  (CameraScannerView for Codes and Bulk, the VisionKit viewfinder for Live
//  Text), debounces results, shows a result sheet, and persists scans to
//  Core Data. Also lets the user import an image from the photo library or
//  Files and decode it with Vision.
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
    /// 1.10 — Codes / Live Text / Bulk, stored as `ScanMode.storedValue`.
    /// Persisted so reopening the app returns the user to the mode they were
    /// actually working in; the Start Scanning intent writes the same key.
    @AppStorage(ScanSettingsKey.scanMode) private var modeRaw: String = ScanMode.codes.storedValue
    /// Bulk capture state. `@StateObject` so the collected list survives the
    /// result sheet, mode and tab switches and a trip to the background for
    /// the lifetime of the screen — in memory only; see `syncBulk()`.
    @StateObject private var bulk = BulkScanSession()
    @State private var showBulkSheet = false
    /// Whether this tab is on screen (between `onAppear` and `onDisappear`).
    /// Bulk only collects while it is.
    @State private var isOnScreen = false
    @Environment(\.scenePhase) private var scenePhase
    /// Start Scanning's "show the camera" (`revealCamera()`).
    @ObservedObject private var intentRouter = ScanIntentRouter.shared
    /// Text the user tapped in Live Text mode, awaiting copy / translate.
    @State private var recognizedText: String?
    /// How many codes the last frame contained — the tamper signal the
    /// safety inspector uses ("two codes in one frame" is a sticker).
    @State private var lastFrameCodeCount = 1
    /// `lastFrameCodeCount` as it was when each on-screen scan was handled,
    /// keyed by scan. The camera keeps running under the result sheet, so
    /// the live count would otherwise rewrite the verdict on a code the user
    /// is already reading. NFC reads and imports have no entry and count as
    /// one code.
    @State private var frameCounts: [UUID: Int] = [:]
    /// NFC tag reading. A tag decode lands in the same result sheet as a
    /// camera scan, so every smart action and the safety inspector apply.
    @StateObject private var nfc = NFCTagWriter()

    // Live Text state
    /// Reaches the VisionKit viewfinder for a still frame.
    @State private var liveTextHandle = LiveTextCameraHandle()
    /// Set when VisionKit gave up; the tab falls back to the Codes camera
    /// until the user picks Live Text again.
    @State private var liveTextFailure: LiveTextUnavailable?
    /// A one-line notice that clears itself (a failed start or capture).
    @State private var liveTextNote: String?
    /// Distinct codes VisionKit has in view, for the "tap one" hint.
    @State private var liveTextCodesInView = 0
    /// A still the user froze for word-level Live Text selection.
    @State private var frozenFrame: FrozenFrame?
    @State private var isFreezing = false

    /// The mode the tab is actually in. A stored Live Text falls back to
    /// Codes where VisionKit can't run, or after it failed to start — the
    /// same rule the Android port applies to its stored mode.
    private var mode: ScanMode {
        let stored = ScanMode(storedValue: modeRaw)
        if stored == .text, liveTextFailure != nil || !ScanMode.isAvailable(.text) {
            return .codes
        }
        return stored
    }

    /// A still the user froze in Live Text mode. Identifiable so a second
    /// freeze rebuilds the view (and re-runs the analysis).
    private struct FrozenFrame: Identifiable {
        let id = UUID()
        let image: UIImage
    }

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
    @State private var isDecoding = false
    @State private var importErrorMessage: String?
    @State private var showImportError = false

    private let dedupeWindow: TimeInterval = 1.5

    var body: some View {
        Group {
            if Platform.isVisionOS {
                // Vision Pro doesn't expose its world cameras to third-party
                // App Store apps (the ARKit `main-camera-access` entitlement
                // is enterprise-only and gated on managed deployment), so
                // the live-camera path is unreachable here. Surface
                // image-import as the *primary* affordance instead — and
                // critically, don't even build a `CameraScannerView`,
                // which would otherwise spin up an `AVCaptureSession`
                // that is going to fail and leave the user staring at a
                // failure banner on what is supposed to be the home tab.
                visionOSImportLayout
            } else {
                cameraScannerLayout
            }
        }
        .navigationTitle("Scan")
        .navigationBarTitleDisplayMode(.inline)
        .photosPicker(
            isPresented: $showPhotoPickerInternal,
            selection: $photoItem,
            matching: .images
        )
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
                codesInFrame: frameCounts[scan.id] ?? 1,
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
        // Start Scanning App Intent — see `ScanIntentRouter`. ContentView
        // brings this tab forward; this screen clears its own cover.
        .onValueChange(of: intentRouter.scannerRequests) { _ in
            revealCamera()
        }
    }

    // MARK: - Camera-scanner layout (iPhone / iPad / Mac Catalyst)

    /// Edge-to-edge live preview with overlays — the standard Scan-tab
    /// experience on every destination *except* visionOS. Extracted into
    /// a computed property so the body can branch cleanly on host
    /// platform (see `Platform.isVisionOS`).
    private var cameraScannerLayout: some View {
        ZStack {
            // Exactly one camera exists at a time: switching between Live
            // Text and the other modes tears one down before the next one
            // starts on appearance, so two sessions never fight over the
            // lens.
            cameraSurface

            // Reticle: snaps to the detected code's bounds when the camera
            // sees one, otherwise centres a default-size square as a hint
            // of where to point the lens. The animation gives the user
            // visible confirmation that a code was just recognised. Live
            // Text has VisionKit's own highlights instead.
            if mode != .text {
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
            }

            VStack {
                Spacer()
                HStack {
                    importMenu
                        .padding(.leading, 24)
                    if NFCTagWriter.isSupported {
                        Button {
                            nfc.read { _, raw in
                                sheetCode = ScannedCode(
                                    value: raw,
                                    symbology: .unknown,
                                    avType: "NDEF",
                                    timestamp: Date(),
                                    previewRect: nil)
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            }
                        } label: {
                            Image(systemName: "wave.3.right")
                                .font(.title2)
                                .padding(14)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .accessibilityLabel("Read an NFC tag")
                        .padding(.leading, 12)
                    }
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
            // Camera chrome is dark in every appearance, as in the system
            // Camera app and on Android: over a dark viewfinder a Light Mode
            // material turns mid-grey and dark text on it becomes unreadable.
            // Set per overlay, never on the whole ZStack — the bulk sheet
            // hangs off it and would inherit the scheme.
            .environment(\.colorScheme, .dark)

            // Live Text's shutter: freezes the frame so single words can be
            // selected — the live scanner only ever reports whole blocks.
            if mode == .text {
                VStack {
                    Spacer()
                    Button {
                        freezeFrame()
                    } label: {
                        Image(systemName: "text.viewfinder")
                            .font(.title2)
                            .padding(14)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .disabled(isFreezing)
                    .accessibilityLabel("Select words in this frame")
                    .padding(.bottom, 32)
                }
                .environment(\.colorScheme, .dark)
            }

            if isDecoding {
                ProgressView("Reading image…")
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .environment(\.colorScheme, .dark)
            }

            // Reported by the AVFoundation camera, so it only describes the
            // screen while that camera is the one showing.
            if let failureReason, mode != .text {
                VStack {
                    Spacer()
                    Text(failureReason)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding()
                    Spacer().frame(height: 100)
                }
                .environment(\.colorScheme, .dark)
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

            modeChrome
                .environment(\.colorScheme, .dark)

            if let frozenFrame {
                FrozenFrameTextView(image: frozenFrame.image) {
                    withAnimation(.easeInOut(duration: 0.2)) { self.frozenFrame = nil }
                }
                .id(frozenFrame.id)
                .transition(.opacity)
            }
        }
        .onAppear {
            isOnScreen = true
            syncBulk()
        }
        .onDisappear {
            isOnScreen = false
            syncBulk()
        }
        .onChange(of: scenePhase) {
            syncBulk()
        }
        .onChange(of: mode) { _, newMode in
            modeDidChange(to: newMode)
        }
        .task(id: liveTextNote) {
            guard liveTextNote != nil else { return }
            do {
                try await Task.sleep(for: .seconds(4))
            } catch {
                // Replaced by a newer note (or the view went away); that
                // note runs its own timer.
                return
            }
            withAnimation { liveTextNote = nil }
        }
        .sheet(isPresented: $showBulkSheet) {
            BulkCaptureSheet(bulk: bulk)
                .presentationDetents([.medium, .large])
        }
    }

    /// The camera for the current mode.
    @ViewBuilder
    private var cameraSurface: some View {
        if mode == .text {
            LiveTextCameraView(
                onCodesInView: { codes in
                    liveTextCodesInView = codes.count
                    lastFrameCodeCount = max(codes.count, 1)
                },
                onCodeAppeared: { code in
                    handleScan(code)
                },
                onCodeTapped: { code in
                    // An explicit tap, so it bypasses the dedupe exactly as
                    // a chooser chip does.
                    selectFromChoices(code)
                },
                onTextTapped: { block in
                    withAnimation(.snappy) { recognizedText = block.text }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                },
                onUnavailable: { reason in
                    liveTextFailure = reason
                    liveTextNote = reason.message
                },
                isPaused: isDecoding || frozenFrame != nil,
                isTorchOn: torchOn,
                handle: liveTextHandle
            )
            .ignoresSafeArea()
        } else {
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
        }
    }

    // MARK: - Mode chrome

    /// The mode switch with its footnote, the bulk-capture HUD, the
    /// transient notices, and the Live Text result card. Kept in one place
    /// so the camera ZStack above stays about the camera. The stacks have no
    /// background, so taps between the controls still reach the camera
    /// (VisionKit's text highlights, the chooser chips).
    private var modeChrome: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    modePicker
                    // The per-mode hint, as Android shows under its picker.
                    Text(mode.footnote)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                Spacer(minLength: 8)
                if mode == .bulk && !bulk.isEmpty {
                    bulkHUD
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            if showsPickOneHint {
                Label("Multiple codes — tap one", systemImage: "square.stack.3d.up")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.opacity)
            }

            if let liveTextNote {
                Text(liveTextNote)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .transition(.opacity)
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
                continuousBanner(last)
            }

            Spacer()

            if mode == .text, let recognizedText {
                RecognizedTextCard(text: recognizedText) {
                    withAnimation { self.recognizedText = nil }
                }
                // A new block is a new card: copy state and any translation
                // belong to the text they were made for.
                .id(recognizedText)
                .padding(.horizontal)
                // Clears the bottom controls.
                .padding(.bottom, 100)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var modePicker: some View {
        Picker("Scan mode", selection: Binding(
            get: { mode },
            set: { select($0) })) {
            ForEach(ScanMode.allCases.filter { ScanMode.isAvailable($0) }) { m in
                Label(m.label, systemImage: m.symbol).tag(m)
            }
        }
        .pickerStyle(.menu)
        .tint(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        // The title is the label ("Scan mode"); VoiceOver gets the current
        // mode as the value, which a menu picker otherwise leaves empty.
        .accessibilityValue(mode.label)
    }

    private var bulkHUD: some View {
        Button {
            showBulkSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.down.right.fill")
                Text("\(bulk.count)")
                    .monospacedDigit()
                if bulk.isFull {
                    // New codes stop counting at the cap; say so while
                    // scanning, not only in the sheet.
                    Text("Limit reached")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .accessibilityLabel("\(bulk.count) codes captured, open list")
    }

    /// "Multiple codes — tap one": over the chooser chips in Codes mode, and
    /// over VisionKit's highlights in Live Text, where two codes in view are
    /// never opened on a guess.
    private var showsPickOneHint: Bool {
        switch mode {
        case .codes: return !multiCodeChoices.isEmpty
        case .text:  return liveTextCodesInView > 1
        case .bulk:  return false
        }
    }

    private func continuousBanner(_ last: ScannedCode) -> some View {
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
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// The picker's setter. Choosing Live Text again is also the retry after
    /// VisionKit failed to start.
    private func select(_ newMode: ScanMode) {
        if newMode == .text { liveTextFailure = nil }
        withAnimation(.snappy) { modeRaw = newMode.storedValue }
    }

    /// Bulk collects only while it is the mode on screen in an app that
    /// isn't in the background. Leaving it — for Codes or Live Text, another
    /// tab, or the background — pauses the capture and keeps the list, and
    /// coming back resumes the same list with the counter showing it; only
    /// Clear in the bulk sheet empties it. The Android port does the same
    /// with its `LifecycleStartEffect(mode)`.
    private func syncBulk() {
        if mode == .bulk, isOnScreen, scenePhase != .background {
            bulk.start()
        } else {
            bulk.stop()
        }
    }

    /// Runs for every change of the effective mode — the picker, the Start
    /// Scanning intent, or Live Text falling back to Codes — so nothing on
    /// screen outlives the camera it came from. A bulk list is the
    /// exception: it is paused, not dropped.
    private func modeDidChange(to newMode: ScanMode) {
        syncBulk()
        multiCodeChoices = []
        recognizedText = nil
        frozenFrame = nil
        liveTextCodesInView = 0
        lastFrameCodeCount = 1
        detectedRect = nil
    }

    /// Start Scanning asked for the camera: take down everything this
    /// screen puts over the viewfinder — the result sheet (its dismissal
    /// releases the same-value dedupe, as Done does), the bulk sheet, the
    /// recognised-text card, a frozen frame, the multi-code chooser, the
    /// photo picker, the Files picker, an import alert and a pending NFC
    /// read — so the intent lands on a live camera. Nothing is lost: the
    /// bulk list stays, and so does History. Asking for Live Text this way
    /// is also the retry after VisionKit gave up, as picking it in the menu
    /// is. (`ContentView` takes down what other tabs presented.)
    private func revealCamera() {
        sheetCode = nil
        showBulkSheet = false
        recognizedText = nil
        frozenFrame = nil
        multiCodeChoices = []
        showPhotoPickerInternal = false
        DocumentPicker.dismissIfPresented()
        showImportError = false
        if nfc.status == .scanning { nfc.cancel() }
        if ScanMode(storedValue: modeRaw) == .text { liveTextFailure = nil }
    }

    /// Captures the viewfinder and opens it with Live Text on top. The live
    /// scanner pauses while the still is up.
    private func freezeFrame() {
        guard !isFreezing else { return }
        isFreezing = true
        Task {
            defer { isFreezing = false }
            do {
                let image = try await liveTextHandle.captureFrame()
                recognizedText = nil
                withAnimation(.easeInOut(duration: 0.2)) {
                    frozenFrame = FrozenFrame(image: image)
                }
            } catch {
                liveTextNote = "Couldn't capture this frame. Try again."
            }
        }
    }

    // MARK: - visionOS import-first layout

    /// Vision Pro replaces the live-camera ZStack with a static
    /// "decode an image or PDF" landing surface. The world cameras are
    /// off-limits to general App Store apps, so trying to start an
    /// `AVCaptureSession` here would only produce a failure banner.
    /// Instead we lead with two big Photo Library / Files buttons and
    /// a one-paragraph explanation so the user immediately understands
    /// what kind of scanning Scan can and can't do on their headset.
    /// Saved scans, the Generator tab, and iCloud-synced History all
    /// continue to work normally.
    private var visionOSImportLayout: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 24)
                Image(systemName: "photo.badge.arrow.down")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text("Scan an image or PDF")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text("Apple Vision Pro doesn't expose its world cameras to third-party apps, so live scanning isn't available here. Pick a screenshot, photo, or PDF and Scan will decode any codes inside it on-device.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 36)

                VStack(spacing: 14) {
                    Button {
                        showPhotoPickerInternal = true
                    } label: {
                        Label("Choose from Photos", systemImage: "photo.on.rectangle")
                            .font(.headline)
                            .frame(maxWidth: 360)
                            .frame(minHeight: 28)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        presentFilePicker()
                    } label: {
                        Label("Choose from Files", systemImage: "folder")
                            .font(.headline)
                            .frame(maxWidth: 360)
                            .frame(minHeight: 28)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.horizontal, 24)

                if isDecoding {
                    ProgressView("Reading image…")
                        .padding(.top, 4)
                }

                Spacer(minLength: 12)

                Text("History syncs across iPhone, iPad, Mac, and Vision Pro via iCloud, and the Generate tab works fully — type Wi-Fi credentials here and show the resulting QR to a guest's phone.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
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
                presentFilePicker()
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
        // Bulk collects in `handleScanBatch`, which sees every code in the
        // frame. The single-code `onScan` that follows each one-code batch
        // would otherwise count the same sighting twice.
        if mode == .bulk { return }
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
        rememberFrameCount(for: code)
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

    /// Pins the frame's code count to this scan for the result sheet. Only
    /// the scans still on screen (sheet, banner) keep their entries.
    private func rememberFrameCount(for code: ScannedCode) {
        var kept = frameCounts.filter { entry in
            entry.key == sheetCode?.id || entry.key == lastContinuousScan?.id
        }
        kept[code.id] = lastFrameCodeCount
        frameCounts = kept
    }

    /// Overlay rendered on top of the camera preview when more than
    /// one code is in frame: numbered chips at each code's `previewRect`
    /// over a dimmed backdrop. The "Multiple codes — tap one" banner lives
    /// in `modeChrome`, under the mode picker. Tapping a chip routes
    /// through the normal scan pipeline.
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

            // Each chip positioned at its bounding-rect centre. A
            // GeometryReader is overkill — the rects are already in
            // CameraScannerView's coordinate space, which matches this
            // one once it too ignores the safe area (both then fill the
            // screen edge-to-edge, as the reticle does).
            ZStack {
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
            .ignoresSafeArea()
        }
    }

    /// Called from `CameraScannerView.onScanBatch` whenever a frame
    /// contains *any* recognised codes. When count == 1 the
    /// single-code `onScan` path has already fired (handled in
    /// CameraScannerView's coordinator), so we just clear the
    /// chooser overlay. When count > 1 we drop into the chooser.
    private func handleScanBatch(_ codes: [ScannedCode]) {
        lastFrameCodeCount = max(codes.count, 1)
        if mode == .bulk, !codes.isEmpty {
            // Bulk capture collects every distinct code in the frame instead
            // of stopping at the first; no chooser, no sheet.
            var addedNew = false
            for code in codes where bulk.ingest(code) { addedNew = true }
            lastDetectionAt = Date()
            if addedNew { emitScanFeedback() }
            if !multiCodeChoices.isEmpty { multiCodeChoices = [] }
            return
        }
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

    /// User picked one of the multi-code chips (or tapped a highlighted
    /// code in Live Text). Clears the chooser and routes through the
    /// normal `handleScan` path so dedupe, continuous-scan, feedback,
    /// and history-save all stay consistent.
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

    /// Present the system document picker imperatively.
    ///
    /// SwiftUI's `.fileImporter` is unreliable on Mac Catalyst — its
    /// completion closure never fires after the NSOpenPanel closes, so the
    /// picked file is never decoded and the import silently does nothing
    /// ("I chose the file but nothing happened"). Presenting
    /// `UIDocumentPickerViewController` modally from the top view controller
    /// works on iOS *and* macOS; `asCopy: true` hands back a readable copy in
    /// the app container, so we don't juggle security-scoped access.
    @MainActor
    private func presentFilePicker() {
        DocumentPicker.pick(contentTypes: [.image, .pdf]) { url in
            Task { await handlePickedFile(url) }
        }
    }

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
        presentAfterPickerDismiss {
            sheetCode = first
            emitScanFeedback()
        }
    }

    /// Safe to call from any context — schedules itself onto the main actor.
    private func presentImportError(_ message: String) {
        presentAfterPickerDismiss {
            importErrorMessage = message
            showImportError = true
        }
    }

    /// Present a sheet / alert *after* the file or photo picker has finished
    /// dismissing.
    ///
    /// Mac Catalyst backs `.fileImporter` and `.photosPicker` with their own
    /// NSWindow modal sessions. A `.sheet` or `.alert` whose state we flip in
    /// the same runloop turn that the picker is being torn down is silently
    /// dropped by UIKit — the imported-code result (or the error) then never
    /// appears. That's the "I chose the file but nothing happened" report on
    /// macOS: the decode succeeds, but the sheet presentation is swallowed.
    /// Yielding a few hundred ms lets the picker's window go away first. On
    /// iOS we only hop to the next runloop — the race is far rarer there, but
    /// the extra beat after an explicit import tap is imperceptible and keeps
    /// the two paths on one code path.
    private func presentAfterPickerDismiss(_ present: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            if Platform.isMac {
                try? await Task.sleep(for: .milliseconds(400))
            }
            present()
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
    /// Distinct codes the camera saw alongside this one. 1 for still-image
    /// imports and history rows.
    var codesInFrame: Int = 1
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

                PayloadActionsView(payload: payload, raw: scan.value, codesInFrame: codesInFrame)

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

// MARK: - Imperative document picker (Mac Catalyst–safe)

/// A thin wrapper around `UIDocumentPickerViewController`, presented
/// imperatively from the top view controller.
///
/// Why not SwiftUI's `.fileImporter`? On **Mac Catalyst** its completion
/// closure never fires after the open panel closes, so the chosen file is
/// never handed back — the user picks a file and nothing happens. (An
/// embedded `UIDocumentPickerViewController` hosted as a `.sheet`'s content
/// misbehaves too — it expects to be *presented* modally, not hosted.)
/// Presenting it modally from the foreground scene's top view controller is
/// reliable on iOS *and* macOS. `asCopy: true` returns a readable copy in the
/// app container, so callers don't manage security-scoped access.
///
/// Lives in `ScannerScreen.swift` (a main-app-only file) so its
/// `UIApplication.shared` use never reaches the `ScanShareExtension` target,
/// where that API is unavailable.
enum DocumentPicker {
    /// Present the picker and call `onPick` with a readable copy of the
    /// chosen file. No-op if no presenter can be found.
    @MainActor
    static func pick(contentTypes: [UTType], onPick: @escaping (URL) -> Void) {
        guard let top = topViewController() else { return }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        picker.allowsMultipleSelection = false
        let delegate = Delegate(onPick: onPick)
        retained = delegate
        picker.delegate = delegate
        presented = picker
        top.present(picker, animated: true)
    }

    /// Takes the picker down without a pick — Start Scanning wants the
    /// camera. It is presented outside SwiftUI state, so nothing else would.
    @MainActor
    static func dismissIfPresented() {
        presented?.dismiss(animated: false)
        presented = nil
        retained = nil
    }

    /// Keeps the one-shot delegate alive while the picker is on screen.
    private static var retained: Delegate?
    /// The picker on screen, for `dismissIfPresented()`. Weak: UIKit owns it.
    private static weak var presented: UIDocumentPickerViewController?

    private final class Delegate: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            defer {
                DocumentPicker.retained = nil
                DocumentPicker.presented = nil
            }
            if let url = urls.first { onPick(url) }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            DocumentPicker.retained = nil
            DocumentPicker.presented = nil
        }
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

// MARK: - Live Text result

/// The text the user tapped in Live Text mode, with the three things worth
/// doing with it. Everything here is local: copy, share, and the on-device
/// translation session.
private struct RecognizedTextCard: View {
    let text: String
    let onDismiss: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Recognised text", systemImage: "text.viewfinder")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss recognised text")
            }

            // A short block shows whole; a long paragraph scrolls inside the
            // card instead of pushing it up over the viewfinder.
            ViewThatFits(in: .vertical) {
                recognizedText
                ScrollView { recognizedText }
            }
            .frame(maxHeight: 160)

            HStack(spacing: 14) {
                Button {
                    UIPasteboard.general.string = text
                    copied = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.footnote)
                }
                ShareLink(item: text) {
                    Label("Share", systemImage: "square.and.arrow.up").font(.footnote)
                }
                Spacer(minLength: 0)
            }

            TranslateRow(text: text)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var recognizedText: some View {
        Text(text)
            .font(.callout)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Bulk capture sheet

/// What Bulk mode collected: every distinct code, how many times the camera
/// saw it, and the two things an inventory flow needs next — save the lot to
/// History, or hand a CSV to a spreadsheet.
private struct BulkCaptureSheet: View {
    @ObservedObject var bulk: BulkScanSession
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var savedCount: Int?
    @State private var exportURL: URL?
    @State private var exportError: String?
    /// "Export failed" or "Couldn't save to History" — which action the
    /// alert below is about (same wording as the Android bulk sheet).
    @State private var errorTitle = "Export failed"

    var body: some View {
        NavigationStack {
            Group {
                if bulk.isEmpty {
                    ContentUnavailableView("Nothing captured yet",
                                           systemImage: "square.stack.3d.down.right",
                                           description: Text("Keep the camera moving over the codes — each distinct one lands here."))
                } else {
                    List {
                        Section {
                            ForEach(bulk.entries) { entry in
                                BulkEntryRow(entry: entry)
                            }
                            .onDelete { offsets in
                                bulk.remove(at: offsets)
                            }
                        } header: {
                            HStack {
                                Text("\(bulk.count) codes")
                                Spacer()
                                if bulk.isFull {
                                    Text("Limit reached")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Bulk capture")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            saveAll()
                        } label: {
                            Label("Save all to History", systemImage: "tray.and.arrow.down")
                        }
                        // Live again once the camera adds a code; never
                        // writes an entry twice.
                        .disabled(!bulk.hasUnsavedEntries)

                        if let exportURL {
                            ShareLink(item: exportURL) {
                                Label("Share CSV", systemImage: "square.and.arrow.up")
                            }
                        } else {
                            Button {
                                export()
                            } label: {
                                Label("Export CSV", systemImage: "tablecells")
                            }
                            .disabled(bulk.isEmpty)
                        }

                        Button(role: .destructive) {
                            bulk.reset()
                            savedCount = nil
                            exportURL = nil
                        } label: {
                            Label("Clear", systemImage: "trash")
                        }
                        .disabled(bulk.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(bulk.isEmpty)
                }
            }
            .overlay(alignment: .bottom) {
                if let savedCount {
                    Label("\(savedCount) saved to History", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .padding(10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 18)
                        .transition(.opacity)
                }
            }
            .alert(errorTitle,
                   isPresented: Binding(
                       get: { exportError != nil },
                       set: { if !$0 { exportError = nil } }),
                   presenting: exportError) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
        // The camera keeps collecting under the sheet; an exported file
        // that no longer matches the list — a new code, or another sighting
        // of one already in it — is re-made on the next export.
        .onChange(of: bulk.csvRevision) {
            exportURL = nil
        }
    }

    /// Writes the entries no earlier Save all wrote, and reports how many.
    private func saveAll() {
        do {
            let added = try bulk.saveUnsaved(into: viewContext)
            guard added > 0 else { return }
            withAnimation { savedCount = added }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorTitle = "Couldn't save to History"
            exportError = error.localizedDescription
        }
    }

    private func export() {
        do {
            exportURL = try HistoryCSV.writeBulk(lines: bulk.csvLines())
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorTitle = "Export failed"
            exportError = error.localizedDescription
        }
    }
}

private struct BulkEntryRow: View {
    let entry: BulkScanSession.Entry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.value)
                    .font(.callout.monospaced())
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text("\(entry.symbology) · \(entry.kindLabel)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Text("\u{00D7}\(entry.sightings)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .accessibilityLabel("\(entry.sightings) sightings")
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = entry.value
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }
}
