//
//  ChessEngineTests.swift
//  ScanTests
//
//  The chess engine's correctness gate.
//
//  ## Perft is the whole point of this file
//
//  `perft(depth)` counts the leaf nodes of the legal-move tree. Its value
//  is that the counts for a handful of standard positions are *published
//  and independently verified* — every serious engine reports the same
//  numbers. So a single integer comparison exercises castling rights,
//  en-passant timing, promotion, pinned pieces, discovered check,
//  check evasion and the fifty other rules interactions simultaneously,
//  and tells you the moment any of them is wrong.
//
//  The six positions below are the standard set from the Chess
//  Programming Wiki, chosen precisely because each breaks a different
//  naive generator:
//
//    1. the initial array — the baseline
//    2. "Kiwipete" — dense middlegame, every castling and pin case
//    3. a sparse endgame that punishes en-passant and promotion errors
//    4. promotion-heavy, and mirrored to catch colour asymmetry
//    5. a known trap for buggy castling-rights bookkeeping
//    6. a quiet position that catches off-by-one in move ordering
//
//  ## Depths, and where the deep counts live
//
//  Tests run against a **Debug** build, where Swift's bounds checks and
//  absent inlining make this code roughly 20x slower than the Release
//  build the app ships (measured: ~1.5M nodes/s here versus ~38M/s
//  optimised). The depths below total about 15M nodes and run in ~17s,
//  which keeps the suite usable on every save while still reaching the
//  depth at which en-passant and promotion bugs actually surface.
//
//  The deepest published counts — startpos(6) at 119M nodes, Kiwipete(5)
//  at 194M — are **not** run from here. They live in `Tools/run-perft.sh`,
//  which compiles these same engine sources with `-O` and checks all 610M
//  nodes in about 17 seconds:
//
//      Tools/run-perft.sh
//
//  Two reasons they are not XCTest cases. The suite would take twelve
//  minutes in Debug; and `xcodebuild test` does not forward shell
//  environment variables to the test process, so the `XCTSkipUnless`
//  gates below can only be flipped from the scheme's Test action inside
//  Xcode — they are there for interactive use, not for CI.
//
//  Run `Tools/run-perft.sh` before shipping any change to move generation.
//

import XCTest
@testable import Scan

final class ChessEngineTests: XCTestCase {

    // MARK: - Perft driver

    /// Count leaf nodes of the legal-move tree to `depth`.
    private func perft(_ position: inout ChessPosition, depth: Int) -> Int {
        // Bulk counting at depth 1: the move list length *is* the answer,
        // which saves a make/unmake pair per leaf. Standard, and it does
        // not change the counts.
        let moves = ChessMoveGenerator.generateLegal(&position)
        if depth <= 1 { return depth == 0 ? 1 : moves.count }

        var nodes = 0
        for index in 0..<moves.count {
            let move = moves[index]
            let undo = position.make(move)
            nodes += perft(&position, depth: depth - 1)
            position.unmake(move, undo)
        }
        return nodes
    }

    /// Per-root-move node counts.
    ///
    /// Not used by any assertion — it is the debugging tool you reach for
    /// when a perft count is wrong. Compare its output against any
    /// reference engine's `divide` and the first differing move tells you
    /// which rule is broken, instead of leaving you with "8 nodes too
    /// many somewhere in 4 million".
    private func perftDivide(_ position: inout ChessPosition, depth: Int) -> [(String, Int)] {
        guard depth >= 1 else { return [] }
        let moves = ChessMoveGenerator.generateLegal(&position)
        var out: [(String, Int)] = []
        for index in 0..<moves.count {
            let move = moves[index]
            let undo = position.make(move)
            out.append((move.uci, depth == 1 ? 1 : perft(&position, depth: depth - 1)))
            position.unmake(move, undo)
        }
        return out.sorted { $0.0 < $1.0 }
    }

