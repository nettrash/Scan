//
//  ChessMove.swift
//  Scan
//
//  A move, packed into 16 bits.
//
//  Layout (the encoding used by most bitboard engines, kept verbatim so
//  the Kotlin port can be a transliteration):
//
//      bits  0...5   from square (0...63)
//      bits  6...11  to square   (0...63)
//      bits 12...15  flags
//
//  Flag values are a small bit-field of their own, which is what makes
//  `isCapture` / `isPromotion` single-instruction tests:
//
//      bit 12 (1) ── promotion kind, low bit   ┐ together: 0=N 1=B 2=R 3=Q
//      bit 13 (2) ── promotion kind, high bit  ┘
//      bit 14 (4) ── capture
//      bit 15 (8) ── promotion
//
//      0  quiet                 8  promote to knight
//      1  double pawn push      9  promote to bishop
//      2  castle kingside      10  promote to rook
//      3  castle queenside     11  promote to queen
//      4  capture              12  capture + promote to knight
//      5  en-passant capture   13  capture + promote to bishop
//                              14  capture + promote to rook
//                              15  capture + promote to queen
//
//  Flags 6 and 7 are unused. Note that flags 1, 2 and 3 are *not*
//  captures despite sitting below bit 14 — the capture bit is only
//  meaningful for values ≥ 4, which is why `isCapture` tests the bit
//  rather than comparing ranges.
//
//  Packing into 16 bits keeps a 256-move buffer at 512 bytes, so move
//  lists live comfortably on the stack and the transposition table can
//  store a best move in a couple of bytes.
//

import Foundation

public struct ChessMove: Hashable, Sendable {

    /// Flag nibble. Raw values are part of the on-wire encoding above.
    public enum Flag: UInt16 {
        case quiet              = 0
        case doublePawnPush     = 1
        case castleKingside     = 2
        case castleQueenside    = 3
        case capture            = 4
        case enPassant          = 5
        case promoteKnight      = 8
        case promoteBishop      = 9
        case promoteRook        = 10
        case promoteQueen       = 11
        case capturePromoteKnight = 12
        case capturePromoteBishop = 13
        case capturePromoteRook   = 14
        case capturePromoteQueen  = 15
    }

    public let rawValue: UInt16

    @inline(__always)
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    @inline(__always)
    public init(from: Int, to: Int, flag: Flag = .quiet) {
        rawValue = UInt16(from) | (UInt16(to) << 6) | (flag.rawValue << 12)
    }

    @inline(__always)
    public init(from: ChessSquare, to: ChessSquare, flag: Flag = .quiet) {
        self.init(from: from.index, to: to.index, flag: flag)
    }

    /// The null move — `a1a1`, which is never legal, so it doubles as
    /// "no move" in the transposition table and in search bookkeeping.
    public static let none = ChessMove(rawValue: 0)

    @inline(__always) public var fromIndex: Int { Int(rawValue & 0x3F) }
    @inline(__always) public var toIndex: Int { Int((rawValue >> 6) & 0x3F) }
    @inline(__always) public var flagBits: UInt16 { (rawValue >> 12) & 0xF }

    @inline(__always) public var from: ChessSquare { ChessSquare(index: fromIndex) }
    @inline(__always) public var to: ChessSquare { ChessSquare(index: toIndex) }
    @inline(__always) public var flag: Flag { Flag(rawValue: flagBits) ?? .quiet }

    @inline(__always) public var isNone: Bool { rawValue == 0 }

    /// True for ordinary captures, en passant, and capture-promotions.
    @inline(__always) public var isCapture: Bool { flagBits & 0b0100 != 0 }

    /// True for all four promotion flags, with or without capture.
    @inline(__always) public var isPromotion: Bool { flagBits & 0b1000 != 0 }

    @inline(__always) public var isEnPassant: Bool { flagBits == Flag.enPassant.rawValue }

    @inline(__always)
    public var isCastle: Bool {
        flagBits == Flag.castleKingside.rawValue || flagBits == Flag.castleQueenside.rawValue
    }

