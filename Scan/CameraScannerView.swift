//
//  CameraScannerView.swift
//  Scan
//
//  SwiftUI wrapper around AVCaptureSession + AVCaptureMetadataOutput
//  that streams decoded barcode/QR results back to the host view.
//

import SwiftUI
import AVFoundation

// `ScannedCode` lives in its own file (`ScannedCode.swift`) so that
// the share-extension target can pull it in without also pulling in
// the AVCaptureSession code below.

struct CameraScannerView: UIViewControllerRepresentable {
    /// Streamed each time a *single* recognised code is decoded. Kept
    /// for callers that don't care about multi-code disambiguation —
    /// it fires on every batch where there's exactly one code, and is
    /// silenced when there are multiple (host picks via `onScanBatch`).
    var onScan: (ScannedCode) -> Void
    /// Streamed every time the camera reports recognised codes — even
    /// when more than one is in frame at once. Host renders a chooser
    /// when `count > 1`. Empty arrays are *not* delivered.
    var onScanBatch: ([ScannedCode]) -> Void = { _ in }
    /// Called with a user-facing failure reason when the camera can't start.
    var onFailure: (String) -> Void
    /// When true, the session is paused; toggle to resume after handling a result.
    var isPaused: Bool = false
    /// When true, torch is on (if the device has one).
    var isTorchOn: Bool = false

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: ScannerViewController, context: Context) {
        context.coordinator.parent = self
        vc.setPaused(isPaused)
        vc.setTorch(on: isTorchOn)
    }

    /// SwiftUI is removing this camera — the switch to Live Text, which
    /// brings its own. Release the session now rather than whenever the
    /// controller happens to deallocate.
    static func dismantleUIViewController(_ vc: ScannerViewController, coordinator: Coordinator) {
        vc.tearDown()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, ScannerViewControllerDelegate {
        var parent: CameraScannerView
        init(_ parent: CameraScannerView) { self.parent = parent }

        func scanner(_ vc: ScannerViewController, didDecodeBatch codes: [ScannedCode]) {
            guard !codes.isEmpty else { return }
            parent.onScanBatch(codes)
            // Single-code convenience: only fire `onScan` when there's
            // unambiguously one thing in frame. Multi-code batches go
            // through the chooser UI in the host instead.
            if codes.count == 1, let only = codes.first {
                parent.onScan(only)
            }
        }
        func scanner(_ vc: ScannerViewController, didFailWith reason: String) {
            parent.onFailure(reason)
        }
    }
}

// MARK: - UIKit scanner

protocol ScannerViewControllerDelegate: AnyObject {
    func scanner(_ vc: ScannerViewController, didDecodeBatch codes: [ScannedCode])
    func scanner(_ vc: ScannerViewController, didFailWith reason: String)
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate, UIGestureRecognizerDelegate {
    weak var delegate: ScannerViewControllerDelegate?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "me.nettrash.Scan.sessionQueue")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var metadataOutput: AVCaptureMetadataOutput?
    private weak var captureDevice: AVCaptureDevice?
    private var hasConfigured = false

    // Run state, main thread only. The session runs while the view is in a
    // window, the host hasn't paused it and SwiftUI hasn't dismantled it —
    // never merely because `updateUIViewController` ran: ScannerScreen
    // re-renders while another tab is showing (a Settings toggle it reads
    // is enough), and "not paused" must not restart the camera, or light
    // the torch, behind that tab.
    private var isInWindow = false
    /// Between `viewWillDisappear` and the next `viewWillAppear` (or the
    /// next time the view enters a window).
    private var isDisappearing = false
    private var isPausedByHost = false
    private var isTornDown = false
    private var wantsTorch = false
    /// Whether the torch is on because this controller lit it. Only that
    /// torch is ours to put out.
    private var litTorch = false

    private var shouldRun: Bool {
        isInWindow && !isDisappearing && !isPausedByHost && !isTornDown
    }