    /// Assert a position's perft counts, one depth at a time so a failure
    /// names the shallowest depth that breaks — which is the one worth
    /// debugging.
    private func assertPerft(_ fen: String,
                             _ expected: [Int],
                             file: StaticString = #filePath,
                             line: UInt = #line) {
        guard var position = ChessPosition(fen: fen) else {
            return XCTFail("could not parse FEN: \(fen)", file: file, line: line)
        }
        for (offset, count) in expected.enumerated() {
            let depth = offset + 1
            let actual = perft(&position, depth: depth)
            XCTAssertEqual(actual, count,
                           "perft(\(depth)) for \(fen)", file: file, line: line)
            // Every deeper count is meaningless once one is wrong, and
            // the deeper ones are the slow ones.
            if actual != count { return }
        }
    }

    private var runsDeepPerft: Bool {
        ProcessInfo.processInfo.environment["SCAN_CHESS_DEEP_PERFT"] == "1"
    }

    // MARK: - The standard positions

    private static let startPosition = ChessPosition.startFEN
    private static let kiwipete =
        "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
    private static let position3 = "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1"
    private static let position4 =
        "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1"
    private static let position5 = "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8"
    private static let position6 =
        "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10"

    func testPerftStartPosition() {
        assertPerft(Self.startPosition, [20, 400, 8902, 197_281, 4_865_609])
    }

    func testPerftKiwipete() {
        assertPerft(Self.kiwipete, [48, 2039, 97_862, 4_085_603])
    }

    func testPerftPosition3() {
        assertPerft(Self.position3, [14, 191, 2812, 43_238, 674_624])
    }

    func testPerftPosition4() {
        assertPerft(Self.position4, [6, 264, 9467, 422_333])
    }

    /// Position 4 mirrored top-to-bottom with the colours swapped. The
    /// node counts are identical by symmetry, so a mismatch between this
    /// and `testPerftPosition4` means something in the generator treats
    /// White and Black differently — pawn direction, promotion rank, or a
    /// castling mask.
    func testPerftPosition4Mirrored() {
        assertPerft("r2q1rk1/pP1p2pp/Q4n2/bbp1p3/Np6/1B3NBn/pPPP1PPP/R3K2R b KQ - 0 1",
                    [6, 264, 9467, 422_333])
    }

    func testPerftPosition5() {
        assertPerft(Self.position5, [44, 1486, 62_379, 2_103_487])
    }

    func testPerftPosition6() {
        assertPerft(Self.position6, [46, 2079, 89_890, 3_894_594])
    }

    // MARK: - Deep perft (opt-in — see the file header)

    func testDeepPerftStartPosition() throws {
        try XCTSkipUnless(runsDeepPerft, "set SCAN_CHESS_DEEP_PERFT=1 in the scheme, or run Tools/run-perft.sh")
        assertPerft(Self.startPosition, [20, 400, 8902, 197_281, 4_865_609, 119_060_324])
    }

    func testDeepPerftKiwipete() throws {
        try XCTSkipUnless(runsDeepPerft, "set SCAN_CHESS_DEEP_PERFT=1 in the scheme, or run Tools/run-perft.sh")
        assertPerft(Self.kiwipete, [48, 2039, 97_862, 4_085_603, 193_690_690])
    }

    func testDeepPerftPosition3() throws {
        try XCTSkipUnless(runsDeepPerft, "set SCAN_CHESS_DEEP_PERFT=1 in the scheme, or run Tools/run-perft.sh")
        assertPerft(Self.position3, [14, 191, 2812, 43_238, 674_624, 11_030_083])
    }

    func testDeepPerftPosition4() throws {
        try XCTSkipUnless(runsDeepPerft, "set SCAN_CHESS_DEEP_PERFT=1 in the scheme, or run Tools/run-perft.sh")
        assertPerft(Self.position4, [6, 264, 9467, 422_333, 15_833_292])
    }