    @inline(__always)
    public var isDoublePawnPush: Bool { flagBits == Flag.doublePawnPush.rawValue }

    /// The piece a promoting pawn becomes, or nil for non-promotions.
    @inline(__always)
    public var promotionKind: ChessPieceKind? {
        guard isPromotion else { return nil }
        // Low two flag bits select N/B/R/Q, which are contiguous in
        // `ChessPieceKind`'s raw values starting at knight = 1.
        return ChessPieceKind(rawValue: Int(flagBits & 0b0011) + 1)
    }

    /// The promotion flag for `kind`, capturing or not. Returns `.quiet`
    /// for kinds a pawn cannot promote to, which callers never pass.
    @inline(__always)
    public static func promotionFlag(_ kind: ChessPieceKind, capture: Bool) -> Flag {
        let base: UInt16
        switch kind {
        case .knight: base = 0
        case .bishop: base = 1
        case .rook:   base = 2
        case .queen:  base = 3
        default:      return .quiet
        }
        return Flag(rawValue: base | 0b1000 | (capture ? 0b0100 : 0))!
    }

    // MARK: - UCI

    /// Long algebraic / UCI form: "e2e4", "e7e8q", "e1g1" for castling.
    ///
    /// Castling is emitted king-from/king-to, not the king-takes-rook
    /// form some engines use, because that is what the UI wants to draw
    /// as an arrow.
    public var uci: String {
        var out = from.algebraic + to.algebraic
        if let kind = promotionKind {
            out.append(Character(kind.fenLetter.lowercased()))
        }
        return out
    }

    /// Parse a UCI move *without* a position to check it against.
    ///
    /// This can recover the squares and the promotion piece, but it
    /// cannot know whether the move is a capture, en passant or castling
    /// — those depend on the position. The result is therefore only
    /// suitable for matching against generated legal moves by
    /// from/to/promotion, which is what `ChessPosition.move(uci:)` does.
    public init?(uci: String) {
        let text = uci.lowercased()
        guard text.count == 4 || text.count == 5 else { return nil }
        let chars = Array(text)
        guard let from = ChessSquare(String(chars[0...1])),
              let to = ChessSquare(String(chars[2...3])) else { return nil }

        var flag = Flag.quiet
        if chars.count == 5 {
            guard let kind = ChessPieceKind(fenLetter: chars[4]),
                  kind != .pawn, kind != .king else { return nil }
            flag = ChessMove.promotionFlag(kind, capture: false)
        }
        self.init(from: from, to: to, flag: flag)
    }
}

extension ChessMove: CustomStringConvertible {
    public var description: String { isNone ? "(none)" : uci }
}

// MARK: - Move list

/// A fixed-capacity, stack-allocated move buffer.
///
/// 256 is comfortably above the most moves any legal position can
/// produce (the known maximum is 218), so generation never has to test
/// for overflow on the hot path — the `assert` catches a generator bug in
/// debug builds and the release build simply drops the extra move rather
/// than trapping in a user's hands mid-analysis.
public struct ChessMoveList {
    public private(set) var count: Int = 0
    private var storage: [ChessMove] = Array(repeating: .none, count: 256)

    public init() {}

    @inline(__always)
    public mutating func append(_ move: ChessMove) {
        assert(count < 256, "move list overflow — generator produced > 256 moves")
        guard count < 256 else { return }
        storage[count] = move
        count += 1
    }

    @inline(__always)
    public subscript(index: Int) -> ChessMove {
        get { storage[index] }
        set { storage[index] = newValue }
    }


    public var isEmpty: Bool { count == 0 }

    /// Copy out as an ordinary array — for tests and UI, not the search.
    public var asArray: [ChessMove] {
        (0..<count).map { storage[$0] }
    }

    /// Swap two entries. Used by the search's selection-sort move picker,
    /// which pulls the best-scoring move to the front one ply at a time
    /// rather than sorting the whole list up front.
    @inline(__always)
    public mutating func swapAt(_ i: Int, _ j: Int) {
        storage.swapAt(i, j)
    }
}
