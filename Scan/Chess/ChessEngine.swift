//
//  ChessEngine.swift
//  Scan
//
//  The engine's public face — what the Chess tab talks to.
//
//  ## Why "both sides" is the primary API
//
//  A scanned board has no move history, so nothing in the photo says
//  whose turn it is. The feature's promise is "here's the best move for
//  White, and the best move for Black", which means running two searches
//  over the same placement with the side-to-move flipped between them.
//
//  The wrinkle is that a given board is often legal for only *one* side
//  to move: if Black is standing in check, it cannot be White's turn,
//  because Black would have had to leave its king en prise. So each side
//  gets its own outcome, and "not a legal position with this side to
//  move" is a first-class answer rather than an error — it is the
//  correct, informative response for roughly half of all real positions.
//
//  ## Threading
//
//  `analyse` is synchronous and CPU-bound; call it off the main actor.
//  `AnalysisSession` wraps that in a cancellable task for the UI, so a
//  user who edits a square mid-search doesn't wait for the old one.
//

import Foundation

// MARK: - Result types

/// What the engine can say about one side's best move.
public enum ChessAnalysisOutcome: Sendable {
    /// A move was found.
    case move(ChessAnalysis)
    /// The side to move has no legal move — the game is already over.
    case terminal(ChessPosition.Outcome)
    /// The board is not a legal chess position with this side to move.
    /// Carries the specific problems so the UI can tell the user what to
    /// fix in the editor.
    case notLegal([ChessLegalityProblem])
}

public struct ChessAnalysis: Sendable {
    /// The move to play.
    public var move: ChessMove
    /// SAN for `move`, e.g. "Nxe5+". Precomputed because rendering it
    /// needs the position, which the UI no longer has by then.
    public var san: String
    /// Centipawns, **from this side's point of view** — positive is good
    /// for the side that was asked. See `displayScore` for the
    /// White-relative form conventionally shown to users.
    public var score: Int
    /// Set when the score is a forced mate: positive = this side mates in
    /// N moves, negative = this side gets mated in N.
    public var mateInMoves: Int?
    /// The expected continuation, starting with `move`.
    public var principalVariation: [ChessMove]
    /// The line in readable form: "15. Nf3 Bd6 16. O-O".
    public var principalVariationSAN: String
    public var depth: Int
    public var nodes: Int
    public var elapsed: TimeInterval

    /// The side this analysis is for.
    public var side: ChessColor

    /// Score in pawns from **White's** perspective, the convention every
    /// chess UI uses: "+1.4" means White is better regardless of who is
    /// to move.
    public var whiteRelativePawns: Double {
        let white = side == .white ? score : -score
        return Double(white) / 100.0
    }

    /// Ready-to-display evaluation: "+1.4", "-0.3", "M3", "-M2".
    public var displayScore: String {
        if let mate = mateInMoves {
            // Flip to White's perspective for display, same as the
            // numeric score.
            let whiteRelative = side == .white ? mate : -mate
            return whiteRelative > 0 ? "M\(whiteRelative)" : "-M\(abs(whiteRelative))"
        }
        return String(format: "%+.1f", whiteRelativePawns)
    }
}

/// Both sides' answers for one board.
public struct ChessBothSidesAnalysis: Sendable {
    public var white: ChessAnalysisOutcome
    public var black: ChessAnalysisOutcome
    /// The placement analysed, without a side to move.
    public var placementFEN: String

    public func outcome(for side: ChessColor) -> ChessAnalysisOutcome {
        side == .white ? white : black
    }
}

// MARK: - Engine

public final class ChessEngine {

    /// How long to think per side. The UI exposes these three; the
    /// default matches the "point the phone and get an answer" feel the
    /// feature is aiming for.
    public enum ThinkTime: TimeInterval, CaseIterable, Sendable {
        case fast = 0.2
        case standard = 1.0
        case deep = 3.0

        public var displayName: String {
            switch self {
            case .fast: return "Fast"
            case .standard: return "Standard"
            case .deep: return "Deep"
            }
        }
    }

    private let search = ChessSearch()

    public init() {}

    /// Stop any in-flight search. Safe from any thread.
    public func stop() { search.stop() }

    /// Analyse `position` for whichever side it says is to move.
    ///
    /// Synchronous and CPU-bound — do not call this on the main thread.
    public func analyse(_ position: ChessPosition,
                        thinkTime: TimeInterval = ThinkTime.standard.rawValue) -> ChessAnalysisOutcome {
        let problems = position.legalityProblems
        guard problems.isEmpty else { return .notLegal(problems) }

        guard let result = search.search(position,
                                         limits: .init(thinkTime: thinkTime)) else {
            // No legal moves: the position is already decided.
            return .terminal(position.isInCheck ? .checkmate : .stalemate)
        }

        // Terminal-but-legal states the search doesn't report as "no
        // move" — it will still hand back a move in a dead-drawn ending.
        if position.hasInsufficientMaterial { return .terminal(.insufficientMaterial) }
        if position.halfmoveClock >= 100 { return .terminal(.fiftyMoveRule) }

        return .move(ChessAnalysis(
            move: result.bestMove,
            san: position.san(for: result.bestMove),
            score: result.score,
            mateInMoves: result.mateInMoves,
            principalVariation: result.principalVariation,
            principalVariationSAN: position.sanLine(result.principalVariation),
            depth: result.depth,
            nodes: result.nodes,
            elapsed: result.elapsed,
            side: position.sideToMove
        ))
    }

    /// Analyse `position` as if `side` were to move.
    ///
    /// Setting the side to move can make the board illegal (the opponent
    /// would be standing in check), which is reported rather than
    /// searched — see the file header.
    public func analyse(_ position: ChessPosition,
                        for side: ChessColor,
                        thinkTime: TimeInterval = ThinkTime.standard.rawValue) -> ChessAnalysisOutcome {
        var flipped = position
        if flipped.sideToMove != side {
            flipped.setSideToMove(side)
            // The en-passant target belonged to the other side's last
            // move; it cannot survive handing the turn over, and leaving
            // it would generate a capture of a pawn that never moved.
            flipped.setEnPassantSquare(nil)
        }
        return analyse(flipped, thinkTime: thinkTime)
    }

    /// The feature's headline call: best move for White *and* for Black
    /// from the same board.
    ///
    /// Runs the two searches back to back on the calling thread. Budget
    /// accordingly — a `.standard` think time means this takes about two
    /// seconds, not one.
    public func analyseBothSides(_ position: ChessPosition,
                                 thinkTime: TimeInterval = ThinkTime.standard.rawValue)
        -> ChessBothSidesAnalysis {
        ChessBothSidesAnalysis(
            white: analyse(position, for: .white, thinkTime: thinkTime),
            black: analyse(position, for: .black, thinkTime: thinkTime),
            placementFEN: position.placementFEN
        )
    }
}
