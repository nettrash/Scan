//
//  ChessFEN.swift
//  Scan
//
//  Forsyth–Edwards Notation, plus the legality checks that decide whether
//  a position is safe to hand to the search.
//
//  These two live together because they exist for the same reason: every
//  position this feature sees comes from *outside* the engine — a FEN the
//  user pasted, or 64 squares a neural network guessed at — and neither
//  source can be trusted to describe legal chess. Parsing establishes
//  that the input is structurally a board; validation establishes that it
//  is a board the rules permit. Move generation assumes both.
//

import Foundation

// MARK: - Encoding

extension ChessPosition {

    /// The full six-field FEN for this position.
    public var fen: String {
        var ranks: [String] = []
        // FEN is written from rank 8 down to rank 1 — the opposite of the
        // engine's LERF index order, hence the reversed stride.
        for rank in stride(from: 7, through: 0, by: -1) {
            var text = ""
            var emptyRun = 0
            for file in 0..<8 {
                if let piece = piece(at: rank * 8 + file) {
                    if emptyRun > 0 { text += String(emptyRun); emptyRun = 0 }
                    text.append(piece.fenChar)
                } else {
                    emptyRun += 1
                }
            }
            if emptyRun > 0 { text += String(emptyRun) }
            ranks.append(text)
        }

        let enPassant = enPassantSquare >= 0
            ? ChessSquare(index: enPassantSquare).algebraic
            : "-"

        return [
            ranks.joined(separator: "/"),
            String(sideToMove.fenChar),
            castlingRights.fenField,
            enPassant,
            String(halfmoveClock),
            String(fullmoveNumber),
        ].joined(separator: " ")
    }

    /// The placement field alone — the part a photo can actually tell us.
    ///
    /// The analysis screen shows this when it wants to identify a
    /// position without implying we know whose turn it is.
    public var placementFEN: String {
        String(fen.prefix(while: { $0 != " " }))
    }
}

// MARK: - Decoding

extension ChessPosition {

    /// Parse a FEN string.
    ///
    /// Tolerant in the ways that matter for a scanner app and strict in
    /// the ways that would corrupt the engine:
    ///
    /// * The placement field must describe exactly 8 ranks of exactly 8
    ///   files, with only recognised piece letters. Anything else → nil.
    /// * The other five fields are optional and default to
    ///   "white to move, no rights, no en passant, clocks at 0/1".
    ///   Placement-only FENs are common in puzzle sources and in our own
    ///   `placementFEN`.
    /// * An unparseable clock falls back to its default rather than
    ///   failing the whole string.
    ///
    /// Chess-level legality is **not** checked here — see
    /// `legalityProblems`.
    public init?(fen: String) {
        let fields = fen.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let placementField = fields.first else { return nil }

        let rankFields = placementField
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard rankFields.count == 8 else { return nil }

        var placement = [ChessPiece?](repeating: nil, count: 64)
        for (offset, rankField) in rankFields.enumerated() {
            // rankFields[0] is rank 8, which is LERF rank index 7.
            let rank = 7 - offset
            var file = 0
            for ch in rankField {
                if let skip = ch.wholeNumberValue, (1...8).contains(skip) {
                    file += skip
                } else if let piece = ChessPiece(fenChar: ch) {
                    guard file < 8 else { return nil }
                    placement[rank * 8 + file] = piece
                    file += 1
                } else {
                    return nil
                }
                guard file <= 8 else { return nil }
            }
            guard file == 8 else { return nil }
        }

        let sideToMove: ChessColor = (fields.count > 1 && fields[1].lowercased() == "b")
            ? .black : .white
        let rights = ChessCastlingRights(fenField: fields.count > 2 ? fields[2] : "-")
        let enPassant: ChessSquare? = (fields.count > 3 && fields[3] != "-")
            ? ChessSquare(fields[3]) : nil
        let halfmove = fields.count > 4 ? (Int(fields[4]) ?? 0) : 0
        let fullmove = fields.count > 5 ? (Int(fields[5]) ?? 1) : 1

        self.init(placement: placement,
                  sideToMove: sideToMove,
                  castlingRights: rights,
                  enPassantSquare: enPassant,
                  halfmoveClock: max(0, halfmove),
                  fullmoveNumber: max(1, fullmove))
    }
}

