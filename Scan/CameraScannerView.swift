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

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: ScannerViewControllerDelegate?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "me.nettrash.Scan.sessionQueue")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasConfigured = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSessionIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        updatePreviewOrientation()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startIfPossible()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    // MARK: - Public controls

    func setPaused(_ paused: Bool) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if paused {
                if self.session.isRunning { self.session.stopRunning() }
            } else {
                if !self.session.isRunning { self.session.startRunning() }
            }
        }
    }

    func setTorch(on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if on {
                try? device.setTorchModeOn(level: 1.0)
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
        } catch {
            // Best-effort; ignore failures.
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
            self.delegate?.scanner(self, didFailWith: "Camera access is not allowed. Enable it in Settings to scan codes.")
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
                self.updatePreviewOrientation()
                self.startIfPossible()
            }
        }
    }

    private func startIfPossible() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.session.inputs.isEmpty { return }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    private func updatePreviewOrientation() {
        guard let connection = previewLayer?.connection,
              let scene = view.window?.windowScene else { return }
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
