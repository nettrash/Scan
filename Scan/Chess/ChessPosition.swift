//
//  ChessPosition.swift
//  Scan
//
//  The board: piece placement, side to move, castling rights, en-passant
//  target, the two clocks, and the incrementally-maintained Zobrist key.
//
//  ## Storage
//
//  Redundant on purpose — twelve piece bitboards *and* a 64-entry mailbox.
//  The bitboards answer "where are all the white knights" in one load
//  (move generation); the mailbox answers "what is standing on e4" in one
//  load (make/unmake, captures, SAN). Keeping both in sync costs a couple
//  of instructions per piece movement and saves a popcount-and-scan on
//  every single one.
//
//  ## Undo is caller-owned
//
//  `make` returns an `Undo` token that the caller hands back to `unmake`.
//  The position deliberately does **not** own a history stack, which keeps
//  it a clean value type: tests can copy it freely, the UI can hold one
//  per screen, and the search can keep its own undo array sized to its
//  own depth. The idiom is always:
//
//      let undo = position.make(move)
//      …
//      position.unmake(move, undo)
//
//  `unmake` restores the Zobrist key wholesale from the token rather than
//  XOR-ing every component back out. Reversing an incremental hash by
//  hand is a classic source of "the transposition table is subtly
//  poisoned" bugs, and the token costs eight bytes we are already paying
//  for.
//
//  ## Validity
//
//  `init?(fen:)` accepts anything *structurally* well-formed, including
//  positions that are illegal chess (no king, nine pawns, a pawn on the
//  back rank). That is deliberate: the position editor has to be able to
//  hold a half-finished board while the user fixes a misread square, and
//  the recogniser's raw output is frequently illegal before the user
//  touches it. Chess-level problems are reported separately by
//  `legalityProblems`, and `ChessEngine` refuses to search a position
//  that has any.
//

import Foundation

public struct ChessPosition: Sendable {

    // MARK: - Storage

    /// One bitboard per (colour, kind), indexed by `ChessPiece.index`.
    private var pieceBB: [ChessBitboard]
    /// Union of each colour's pieces, indexed by `ChessColor.rawValue`.
    private var colorBB: [ChessBitboard]
    /// Union of both colours.
    public private(set) var occupied: ChessBitboard
    /// Mailbox: dense piece index per square, or -1 for empty.
    private var board: [Int8]

    public private(set) var sideToMove: ChessColor
    public private(set) var castlingRights: ChessCastlingRights
    /// En-passant target square index, or -1 when there is none.
    ///
    /// This is the square *behind* the pawn that just double-pushed (the
    /// square a capturing pawn moves **to**), matching FEN. It is stored
    /// exactly as given rather than being cleared when no capture is
    /// actually available — the standard perft positions depend on that
    /// literal reading.
    public private(set) var enPassantSquare: Int
    public private(set) var halfmoveClock: Int
    public private(set) var fullmoveNumber: Int
    public private(set) var key: UInt64

    /// State that `make` destroys and `unmake` needs back.
    public struct Undo: Sendable {
        var capturedPiece: Int8
        var castlingRights: ChessCastlingRights
        var enPassantSquare: Int
        var halfmoveClock: Int
        var key: UInt64
    }

    // MARK: - Construction

    /// An empty board, White to move, no rights.
    public init() {
        pieceBB = [ChessBitboard](repeating: .empty, count: 12)
        colorBB = [ChessBitboard](repeating: .empty, count: 2)
        occupied = .empty
        board = [Int8](repeating: -1, count: 64)
        sideToMove = .white
        castlingRights = .none
        enPassantSquare = -1
        halfmoveClock = 0
        fullmoveNumber = 1
        key = 0
        recomputeKey()
    }

