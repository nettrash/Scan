//
//  ChessEvaluation.swift
//  Scan
//
//  Static evaluation: how good is this position, in centipawns, for the
//  side to move?
//
//  ## Scale and sign
//
//  One pawn = 100. The returned score is **always from the perspective of
//  the side to move** (negamax convention) — a position where the mover
//  is a rook up scores around +500 whether the mover is White or Black.
//  The UI converts to White's perspective for display, because "+2.4" is
//  conventionally read as "White is better".
//
//  ## Tapering
//
//  A king belongs behind a pawn wall in the middlegame and in the centre
//  in the endgame; a pawn on the seventh is worth far more when the
//  queens are gone. So the king and pawn tables come in two versions and
//  the score interpolates between them by *game phase*, computed from the
//  remaining non-pawn material. Without this the engine walks its king
//  into the open at move 15, or refuses to activate it at move 60 — both
//  of which look obviously wrong to a user reading a suggestion.
//
//  ## What is deliberately missing
//
//  No king-attack scoring, no piece-coordination terms, no endgame
//  tablebase knowledge. This eval is aimed at "suggest a good move to a
//  club player", not at competing with anything. The search depth does
//  most of the tactical work; the eval only has to rank quiet positions
//  sensibly. Each term below is one an engine can be *wrong* about
//  cheaply — adding more would mean tuning them against each other, and
//  untuned terms make an engine worse, not better.
//
//  Piece values and the piece-square tables follow Tomasz Michniewski's
//  "Simplified Evaluation Function", the standard published starting
//  point for exactly this kind of engine.
//

import Foundation

public enum ChessEvaluation {

    // MARK: - Material

    /// Centipawn value per kind, indexed by `ChessPieceKind.rawValue`.
    ///
    /// The king's value is zero, not a huge number: kings are never
    /// captured, legality guarantees both are on the board, and giving it
    /// a value would only add a constant to every score.
    public static let pieceValue: [Int] = [100, 320, 330, 500, 900, 0]

    /// Material counted for *move ordering and pruning* decisions, where
    /// a king does need a finite large value (MVV-LVA sorts by victim).
    static let captureValue: [Int] = [100, 320, 330, 500, 900, 20_000]

    // MARK: - Game phase

    /// Phase weight per kind — how much each piece keeps the game in the
    /// middlegame. Pawns and kings contribute nothing; they are on the
    /// board in every phase.
    private static let phaseWeight: [Int] = [0, 1, 1, 2, 4, 0]

    /// Phase at the starting array: 4 knights + 4 bishops + 4 rooks×2 +
    /// 2 queens×4 = 24.
    private static let maximumPhase = 24

    /// 24 (full middlegame) down to 0 (bare kings and pawns).
    static func phase(of position: ChessPosition) -> Int {
        var total = 0
        for kind in [ChessPieceKind.knight, .bishop, .rook, .queen] {
            total += position.pieces(kind).count * phaseWeight[kind.rawValue]
        }
        return min(total, maximumPhase)
    }

    // MARK: - Piece-square tables
    //
    // Written rank 8 first, so each table reads as a board seen from
    // White's side. `tableIndex` flips that into the engine's LERF
    // indexing, and mirrors for Black.

    /// Map a LERF square to an index into the tables below.
    ///
    /// White flips the rank (`square ^ 56`) because the tables are written
    /// with rank 8 at the top; Black reads them directly, which mirrors
    /// them vertically — exactly the symmetry the tables assume.
    @inline(__always)
    private static func tableIndex(_ square: Int, _ color: ChessColor) -> Int {
        color == .white ? square ^ 56 : square
    }

    private static let pawnTable: [Int] = [
          0,  0,  0,  0,  0,  0,  0,  0,
         50, 50, 50, 50, 50, 50, 50, 50,
         10, 10, 20, 30, 30, 20, 10, 10,
          5,  5, 10, 25, 25, 10,  5,  5,
          0,  0,  0, 20, 20,  0,  0,  0,
          5, -5,-10,  0,  0,-10, -5,  5,
          5, 10, 10,-20,-20, 10, 10,  5,
          0,  0,  0,  0,  0,  0,  0,  0,
    ]

    /// In the endgame a pawn's only real virtue is how close it is to
    /// promoting, so the file-based shaping above gives way to a pure
    /// rank gradient.
    private static let pawnEndgameTable: [Int] = [
          0,  0,  0,  0,  0,  0,  0,  0,
         90, 90, 90, 90, 90, 90, 90, 90,
         55, 55, 55, 55, 55, 55, 55, 55,
         33, 33, 33, 33, 33, 33, 33, 33,
         20, 20, 20, 20, 20, 20, 20, 20,
         12, 12, 12, 12, 12, 12, 12, 12,
          8,  8,  8,  8,  8,  8,  8,  8,
          0,  0,  0,  0,  0,  0,  0,  0,
    ]