// MARK: - Legality

/// A reason a position cannot be analysed, in words the analysis screen
/// can show verbatim.
public enum ChessLegalityProblem: Hashable, Sendable {
    case missingKing(ChessColor)
    case tooManyKings(ChessColor)
    case tooManyPawns(ChessColor, count: Int)
    case tooManyPieces(ChessColor, count: Int)
    case pawnOnBackRank(ChessSquare)
    case impossiblePromotionCount(ChessColor)
    case opponentInCheck(ChessColor)

    /// User-facing text. Deliberately describes what to *do*, because
    /// every one of these is reachable by a misread square that the user
    /// can fix in the editor.
    public var message: String {
        switch self {
        case .missingKing(let color):
            return "\(color.displayName) has no king — tap an empty square to add one."
        case .tooManyKings(let color):
            return "\(color.displayName) has more than one king — remove the extras."
        case .tooManyPawns(let color, let count):
            return "\(color.displayName) has \(count) pawns; a side can have at most 8."
        case .tooManyPieces(let color, let count):
            return "\(color.displayName) has \(count) pieces; a side can have at most 16."
        case .pawnOnBackRank(let square):
            return "A pawn can't stand on \(square.algebraic) — pawns never occupy rank 1 or 8."
        case .impossiblePromotionCount(let color):
            return "\(color.displayName) has more promoted pieces than missing pawns to explain them."
        case .opponentInCheck(let color):
            return "\(color.displayName) is in check, so it can't be \(color.opposite.displayName)'s turn."
        }
    }
}

extension ChessColor {
    /// Capitalised side name for user-facing strings.
    public var displayName: String { self == .white ? "White" : "Black" }
}

extension ChessPosition {

    /// Everything wrong with this position, chess-wise. Empty means the
    /// engine can search it.
    ///
    /// The checks are the ones a misread board actually trips — a third
    /// king, a ninth pawn, a pawn hallucinated onto rank 8 — plus the
    /// side-to-move check that decides whether "best move for White" and
    /// "best move for Black" are *both* answerable for this board.
    ///
    /// Note what is deliberately **not** checked: whether the position is
    /// reachable from the starting array. That is undecidable in general
    /// and irrelevant here — a photo of a puzzle set up by hand is a
    /// perfectly good thing to analyse.
    public var legalityProblems: [ChessLegalityProblem] {
        var problems: [ChessLegalityProblem] = []

        for color in [ChessColor.white, .black] {
            let kings = pieces(color, .king).count
            if kings == 0 { problems.append(.missingKing(color)) }
            if kings > 1 { problems.append(.tooManyKings(color)) }

            let pawns = pieces(color, .pawn).count
            if pawns > 8 { problems.append(.tooManyPawns(color, count: pawns)) }

            let total = pieces(color).count
            if total > 16 { problems.append(.tooManyPieces(color, count: total)) }

            // Every piece beyond the starting complement has to be a
            // promotion, and every promotion costs a pawn. Extra queens
            // are the usual culprit in a misread — a queen and a bishop
            // look alike from a low angle.
            let extras = max(0, pieces(color, .queen).count - 1)
                + max(0, pieces(color, .rook).count - 2)
                + max(0, pieces(color, .bishop).count - 2)
                + max(0, pieces(color, .knight).count - 2)
            if extras > 8 - pawns {
                problems.append(.impossiblePromotionCount(color))
            }
        }

        let backRanks = ChessBitboard.rank1 | ChessBitboard.rank8
        var strandedPawns = pieces(.pawn) & backRanks
        while strandedPawns.isNotEmpty {
            problems.append(.pawnOnBackRank(ChessSquare(index: strandedPawns.popLsb())))
        }

        // The side that just moved cannot have left its own king in check.
        if opponentIsInCheck {
            problems.append(.opponentInCheck(sideToMove.opposite))
        }

        return problems
    }

    /// True when the engine will accept this position.
    public var isAnalysable: Bool { legalityProblems.isEmpty }
}