    /// Fraction of the preview's shorter side used for the centred
    /// region-of-interest. Codes outside this rect are not delivered
    /// by AVFoundation — saves cycles and stops a stray code at the
    /// edge of the frame from competing with the centred one the
    /// user is actually trying to scan. The 0.78 factor is sized to
    /// be slightly larger than the SwiftUI reticle (260×260 pt) on a
    /// typical phone preview, so anything visually inside the
    /// brackets is also inside the ROI.
    private let roiFraction: CGFloat = 0.78

    override func loadView() {
        // Window membership is the "on screen" signal that holds however
        // SwiftUI inserts this controller (a tab switch takes the view out
        // of the window); the appearance callbacks below add to it.
        let root = CameraHostView()
        root.onWindowChange = { [weak self] inWindow in
            guard let self else { return }
            self.isInWindow = inWindow
            if inWindow { self.isDisappearing = false }
            self.updateRunState()
        }
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSessionIfNeeded()
        installPinchGesture()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        updatePreviewOrientation()
        applyRectOfInterest()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isDisappearing = false
        updateRunState()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isDisappearing = true
        updateRunState()
    }

    // MARK: - Public controls

    /// The host's pause (an imported image is decoding). Acts on a change
    /// only — SwiftUI calls this on every update.
    func setPaused(_ paused: Bool) {
        guard paused != isPausedByHost else { return }
        isPausedByHost = paused
        updateRunState()
    }

    /// Re-applied on every update, which is cheap when nothing changed and
    /// heals a torch the session reset when it started.
    func setTorch(on: Bool) {
        wantsTorch = on
        applyTorch()
    }

    /// The camera is going away for good (see `dismantleUIViewController`).
    /// The torch is left alone: the Live Text camera taking over the lens
    /// sets its own.
    func tearDown() {
        isTornDown = true
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    /// Starts or stops the session to match `shouldRun`. The session queue
    /// runs the requests in order, so the last one wins.
    private func updateRunState() {
        let run = shouldRun
        if !run { applyTorch() }
        sessionQueue.async { [weak self, session] in
            if run {
                // No inputs yet: `buildSession` calls back here when done.
                guard !session.inputs.isEmpty, !session.isRunning else { return }
                session.startRunning()
                DispatchQueue.main.async { self?.applyTorch() }
            } else if session.isRunning {
                session.stopRunning()
            }
        }
    }

    /// The torch follows `wantsTorch` while the camera runs for this screen
    /// and is off otherwise — a torch set with no session behind it would
    /// stay lit as a flashlight. Best-effort, as before.
    private func applyTorch() {
        guard !isTornDown else { return }
        let on = wantsTorch && shouldRun
        guard on || litTorch,
              let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }
        if device.torchMode == (on ? .on : .off) {
            litTorch = on
            return
        }
        if on, !device.isTorchAvailable { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if on {
                try device.setTorchModeOn(level: 1.0)
            } else {
                device.torchMode = .off
            }
            litTorch = on
        } catch {
            // Best-effort; another client may hold the configuration.
        }
    }

    // MARK: - Setup

