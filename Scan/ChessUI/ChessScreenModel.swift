//
//  ChessScreenModel.swift
//  Scan
//
//  State for the Chess tab.
//
//  ## Analysis is debounced and cancellable
//
//  Every edit invalidates the analysis, and a user correcting three
//  misread squares makes three edits in about a second. Kicking off a
//  search per keystroke would leave two stale searches burning CPU behind
//  a phone's back. So each change cancels the running search, waits a
//  beat, and starts one — and because the engine's `stop()` is safe from
//  any thread and its iterative deepening always leaves a usable answer,
//  cancelling is cheap and never loses a move.
//
//  ## Both sides, every time
//
//  `analyseBothSides` runs two searches back to back, so a `.standard`
//  think time costs about two seconds of wall clock. That is budgeted for
//  deliberately: the feature's promise is a move for each side, and
//  answering only the side we guessed would be the wrong kind of fast.
//

import Combine
import CoreGraphics
import CoreImage
import Foundation
import SwiftUI
import UIKit

@MainActor
final class ChessScreenModel: ObservableObject {

    // MARK: - Board state

    @Published private(set) var placement: [ChessPiece?] = Array(repeating: nil, count: 64)
    /// Per-square confidence from the last recognition, if any. Empty
    /// after a manual edit, because a square the user set is certain.
    @Published private(set) var confidence: [Double] = []
    @Published private(set) var repairs: [String] = []

    /// The square whose piece palette is open, if any.
    @Published var paletteSquare: ChessSquare?

    /// Castling rights, as the raw option-set value so `@AppStorage` and
    /// `Picker` can bind to it directly.
    @Published var castlingRightsRaw: UInt8 = 0 {
        didSet { if oldValue != castlingRightsRaw { scheduleAnalysis() } }
    }

    // MARK: - Analysis state

    @Published private(set) var white: ChessAnalysisOutcome?
    @Published private(set) var black: ChessAnalysisOutcome?
    @Published private(set) var isAnalysing = false
    /// Which side's move is drawn as an arrow.
    @Published private(set) var highlightedSide: ChessColor = .white

    /// Set by the capture button; the view presents the camera on it.
    @Published var captureRequested = false

    // MARK: - Manual corner placement
    //
    // The model-free path, and the one that collects fine-tuning data.
    // The user imports a photograph, drags the four corners onto the
    // board, and names the position in the editor; that pair is a
    // training sample. See `ChessTrainingExport`.

    /// The photograph awaiting corner placement, if any.
    @Published var pendingImage: UIImage?
    /// Corners in image pixels, board order, while being adjusted.
    @Published var pendingCorners: [CGPoint] = []
    /// The rectified board from the last confirmed placement.
    @Published private(set) var warpedBoard: UIImage?

    private var warpedCI: CIImage?
    private var warpedFromCorners: [CGPoint] = []
    private var warpedSourceSize: CGSize = .zero

    /// True once a board has been rectified and can be exported with a
    /// position. Drives the "save training sample" affordance.
    var canExportTrainingSample: Bool {
        warpedCI != nil
            && UserDefaults.standard.bool(forKey: ScanSettingsKey.chessExportTrainingSquares)
    }

    var thinkTime: TimeInterval = ChessEngine.ThinkTime.standard.rawValue {
        didSet { if oldValue != thinkTime { scheduleAnalysis() } }
    }

    private let engine = ChessEngine()
    private let recognizer: any ChessRecognizing
    private var analysisTask: Task<Void, Never>?

    var recognizerAvailable: Bool { recognizer.isAvailable }

    init(recognizer: (any ChessRecognizing)? = nil) {
        self.recognizer = recognizer ?? ChessRecognizerFactory.make()
    }

    // MARK: - Derived

    var position: ChessPosition {
        ChessPosition(placement: placement,
                      sideToMove: highlightedSide,
                      castlingRights: ChessCastlingRights(rawValue: castlingRightsRaw))
    }

    var placementFEN: String { position.placementFEN }

    func outcome(for side: ChessColor) -> ChessAnalysisOutcome? {
        side == .white ? white : black
    }

    /// The arrow drawn on the board: the highlighted side's suggested move.
    var arrow: (from: ChessSquare, to: ChessSquare)? {
        guard case .move(let analysis)? = outcome(for: highlightedSide) else { return nil }
        return (analysis.move.from, analysis.move.to)
    }

    /// Square decorations: the move's endpoints, the open palette, and the
    /// squares the recogniser was least sure about.
    var decorations: [Int: ChessSquareDecoration] {
        var result: [Int: ChessSquareDecoration] = [:]

        // Ring only the genuinely shaky squares, and only a few. Ringing
        // twenty is the same as ringing none.
        if !confidence.isEmpty {
            let shaky = (0..<64)
                .filter { confidence[$0] < 0.80 && placement[$0] != nil || confidence[$0] < 0.65 }
                .sorted { confidence[$0] < confidence[$1] }
                .prefix(5)
            for square in shaky {
                result[square, default: ChessSquareDecoration()].isUncertain = true
            }
        }

        if let arrow {
            result[arrow.from.index, default: ChessSquareDecoration()].isMoveEndpoint = true
            result[arrow.to.index, default: ChessSquareDecoration()].isMoveEndpoint = true
        }
        if let paletteSquare {
            result[paletteSquare.index, default: ChessSquareDecoration()].isSelected = true
        }
        return result
    }

    // MARK: - Editing

    func tapped(_ square: ChessSquare) {
        paletteSquare = (paletteSquare == square) ? nil : square
    }

