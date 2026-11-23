//
//  VisionTextScanner.swift
//  Scan
//
//  Live Text mode's camera. VisionKit's `DataScannerViewController` reads
//  text *and* barcodes off the same viewfinder, highlights what it found and
//  reports taps on it; `ImageAnalysisInteraction` adds word-level Live Text
//  (select, then Copy / Look Up / Translate / Share from the system menu)
//  over a frozen frame. The split is VisionKit's, not ours: the live scanner
//  only ever hands back whole recognised items, and word selection exists
//  only on a still image.
//
//  Why VisionKit for this mode rather than our own AVCaptureSession: the
//  highlighting, the tap targets and the text recogniser are what people
//  judge a text reader by, and the system already does them on-device.
//  Nothing in this file talks to the network. The system menu's Look Up and
//  Translate are iOS services that may; the frozen frame's hint says so.
//
//  The AVFoundation `CameraScannerView` stays the camera for Codes and Bulk,
//  and is the fallback whenever VisionKit can't run: Mac Catalyst (where
//  `DataScannerViewController` is unavailable, so that half is compiled
//  out), Vision Pro, the Simulator, hardware Apple excludes, and a camera
//  the user hasn't allowed.
//

import SwiftUI
import AVFoundation
import Vision
import VisionKit

// MARK: - Availability

@MainActor
enum VisionTextScanner {

    /// Whether this device can run the VisionKit viewfinder at all: an
    /// A12-or-later iPhone or iPad, never the Simulator, Mac Catalyst or
    /// Vision Pro.
    static var isSupported: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return !Platform.isVisionOS && DataScannerViewController.isSupported
        #endif
    }

    /// Supported *and* usable now. VisionKit answers false once the camera
    /// is denied or restricted; a camera nobody has asked about yet still
    /// counts, because the viewfinder asks for it before it starts.
    static var isAvailable: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        guard isSupported else { return false }
        return DataScannerViewController.isAvailable
            || AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined
        #endif
    }

    /// The Vision spelling of the set the AVFoundation path asks for
    /// (`SupportedSymbologies.all`), so a code that reads in Codes mode also
    /// reads in Live Text.
    static let symbologies: [VNBarcodeSymbology] = [
        .qr, .microQR, .aztec, .pdf417, .microPDF417, .dataMatrix,
        .ean8, .ean13, .upce,
        .code39, .code39Checksum, .code39FullASCII, .code39FullASCIIChecksum,
        .code93, .code93i, .code128,
        .itf14, .i2of5, .i2of5Checksum,
        .codabar, .gs1DataBar, .gs1DataBarExpanded, .gs1DataBarLimited,
    ]
}

// MARK: - What the viewfinder reports

/// One block of text the user tapped, and where it sat in the viewfinder
/// (view coordinates, top-left origin). The Android port's
/// `RecognizedTextBlock` mirrors it.
struct RecognizedTextBlock: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let rect: CGRect?
}

/// Why the VisionKit viewfinder gave up. The Scan tab drops back to the
/// AVFoundation camera for all of them.
enum LiveTextUnavailable: Equatable {
    case cameraDenied
    case unsupported
    case failedToStart

    /// One line for the Scan tab, or nil when the fallback camera already
    /// explains it (a denied camera gets the Codes camera's own message).
    var message: String? {
        switch self {
        case .cameraDenied:
            return nil
        case .unsupported:
            return "Live Text isn't available on this device right now, so Scan is reading codes instead."
        case .failedToStart:
            return "Live Text couldn't start the camera, so Scan is reading codes instead."
        }
    }
}

/// Lets the Scan tab ask the live viewfinder for a still frame without
/// holding on to the view controller. Weak, so a torn-down viewfinder is
/// simply "not running".
@MainActor
final class LiveTextCameraHandle {

    enum CaptureError: LocalizedError {
        case notRunning
        var errorDescription: String? { "The camera isn't running." }
    }

    #if !targetEnvironment(macCatalyst)
    fileprivate weak var scanner: DataScannerViewController?
    #endif

    /// A full-resolution still of what the viewfinder shows right now.
    func captureFrame() async throws -> UIImage {
        #if targetEnvironment(macCatalyst)
        throw CaptureError.notRunning
        #else
        guard let scanner, scanner.isScanning else { throw CaptureError.notRunning }
        return try await scanner.capturePhoto()
        #endif
    }
}

