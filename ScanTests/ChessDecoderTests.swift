//
//  ChessDecoderTests.swift
//  ScanTests
//
//  Constrained decoding — the port of `chess-vision/tests/test_decode.py`.
//
//  Each case is a misread the recogniser genuinely produces: a third
//  king, a ninth pawn, a pawn hallucinated onto the back rank, more
//  queens than missing pawns can pay for. The assertion is always the
//  same shape — whatever went in, what comes out is a position
//  `legalityProblems` accepts — because the engine refuses to search
//  anything else, and "the app just shows nothing" is not an acceptable
//  answer to a slightly-wrong photo.
//
//  The adversarial cases matter more than the happy path. A decoder that
//  only works when the classifier was already right is doing nothing.
//
//  These tests, the Python ones, and the Kotlin port to come must stay in
//  agreement; the Python file is the specification.
//

import XCTest
@testable import Scan

final class ChessDecoderTests: XCTestCase {

    private let classes = ChessSquareLabel.count

    /// A distribution that argmaxes to `labels`, with the rest spread flat.
    private func oneHot(_ labels: [Int], confidence: Double = 0.99) -> [[Double]] {
        let spread = (1.0 - confidence) / Double(classes - 1)
        return labels.map { label in
            (0..<classes).map { $0 == label ? confidence : spread }
        }
    }

    private func labels(fen: String) -> [Int] {
        let position = ChessPosition(fen: fen)!
        return position.placement.map { $0.map { ChessSquareLabel.label(for: $0) } ?? 0 }
    }

    private func square(_ name: String) -> Int { ChessSquare(name)!.index }

    /// The decoder's whole contract in one predicate.
    private func assertLegal(_ decoded: ChessRecognizedPosition,
                             file: StaticString = #filePath, line: UInt = #line) {
        let problems = decoded.position().legalityProblems
        // `opponentInCheck` depends on whose turn it is, which the decoder
        // has no opinion about — a photo cannot show it. Everything else
        // is the decoder's responsibility.
        let structural = problems.filter {
            if case .opponentInCheck = $0 { return false }
            return true
        }
        XCTAssertTrue(structural.isEmpty,
                      "expected a legal placement, got \(structural) in \(decoded.position().placementFEN)",
                      file: file, line: line)
    }

    private static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR"

    // MARK: - The happy path

    func testACleanReadIsLeftAlone() {
        let truth = labels(fen: Self.startFEN)
        let decoded = ChessPositionDecoder.decode(probabilities: oneHot(truth))
        XCTAssertEqual(decoded.position().placementFEN, Self.startFEN)
        XCTAssertTrue(decoded.repairs.isEmpty)
        assertLegal(decoded)
    }

    func testConfidenceIsReportedPerSquare() {
        let truth = labels(fen: Self.startFEN)
        let decoded = ChessPositionDecoder.decode(probabilities: oneHot(truth, confidence: 0.9))
        XCTAssertEqual(decoded.confidence.count, 64)
        XCTAssertTrue(decoded.confidence.allSatisfy { $0 > 0.85 && $0 <= 1.0 })
    }

    func testWeakestSquaresAreOrderedLeastConfidentFirst() {
        var probabilities = oneHot(labels(fen: Self.startFEN))
        let shaky = square("d4")
        probabilities[shaky] = Array(repeating: 1.0 / Double(classes), count: classes)
        let decoded = ChessPositionDecoder.decode(probabilities: probabilities)
        XCTAssertEqual(decoded.weakestSquares.first?.index, shaky)
    }

    // MARK: - The misreads

    func testThreeKingsIsReducedToOne() {
        var truth = labels(fen: Self.startFEN)
        truth[square("d4")] = ChessSquareLabel.whiteKing
        var probabilities = oneHot(truth)
        // Make the spurious king less confident than the real one on e1.
        probabilities[square("d4")][ChessSquareLabel.whiteKing] = 0.55

        let decoded = ChessPositionDecoder.decode(probabilities: probabilities)
        XCTAssertEqual(decoded.placement[square("e1")], ChessPiece(.white, .king))
        XCTAssertNotEqual(decoded.placement[square("d4")], ChessPiece(.white, .king))
        XCTAssertFalse(decoded.repairs.isEmpty)
        assertLegal(decoded)
    }