    func testDeepPerftPosition5() throws {
        try XCTSkipUnless(runsDeepPerft, "set SCAN_CHESS_DEEP_PERFT=1 in the scheme, or run Tools/run-perft.sh")
        assertPerft(Self.position5, [44, 1486, 62_379, 2_103_487, 89_941_194])
    }

    func testDeepPerftPosition6() throws {
        try XCTSkipUnless(runsDeepPerft, "set SCAN_CHESS_DEEP_PERFT=1 in the scheme, or run Tools/run-perft.sh")
        assertPerft(Self.position6, [46, 2079, 89_890, 3_894_594, 164_075_551])
    }

    // MARK: - FEN

    func testStartPositionRoundTrip() {
        let position = ChessPosition.standard
        XCTAssertEqual(position.fen, ChessPosition.startFEN)
    }

    func testFENRoundTripsForEveryTestPosition() {
        for fen in [Self.startPosition, Self.kiwipete, Self.position3,
                    Self.position4, Self.position5, Self.position6] {
            guard let position = ChessPosition(fen: fen) else {
                return XCTFail("could not parse \(fen)")
            }
            XCTAssertEqual(position.fen, fen)
        }
    }

    func testPlacementOnlyFENDefaultsTheRest() {
        guard let position = ChessPosition(fen: "8/8/8/4k3/8/8/4K3/8") else {
            return XCTFail("placement-only FEN should parse")
        }
        XCTAssertEqual(position.sideToMove, .white)
        XCTAssertEqual(position.castlingRights, .none)
        XCTAssertEqual(position.enPassantSquare, -1)
        XCTAssertEqual(position.halfmoveClock, 0)
        XCTAssertEqual(position.fullmoveNumber, 1)
        XCTAssertEqual(position.fen, "8/8/8/4k3/8/8/4K3/8 w - - 0 1")
    }

    func testMalformedFENsAreRejected() {
        let bad = [
            "",                                       // empty
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP",     // 7 ranks
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR/8", // 9 ranks
            "rnbqkbnr/ppppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR",  // 9 files
            "rnbqkbnr/7/8/8/8/8/PPPPPPPP/RNBQKBNR",   // rank sums to 7
            "rnbqkbXr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR",   // bogus letter
        ]
        for fen in bad {
            XCTAssertNil(ChessPosition(fen: fen), "should have rejected: \(fen)")
        }
    }

    func testSquareIndexingMatchesAlgebraic() {
        XCTAssertEqual(ChessSquare("a1")?.index, 0)
        XCTAssertEqual(ChessSquare("h1")?.index, 7)
        XCTAssertEqual(ChessSquare("a8")?.index, 56)
        XCTAssertEqual(ChessSquare("h8")?.index, 63)
        XCTAssertEqual(ChessSquare("e4")?.index, 28)
        for square in ChessSquare.all {
            XCTAssertEqual(ChessSquare(square.algebraic), square)
        }
    }

    /// h1 and a8 are light; a1 and h8 are dark. This parity is shared with
    /// the recogniser's light/dark square baselines, so it is worth
    /// pinning down rather than leaving implicit.
    func testSquareColourParity() {
        XCTAssertTrue(ChessSquare.h1.isLight)
        XCTAssertTrue(ChessSquare.a8.isLight)
        XCTAssertFalse(ChessSquare.a1.isLight)
        XCTAssertFalse(ChessSquare.h8.isLight)
    }

    // MARK: - Make / unmake invariants