// MARK: - SwiftUI surface

/// The Live Text viewfinder as the Scan tab hosts it. Platform-neutral so
/// the screen needs no `#if`: on Mac Catalyst `VisionTextScanner.isAvailable`
/// is false and this view is never built.
struct LiveTextCameraView: View {
    /// Every distinct barcode in view, whenever that set changes — empty
    /// once the codes leave the frame. The count is the tamper signal.
    var onCodesInView: ([ScannedCode]) -> Void
    /// A code alone in view, once per stay in the frame: the Live Text
    /// counterpart of the Codes camera's single-code read. Two or more at
    /// once are left for the user to tap, because guessing is how a tamper
    /// sticker wins.
    var onCodeAppeared: (ScannedCode) -> Void
    /// The user tapped a highlighted code.
    var onCodeTapped: (ScannedCode) -> Void
    /// The user tapped a highlighted block of text.
    var onTextTapped: (RecognizedTextBlock) -> Void
    /// VisionKit stopped for good; the host falls back to the Codes camera.
    var onUnavailable: (LiveTextUnavailable) -> Void
    /// Recognition and the camera stop while true (an import is decoding,
    /// a frozen frame is up).
    var isPaused: Bool = false
    var isTorchOn: Bool = false
    let handle: LiveTextCameraHandle

    var body: some View {
        #if targetEnvironment(macCatalyst)
        Color.black
        #else
        DataScannerRepresentable(onCodesInView: onCodesInView,
                                 onCodeAppeared: onCodeAppeared,
                                 onCodeTapped: onCodeTapped,
                                 onTextTapped: onTextTapped,
                                 onUnavailable: onUnavailable,
                                 isPaused: isPaused,
                                 isTorchOn: isTorchOn,
                                 handle: handle)
        #endif
    }
}

#if !targetEnvironment(macCatalyst)

// MARK: - DataScannerViewController bridge

/// `DataScannerViewController` bridged into SwiftUI, text and barcodes at
/// once — a menu at a café usually carries a loyalty QR next to the text,
/// and both recognisers run from the one camera session.
private struct DataScannerRepresentable: UIViewControllerRepresentable {
    var onCodesInView: ([ScannedCode]) -> Void
    var onCodeAppeared: (ScannedCode) -> Void
    var onCodeTapped: (ScannedCode) -> Void
    var onTextTapped: (RecognizedTextBlock) -> Void
    var onUnavailable: (LiveTextUnavailable) -> Void
    var isPaused: Bool
    var isTorchOn: Bool
    let handle: LiveTextCameraHandle