    /// Build a position from a 64-entry placement array, a1 first (LERF —
    /// see `ChessTypes.swift`).
    ///
    /// This is the constructor the recogniser uses: constrained decoding
    /// hands back exactly this shape — one optional piece per square —
    /// and the position editor edits it in place. FEN parsing routes
    /// through here too, so there is one path that establishes the
    /// invariants and computes the key.
    ///
    /// - Parameter placement: must have exactly 64 entries; anything else
    ///   is a programming error and traps.
    public init(placement: [ChessPiece?],
                sideToMove: ChessColor = .white,
                castlingRights: ChessCastlingRights = .none,
                enPassantSquare: ChessSquare? = nil,
                halfmoveClock: Int = 0,
                fullmoveNumber: Int = 1) {
        precondition(placement.count == 64, "placement must describe all 64 squares")
        self.init()
        for square in 0..<64 {
            if let piece = placement[square] { put(piece.index, at: square) }
        }
        self.sideToMove = sideToMove
        self.castlingRights = castlingRights
        self.enPassantSquare = enPassantSquare?.index ?? -1
        self.halfmoveClock = halfmoveClock
        self.fullmoveNumber = fullmoveNumber
        recomputeKey()
    }

    /// The 64-entry placement array, a1 first — the inverse of
    /// `init(placement:…)`, and what the position editor renders from.
    public var placement: [ChessPiece?] {
        (0..<64).map { board[$0] < 0 ? nil : ChessPiece(index: Int(board[$0])) }
    }

    /// The standard starting array.
    public static let standard = ChessPosition(fen: ChessPosition.startFEN)!

    public static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    // MARK: - Piece access

    @inline(__always)
    public func pieces(_ color: ChessColor, _ kind: ChessPieceKind) -> ChessBitboard {
        pieceBB[color.rawValue * 6 + kind.rawValue]
    }

    /// Both colours' pieces of one kind.
    @inline(__always)
    public func pieces(_ kind: ChessPieceKind) -> ChessBitboard {
        pieceBB[kind.rawValue] | pieceBB[6 + kind.rawValue]
    }

    @inline(__always)
    public func pieces(_ color: ChessColor) -> ChessBitboard {
        colorBB[color.rawValue]
    }

    @inline(__always)
    public func piece(at square: Int) -> ChessPiece? {
        let index = board[square]
        return index < 0 ? nil : ChessPiece(index: Int(index))
    }

    @inline(__always)
    public func piece(at square: ChessSquare) -> ChessPiece? {
        piece(at: square.index)
    }

    /// Square index of `color`'s king, or -1 if that side has no king.
    ///
    /// A kingless position is illegal but representable (see the file
    /// header), so this returns -1 rather than trapping. Every caller on
    /// the search path runs after validation and can treat -1 as
    /// unreachable; the UI checks for it.
    @inline(__always)
    public func kingSquare(_ color: ChessColor) -> Int {
        let bb = pieces(color, .king)
        return bb.isEmpty ? -1 : bb.lsbIndex
    }

    // MARK: - Board mutation primitives
    //
    // Each keeps the bitboards, the mailbox and the Zobrist key in step.
    // Nothing else in the file touches `pieceBB` / `colorBB` / `board`
    // directly, so there is exactly one place for a desync bug to live.

    @inline(__always)
    private mutating func put(_ pieceIndex: Int, at square: Int) {
        let bit = ChessBitboard(1 << UInt64(square))
        pieceBB[pieceIndex] |= bit
        colorBB[pieceIndex < 6 ? 0 : 1] |= bit
        occupied |= bit
        board[square] = Int8(pieceIndex)
        key ^= ChessZobrist.piece(index: pieceIndex, square: square)
    }

    @inline(__always)
    private mutating func remove(at square: Int) {
        let pieceIndex = Int(board[square])
        let bit = ChessBitboard(1 << UInt64(square))
        pieceBB[pieceIndex] ^= bit
        colorBB[pieceIndex < 6 ? 0 : 1] ^= bit
        occupied ^= bit
        board[square] = -1
        key ^= ChessZobrist.piece(index: pieceIndex, square: square)
    }