    /// Making and then unmaking any legal move must restore the position
    /// *exactly* — placement, clocks, rights, en-passant target and the
    /// Zobrist key. This is the invariant perft silently depends on, so
    /// when it breaks it is worth failing here with a readable message
    /// rather than as a node-count mismatch.
    func testMakeUnmakeRestoresPositionExactly() {
        for fen in [Self.startPosition, Self.kiwipete, Self.position3,
                    Self.position4, Self.position5, Self.position6] {
            guard var position = ChessPosition(fen: fen) else {
                return XCTFail("could not parse \(fen)")
            }
            let before = position.fen
            let keyBefore = position.key

            let moves = ChessMoveGenerator.generateLegal(&position)
            for index in 0..<moves.count {
                let move = moves[index]
                let undo = position.make(move)
                position.unmake(move, undo)
                XCTAssertEqual(position.fen, before, "after \(move.uci) in \(fen)")
                XCTAssertEqual(position.key, keyBefore, "key after \(move.uci) in \(fen)")
            }
        }
    }

    /// The incrementally-updated Zobrist key must equal a from-scratch
    /// recomputation after every move. A drift here would not break move
    /// generation at all — it would quietly corrupt the transposition
    /// table and make the search return moves for a different position.
    func testIncrementalZobristMatchesRecomputed() {
        for fen in [Self.startPosition, Self.kiwipete, Self.position4, Self.position5] {
            guard var position = ChessPosition(fen: fen) else {
                return XCTFail("could not parse \(fen)")
            }
            let moves = ChessMoveGenerator.generateLegal(&position)
            for index in 0..<moves.count {
                let move = moves[index]
                let undo = position.make(move)

                let incremental = position.key
                var recomputed = position
                recomputed.refreshKey()
                XCTAssertEqual(incremental, recomputed.key,
                               "key drifted after \(move.uci) in \(fen)")

                position.unmake(move, undo)
            }
        }
    }

    func testNullMoveRoundTrips() {
        var position = ChessPosition(fen: Self.kiwipete)!
        let before = position.fen
        let key = position.key
        let undo = position.makeNull()
        XCTAssertEqual(position.sideToMove, .black)
        XCTAssertEqual(position.enPassantSquare, -1)
        position.unmakeNull(undo)
        XCTAssertEqual(position.fen, before)
        XCTAssertEqual(position.key, key)
    }

    // MARK: - Move encoding

    func testMoveEncodingRoundTrips() {
        for from in 0..<64 {
            for to in 0..<64 where to != from {
                for flag: ChessMove.Flag in [.quiet, .capture, .enPassant, .doublePawnPush,
                                             .castleKingside, .castleQueenside,
                                             .promoteQueen, .capturePromoteKnight] {
                    let move = ChessMove(from: from, to: to, flag: flag)
                    XCTAssertEqual(move.fromIndex, from)
                    XCTAssertEqual(move.toIndex, to)
                    XCTAssertEqual(move.flag, flag)
                }
            }
        }
    }

    func testMoveFlagPredicates() {
        XCTAssertFalse(ChessMove(from: 0, to: 1, flag: .quiet).isCapture)
        XCTAssertFalse(ChessMove(from: 0, to: 1, flag: .doublePawnPush).isCapture)
        XCTAssertFalse(ChessMove(from: 0, to: 1, flag: .castleKingside).isCapture)
        XCTAssertFalse(ChessMove(from: 0, to: 1, flag: .castleQueenside).isCapture)
        XCTAssertTrue(ChessMove(from: 0, to: 1, flag: .capture).isCapture)
        XCTAssertTrue(ChessMove(from: 0, to: 1, flag: .enPassant).isCapture)
        XCTAssertTrue(ChessMove(from: 0, to: 1, flag: .capturePromoteRook).isCapture)

        XCTAssertTrue(ChessMove(from: 0, to: 1, flag: .promoteQueen).isPromotion)
        XCTAssertEqual(ChessMove(from: 0, to: 1, flag: .promoteQueen).promotionKind, .queen)
        XCTAssertEqual(ChessMove(from: 0, to: 1, flag: .promoteKnight).promotionKind, .knight)
        XCTAssertEqual(ChessMove(from: 0, to: 1, flag: .capturePromoteBishop).promotionKind, .bishop)
        XCTAssertEqual(ChessMove(from: 0, to: 1, flag: .capturePromoteRook).promotionKind, .rook)
        XCTAssertNil(ChessMove(from: 0, to: 1, flag: .capture).promotionKind)
    }