    func makeUIViewController(context: Context) -> LiveTextHostController {
        // `recognizedDataTypes` is fixed for the controller's lifetime, which
        // is fine: this view only ever exists in Live Text mode.
        let scanner = DataScannerViewController(
            recognizedDataTypes: [
                .text(),
                .barcode(symbologies: VisionTextScanner.symbologies),
            ],
            qualityLevel: .balanced,
            // Every block on a menu should be tappable, not just the one
            // nearest the centre.
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            // VisionKit's guidance captions sit where the mode picker is,
            // and the mode footnote already says what to do.
            isGuidanceEnabled: false,
            // The system highlights are the tap targets.
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        handle.scanner = scanner

        let host = LiveTextHostController(scanner: scanner)
        let coordinator = context.coordinator
        host.onUnavailable = { [weak coordinator] reason in
            coordinator?.parent.onUnavailable(reason)
        }
        host.isTorchOn = isTorchOn
        host.isPaused = isPaused
        coordinator.host = host
        return host
    }

    func updateUIViewController(_ host: LiveTextHostController, context: Context) {
        context.coordinator.parent = self
        handle.scanner = host.scanner
        host.isTorchOn = isTorchOn
        host.isPaused = isPaused
        host.applyTorch()
    }

    static func dismantleUIViewController(_ host: LiveTextHostController, coordinator: Coordinator) {
        host.tearDown()
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: DataScannerViewControllerDelegate {
        var parent: DataScannerRepresentable
        weak var host: LiveTextHostController?

        /// Values last reported through `onCodesInView`, so a code merely
        /// moving in the frame (VisionKit updates at frame rate) is not
        /// re-reported.
        private var valuesInView: [String] = []
        /// Items already opened on their own. A code opens once per stay in
        /// the frame — dismissing its sheet doesn't re-open it while it is
        /// still in view; leaving and coming back makes it a new item.
        private var openedItemIDs: Set<UUID> = []

        init(parent: DataScannerRepresentable) {
            self.parent = parent
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didTapOn item: RecognizedItem) {
            switch item {
            case .text(let text):
                let transcript = text.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !transcript.isEmpty else { return }
                parent.onTextTapped(RecognizedTextBlock(text: transcript,
                                                        rect: Self.rect(of: text.bounds)))
            case .barcode(let barcode):
                if let code = Self.scannedCode(barcode, at: Date()) {
                    parent.onCodeTapped(code)
                }
            @unknown default:
                break
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            report(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didUpdate updatedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            report(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didRemove removedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            report(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            switch error {
            case .cameraRestricted:
                host?.giveUp(.cameraDenied)
            case .unsupported:
                host?.giveUp(.unsupported)
            @unknown default:
                host?.giveUp(.unsupported)
            }
        }

        /// Every add / update / remove lands here with VisionKit's full list.
        /// Reports the codes in view when that set changed, then opens a code
        /// that is alone in view and hasn't been opened during this stay —
        /// whether it just arrived, its payload only now decoded, or a second
        /// code just left the frame (what the Codes camera does too).
        private func report(_ allItems: [RecognizedItem]) {
            let inView = Self.codes(in: allItems)
            let codes = inView.map(\.code)
            let values = codes.map(\.value)
            if values != valuesInView {
                valuesInView = values
                parent.onCodesInView(codes)
            }
            openedItemIDs.formIntersection(allItems.map(\.id))
            guard inView.count == 1, let only = inView.first,
                  openedItemIDs.insert(only.itemID).inserted else { return }
            parent.onCodeAppeared(only.code)
        }

        // MARK: Item → model

        /// Distinct barcodes among `items` (by value, as the Codes camera
        /// dedupes), in VisionKit's order, with the item each came from.
        private static func codes(in items: [RecognizedItem]) -> [(itemID: UUID, code: ScannedCode)] {
            var seen = Set<String>()
            let now = Date()
            return items.compactMap { item in
                guard case .barcode(let barcode) = item,
                      let code = scannedCode(barcode, at: now),
                      seen.insert(code.value).inserted else { return nil }
                return (item.id, code)
            }
        }

        private static func scannedCode(_ barcode: RecognizedItem.Barcode, at time: Date) -> ScannedCode? {
            guard let value = barcode.payloadStringValue, !value.isEmpty else { return nil }
            let symbology = barcode.observation.symbology
            return ScannedCode(value: value,
                               symbology: Symbology(visionSymbology: symbology),
                               avType: symbology.rawValue,
                               timestamp: time,
                               previewRect: rect(of: barcode.bounds))
        }

        /// VisionKit reports a quadrilateral in the scanner view's own
        /// coordinates; the overlays want its bounding box.
        private static func rect(of bounds: RecognizedItem.Bounds) -> CGRect {
            let corners = [bounds.topLeft, bounds.topRight, bounds.bottomRight, bounds.bottomLeft]
            let xs = corners.map(\.x)
            let ys = corners.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else { return .zero }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }
}

// MARK: - Lifecycle host

/// Owns the `DataScannerViewController` as a child so recognition — and the
/// camera with it — runs only while this view is on screen and not paused:
/// the contract `ScannerViewController` keeps for the AVFoundation camera,
/// so switching tabs or modes never leaves a second camera session behind.
/// VisionKit also wants `startScanning()` once the view is on screen, not
/// when the controller is created.
private final class LiveTextHostController: UIViewController {
    let scanner: DataScannerViewController
    var onUnavailable: ((LiveTextUnavailable) -> Void)?

    var isPaused = false {
        didSet { if isPaused != oldValue { updateRunState() } }
    }
    var isTorchOn = false

    private var isOnScreen = false
    private var isAskingForCamera = false
    /// Set once VisionKit has failed, so the next appearance doesn't loop
    /// start → fail → start while the host swaps cameras.
    private var hasGivenUp = false
    /// Set when SwiftUI dismantles the view; nothing restarts after it.
    private var isTornDown = false

    init(scanner: DataScannerViewController) {
        self.scanner = scanner
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func loadView() {
        // Window membership is the "on screen" signal that holds however
        // SwiftUI inserts this controller; the appearance callbacks below
        // add the tab-bar and presentation transitions on top of it.
        let root = WindowObservingView()
        root.backgroundColor = .black
        root.onWindowChange = { [weak self] isInWindow in
            self?.setOnScreen(isInWindow)
        }
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(scanner)
        scanner.view.frame = view.bounds
        scanner.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scanner.view)
        scanner.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setOnScreen(true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setOnScreen(false)
    }

    private func setOnScreen(_ onScreen: Bool) {
        guard isOnScreen != onScreen else { return }
        isOnScreen = onScreen
        updateRunState()
    }

    /// Starts or stops recognition to match visibility and `isPaused`.
    func updateRunState() {
        if isOnScreen, !isPaused, !hasGivenUp, !isTornDown {
            startIfAllowed()
        } else if scanner.isScanning {
            setTorch(false)
            scanner.stopScanning()
        }
    }

    /// Re-applies the torch while scanning. Cheap when nothing changed, and
    /// it heals a torch the capture session reset when it started.
    func applyTorch() {
        guard scanner.isScanning else { return }
        setTorch(isTorchOn)
    }

    /// The SwiftUI view is going away: release the camera now rather than
    /// whenever the controller happens to deallocate.
    func tearDown() {
        isTornDown = true
        isOnScreen = false
        if scanner.isScanning {
            setTorch(false)
            scanner.stopScanning()
        }
        scanner.delegate = nil
        onUnavailable = nil
        // Detach the child too: VisionKit overrides `removeFromParent()`,
        // so the scanner gets its own chance to release the camera before
        // the Codes camera (or the next Live Text) asks for it.
        scanner.willMove(toParent: nil)
        scanner.view.removeFromSuperview()
        scanner.removeFromParent()
    }

    func giveUp(_ reason: LiveTextUnavailable) {
        guard !hasGivenUp else { return }
        hasGivenUp = true
        if scanner.isScanning {
            setTorch(false)
            scanner.stopScanning()
        }
        // Reported on the next turn: this can run inside a SwiftUI update
        // (via `isPaused`), and the host reacts by changing its state.
        Task { [weak self] in
            self?.onUnavailable?(reason)
        }
    }

    private func startIfAllowed() {
        guard !scanner.isScanning, !isAskingForCamera else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            // Ask first, the way the Codes camera does, so a "Don't Allow"
            // lands in the same fallback as a restricted camera.
            isAskingForCamera = true
            Task { [weak self] in
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                guard let self else { return }
                self.isAskingForCamera = false
                if granted {
                    self.updateRunState()
                } else {
                    self.giveUp(.cameraDenied)
                }
            }
            return
        default:
            giveUp(.cameraDenied)
            return
        }
        do {
            try scanner.startScanning()
            setTorch(isTorchOn)
        } catch {
            // VisionKit refuses to start when the camera is unavailable,
            // e.g. held by another app.
            giveUp(.failedToStart)
        }
    }

    /// `DataScannerViewController` has no torch API, so the torch is set on
    /// the capture device directly, best-effort, as the Codes camera does.
    private func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        if device.torchMode == (on ? .on : .off) { return }
        if on, !device.isTorchAvailable { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if on {
                try device.setTorchModeOn(level: 1.0)
            } else {
                device.torchMode = .off
            }
        } catch {
            // Another client holds the device configuration; the next
            // update tries again.
        }
    }
}

/// The host's root view; reports when it enters or leaves a window.
private final class WindowObservingView: UIView {
    var onWindowChange: ((Bool) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?(window != nil)
    }
}

#endif

// MARK: - Live Text over a frozen frame

/// A still from the viewfinder with the system Live Text interaction on it:
/// touch and hold a word to select it, drag to widen the selection, and the
/// system menu offers Copy, Look Up, Translate and Share. Data detectors are
/// left off on purpose — a printed link opens only through a scanned code,
/// where the safety inspector sees it first.
struct FrozenFrameTextView: View {
    let image: UIImage
    let onDone: () -> Void

    /// The hint once the frame's words are selectable. That menu's Look Up
    /// and Translate are iOS services, not Scan's, and may send the selection
    /// to Apple — Apple's Translation privacy notice says so for text in
    /// images unless both languages are downloaded — so the hint says so and
    /// points at the card's Translate, which runs on this device.
    static let selectionHint = "Touch and hold a word to select it. Look Up and Translate in that menu are iOS services that may send the selection to Apple; tap the text in the live view for Scan's on-device Translate."

    @State private var analysis: ImageAnalysis?
    @State private var phase: Phase = .reading

    private enum Phase: Equatable {
        case reading, ready, noText, unavailable
    }

    /// VisionKit recommends one shared analyser.
    private static let analyzer = ImageAnalyzer()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LiveTextImageView(image: image, analysis: analysis)
                .ignoresSafeArea()
            VStack {
                HStack(alignment: .top, spacing: 12) {
                    statusLabel
                    Spacer(minLength: 0)
                    Button("Done", action: onDone)
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                Spacer()
            }
        }
        .task(id: ObjectIdentifier(image)) { await analyse() }
    }

    @ViewBuilder
    private var statusLabel: some View {
        HStack(spacing: 8) {
            switch phase {
            case .reading:
                ProgressView().controlSize(.small)
                Text("Reading the text…")
            case .ready:
                Image(systemName: "text.viewfinder")
                Text(Self.selectionHint)
            case .noText:
                Image(systemName: "text.badge.xmark")
                Text("No text found in this frame.")
            case .unavailable:
                Image(systemName: "exclamationmark.triangle")
                Text("Live Text can't read this frame on this device.")
            }
        }
        .font(.footnote)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func analyse() async {
        guard ImageAnalyzer.isSupported else {
            phase = .unavailable
            return
        }
        phase = .reading
        do {
            let result = try await Self.analyzer.analyze(image,
                                                         configuration: ImageAnalyzer.Configuration([.text]))
            analysis = result
            phase = result.hasResults(for: .text) ? .ready : .noText
        } catch {
            analysis = nil
            phase = .unavailable
        }
    }
}

/// The frozen frame as an image view carrying the Live Text interaction.
private struct LiveTextImageView: UIViewRepresentable {
    let image: UIImage
    let analysis: ImageAnalysis?

    func makeUIView(context: Context) -> LiveTextImageSurface {
        LiveTextImageSurface()
    }

    func updateUIView(_ surface: LiveTextImageSurface, context: Context) {
        surface.show(image, analysis: analysis)
    }
}

/// `UIImageView` with an `ImageAnalysisInteraction`, aspect-fit so the
/// whole captured frame — and every word in it — is reachable.
private final class LiveTextImageSurface: UIImageView, ImageAnalysisInteractionDelegate {
    private let interaction = ImageAnalysisInteraction()

    init() {
        super.init(frame: .zero)
        contentMode = .scaleAspectFit
        backgroundColor = .black
        // Image views ignore touches by default; Live Text needs them.
        isUserInteractionEnabled = true
        interaction.preferredInteractionTypes = .textSelection
        interaction.delegate = self
        addInteraction(interaction)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// No intrinsic size: a 12-megapixel still would otherwise ask SwiftUI
    /// for thousands of points.
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        interaction.setContentsRectNeedsUpdate()
    }

    func show(_ newImage: UIImage, analysis: ImageAnalysis?) {
        if image !== newImage {
            image = newImage
            interaction.setContentsRectNeedsUpdate()
        }
        guard interaction.analysis !== analysis else { return }
        interaction.analysis = analysis
        // Light up every selectable word at once — the state the system
        // Camera enters when its Live Text button is pressed.
        interaction.selectableItemsHighlighted = analysis != nil
    }

    // MARK: ImageAnalysisInteractionDelegate

    /// Where the aspect-fitted image sits inside the view, in unit
    /// coordinates, so the highlights land on the words.
    func contentsRect(for interaction: ImageAnalysisInteraction) -> CGRect {
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        guard let image, bounds.width > 0, bounds.height > 0,
              image.size.width > 0, image.size.height > 0 else { return unit }
        let fitted = AVMakeRect(aspectRatio: image.size, insideRect: bounds)
        return CGRect(x: (fitted.minX - bounds.minX) / bounds.width,
                      y: (fitted.minY - bounds.minY) / bounds.height,
                      width: fitted.width / bounds.width,
                      height: fitted.height / bounds.height)
    }
}
