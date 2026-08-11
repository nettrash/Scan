//
//  ChessRecognizer.swift
//  Scan
//
//  The seam between "a picture" and "a position".
//
//  Everything downstream of this protocol — the editor, the analysis
//  screen, the engine — is finished and testable today. The two Core ML
//  models it will eventually call are not: they are being trained in the
//  sibling `chess-vision` repo. Putting a protocol here means the whole
//  feature can be built, run and demoed against a stub, and the real
//  implementation drops in without touching a line of UI.
//
//  ## The pipeline the real implementation will run
//
//    1. **BoardNet** on the frame → four corners (normalised, in board
//       order a8/h8/h1/a1) plus a presence logit.
//    2. **Presence gate** → below threshold, report `.noBoardFound` and
//       show nothing. This is the explicit fix for the prototype's
//       `BoardDetector`, which returned its best-guess rectangle even
//       when its own board test failed.
//    3. **Grid refinement** → project the warped board's gradient onto
//       each axis, fit a nine-line comb, solve the residual homography.
//       Cheap, deterministic, and what stops a wooden frame shifting the
//       whole grid by a fraction of a square.
//    4. **Warp** to 288×288 with a one-square margin — a standing piece
//       is taller than its square, so an exact warp crops the top off
//       every back-rank piece.
//    5. **PieceNet** → 8×8×13 logits in a single inference.
//    6. **Constrained decoding** (`ChessPositionDecoder`) → the most
//       probable *legal* position, plus per-square confidence.
//
//  Steps 1 and 5 need the models. Steps 2, 3, 4 and 6 are ours, and 6 is
//  already written and tested.
//

import CoreGraphics
import Foundation

/// Why a recognition attempt produced nothing.
public enum ChessRecognitionFailure: Error, Equatable, Sendable {
    /// No board in the frame, or the presence gate rejected it.
    case noBoardFound
    /// A board was found but too little of it is visible to read.
    case boardTooSmall
    /// The models are not bundled in this build.
    case modelUnavailable
    /// Core ML or the image pipeline failed.
    case inferenceFailed(String)

    /// Text the capture screen shows verbatim. Each says what to *do*,
    /// because every one of these is recoverable by the user moving.
    public var message: String {
        switch self {
        case .noBoardFound:
            return "No chess board in view. Fill more of the frame with the board."
        case .boardTooSmall:
            return "Move closer — too little of the board is visible to read it."
        case .modelUnavailable:
            return "Board recognition isn't available in this build."
        case .inferenceFailed(let reason):
            return "Couldn't read the board: \(reason)"
        }
    }
}

/// What a successful recognition returns.
public struct ChessRecognitionResult: Sendable {
    /// The decoded, legality-repaired position.
    public var recognized: ChessRecognizedPosition
    /// Board corners in **normalised image coordinates** (0...1, origin
    /// top-left), in board order a8/h8/h1/a1.
    ///
    /// Normalised so the overlay can be drawn at any preview size, and in
    /// board order so the capture view can label which corner is which
    /// when the user drags them.
    public var corners: [CGPoint]
    /// BoardNet's confidence that this is a board at all, 0...1.
    public var boardConfidence: Double
    /// True when the source was already rectilinear — an imported
    /// screenshot rather than a photograph. The pipeline must not
    /// re-warp these.
    public var wasAlreadyRectilinear: Bool

    public init(recognized: ChessRecognizedPosition,
                corners: [CGPoint],
                boardConfidence: Double,
                wasAlreadyRectilinear: Bool = false) {
        self.recognized = recognized
        self.corners = corners
        self.boardConfidence = boardConfidence
        self.wasAlreadyRectilinear = wasAlreadyRectilinear
    }
}

/// Reads a chess position from an image.
public protocol ChessRecognizing: Sendable {
    /// True when this implementation can actually do anything — i.e. the
    /// models are present. The Chess tab uses it to decide whether to
    /// offer the camera at all.
    var isAvailable: Bool { get }

    /// Recognise a position from a still image.
    func recognize(image: CGImage) async -> Result<ChessRecognitionResult, ChessRecognitionFailure>

    /// Recognise using corners the user placed by hand.
    ///
    /// The manual override, and the reason the feature is usable before
    /// `BoardNet` is any good: with the corners supplied, only piece
    /// classification remains. Every capture offers draggable handles for
    /// this reason.
    func recognize(image: CGImage,
                   corners: [CGPoint]) async -> Result<ChessRecognitionResult, ChessRecognitionFailure>
}

// MARK: - Stub

/// Stands in until the Core ML models land.
///
/// Deliberately **not** a fake that returns plausible-looking positions:
/// it reports `.modelUnavailable`, so nothing downstream can accidentally
/// be built or demoed against invented data. The one thing it does offer
/// is `startingPosition`, used by previews and by the editor's "set up
/// the initial position" affordance — a real feature, not a mock.
public struct ChessRecognizerStub: ChessRecognizing {
    public var isAvailable: Bool { false }

    public init() {}

    public func recognize(
        image: CGImage
    ) async -> Result<ChessRecognitionResult, ChessRecognitionFailure> {
        .failure(.modelUnavailable)
    }

    public func recognize(
        image: CGImage, corners: [CGPoint]
    ) async -> Result<ChessRecognitionResult, ChessRecognitionFailure> {
        .failure(.modelUnavailable)
    }

    /// A perfectly-confident reading of the starting array.
    public static var startingPosition: ChessRecognizedPosition {
        ChessRecognizedPosition(
            placement: ChessPosition.standard.placement,
            confidence: Array(repeating: 1.0, count: 64),
            repairs: []
        )
    }
}

/// The recogniser the app uses.
///
/// A single switch point: when `ChessCoreMLRecognizer` exists, this
/// returns it when its models are bundled and the stub otherwise, and no
/// call site changes.
public enum ChessRecognizerFactory {
    public static func make() -> any ChessRecognizing {
        ChessRecognizerStub()
    }
}
