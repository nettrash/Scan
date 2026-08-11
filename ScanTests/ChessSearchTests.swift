//
//  ChessSearchTests.swift
//  ScanTests
//
//  Search, evaluation, SAN, and the both-sides analysis the Chess tab
//  actually calls.
//
//  Where `ChessEngineTests` proves the *rules* are right (via perft),
//  this file proves the engine *plays* — that it finds forced mates,
//  takes free material, and reports what it found honestly.
//
//  ## Mates are verified by playing them out
//
//  Rather than trusting hand-picked puzzle solutions, the mate tests
//  assert two things together: that the engine reports a mate, and that
//  its own principal variation, played move by move on a real board,
//  actually ends in checkmate after exactly the number of moves it
//  claimed. A search that hallucinates a mate fails the playout; one
//  that finds a mate but misreports the distance fails the comparison.
//  Neither can pass by accident.
//
//  ## Determinism
//
//  Tests search to a fixed **depth**, never to a fixed time. A
//  time-limited search returns whatever it reached before the clock ran
//  out, which varies with machine load and would make these tests flaky
//  in CI.
//

import XCTest
@testable import Scan

final class ChessSearchTests: XCTestCase {

    // MARK: - Helpers

    /// Search to a fixed depth. The generous think time is a safety valve,
    /// not the limit — depth is what makes the result reproducible.
    private func search(_ fen: String, depth: Int) -> (ChessPosition, ChessSearch.Result)? {
        guard let position = ChessPosition(fen: fen) else {
            XCTFail("could not parse FEN: \(fen)")
            return nil
        }
        let engine = ChessSearch()
        guard let result = engine.search(position,
                                         limits: .init(thinkTime: 30, maximumDepth: depth)) else {
            return nil
        }
        return (position, result)
    }

    /// Play `line` from `position` and return how many plies it took to
    /// reach checkmate, or nil if it never does (or contains an illegal
    /// move).
    private func pliesToMate(from position: ChessPosition, playing line: [ChessMove]) -> Int? {
        var board = position
        var plies = 0
        for move in line {
            var scratch = board
            guard ChessMoveGenerator.generateLegal(&scratch).asArray.contains(move) else {
                XCTFail("principal variation contains an illegal move: \(move.uci)")
                return nil
            }
            board.make(move)
            plies += 1
            if board.outcome == .checkmate { return plies }
        }
        return nil
    }

    /// Assert the engine finds a forced mate here, and that its own line
    /// delivers exactly that mate.
    private func assertFindsMate(_ fen: String,
                                 inMoves expected: Int,
                                 depth: Int,
                                 file: StaticString = #filePath,
                                 line: UInt = #line) {
        guard let (position, result) = search(fen, depth: depth) else {
            return XCTFail("no legal moves in \(fen)", file: file, line: line)
        }
        XCTAssertEqual(result.mateInMoves, expected,
                       "reported mate distance for \(fen)", file: file, line: line)

        guard let plies = pliesToMate(from: position, playing: result.principalVariation) else {
            return XCTFail("PV \(result.principalVariation.map(\.uci)) does not mate in \(fen)",
                           file: file, line: line)
        }
        XCTAssertEqual((plies + 1) / 2, expected,
                       "played-out mate distance for \(fen)", file: file, line: line)
    }

    // MARK: - Mate finding

    /// Back-rank mate: the king is sealed in by its own pawns.
    func testFindsBackRankMateInOne() {
        assertFindsMate("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1", inMoves: 1, depth: 3)
    }

    /// Rook mate supported by the enemy king covering the escape squares.
    func testFindsSupportedRookMateInOne() {
        assertFindsMate("4k3/8/4K3/8/8/8/8/7R w - - 0 1", inMoves: 1, depth: 3)
    }

    /// Black to move, mating White — makes sure the mate scoring isn't
    /// written from White's point of view somewhere.
    func testFindsMateInOneForBlack() {
        assertFindsMate("r5k1/8/8/8/8/8/5PPP/6K1 b - - 0 1", inMoves: 1, depth: 3)
    }

    /// Two moves deep: the black rook can interpose on b8, which buys
    /// exactly one move. 1.Ra8+ Rb8 2.Rxb8#.
    func testFindsMateInTwo() {
        assertFindsMate("6k1/1r3ppp/8/8/8/8/5PPP/R5K1 w - - 0 1", inMoves: 2, depth: 6)
    }

    /// A mate must outrank any amount of material.
    ///
    /// White can win a whole queen with Rxh6, or mate at once with Ra8#.
    /// The black queen on h6 is deliberately placed where it can neither
    /// reach the a8-g8 checking ray (its f8 diagonal is blocked by its
    /// own g7 pawn) nor capture on a8 — so Ra8 really is mate.
    func testPrefersMateOverMaterial() {
        guard let (_, result) = search("6k1/5ppp/7q/8/8/8/7R/R5K1 w - - 0 1", depth: 5) else {
            return XCTFail("expected legal moves")
        }
        XCTAssertEqual(result.mateInMoves, 1)
        XCTAssertEqual(result.bestMove.uci, "a1a8", "mate beats winning a queen")
    }