    @inline(__always)
    private mutating func movePiece(from: Int, to: Int) {
        let pieceIndex = Int(board[from])
        let mask = ChessBitboard((1 << UInt64(from)) | (1 << UInt64(to)))
        pieceBB[pieceIndex] ^= mask
        colorBB[pieceIndex < 6 ? 0 : 1] ^= mask
        occupied ^= mask
        board[from] = -1
        board[to] = Int8(pieceIndex)
        key ^= ChessZobrist.piece(index: pieceIndex, square: from)
        key ^= ChessZobrist.piece(index: pieceIndex, square: to)
    }

    /// Place or clear a square wholesale. For the position editor and FEN
    /// parsing — *not* for making moves, which must go through `make` so
    /// that clocks, rights and the key stay coherent.
    public mutating func setPiece(_ piece: ChessPiece?, at square: ChessSquare) {
        if board[square.index] >= 0 { remove(at: square.index) }
        if let piece { put(piece.index, at: square.index) }
    }

    /// Rebuild the key from scratch. Used after bulk edits (FEN parsing,
    /// the editor) where incremental updating would be busywork.
    private mutating func recomputeKey() {
        var fresh: UInt64 = 0
        for square in 0..<64 where board[square] >= 0 {
            fresh ^= ChessZobrist.piece(index: Int(board[square]), square: square)
        }
        if sideToMove == .black { fresh ^= ChessZobrist.sideToMove }
        fresh ^= ChessZobrist.castling(castlingRights)
        if enPassantSquare >= 0 { fresh ^= ChessZobrist.enPassantFile(enPassantSquare & 7) }
        key = fresh
    }

    /// Re-derive the key after direct edits via `setPiece` / the setters
    /// below. The editor calls this once when the user is done, rather
    /// than after every tap.
    public mutating func refreshKey() { recomputeKey() }

    public mutating func setSideToMove(_ color: ChessColor) {
        sideToMove = color
        recomputeKey()
    }

    public mutating func setCastlingRights(_ rights: ChessCastlingRights) {
        castlingRights = rights
        recomputeKey()
    }

    /// - Parameter square: the square a capturing pawn would move *to*,
    ///   or nil to clear.
    public mutating func setEnPassantSquare(_ square: ChessSquare?) {
        enPassantSquare = square?.index ?? -1
        recomputeKey()
    }

    // MARK: - Castling-rights masks

    /// `castlingMask[square]` is AND-ed into the rights whenever a piece
    /// leaves *or* lands on `square`.
    ///
    /// Handling it as a from/to mask pair rather than as explicit
    /// "if the king moved… if a rook moved…" branches means rook
    /// *captures* are covered for free: capturing on h8 clears Black's
    /// kingside right without anyone having to remember that case.
    private static let castlingMask: [ChessCastlingRights] = {
        var mask = [ChessCastlingRights](repeating: .all, count: 64)
        mask[ChessSquare.a1.index].remove(.whiteQueenside)
        mask[ChessSquare.h1.index].remove(.whiteKingside)
        mask[ChessSquare.e1.index].subtract([.whiteKingside, .whiteQueenside])
        mask[ChessSquare.a8.index].remove(.blackQueenside)
        mask[ChessSquare.h8.index].remove(.blackKingside)
        mask[ChessSquare.e8.index].subtract([.blackKingside, .blackQueenside])
        return mask
    }()

    // MARK: - Make / unmake