    private func configureSessionIfNeeded() {
        guard !hasConfigured else { return }
        hasConfigured = true

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            buildSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if granted {
                        self.buildSession()
                    } else {
                        self.delegate?.scanner(self, didFailWith: "Camera access was denied. Enable it in Settings to scan codes.")
                    }
                }
            }
        default:
            // On the next turn, as the paths above report: this runs from
            // `viewDidLoad`, inside SwiftUI's update, where the host's
            // state change would be dropped and the screen left blank.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.scanner(self, didFailWith: "Camera access is not allowed. Enable it in Settings to scan codes.")
            }
        }
    }

    private func buildSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()

            guard
                let device = AVCaptureDevice.default(for: .video),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input)
            else {
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.delegate?.scanner(self, didFailWith: "No camera available on this device.")
                }
                return
            }
            self.session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard self.session.canAddOutput(output) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.delegate?.scanner(self, didFailWith: "Couldn't attach metadata output.")
                }
                return
            }
            self.session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)

            // Filter desired types to only those supported by this device/OS.
            let desired = SupportedSymbologies.all
            let available = Set(output.availableMetadataObjectTypes)
            output.metadataObjectTypes = desired.filter { available.contains($0) }

            self.session.commitConfiguration()

            DispatchQueue.main.async {
                let layer = AVCaptureVideoPreviewLayer(session: self.session)
                layer.videoGravity = .resizeAspectFill
                layer.frame = self.view.bounds
                self.view.layer.addSublayer(layer)
                self.previewLayer = layer
                self.metadataOutput = output
                self.captureDevice = device
                self.updatePreviewOrientation()
                self.applyRectOfInterest()
                self.updateRunState()
            }
        }
    }

    // MARK: - Region-of-interest

    /// Compute a centred square ROI in the preview layer's coordinate
    /// space, then ask the preview layer to convert that to the
    /// metadata output's normalised coordinate space (0..1, top-left
    /// origin) and apply it. Re-runs on every layout pass so rotation
    /// and split-screen resizes don't leave a stale rect.
    private func applyRectOfInterest() {
        guard let previewLayer = previewLayer,
              let output = metadataOutput,
              previewLayer.bounds.width > 0,
              previewLayer.bounds.height > 0
        else { return }

        let layerSize = previewLayer.bounds.size
        let side = min(layerSize.width, layerSize.height) * roiFraction
        let layerRect = CGRect(
            x: (layerSize.width  - side) / 2,
            y: (layerSize.height - side) / 2,
            width: side,
            height: side
        )
        let metadataRect = previewLayer.metadataOutputRectConverted(fromLayerRect: layerRect)
        // metadataOutputRectConverted can return out-of-range values
        // briefly during layout — clamp to [0,1] so we never hand
        // AVFoundation a garbage rect (it logs noisy warnings and
        // falls back to full-frame in that case).
        let clamped = CGRect(
            x: metadataRect.origin.x.clamped(to: 0...1),
            y: metadataRect.origin.y.clamped(to: 0...1),
            width: max(0, min(metadataRect.width,
                              1 - metadataRect.origin.x.clamped(to: 0...1))),
            height: max(0, min(metadataRect.height,
                               1 - metadataRect.origin.y.clamped(to: 0...1)))
        )
        if clamped.width > 0 && clamped.height > 0 {
            output.rectOfInterest = clamped
        }
    }

    // MARK: - Pinch-to-zoom

    private var pinchStartZoom: CGFloat = 1.0

    /// Attaches a single pinch recogniser to the controller's view.
    /// Lives in `viewDidLoad` because the view is in scope and
    /// pinch state survives layout / orientation changes.
    private func installPinchGesture() {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        view.addGestureRecognizer(pinch)
    }

    @objc
    private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard let device = captureDevice else { return }

        switch recognizer.state {
        case .began:
            pinchStartZoom = device.videoZoomFactor
        case .changed:
            let target = pinchStartZoom * recognizer.scale
            // `min/maxAvailableVideoZoomFactor` reflect the
            // *currently usable* range — they collapse around the
            // active format's natural zoom on multi-lens devices,
            // so reading them every frame is safer than caching.
            let lower = max(device.minAvailableVideoZoomFactor, 1.0)
            let upper = min(device.maxAvailableVideoZoomFactor, 8.0) // cap at 8× — anything more is just blur
            let clamped = max(lower, min(upper, target))
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch {
                // Zoom is best-effort. A locked configuration on
                // another thread loses to that thread; we'll pick
                // up the next pinch frame.
            }
        default:
            break
        }
    }

    private func updatePreviewOrientation() {
        guard let connection = previewLayer?.connection else { return }

        // Mac Catalyst: the Mac webcam (built-in FaceTime HD or
        // Continuity Camera) delivers frames in its sensor's native
        // landscape orientation, but `effectiveGeometry.interfaceOrientation`
        // on a Catalyst window is always reported as `.portrait`, so the
        // iPhone rotation map below would request 90° and tilt the
        // preview. Force 0° to let the landscape frame pass straight
        // through to the preview layer, which then aspect-fills into
        // whatever shape the Catalyst window currently is.
        if Platform.isMacCatalyst {
            if connection.isVideoRotationAngleSupported(0) {
                connection.videoRotationAngle = 0
            }
            return
        }

        // Note: the Designed-for-iPad-on-Mac destination is no longer
        // shipped (`SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO` in the
        // pbxproj) — that runtime layered its own opaque rotation
        // transform on top of any `videoRotationAngle` value, so no
        // single setting could land the preview upright. Catalyst is
        // the canonical Mac experience and is handled above. The
        // `Platform.isMac` predicate stays defined in `Platform.swift`
        // as defensive plumbing in case the Designed-for-iPad-on-Mac
        // destination is ever re-enabled.

        // Real iOS devices (iPhone / iPad, including iPad in any
        // orientation): track the window scene's interface orientation.
        guard let scene = view.window?.windowScene else { return }
        let orient = scene.effectiveGeometry.interfaceOrientation
        let angle = Self.videoRotationAngle(for: orient)
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    /// Map a UI orientation to the rotation angle the iOS 17+
    /// `AVCaptureConnection.videoRotationAngle` API expects. Mapping
    /// covers the back camera; the front camera is mirrored at the
    /// layer level by AVFoundation, so the same angles apply.
    ///
    /// Not used on Mac Catalyst — see `updatePreviewOrientation()`
    /// above for the early-return that bypasses this entire mapping.
    private static func videoRotationAngle(for orient: UIInterfaceOrientation) -> CGFloat {
        switch orient {
        case .portrait:           return 90
        case .portraitUpsideDown: return 270
        case .landscapeLeft:      return 180
        case .landscapeRight:     return 0
        default:                  return 90
        }
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        // A frame still in flight when SwiftUI dismantled this camera
        // belongs to the mode the user just left.
        guard !isTornDown else { return }
        // Collect *all* readable codes in the frame — the SwiftUI
        // host decides what to do with multiplicity (single-code path
        // goes straight through; multi-code path renders a chooser).
        // Dedupe on `value` while preserving order so the same payload
        // recognised twice in a frame doesn't show as two chooser chips.
        var seen = Set<String>()
        var batch: [ScannedCode] = []
        let now = Date()
        for obj in metadataObjects {
            guard let readable = obj as? AVMetadataMachineReadableCodeObject,
                  let value = readable.stringValue,
                  !value.isEmpty,
                  !seen.contains(value) else { continue }
            seen.insert(value)
            // Transform the metadata object into the preview layer's
            // coordinate space — the resulting `bounds` is then in points
            // inside the view (top-left origin), ready to drive the
            // SwiftUI overlay reticle.
            let transformed = previewLayer?.transformedMetadataObject(for: readable)
                as? AVMetadataMachineReadableCodeObject
            batch.append(ScannedCode(
                value: value,
                symbology: Symbology(readable.type),
                avType: readable.type.rawValue,
                timestamp: now,
                previewRect: transformed?.bounds
            ))
        }
        guard !batch.isEmpty else { return }
        delegate?.scanner(self, didDecodeBatch: batch)
    }
}

// MARK: - Helpers

/// The scanner's root view; reports when it enters or leaves a window.
private final class CameraHostView: UIView {
    var onWindowChange: ((Bool) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?(window != nil)
    }
}

private extension Comparable {
    /// Clamp a value to a closed range. Used by the ROI mapping to
    /// guard against the brief out-of-range values that
    /// `metadataOutputRectConverted(fromLayerRect:)` can return
    /// during layout transitions.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