    private static let knightTable: [Int] = [
        -50,-40,-30,-30,-30,-30,-40,-50,
        -40,-20,  0,  0,  0,  0,-20,-40,
        -30,  0, 10, 15, 15, 10,  0,-30,
        -30,  5, 15, 20, 20, 15,  5,-30,
        -30,  0, 15, 20, 20, 15,  0,-30,
        -30,  5, 10, 15, 15, 10,  5,-30,
        -40,-20,  0,  5,  5,  0,-20,-40,
        -50,-40,-30,-30,-30,-30,-40,-50,
    ]

    private static let bishopTable: [Int] = [
        -20,-10,-10,-10,-10,-10,-10,-20,
        -10,  0,  0,  0,  0,  0,  0,-10,
        -10,  0,  5, 10, 10,  5,  0,-10,
        -10,  5,  5, 10, 10,  5,  5,-10,
        -10,  0, 10, 10, 10, 10,  0,-10,
        -10, 10, 10, 10, 10, 10, 10,-10,
        -10,  5,  0,  0,  0,  0,  5,-10,
        -20,-10,-10,-10,-10,-10,-10,-20,
    ]

    private static let rookTable: [Int] = [
          0,  0,  0,  0,  0,  0,  0,  0,
          5, 10, 10, 10, 10, 10, 10,  5,
         -5,  0,  0,  0,  0,  0,  0, -5,
         -5,  0,  0,  0,  0,  0,  0, -5,
         -5,  0,  0,  0,  0,  0,  0, -5,
         -5,  0,  0,  0,  0,  0,  0, -5,
         -5,  0,  0,  0,  0,  0,  0, -5,
          0,  0,  0,  5,  5,  0,  0,  0,
    ]

    private static let queenTable: [Int] = [
        -20,-10,-10, -5, -5,-10,-10,-20,
        -10,  0,  0,  0,  0,  0,  0,-10,
        -10,  0,  5,  5,  5,  5,  0,-10,
         -5,  0,  5,  5,  5,  5,  0, -5,
          0,  0,  5,  5,  5,  5,  0, -5,
        -10,  5,  5,  5,  5,  5,  0,-10,
        -10,  0,  5,  0,  0,  0,  0,-10,
        -20,-10,-10, -5, -5,-10,-10,-20,
    ]

    /// Middlegame king: stay home, behind the pawns, preferably castled.
    private static let kingTable: [Int] = [
        -30,-40,-40,-50,-50,-40,-40,-30,
        -30,-40,-40,-50,-50,-40,-40,-30,
        -30,-40,-40,-50,-50,-40,-40,-30,
        -30,-40,-40,-50,-50,-40,-40,-30,
        -20,-30,-30,-40,-40,-30,-30,-20,
        -10,-20,-20,-20,-20,-20,-20,-10,
         20, 20,  0,  0,  0,  0, 20, 20,
         20, 30, 10,  0,  0, 10, 30, 20,
    ]

    /// Endgame king: march to the centre. The sign flip against the
    /// middlegame table is the single most valuable thing tapering buys.
    private static let kingEndgameTable: [Int] = [
        -50,-40,-30,-20,-20,-30,-40,-50,
        -30,-20,-10,  0,  0,-10,-20,-30,
        -30,-10, 20, 30, 30, 20,-10,-30,
        -30,-10, 30, 40, 40, 30,-10,-30,
        -30,-10, 30, 40, 40, 30,-10,-30,
        -30,-10, 20, 30, 30, 20,-10,-30,
        -30,-30,  0,  0,  0,  0,-30,-30,
        -50,-30,-30,-30,-30,-30,-30,-50,
    ]

    private static let middlegameTables: [[Int]] =
        [pawnTable, knightTable, bishopTable, rookTable, queenTable, kingTable]
    private static let endgameTables: [[Int]] =
        [pawnEndgameTable, knightTable, bishopTable, rookTable, queenTable, kingEndgameTable]

    // MARK: - Bonuses

    private static let bishopPairBonus = 30
    private static let rookOpenFileBonus = 20
    private static let rookSemiOpenFileBonus = 10
    private static let doubledPawnPenalty = -12
    private static let isolatedPawnPenalty = -18
    /// Indexed by how far the pawn has advanced (its rank from its own
    /// side's view). A passer on the seventh is nearly a queen.
    private static let passedPawnBonus = [0, 5, 15, 30, 55, 90, 140, 0]
    private static let mobilityWeight = 2
    /// Per missing pawn in front of a castled king, scaled by phase.
    private static let kingShieldPenalty = -14

    // MARK: - Evaluate

    /// Static evaluation in centipawns, from the side to move's view.
    public static func evaluate(_ position: ChessPosition) -> Int {
        let phaseNow = phase(of: position)
        let white = score(position, for: .white, phase: phaseNow)
        let black = score(position, for: .black, phase: phaseNow)
        let whiteRelative = white - black
        return position.sideToMove == .white ? whiteRelative : -whiteRelative
    }