    @discardableResult
    public mutating func make(_ move: ChessMove) -> Undo {
        let from = move.fromIndex
        let to = move.toIndex
        let mover = sideToMove

        var undo = Undo(capturedPiece: -1,
                        castlingRights: castlingRights,
                        enPassantSquare: enPassantSquare,
                        halfmoveClock: halfmoveClock,
                        key: key)

        // The old en-passant key leaves as soon as the move is played,
        // whatever the move is.
        if enPassantSquare >= 0 { key ^= ChessZobrist.enPassantFile(enPassantSquare & 7) }

        halfmoveClock += 1

        if move.isEnPassant {
            // The captured pawn is not on `to` — it is one push behind it.
            let capturedSquare = to - mover.pawnPush
            undo.capturedPiece = board[capturedSquare]
            remove(at: capturedSquare)
            halfmoveClock = 0
        } else if move.isCapture {
            undo.capturedPiece = board[to]
            remove(at: to)
            halfmoveClock = 0
        }

        let movingKind = ChessPiece(index: Int(board[from])).kind
        movePiece(from: from, to: to)
        if movingKind == .pawn { halfmoveClock = 0 }

        if let promotion = move.promotionKind {
            remove(at: to)
            put(ChessPiece(mover, promotion).index, at: to)
        }

        if move.isCastle {
            let (rookFrom, rookTo) = ChessPosition.rookCastleSquares(kingTo: to)
            movePiece(from: rookFrom, to: rookTo)
        }

        key ^= ChessZobrist.castling(castlingRights)
        castlingRights.formIntersection(ChessPosition.castlingMask[from])
        castlingRights.formIntersection(ChessPosition.castlingMask[to])
        key ^= ChessZobrist.castling(castlingRights)

        enPassantSquare = move.isDoublePawnPush ? from + mover.pawnPush : -1
        if enPassantSquare >= 0 { key ^= ChessZobrist.enPassantFile(enPassantSquare & 7) }

        if mover == .black { fullmoveNumber += 1 }
        sideToMove = mover.opposite
        key ^= ChessZobrist.sideToMove

        return undo
    }

    public mutating func unmake(_ move: ChessMove, _ undo: Undo) {
        let from = move.fromIndex
        let to = move.toIndex

        sideToMove = sideToMove.opposite
        let mover = sideToMove
        if mover == .black { fullmoveNumber -= 1 }

        // Turn the promoted piece back into the pawn that will walk home.
        if move.isPromotion {
            remove(at: to)
            put(ChessPiece(mover, .pawn).index, at: to)
        }

        if move.isCastle {
            let (rookFrom, rookTo) = ChessPosition.rookCastleSquares(kingTo: to)
            movePiece(from: rookTo, to: rookFrom)
        }

        movePiece(from: to, to: from)

        if move.isEnPassant {
            put(Int(undo.capturedPiece), at: to - mover.pawnPush)
        } else if undo.capturedPiece >= 0 {
            put(Int(undo.capturedPiece), at: to)
        }

        castlingRights = undo.castlingRights
        enPassantSquare = undo.enPassantSquare
        halfmoveClock = undo.halfmoveClock
        // Restored, not un-XOR-ed — see the file header.
        key = undo.key
    }

    /// Play a "null move": hand the turn over without touching a piece.
    ///
    /// Used by the search's null-move pruning. Clears the en-passant
    /// target (the opponent cannot capture en passant on a move that
    /// never happened) and leaves the clocks alone.
    public mutating func makeNull() -> Undo {
        let undo = Undo(capturedPiece: -1,
                        castlingRights: castlingRights,
                        enPassantSquare: enPassantSquare,
                        halfmoveClock: halfmoveClock,
                        key: key)
        if enPassantSquare >= 0 { key ^= ChessZobrist.enPassantFile(enPassantSquare & 7) }
        enPassantSquare = -1
        if sideToMove == .black { fullmoveNumber += 1 }
        sideToMove = sideToMove.opposite
        key ^= ChessZobrist.sideToMove
        return undo
    }

    public mutating func unmakeNull(_ undo: Undo) {
        if sideToMove == .white { fullmoveNumber -= 1 }
        sideToMove = sideToMove.opposite
        enPassantSquare = undo.enPassantSquare
        key = undo.key
    }