    // MARK: - Material

    /// The simplest sanity check there is: a queen is hanging, take it.
    func testTakesAFreeQueen() {
        guard let (_, result) = search("4k3/8/8/3q4/8/8/8/3RK3 w - - 0 1", depth: 6) else {
            return XCTFail("expected legal moves")
        }
        XCTAssertEqual(result.bestMove.uci, "d1d5", "Rxd5 wins a queen for nothing")
        XCTAssertGreaterThan(result.score, 500)
    }

    /// Quiescence's whole job: don't grab a defended pawn with a queen
    /// and call it winning. Without a quiescence search the engine
    /// evaluates the position one ply after the capture and thinks it is
    /// a pawn up.
    func testDoesNotGrabADefendedPawnWithTheQueen() {
        // Queens are level; the black pawn on d5 is defended by c6.
        // Qxd5?? cxd5 simply drops the queen.
        let fen = "3qk3/8/2p5/3p4/8/8/3Q4/4K3 w - - 0 1"
        guard let (_, result) = search(fen, depth: 6) else {
            return XCTFail("expected legal moves")
        }
        XCTAssertNotEqual(result.bestMove.uci, "d2d5", "Qxd5 loses the queen to cxd5")
        XCTAssertLessThan(result.score, 200, "should not evaluate this as winning material")
    }

    /// The evaluation is symmetric: mirroring a position vertically and
    /// swapping colours must produce the same score for the side to move.
    /// An asymmetry here would mean the engine plays one colour better
    /// than the other, which is exactly the bug a "best move for White
    /// and for Black" feature cannot afford.
    func testEvaluationIsColourSymmetric() {
        let pairs = [
            ("r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 0 1",
             "rnbqk2r/pppp1ppp/5n2/2b1p3/4P3/2N5/PPPP1PPP/R1BQKBNR w KQkq - 0 1"),
            ("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
             "8/4p1p1/8/1r3P1K/kp5R/3P4/2P5/8 b - - 0 1"),
        ]
        for (white, black) in pairs {
            let a = ChessEvaluation.evaluate(ChessPosition(fen: white)!)
            let b = ChessEvaluation.evaluate(ChessPosition(fen: black)!)
            XCTAssertEqual(a, b, "evaluation asymmetric between\n  \(white)\n  \(black)")
        }
    }

    /// The starting position is dead level by construction.
    func testStartingPositionEvaluatesAsBalanced() {
        XCTAssertEqual(ChessEvaluation.evaluate(.standard), 0)
    }

    // MARK: - Search behaviour

    func testSearchIsDeterministicAtFixedDepth() {
        let fen = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
        guard let first = search(fen, depth: 5), let second = search(fen, depth: 5) else {
            return XCTFail("expected legal moves")
        }
        XCTAssertEqual(first.1.bestMove, second.1.bestMove)
        XCTAssertEqual(first.1.score, second.1.score)
    }

    /// The principal variation must be playable from the root. A PV with
    /// an illegal move in it means the triangular table is being written
    /// wrong — and the UI draws arrows from this line.
    func testPrincipalVariationIsFullyLegal() {
        let fen = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
        guard let (position, result) = search(fen, depth: 6) else {
            return XCTFail("expected legal moves")
        }
        XCTAssertFalse(result.principalVariation.isEmpty)
        XCTAssertEqual(result.principalVariation.first, result.bestMove)

        var board = position
        for move in result.principalVariation {
            var scratch = board
            let legal = ChessMoveGenerator.generateLegal(&scratch).asArray
            XCTAssertTrue(legal.contains(move),
                          "PV move \(move.uci) is illegal at \(board.fen)")
            guard legal.contains(move) else { return }
            board.make(move)
        }
    }

