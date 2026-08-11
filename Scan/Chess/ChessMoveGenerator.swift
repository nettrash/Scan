//
//  ChessMoveGenerator.swift
//  Scan
//
//  Move generation.
//
//  ## Pseudo-legal, then filtered
//
//  Generation happens in two passes: build every move that obeys the
//  *movement* rules, then drop the ones that leave your own king en
//  prise by playing each and asking. That is the slower of the two
//  standard designs — the faster one computes pins and check masks up
//  front and only ever emits legal moves.
//
//  We take the slow one because the failure modes are so lopsided.
//  Pin-aware generation is where engines hide their subtlest bugs
//  (a rook pinned along the rank that captures en passant and exposes
//  the king is the famous one), and those bugs surface as a perft
//  mismatch six plies deep with no clue attached. Play-and-check cannot
//  be wrong: it asks the same `isAttacked` the rest of the engine trusts.
//
//  The cost is real but bounded — roughly one extra make/unmake per
//  generated move — and move generation is not what limits this engine
//  at a 1-3 s/move budget. If that changes, `generateLegal` is the single
//  function to replace, and perft is already standing by to prove the
//  replacement equivalent.
//

import Foundation

public enum ChessMoveGenerator {

    /// What to generate.
    public enum Mode {
        /// Everything legal.
        case all
        /// Captures, en passant and promotions only — the quiescence
        /// search's diet. Quiet promotions are included because a pawn
        /// reaching the eighth rank changes the material balance just as
        /// violently as a capture does, and leaving them out makes
        /// quiescence blind to the most forcing move on the board.
        case capturesAndPromotions
    }

    // MARK: - Legal moves

    /// Every legal move in `position`.
    ///
    /// Takes the position `inout` and leaves it **exactly as it found
    /// it**: the filter plays each candidate on the real board and takes
    /// it back, which avoids copying three arrays per node. The `inout`
    /// is what makes that safe to say out loud in the signature.
    public static func generateLegal(_ position: inout ChessPosition,
                                     mode: Mode = .all) -> ChessMoveList {
        let pseudoLegal = generatePseudoLegal(position, mode: mode)
        let us = position.sideToMove
        let them = us.opposite

        var legal = ChessMoveList()
        for index in 0..<pseudoLegal.count {
            let move = pseudoLegal[index]
            let undo = position.make(move)
            let king = position.kingSquare(us)
            // A kingless side has nothing to expose. That position is
            // illegal and the engine refuses to search it, but the editor
            // can hold one and still wants a move list to highlight.
            if king < 0 || !position.isAttacked(king, by: them) {
                legal.append(move)
            }
            position.unmake(move, undo)
        }
        return legal
    }

    /// Convenience for callers that hold an immutable position — the UI,
    /// mostly. Copies, so don't use it inside the search.
    public static func legalMoves(in position: ChessPosition, mode: Mode = .all) -> [ChessMove] {
        var scratch = position
        return generateLegal(&scratch, mode: mode).asArray
    }

    // MARK: - Pseudo-legal moves

    /// Every move that obeys the movement rules, ignoring whether it
    /// leaves your own king in check.
    ///
    /// Castling is the exception: its "you may not castle out of, through
    /// or into check" conditions are checked here rather than left to the
    /// filter, because the filter only ever tests the king's *final*
    /// square and would happily let a king walk through a checked f1.
    public static func generatePseudoLegal(_ position: ChessPosition,
                                           mode: Mode = .all) -> ChessMoveList {
        var moves = ChessMoveList()
        let us = position.sideToMove
        let them = us.opposite
        let ourPieces = position.pieces(us)
        let theirPieces = position.pieces(them)
        let occupancy = position.occupied

        // Non-captures are only wanted in `.all` mode; the target mask
        // does that filtering once instead of at every emit site.
        let quietTargets = mode == .all ? ~occupancy : ChessBitboard.empty

        generatePawnMoves(position, us: us, mode: mode, into: &moves)

        for kind in [ChessPieceKind.knight, .bishop, .rook, .queen] {
            var from = position.pieces(us, kind)
            while from.isNotEmpty {
                let square = from.popLsb()
                let attacks = kind == .knight
                    ? ChessTables.knightAttacks[square]
                    : ChessTables.sliderAttacks(kind, square, occupancy)
                emit(from: square,
                     targets: attacks & ~ourPieces & (theirPieces | quietTargets),
                     theirPieces: theirPieces,
                     into: &moves)
            }
        }

        let kingSquare = position.kingSquare(us)
        if kingSquare >= 0 {
            emit(from: kingSquare,
                 targets: ChessTables.kingAttacks[kingSquare] & ~ourPieces & (theirPieces | quietTargets),
                 theirPieces: theirPieces,
                 into: &moves)
            if mode == .all {
                generateCastles(position, us: us, kingSquare: kingSquare, into: &moves)
            }
        }

        return moves
    }