    func setPiece(_ piece: ChessPiece?, at square: ChessSquare) {
        placement[square.index] = piece
        // A square the user set is not a guess any more, so it should stop
        // being flagged as uncertain.
        if !confidence.isEmpty { confidence[square.index] = 1.0 }
        paletteSquare = nil
        scheduleAnalysis()
    }

    func loadStartingPosition() {
        apply(ChessRecognizerStub.startingPosition)
        castlingRightsRaw = ChessCastlingRights.all.rawValue
    }

    func clearBoard() {
        placement = Array(repeating: nil, count: 64)
        confidence = []
        repairs = []
        castlingRightsRaw = 0
        paletteSquare = nil
        cancelAnalysis()
        white = nil
        black = nil
    }

    func highlight(_ side: ChessColor) {
        highlightedSide = side
    }

    // MARK: - Recognition

    func apply(_ recognized: ChessRecognizedPosition) {
        placement = recognized.placement
        confidence = recognized.confidence
        repairs = recognized.repairs
        paletteSquare = nil
        // Castling rights can't be seen, but they can be *bounded*: if a
        // king or rook isn't home, that right is impossible. Offering
        // "both sides" when the king has clearly moved would be a worse
        // default than offering none.
        castlingRightsRaw = Self.plausibleCastlingRights(placement).rawValue
        scheduleAnalysis()
    }

    /// Begin manual placement on an imported photograph.
    func beginCornerPlacement(with image: UIImage) {
        pendingImage = image
        pendingCorners = ChessBoardWarp.defaultCorners(in: image.size)
    }

    func cancelCornerPlacement() {
        pendingImage = nil
        pendingCorners = []
    }

    /// Rectify using the corners the user placed.
    ///
    /// Deliberately does **not** try to read the position — there is no
    /// model yet. It shows the rectified board and leaves the editor to
    /// the user, which is exactly the interaction that produces a labelled
    /// sample.
    func confirmCornerPlacement() {
        guard let image = pendingImage,
              let ciImage = CIImage(image: image),
              ChessBoardWarp.isUsableQuad(pendingCorners, minimumArea: 400),
              let warped = ChessBoardWarp.warp(ciImage, corners: pendingCorners)
        else {
            repairs = ["Those corners don't make a usable board — try again."]
            return
        }

        warpedCI = warped
        warpedFromCorners = pendingCorners
        warpedSourceSize = image.size

        let context = CIContext()
        if let rendered = context.createCGImage(warped, from: warped.extent) {
            warpedBoard = UIImage(cgImage: rendered)
        }

        pendingImage = nil
        pendingCorners = []
        repairs = []
    }

    /// Save the rectified board and the current position as one training
    /// sample. Returns a message for the UI.
    func exportTrainingSample() -> String {
        guard let warped = warpedCI else { return "Nothing to save yet." }
        do {
            try ChessTrainingExport.write(
                warped: warped,
                position: position,
                corners: warpedFromCorners,
                cornerSource: .manual,
                sourceSize: warpedSourceSize
            )
            return "Saved — \(ChessTrainingExport.sampleCount) sample(s) collected."
        } catch {
            return "Couldn't save: \(error.localizedDescription)"
        }
    }

    func recognize(image: CGImage) async {
        switch await recognizer.recognize(image: image) {
        case .success(let result):
            apply(result.recognized)
        case .failure(let failure):
            repairs = [failure.message]
        }
    }

    /// Rights that are at least *possible* given where the kings and rooks
    /// stand. Not proof they exist — only that they aren't ruled out.
    ///
    /// `nonisolated` because it is a pure function of its argument: it
    /// touches no model state, and the tests call it directly.
    nonisolated static func plausibleCastlingRights(
        _ placement: [ChessPiece?]
    ) -> ChessCastlingRights {
        var rights: ChessCastlingRights = []
        func piece(_ square: ChessSquare) -> ChessPiece? { placement[square.index] }

        if piece(.e1) == ChessPiece(.white, .king) {
            if piece(.h1) == ChessPiece(.white, .rook) { rights.insert(.whiteKingside) }
            if piece(.a1) == ChessPiece(.white, .rook) { rights.insert(.whiteQueenside) }
        }
        if piece(.e8) == ChessPiece(.black, .king) {
            if piece(.h8) == ChessPiece(.black, .rook) { rights.insert(.blackKingside) }
            if piece(.a8) == ChessPiece(.black, .rook) { rights.insert(.blackQueenside) }
        }
        return rights
    }

    // MARK: - Analysis

    private func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        engine.stop()
    }

    func scheduleAnalysis() {
        cancelAnalysis()

        let board = ChessPosition(
            placement: placement,
            castlingRights: ChessCastlingRights(rawValue: castlingRightsRaw)
        )
        let budget = thinkTime

        // Nothing to say about a board with no pieces.
        guard board.pieces(.white).isNotEmpty || board.pieces(.black).isNotEmpty else {
            white = nil
            black = nil
            return
        }

        isAnalysing = true
        analysisTask = Task { [engine] in
            // Settle first: a burst of edits should produce one search,
            // not one per tap.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }

            let result = await Task.detached(priority: .userInitiated) {
                engine.analyseBothSides(board, thinkTime: budget)
            }.value

            guard !Task.isCancelled else { return }
            self.white = result.white
            self.black = result.black
            self.isAnalysing = false

            // Point the arrow at whichever side can actually move, so the
            // board isn't blank on a position that is legal for only one.
            if case .move = result.white {} else if case .move = result.black {
                self.highlightedSide = .black
            }
        }
    }
}