    /// Rook origin and destination for a castling move, keyed off where
    /// the *king* lands. The four cases are the only legal ones.
    @inline(__always)
    private static func rookCastleSquares(kingTo: Int) -> (from: Int, to: Int) {
        switch kingTo {
        case ChessSquare.g1.index: return (ChessSquare.h1.index, ChessSquare.f1.index)
        case ChessSquare.c1.index: return (ChessSquare.a1.index, ChessSquare.d1.index)
        case ChessSquare.g8.index: return (ChessSquare.h8.index, ChessSquare.f8.index)
        default:                   return (ChessSquare.a8.index, ChessSquare.d8.index)
        }
    }

    // MARK: - Attacks

    /// Every piece of either colour attacking `square`, given `occupancy`.
    ///
    /// Taking occupancy as a parameter rather than reading `occupied` is
    /// what lets the king-safety check remove the king from the board
    /// first — otherwise a king "blocks" the very ray that is checking it
    /// and stepping backwards along that ray looks safe.
    public func attackersTo(_ square: Int, occupancy: ChessBitboard) -> ChessBitboard {
        var attackers = ChessBitboard.empty
        attackers |= ChessTables.pawnAttacks[ChessColor.white.rawValue][square] & pieces(.black, .pawn)
        attackers |= ChessTables.pawnAttacks[ChessColor.black.rawValue][square] & pieces(.white, .pawn)
        attackers |= ChessTables.knightAttacks[square] & pieces(.knight)
        attackers |= ChessTables.kingAttacks[square] & pieces(.king)
        attackers |= ChessTables.bishopAttacks(square, occupancy) & (pieces(.bishop) | pieces(.queen))
        attackers |= ChessTables.rookAttacks(square, occupancy) & (pieces(.rook) | pieces(.queen))
        return attackers
    }

    /// Is `square` attacked by any piece of `color`?
    ///
    /// Short-circuits kind by kind rather than building the full
    /// `attackersTo` set, because the overwhelmingly common caller is
    /// "am I in check", which usually answers no after the first two
    /// tests.
    public func isAttacked(_ square: Int, by color: ChessColor, occupancy: ChessBitboard) -> Bool {
        // A pawn of `color` attacks `square` exactly when it stands on a
        // square that a pawn of the *opposite* colour on `square` would
        // attack — hence the flipped index.
        if (ChessTables.pawnAttacks[color.opposite.rawValue][square] & pieces(color, .pawn)).isNotEmpty {
            return true
        }
        if (ChessTables.knightAttacks[square] & pieces(color, .knight)).isNotEmpty { return true }
        if (ChessTables.kingAttacks[square] & pieces(color, .king)).isNotEmpty { return true }

        let bishopsQueens = pieces(color, .bishop) | pieces(color, .queen)
        if (ChessTables.bishopAttacks(square, occupancy) & bishopsQueens).isNotEmpty { return true }

        let rooksQueens = pieces(color, .rook) | pieces(color, .queen)
        if (ChessTables.rookAttacks(square, occupancy) & rooksQueens).isNotEmpty { return true }

        return false
    }

    @inline(__always)
    public func isAttacked(_ square: Int, by color: ChessColor) -> Bool {
        isAttacked(square, by: color, occupancy: occupied)
    }

    /// Is `color`'s king currently in check? False when that side has no
    /// king at all (an illegal position the editor may transiently hold).
    public func isInCheck(_ color: ChessColor) -> Bool {
        let king = kingSquare(color)
        guard king >= 0 else { return false }
        return isAttacked(king, by: color.opposite)
    }

    /// Is the side to move in check?
    @inline(__always)
    public var isInCheck: Bool { isInCheck(sideToMove) }

    /// True when the position is one the side *not* to move could never
    /// have left behind: their king is standing in check on our turn.
    ///
    /// A recognised photo has no move history, so the user picks who is
    /// to move — and for most positions only one choice is legal. This is
    /// the test behind the analysis screen's per-side "not a legal
    /// position with this side to move" message.
    public var opponentIsInCheck: Bool { isInCheck(sideToMove.opposite) }
}