    /// Turn a target bitboard into quiet/capture moves from one origin.
    @inline(__always)
    private static func emit(from: Int,
                             targets: ChessBitboard,
                             theirPieces: ChessBitboard,
                             into moves: inout ChessMoveList) {
        var targets = targets
        while targets.isNotEmpty {
            let to = targets.popLsb()
            let flag: ChessMove.Flag = theirPieces.contains(index: to) ? .capture : .quiet
            moves.append(ChessMove(from: from, to: to, flag: flag))
        }
    }

    // MARK: - Pawns

    private static func generatePawnMoves(_ position: ChessPosition,
                                          us: ChessColor,
                                          mode: Mode,
                                          into moves: inout ChessMoveList) {
        let pawns = position.pieces(us, .pawn)
        guard pawns.isNotEmpty else { return }

        let white = us == .white
        let push = us.pawnPush
        let empty = ~position.occupied
        let theirPieces = position.pieces(us.opposite)
        let promotionRank = white ? ChessBitboard.rank8 : ChessBitboard.rank1
        // Squares a *single* push lands on when the pawn started on its
        // home rank — the springboard for the double push.
        let springboard = white ? ChessBitboard.rank(2) : ChessBitboard.rank(5)

        // --- Pushes ---
        let singlePushes = (white ? pawns << 8 : pawns >> 8) & empty
        var pending = singlePushes
        while pending.isNotEmpty {
            let to = pending.popLsb()
            let from = to - push
            if promotionRank.contains(index: to) {
                appendPromotions(from: from, to: to, capture: false, into: &moves)
            } else if mode == .all {
                moves.append(ChessMove(from: from, to: to, flag: .quiet))
            }
        }

        if mode == .all {
            let launched = singlePushes & springboard
            var doublePushes = (white ? launched << 8 : launched >> 8) & empty
            while doublePushes.isNotEmpty {
                let to = doublePushes.popLsb()
                moves.append(ChessMove(from: to - 2 * push, to: to, flag: .doublePawnPush))
            }
        }

        // --- Captures ---
        var from = pawns
        while from.isNotEmpty {
            let square = from.popLsb()
            var targets = ChessTables.pawnAttacks[us.rawValue][square] & theirPieces
            while targets.isNotEmpty {
                let to = targets.popLsb()
                if promotionRank.contains(index: to) {
                    appendPromotions(from: square, to: to, capture: true, into: &moves)
                } else {
                    moves.append(ChessMove(from: square, to: to, flag: .capture))
                }
            }
        }

        // --- En passant ---
        //
        // A pawn of ours can capture onto the target square exactly when
        // it stands on a square that an *enemy* pawn on the target would
        // attack — the same index flip `isAttacked` uses.
        let enPassant = position.enPassantSquare
        if enPassant >= 0 {
            var capturers = ChessTables.pawnAttacks[us.opposite.rawValue][enPassant] & pawns
            while capturers.isNotEmpty {
                moves.append(ChessMove(from: capturers.popLsb(), to: enPassant, flag: .enPassant))
            }
        }
    }

    @inline(__always)
    private static func appendPromotions(from: Int,
                                         to: Int,
                                         capture: Bool,
                                         into moves: inout ChessMoveList) {
        // Queen first: it is the right answer almost always, and putting
        // it at the head of the list means the search's move ordering
        // starts from a good guess even before scoring.
        for kind in [ChessPieceKind.queen, .knight, .rook, .bishop] {
            moves.append(ChessMove(from: from,
                                   to: to,
                                   flag: ChessMove.promotionFlag(kind, capture: capture)))
        }
    }