    func testUCIRoundTrips() {
        XCTAssertEqual(ChessMove(from: ChessSquare("e2")!, to: ChessSquare("e4")!,
                                 flag: .doublePawnPush).uci, "e2e4")
        XCTAssertEqual(ChessMove(from: ChessSquare("e7")!, to: ChessSquare("e8")!,
                                 flag: .promoteQueen).uci, "e7e8q")
        XCTAssertEqual(ChessMove(uci: "e2e4")?.fromIndex, ChessSquare("e2")!.index)
        XCTAssertEqual(ChessMove(uci: "e7e8n")?.promotionKind, .knight)
        XCTAssertNil(ChessMove(uci: "e2e"))
        XCTAssertNil(ChessMove(uci: "e7e8k"))   // can't promote to a king
    }

    // MARK: - Rules corner cases

    /// A rook capture on h8 must strip Black's kingside castling right
    /// even though no black piece moved. This is the case that the
    /// from/to castling-mask design exists to get right for free.
    func testCapturingARookClearsTheirCastlingRight() {
        var position = ChessPosition(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")!
        let moves = ChessMoveGenerator.generateLegal(&position)
        guard let capture = moves.asArray.first(where: { $0.uci == "h1h8" }) else {
            return XCTFail("Rxh8 should be legal here")
        }
        position.make(capture)
        XCTAssertFalse(position.castlingRights.contains(.blackKingside),
                       "capturing on h8 must remove Black's kingside right")
        XCTAssertTrue(position.castlingRights.contains(.blackQueenside))
        XCTAssertFalse(position.castlingRights.contains(.whiteKingside),
                       "the capturing rook left h1, so White loses that right too")
    }

    /// You may not castle *through* an attacked square, even though the
    /// king's final square is safe. The play-and-check legality filter
    /// only tests the destination, which is exactly why castling legality
    /// is resolved during generation instead.
    func testCannotCastleThroughCheck() {
        // Black rook on f8 attacks f1, the square the white king crosses.
        var position = ChessPosition(fen: "5r2/8/8/8/8/8/8/4K2R w K - 0 1")!
        let moves = ChessMoveGenerator.legalMoves(in: position)
        XCTAssertFalse(moves.contains { $0.isCastle },
                       "castling through the attacked f1 must be illegal")

        // Move the rook to g8 — now it attacks the king's landing square.
        position = ChessPosition(fen: "6r1/8/8/8/8/8/8/4K2R w K - 0 1")!
        XCTAssertFalse(ChessMoveGenerator.legalMoves(in: position).contains { $0.isCastle },
                       "castling into the attacked g1 must be illegal")

        // And with the rook on h8 attacking only h1, castling is fine.
        position = ChessPosition(fen: "7r/8/8/8/8/8/8/4K2R w K - 0 1")!
        XCTAssertTrue(ChessMoveGenerator.legalMoves(in: position).contains { $0.isCastle },
                      "nothing attacks e1/f1/g1, so O-O is legal")
    }

    /// Castling out of check is illegal.
    func testCannotCastleOutOfCheck() {
        var position = ChessPosition(fen: "4r3/8/8/8/8/8/8/4K2R w K - 0 1")!
        let moves = ChessMoveGenerator.generateLegal(&position)
        XCTAssertFalse(moves.asArray.contains { $0.isCastle })
    }

    /// Rights claiming a rook that isn't there must not produce a castle —
    /// a hand-edited or recognised position can easily say "KQkq" with an
    /// empty h1.
    func testCastlingRightsWithoutARookGenerateNothing() {
        let position = ChessPosition(fen: "4k3/8/8/8/8/8/8/4K3 w KQkq - 0 1")!
        XCTAssertFalse(ChessMoveGenerator.legalMoves(in: position).contains { $0.isCastle })
    }

    /// The en-passant capture that exposes the capturing side's own king
    /// along the fifth rank — two pawns leave the rank in one move, which
    /// no other move in chess does.
    func testEnPassantThatWouldExposeTheKingIsIllegal() {
        // White Kh5 … black pawn b5, white pawn a5, black rook h5-side.
        // After bxa6 e.p. both pawns vacate rank 5 and the rook checks.
        var position = ChessPosition(fen: "8/8/8/K1Pp3r/8/8/8/7k w - d6 0 1")!
        let moves = ChessMoveGenerator.generateLegal(&position)
        XCTAssertFalse(moves.asArray.contains { $0.isEnPassant },
                       "en passant that uncovers the king along the rank is illegal")
    }

    func testEnPassantIsGeneratedWhenLegal() {
        var position = ChessPosition(fen: "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")!
        let moves = ChessMoveGenerator.generateLegal(&position)
        let enPassant = moves.asArray.filter(\.isEnPassant)
        XCTAssertEqual(enPassant.count, 1)
        XCTAssertEqual(enPassant.first?.uci, "e5d6")

        // And it actually removes the pawn on d5, not the empty d6.
        position.make(enPassant[0])
        XCTAssertNil(position.piece(at: ChessSquare("d5")!))
        XCTAssertEqual(position.piece(at: ChessSquare("d6")!), ChessPiece(.white, .pawn))
    }

    func testPromotionGeneratesAllFourKinds() {
        let position = ChessPosition(fen: "4k3/P7/8/8/8/8/8/4K3 w - - 0 1")!
        let promotions = ChessMoveGenerator.legalMoves(in: position).filter(\.isPromotion)
        XCTAssertEqual(Set(promotions.map(\.uci)), ["a7a8q", "a7a8r", "a7a8b", "a7a8n"])
    }

    func testCheckmateAndStalemateAreDistinguished() {
        // Fool's mate.
        let mate = ChessPosition(fen: "rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3")!
        XCTAssertEqual(mate.outcome, .checkmate)
        XCTAssertTrue(mate.isInCheck)

        // Classic king-and-queen stalemate: Black to move, not in check,
        // no legal move.
        let stalemate = ChessPosition(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")!
        XCTAssertEqual(stalemate.outcome, .stalemate)
        XCTAssertFalse(stalemate.isInCheck)
    }

    func testInsufficientMaterial() {
        XCTAssertTrue(ChessPosition(fen: "4k3/8/8/8/8/8/8/4K3 w - - 0 1")!.hasInsufficientMaterial)
        XCTAssertTrue(ChessPosition(fen: "4k3/8/8/8/8/8/8/4KB2 w - - 0 1")!.hasInsufficientMaterial)
        XCTAssertTrue(ChessPosition(fen: "4k3/8/8/8/8/8/8/4KN2 w - - 0 1")!.hasInsufficientMaterial)
        // Bishops of *both* colours on the board still can't mate when
        // they all stand on one square colour. f8 and c1 are both dark.
        XCTAssertTrue(ChessPosition(fen: "4kb2/8/8/8/8/8/8/2B1K3 w - - 0 1")!.hasInsufficientMaterial)
        // …but put them on opposite square colours (c8 is light, c1 dark)
        // and a mate exists in contrived positions, so it is not dead.
        XCTAssertFalse(ChessPosition(fen: "2b1k3/8/8/8/8/8/8/2B1K3 w - - 0 1")!.hasInsufficientMaterial)
        // A pawn is always enough to keep playing.
        XCTAssertFalse(ChessPosition(fen: "4k3/8/8/8/8/8/P7/4K3 w - - 0 1")!.hasInsufficientMaterial)
        // Deliberately *not* a draw by our conservative rule — see
        // `hasInsufficientMaterial`'s documentation.
        XCTAssertFalse(ChessPosition(fen: "4k3/8/8/8/8/8/8/3NKN2 w - - 0 1")!.hasInsufficientMaterial)
    }

    // MARK: - Legality reporting

    func testLegalPositionHasNoProblems() {
        XCTAssertTrue(ChessPosition.standard.isAnalysable)
        XCTAssertEqual(ChessPosition(fen: Self.kiwipete)!.legalityProblems.count, 0)
    }

    /// The misreads the recogniser actually produces, each of which the
    /// analysis screen has to explain rather than silently search.
    func testRecogniserMisreadsAreReported() {
        // A third king — two white kings.
        let threeKings = ChessPosition(fen: "4k3/8/8/8/8/8/8/3KK3 w - - 0 1")!
        XCTAssertTrue(threeKings.legalityProblems.contains(.tooManyKings(.white)))

        // A missing king.
        let noKing = ChessPosition(fen: "4k3/8/8/8/8/8/8/8 w - - 0 1")!
        XCTAssertTrue(noKing.legalityProblems.contains(.missingKing(.white)))

        // Nine pawns.
        let ninePawns = ChessPosition(fen: "4k3/8/8/8/8/PPPPPPPP/P7/4K3 w - - 0 1")!
        XCTAssertTrue(ninePawns.legalityProblems.contains(.tooManyPawns(.white, count: 9)))

        // A pawn hallucinated onto the back rank.
        let backRankPawn = ChessPosition(fen: "4k3/8/8/8/8/8/8/P3K3 w - - 0 1")!
        XCTAssertTrue(backRankPawn.legalityProblems.contains(.pawnOnBackRank(ChessSquare.a1)))

        // Both sides' full pawn set plus three extra queens — no pawns
        // could have promoted to make them.
        let impossibleQueens = ChessPosition(
            fen: "4k3/pppppppp/8/8/QQQQ4/8/PPPPPPPP/4K3 w - - 0 1")!
        XCTAssertTrue(impossibleQueens.legalityProblems.contains(.impossiblePromotionCount(.white)))
    }

    /// The position that decides whether the analysis screen can offer a
    /// move for *both* sides: if Black is already in check while White is
    /// to move, "best move for Black" is not a question about a legal
    /// position.
    func testSideToMoveWithOpponentInCheckIsReported() {
        // White rook on e2 checks the black king down the open e-file,
        // while it is White's move — a board no legal game could reach.
        let position = ChessPosition(fen: "4k3/8/8/8/8/8/4R3/K7 w - - 0 1")!
        XCTAssertTrue(position.opponentIsInCheck)
        XCTAssertTrue(position.legalityProblems.contains(.opponentInCheck(.black)))
        XCTAssertFalse(position.isAnalysable)

        var flipped = position
        flipped.setSideToMove(.black)
        XCTAssertTrue(flipped.isAnalysable, "with Black to move the same board is fine")
    }

    // MARK: - Placement round-trip (the recogniser's entry point)

    func testPlacementArrayRoundTrips() {
        let original = ChessPosition(fen: Self.kiwipete)!
        let rebuilt = ChessPosition(placement: original.placement,
                                    sideToMove: original.sideToMove,
                                    castlingRights: original.castlingRights,
                                    enPassantSquare: nil,
                                    halfmoveClock: original.halfmoveClock,
                                    fullmoveNumber: original.fullmoveNumber)
        XCTAssertEqual(rebuilt.fen, original.fen)
        XCTAssertEqual(rebuilt.key, original.key)
    }

    func testEditingASquareUpdatesTheKey() {
        var position = ChessPosition.standard
        let before = position.key
        position.setPiece(nil, at: ChessSquare("e2")!)
        position.refreshKey()
        XCTAssertNotEqual(position.key, before)

        position.setPiece(ChessPiece(.white, .pawn), at: ChessSquare("e2")!)
        position.refreshKey()
        XCTAssertEqual(position.key, before, "putting it back must restore the key")
    }
}