    func testAMissingKingIsRestored() {
        var truth = labels(fen: Self.startFEN)
        truth[square("e1")] = ChessSquareLabel.empty
        var probabilities = oneHot(truth)
        // e1 is where the model was second-guessing a king.
        probabilities[square("e1")][ChessSquareLabel.whiteKing] = 0.30

        let decoded = ChessPositionDecoder.decode(probabilities: probabilities)
        XCTAssertEqual(decoded.placement[square("e1")], ChessPiece(.white, .king))
        assertLegal(decoded)
    }

    func testNinePawnsIsReducedToEight() {
        var truth = labels(fen: Self.startFEN)
        truth[square("d4")] = ChessSquareLabel.whitePawn
        var probabilities = oneHot(truth)
        probabilities[square("d4")][ChessSquareLabel.whitePawn] = 0.40

        let decoded = ChessPositionDecoder.decode(probabilities: probabilities)
        let pawns = decoded.placement.filter { $0 == ChessPiece(.white, .pawn) }.count
        XCTAssertEqual(pawns, 8)
        XCTAssertNotEqual(decoded.placement[square("d4")], ChessPiece(.white, .pawn))
        assertLegal(decoded)
    }

    func testAPawnOnTheBackRankIsRelabelled() {
        var truth = labels(fen: "4k3/8/8/8/8/8/8/4K3")
        truth[square("a1")] = ChessSquareLabel.whitePawn
        truth[square("h8")] = ChessSquareLabel.blackPawn

        let decoded = ChessPositionDecoder.decode(probabilities: oneHot(truth))
        XCTAssertNotEqual(decoded.placement[square("a1")], ChessPiece(.white, .pawn))
        XCTAssertNotEqual(decoded.placement[square("h8")], ChessPiece(.black, .pawn))
        XCTAssertGreaterThanOrEqual(decoded.repairs.count, 2)
        assertLegal(decoded)
    }

    /// A full pawn set plus four extra queens: no pawns could have
    /// promoted to make them, so some queens have to go.
    func testImpossiblePromotionCountIsPaidFor() {
        var truth = labels(fen: Self.startFEN)
        for name in ["a4", "b4", "c4", "d4"] {
            truth[square(name)] = ChessSquareLabel.label(for: ChessPiece(.white, .queen))
        }
        var probabilities = oneHot(truth)
        for name in ["a4", "b4", "c4", "d4"] {
            probabilities[square(name)][ChessSquareLabel.label(for: ChessPiece(.white, .queen))] = 0.45
        }

        let decoded = ChessPositionDecoder.decode(probabilities: probabilities)
        let queens = decoded.placement.filter { $0 == ChessPiece(.white, .queen) }.count
        XCTAssertLessThanOrEqual(queens, 1)
        assertLegal(decoded)
    }

    func testTooManyPiecesIsTrimmed() {
        var truth = labels(fen: "4k3/8/8/8/8/8/8/4K3")
        for index in 16..<36 {
            truth[index] = ChessSquareLabel.label(for: ChessPiece(.white, .rook))
        }
        let decoded = ChessPositionDecoder.decode(probabilities: oneHot(truth))
        let owned = decoded.placement.filter { $0?.color == .white }.count
        XCTAssertLessThanOrEqual(owned, 16)
        assertLegal(decoded)
    }

    /// Every square claimed to be a white queen — the worst realistic
    /// classifier collapse.
    func testAPathologicalReadStillProducesALegalBoard() {
        let truth = Array(repeating: ChessSquareLabel.label(for: ChessPiece(.white, .queen)),
                          count: 64)
        assertLegal(ChessPositionDecoder.decode(probabilities: oneHot(truth)))
    }

    /// No signal at all. This is the case that caught the bug where White
    /// and Black promoted their kings onto the *same* square, because with
    /// a flat distribution every square costs exactly the same.
    func testUniformNoiseProducesALegalBoard() {
        let flat = Array(repeating: Array(repeating: 1.0 / Double(classes), count: classes),
                         count: 64)
        let decoded = ChessPositionDecoder.decode(probabilities: flat)
        XCTAssertEqual(decoded.placement.filter { $0 == ChessPiece(.white, .king) }.count, 1)
        XCTAssertEqual(decoded.placement.filter { $0 == ChessPiece(.black, .king) }.count, 1)
        assertLegal(decoded)
    }