    // MARK: - Castling

    private static func generateCastles(_ position: ChessPosition,
                                        us: ChessColor,
                                        kingSquare: Int,
                                        into moves: inout ChessMoveList) {
        let them = us.opposite
        let home = us == .white ? ChessSquare.e1.index : ChessSquare.e8.index
        // Rights can outlive the pieces they describe when the position
        // came from a hand-written FEN or the editor, so verify the king
        // is actually home before trusting them.
        guard kingSquare == home else { return }
        guard !position.isAttacked(kingSquare, by: them) else { return }

        let backRank = us == .white ? 0 : 56

        if position.castlingRights.contains(.kingside(us)) {
            let rook = backRank + 7
            let through = backRank + 5   // f1 / f8
            let landing = backRank + 6   // g1 / g8
            if position.piece(at: rook) == ChessPiece(us, .rook),
               position.occupied.contains(index: through) == false,
               position.occupied.contains(index: landing) == false,
               !position.isAttacked(through, by: them),
               !position.isAttacked(landing, by: them) {
                moves.append(ChessMove(from: kingSquare, to: landing, flag: .castleKingside))
            }
        }

        if position.castlingRights.contains(.queenside(us)) {
            let rook = backRank            // a1 / a8
            let knightSquare = backRank + 1 // b1 / b8 — must be empty, but
                                            // may be attacked: the king
                                            // never sets foot on it.
            let through = backRank + 3      // d1 / d8
            let landing = backRank + 2      // c1 / c8
            if position.piece(at: rook) == ChessPiece(us, .rook),
               position.occupied.contains(index: knightSquare) == false,
               position.occupied.contains(index: through) == false,
               position.occupied.contains(index: landing) == false,
               !position.isAttacked(through, by: them),
               !position.isAttacked(landing, by: them) {
                moves.append(ChessMove(from: kingSquare, to: landing, flag: .castleQueenside))
            }
        }
    }
}

// MARK: - Game state

extension ChessPosition {

    /// How the game stands for the side to move.
    public enum Outcome: Hashable, Sendable {
        case ongoing
        case checkmate
        case stalemate
        /// Fifty full moves without a capture or a pawn move.
        case fiftyMoveRule
        /// Neither side has enough material to force mate.
        case insufficientMaterial
    }

    /// Evaluate the position's terminal state.
    ///
    /// Copies the position (it needs move generation), so this is a UI
    /// and test entry point — the search tracks the same facts inline.
    public var outcome: Outcome {
        var scratch = self
        let moves = ChessMoveGenerator.generateLegal(&scratch)
        if moves.isEmpty {
            return isInCheck ? .checkmate : .stalemate
        }
        if hasInsufficientMaterial { return .insufficientMaterial }
        if halfmoveClock >= 100 { return .fiftyMoveRule }
        return .ongoing
    }

    /// The uncontroversial half of the insufficient-material rule: lone
    /// kings, king + minor, and king + bishop each where both bishops
    /// share a square colour.
    ///
    /// Deliberately conservative. King + two knights is *not* included —
    /// mate is unforceable but not impossible, and FIDE only draws it
    /// when no mate exists in the actual position. For a move-suggestion
    /// feature, calling a drawn-ish position "ongoing" is the harmless
    /// error; calling a winnable one "dead drawn" is not.
    public var hasInsufficientMaterial: Bool {
        if pieces(.pawn).isNotEmpty || pieces(.rook).isNotEmpty || pieces(.queen).isNotEmpty {
            return false
        }
        let knights = pieces(.knight).count
        let bishops = pieces(.bishop)

        if knights == 0 && bishops.isEmpty { return true }              // K v K
        if knights + bishops.count == 1 { return true }                 // K+minor v K
        if knights == 0 {
            // Any number of bishops, provided they all stand on one
            // square colour — neither side can ever control the other.
            let light = bishops.squares.filter(\.isLight).count
            return light == 0 || light == bishops.count
        }
        return false
    }
}