    func testSearchReturnsNilWhenThereAreNoLegalMoves() {
        let mate = ChessPosition(fen: "rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3")!
        XCTAssertNil(ChessSearch().search(mate, limits: .init(thinkTime: 1, maximumDepth: 4)))

        let stalemate = ChessPosition(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")!
        XCTAssertNil(ChessSearch().search(stalemate, limits: .init(thinkTime: 1, maximumDepth: 4)))
    }

    /// The time budget is the contract the UI relies on. Allow generous
    /// slack for a loaded CI machine, but catch a search that ignores the
    /// clock entirely.
    func testRespectsTheTimeBudget() {
        let position = ChessPosition(fen:
            "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")!
        let started = Date()
        let result = ChessSearch().search(position, limits: .init(thinkTime: 0.3))
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertNotNil(result)
        XCTAssertLessThan(elapsed, 3.0, "0.3s budget overshot badly")
    }

    /// `stop()` from another thread must cut an in-flight search short and
    /// still hand back a usable move — this is what the UI does when the
    /// user edits a square mid-analysis.
    func testStopCutsAnInFlightSearchShort() {
        let position = ChessPosition(fen:
            "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")!
        let engine = ChessSearch()

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { engine.stop() }

        let started = Date()
        // A 30s budget it must not come close to spending.
        let result = engine.search(position, limits: .init(thinkTime: 30))
        let elapsed = Date().timeIntervalSince(started)

        guard let result else { return XCTFail("expected a move") }
        XCTAssertLessThan(elapsed, 5.0, "stop() did not interrupt the search")
        XCTAssertFalse(result.bestMove.isNone)
        XCTAssertTrue(ChessMoveGenerator.legalMoves(in: position).contains(result.bestMove))
    }

    /// Even with a budget too short to finish depth 1, the search must
    /// return a legal move rather than `.none` — the UI has no fallback.
    func testReturnsALegalMoveOnAVanishingBudget() {
        let position = ChessPosition(fen:
            "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")!
        guard let result = ChessSearch().search(position, limits: .init(thinkTime: 0.001)) else {
            return XCTFail("expected a move")
        }
        XCTAssertFalse(result.bestMove.isNone)
        XCTAssertTrue(ChessMoveGenerator.legalMoves(in: position).contains(result.bestMove))
    }

    // MARK: - SAN

    func testSANBasics() {
        let position = ChessPosition.standard
        XCTAssertEqual(position.san(for: position.move(uci: "e2e4")!), "e4")
        XCTAssertEqual(position.san(for: position.move(uci: "g1f3")!), "Nf3")
    }

    func testSANPawnCapture() {
        let position = ChessPosition(fen: "4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1")!
        XCTAssertEqual(position.san(for: position.move(uci: "e4d5")!), "exd5")
    }

    func testSANFileDisambiguation() {
        // Knights on c3 and g1 both reach e2.
        let position = ChessPosition(fen: "4k3/8/8/8/8/2N5/8/4K1N1 w - - 0 1")!
        XCTAssertEqual(position.san(for: position.move(uci: "c3e2")!), "Nce2")
        XCTAssertEqual(position.san(for: position.move(uci: "g1e2")!), "Nge2")
    }

    func testSANRankDisambiguation() {
        // Rooks on a1 and a8 share a file, so the rank disambiguates.
        // The black king sits off the 8th rank and off the a-file so that
        // neither rook is giving check — otherwise every move picks up a
        // "+" and the comparison is about something else.
        let position = ChessPosition(fen: "R7/8/4k3/8/8/8/8/R3K3 w - - 0 1")!
        XCTAssertEqual(position.san(for: position.move(uci: "a1a4")!), "R1a4")
        XCTAssertEqual(position.san(for: position.move(uci: "a8a4")!), "R8a4")
    }

    func testSANCastling() {
        let position = ChessPosition(fen: "4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1")!
        XCTAssertEqual(position.san(for: position.move(uci: "e1g1")!), "O-O")
        XCTAssertEqual(position.san(for: position.move(uci: "e1c1")!), "O-O-O")
    }

    func testSANPromotionAndCheck() {
        let position = ChessPosition(fen: "4k3/P7/8/8/8/8/8/4K3 w - - 0 1")!
        XCTAssertEqual(position.san(for: position.move(uci: "a7a8q")!), "a8=Q+")
        XCTAssertEqual(position.san(for: position.move(uci: "a7a8n")!), "a8=N")
    }

    func testSANMateSuffix() {
        let position = ChessPosition(fen: "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1")!
        XCTAssertEqual(position.san(for: position.move(uci: "a1a8")!), "Ra8#")
    }

    /// A pinned piece cannot reach the square, so it is not a rival and
    /// must not force a disambiguation hint onto the piece that can.
    ///
    /// Knights on b3 and f3 both attack d4, but the f3 knight is pinned
    /// against the king on f1 by the rook on f8. So "Nd4" is correct and
    /// "Nbd4" would be wrong.
    func testSANIgnoresPinnedRivals() {
        let position = ChessPosition(fen: "5r1k/8/8/8/8/1N3N2/8/5K2 w - - 0 1")!
        let legal = ChessMoveGenerator.legalMoves(in: position).map { position.san(for: $0) }
        XCTAssertTrue(legal.contains("Nd4"),
                      "the unpinned knight needs no hint; got \(legal)")
        XCTAssertFalse(legal.contains("Nbd4"), "the f3 knight is pinned, so it is not a rival")
        XCTAssertFalse(legal.contains("Nfd4"), "the pinned knight cannot legally reach d4")
    }

    func testSANLineNumbering() {
        let position = ChessPosition.standard
        let line = [position.move(uci: "e2e4")!]
        var next = position
        next.make(line[0])
        let reply = next.move(uci: "e7e5")!
        XCTAssertEqual(position.sanLine([line[0], reply]), "1. e4 e5")

        // A line beginning on Black's move gets the "1..." form.
        XCTAssertEqual(next.sanLine([reply]), "1... e5")
    }

    func testMoveByUCIRejectsIllegalMoves() {
        let position = ChessPosition.standard
        XCTAssertNotNil(position.move(uci: "e2e4"))
        XCTAssertNil(position.move(uci: "e2e5"), "not a legal pawn move")
        XCTAssertNil(position.move(uci: "a1a5"), "rook is blocked")
    }

    /// A UCI string carries no capture flag, so the returned move must be
    /// the *generated* one with its flags intact — otherwise `make` would
    /// move the piece without removing the captured one.
    func testMoveByUCICarriesTheRightFlags() {
        let position = ChessPosition(fen: "4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1")!
        let capture = position.move(uci: "e4d5")
        XCTAssertEqual(capture?.flag, .capture)

        let enPassant = ChessPosition(fen: "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")!
        XCTAssertEqual(enPassant.move(uci: "e5d6")?.flag, .enPassant)

        let castle = ChessPosition(fen: "4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1")!
        XCTAssertEqual(castle.move(uci: "e1g1")?.flag, .castleKingside)
    }

    // MARK: - The both-sides API

    /// The feature's headline call on an ordinary position: both sides
    /// get a move.
    func testBothSidesAnalysisOnALegalPosition() {
        let position = ChessPosition.standard
        let analysis = ChessEngine().analyseBothSides(position, thinkTime: 0.2)

        guard case .move(let white) = analysis.white else {
            return XCTFail("expected a move for White, got \(analysis.white)")
        }
        guard case .move(let black) = analysis.black else {
            return XCTFail("expected a move for Black, got \(analysis.black)")
        }
        XCTAssertEqual(white.side, .white)
        XCTAssertEqual(black.side, .black)
        XCTAssertFalse(white.san.isEmpty)
        XCTAssertFalse(black.san.isEmpty)
        XCTAssertEqual(analysis.placementFEN,
                       "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR")
    }

    /// The case that makes "both sides" interesting: a board that is only
    /// legal for one of them. White cannot be to move while Black stands
    /// in check, so that side reports why instead of inventing a move.
    func testBothSidesAnalysisWhenOnlyOneSideMayMove() {
        // White rook on e2 checks the black king down the e-file.
        let position = ChessPosition(fen: "4k3/8/8/8/8/8/4R3/K7 w - - 0 1")!
        let analysis = ChessEngine().analyseBothSides(position, thinkTime: 0.2)

        guard case .notLegal(let problems) = analysis.white else {
            return XCTFail("White to move here is illegal; got \(analysis.white)")
        }
        XCTAssertTrue(problems.contains(.opponentInCheck(.black)))

        guard case .move = analysis.black else {
            return XCTFail("Black to move is legal — it must escape the check")
        }
    }

    /// A misread board reports its problems rather than searching
    /// garbage. This is what the analysis screen shows the user.
    func testAnalysisRefusesAnIllegalPosition() {
        let noKing = ChessPosition(fen: "4k3/8/8/8/8/8/8/8 w - - 0 1")!
        guard case .notLegal(let problems) = ChessEngine().analyse(noKing, thinkTime: 0.1) else {
            return XCTFail("expected .notLegal")
        }
        XCTAssertTrue(problems.contains(.missingKing(.white)))
    }

    func testAnalysisReportsCheckmateAsTerminal() {
        let mate = ChessPosition(fen: "rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3")!
        guard case .terminal(let outcome) = ChessEngine().analyse(mate, thinkTime: 0.1) else {
            return XCTFail("expected .terminal")
        }
        XCTAssertEqual(outcome, .checkmate)
    }

    /// Scores are reported from each side's own perspective internally,
    /// but `displayScore` is White-relative — the convention every chess
    /// UI uses.
    func testDisplayScoreIsWhiteRelative() {
        // Black is a queen up here, so both sides should agree the
        // evaluation favours Black, i.e. a negative display score.
        let position = ChessPosition(fen: "3qk3/8/8/8/8/8/8/4K3 w - - 0 1")!
        let analysis = ChessEngine().analyseBothSides(position, thinkTime: 0.2)

        if case .move(let white) = analysis.white {
            XCTAssertLessThan(white.whiteRelativePawns, 0, "White is a queen down")
            XCTAssertTrue(white.displayScore.hasPrefix("-"), white.displayScore)
        } else {
            XCTFail("expected a move for White, got \(analysis.white)")
        }
    }
}