    /// Genuinely random per-class probabilities — what a confused
    /// classifier actually emits, as opposed to a flat distribution.
    ///
    /// This is a regression test for a real bug. `repairKings` settles the
    /// king count first, but the *later* repairs then relabelled squares
    /// via a "next best class" lookup that was free to pick a king — so a
    /// noisy read came back with seven white kings. Uniform noise never
    /// caught it, because with every class equal the lookup lands on
    /// `empty`; only unequal per-class values expose it.
    func testRandomNoiseProducesALegalBoard() {
        for trial in 0..<25 {
            // Deterministic per trial, so a failure is reproducible.
            // All-UInt64: doing this in Int overflows to a negative value,
            // and UInt64(negative) traps.
            var seed = UInt64(trial) &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            func nextUnit() -> Double {
                seed ^= seed >> 12
                seed ^= seed << 25
                seed ^= seed >> 27
                return Double(seed &* 2_685_821_657_736_338_717 >> 11) / Double(1 << 53)
            }
            let probabilities: [[Double]] = (0..<64).map { _ in
                let raw = (0..<classes).map { _ in nextUnit() + 1e-6 }
                let total = raw.reduce(0, +)
                return raw.map { $0 / total }
            }

            let decoded = ChessPositionDecoder.decode(probabilities: probabilities)
            XCTAssertEqual(decoded.placement.filter { $0 == ChessPiece(.white, .king) }.count, 1,
                           "trial \(trial): exactly one white king")
            XCTAssertEqual(decoded.placement.filter { $0 == ChessPiece(.black, .king) }.count, 1,
                           "trial \(trial): exactly one black king")
            assertLegal(decoded)
        }
    }

    // MARK: - Plumbing

    func testSoftmaxNormalises() {
        var row = Array(repeating: 0.0, count: classes)
        row[1] = 1.0
        let probabilities = ChessPositionDecoder.probabilities(fromLogits: [row])[0]
        XCTAssertEqual(probabilities.reduce(0, +), 1.0, accuracy: 1e-9)
        XCTAssertEqual(probabilities.max(), probabilities[1])
    }

    func testLabelSchemeMatchesChessPieceIndex() {
        // The apps decode a square as `ChessPiece(index: label - 1)`, and
        // the models are trained against exactly this numbering.
        XCTAssertEqual(ChessSquareLabel.label(for: ChessPiece(.white, .pawn)), 1)
        XCTAssertEqual(ChessSquareLabel.label(for: ChessPiece(.white, .king)), 6)
        XCTAssertEqual(ChessSquareLabel.label(for: ChessPiece(.black, .pawn)), 7)
        XCTAssertEqual(ChessSquareLabel.label(for: ChessPiece(.black, .king)), 12)
        XCTAssertNil(ChessSquareLabel.piece(0))
        for label in 1...12 {
            XCTAssertEqual(ChessSquareLabel.label(for: ChessSquareLabel.piece(label)!), label)
        }
    }

    // MARK: - Castling inference

    /// Rights can't be seen in a photo, but they can be *bounded*: a right
    /// is impossible unless the king and that rook are both home.
    func testPlausibleCastlingRights() {
        let full = ChessScreenModel.plausibleCastlingRights(ChessPosition.standard.placement)
        XCTAssertEqual(full, .all)

        // King off e1: White has no rights at all, Black keeps both.
        let movedKing = ChessPosition(fen: "r3k2r/8/8/8/8/8/8/R4RK1")!
        let partial = ChessScreenModel.plausibleCastlingRights(movedKing.placement)
        XCTAssertFalse(partial.contains(.whiteKingside))
        XCTAssertFalse(partial.contains(.whiteQueenside))
        XCTAssertTrue(partial.contains(.blackKingside))
        XCTAssertTrue(partial.contains(.blackQueenside))

        // Missing h1 rook: kingside impossible, queenside still open.
        let missingRook = ChessPosition(fen: "4k3/8/8/8/8/8/8/R3K3")!
        let queensideOnly = ChessScreenModel.plausibleCastlingRights(missingRook.placement)
        XCTAssertFalse(queensideOnly.contains(.whiteKingside))
        XCTAssertTrue(queensideOnly.contains(.whiteQueenside))
    }
}