    /// One side's total, always positive-is-good-for-that-side.
    private static func score(_ position: ChessPosition,
                              for color: ChessColor,
                              phase phaseNow: Int) -> Int {
        var middlegame = 0
        var endgame = 0

        let ourPawns = position.pieces(color, .pawn)
        let theirPawns = position.pieces(color.opposite, .pawn)
        let occupancy = position.occupied

        for kind in ChessPieceKind.allCases {
            var bb = position.pieces(color, kind)
            let value = pieceValue[kind.rawValue]
            let middlegameTable = middlegameTables[kind.rawValue]
            let endgameTable = endgameTables[kind.rawValue]

            while bb.isNotEmpty {
                let square = bb.popLsb()
                let index = tableIndex(square, color)
                middlegame += value + middlegameTable[index]
                endgame += value + endgameTable[index]

                switch kind {
                case .pawn:
                    let bonus = pawnStructure(square: square,
                                              color: color,
                                              ourPawns: ourPawns,
                                              theirPawns: theirPawns)
                    middlegame += bonus
                    endgame += bonus

                case .knight, .bishop, .rook, .queen:
                    // Mobility: how many squares this piece can reach.
                    // Cheap, and it captures "my bishop is buried behind
                    // my own pawns" better than any static table can.
                    let attacks = kind == .knight
                        ? ChessTables.knightAttacks[square]
                        : ChessTables.sliderAttacks(kind, square, occupancy)
                    let moves = (attacks & ~position.pieces(color)).count * mobilityWeight
                    middlegame += moves
                    endgame += moves

                    if kind == .rook {
                        let file = ChessBitboard.file(square & 7)
                        if (ourPawns & file).isEmpty {
                            let bonus = (theirPawns & file).isEmpty
                                ? rookOpenFileBonus : rookSemiOpenFileBonus
                            middlegame += bonus
                            endgame += bonus
                        }
                    }

                case .king:
                    // Pawn shield — only a middlegame concern, which the
                    // taper handles by not adding it to `endgame`.
                    middlegame += kingShield(square: square, color: color, ourPawns: ourPawns)
                }
            }
        }

        if position.pieces(color, .bishop).count >= 2 {
            middlegame += bishopPairBonus
            endgame += bishopPairBonus
        }

        // Interpolate. `phaseNow` is 24 at the start and 0 with bare
        // kings, so this weights the middlegame score by how much
        // material is still on.
        return (middlegame * phaseNow + endgame * (maximumPhase - phaseNow)) / maximumPhase
    }

    // MARK: - Pawn structure

    private static func pawnStructure(square: Int,
                                      color: ChessColor,
                                      ourPawns: ChessBitboard,
                                      theirPawns: ChessBitboard) -> Int {
        var total = 0
        let file = square & 7
        let rank = square >> 3
        let fileMask = ChessBitboard.file(file)

        // Doubled: another friendly pawn on the same file. Counted once
        // per pawn, so a doubled pair is penalised twice — intentionally.
        if (ourPawns & fileMask).count > 1 { total += doubledPawnPenalty }

        // Isolated: no friendly pawn on either adjacent file.
        var neighbours = ChessBitboard.empty
        if file > 0 { neighbours |= ChessBitboard.file(file - 1) }
        if file < 7 { neighbours |= ChessBitboard.file(file + 1) }
        if (ourPawns & neighbours).isEmpty { total += isolatedPawnPenalty }

        // Passed: no enemy pawn ahead on this file or the two beside it.
        let ahead = squaresAhead(rank: rank, color: color)
        if (theirPawns & (fileMask | neighbours) & ahead).isEmpty {
            let advanced = color == .white ? rank : 7 - rank
            total += passedPawnBonus[advanced]
        }

        return total
    }

    /// Every square strictly in front of `rank` from `color`'s point of
    /// view — the region a passed pawn needs clear of enemy pawns.
    @inline(__always)
    private static func squaresAhead(rank: Int, color: ChessColor) -> ChessBitboard {
        if color == .white {
            guard rank < 7 else { return .empty }
            // All ranks above `rank`.
            return ChessBitboard(~0 << UInt64((rank + 1) * 8))
        } else {
            guard rank > 0 else { return .empty }
            // All ranks below `rank`.
            return ChessBitboard(~0 >> UInt64((8 - rank) * 8))
        }
    }

    /// Penalise missing pawns on the three files in front of a king that
    /// has gone to a corner. A king in the centre is already punished by
    /// the middlegame table, so this only looks at castled positions.
    private static func kingShield(square: Int, color: ChessColor, ourPawns: ChessBitboard) -> Int {
        let file = square & 7
        // Only kings that have actually tucked away get a shield term.
        guard file <= 2 || file >= 5 else { return 0 }

        let rank = square >> 3
        let shieldRank = color == .white ? rank + 1 : rank - 1
        guard (0...7).contains(shieldRank) else { return 0 }

        var missing = 0
        for shieldFile in max(0, file - 1)...min(7, file + 1) {
            let mask = ChessBitboard.file(shieldFile) & ChessBitboard.rank(shieldRank)
            if (ourPawns & mask).isEmpty { missing += 1 }
        }
        return missing * kingShieldPenalty
    }
}
