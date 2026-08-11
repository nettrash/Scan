//
//  ChessTypes.swift
//  Scan
//
//  Core chess value types for the v1.10 board-recognition feature.
//
//  Seeded from the (well-tested) `Chess/ChessTypes.swift` in the
//  game-helper-ios prototype, then reworked for an engine rather than a
//  viewer: squares carry a raw 0...63 index so they can index bitboards
//  and lookup tables directly, and the types are frozen-ish value types
//  with no allocation anywhere on the search path.
//
//  Names are prefixed `Chess…` rather than nested in a namespace enum.
//  Scan is a single module with a flat file layout and generic names
//  like `Piece` / `Square` / `Move` would be collision bait; the prefix
//  also makes the engine trivially greppable against the payload code
//  that dominates the rest of the target.
//
//  ## Square indexing — the one convention everything else assumes
//
//  Squares are **LERF** (Little-Endian Rank-File): index = rank * 8 + file,
//  so a1 = 0, b1 = 1, … h1 = 7, a2 = 8, … h8 = 63.
//
//      8 | 56 57 58 59 60 61 62 63
//      7 | 48 49 50 51 52 53 54 55
//      6 | 40 41 42 43 44 45 46 47
//      5 | 32 33 34 35 36 37 38 39
//      4 | 24 25 26 27 28 29 30 31
//      3 | 16 17 18 19 20 21 22 23
//      2 |  8  9 10 11 12 13 14 15
//      1 |  0  1  2  3  4  5  6  7
//        +------------------------
//           a  b  c  d  e  f  g  h
//
//  This is the mapping that makes bitboard shifts mean what they look
//  like: `bb << 8` is "one rank up (towards rank 8)" and `bb >> 8` is
//  "one rank down". Note that this is the *opposite* vertical order from
//  how FEN is written (FEN starts at rank 8), which is why
//  `ChessPosition`'s FEN code walks ranks downwards. It also matches the
//  prototype's `rank * 8 + file`, so recognised boards map across
//  unchanged.
//

import Foundation

// MARK: - Colour

/// The side to move, or the owner of a piece.
public enum ChessColor: Int, CaseIterable, Sendable, Codable {
    case white = 0
    case black = 1

    @inline(__always)
    public var opposite: ChessColor { self == .white ? .black : .white }

    /// Single-character side identifier as used in FEN ("w" / "b").
    public var fenChar: Character { self == .white ? "w" : "b" }

    /// Direction a pawn of this colour travels, in *square indices*:
    /// +8 for white (up the board), -8 for black.
    @inline(__always)
    public var pawnPush: Int { self == .white ? 8 : -8 }
}

// MARK: - Piece kind

/// One of the six chess piece kinds.
///
/// Raw values are the index used by every `[6]`-sized table in the
/// engine (material values, piece-square tables, per-kind bitboards), so
/// the ordering here is load-bearing — don't reorder.
public enum ChessPieceKind: Int, CaseIterable, Sendable, Codable {
    case pawn   = 0
    case knight = 1
    case bishop = 2
    case rook   = 3
    case queen  = 4
    case king   = 5

    /// FEN letter, uppercase. Lowercase represents black.
    public var fenLetter: Character {
        switch self {
        case .pawn:   return "P"
        case .knight: return "N"
        case .bishop: return "B"
        case .rook:   return "R"
        case .queen:  return "Q"
        case .king:   return "K"
        }
    }

    public init?(fenLetter ch: Character) {
        switch ch {
        case "P", "p": self = .pawn
        case "N", "n": self = .knight
        case "B", "b": self = .bishop
        case "R", "r": self = .rook
        case "Q", "q": self = .queen
        case "K", "k": self = .king
        default: return nil
        }
    }
}

// MARK: - Piece

/// A coloured piece occupying a square.
public struct ChessPiece: Hashable, Sendable, Codable {
    public let color: ChessColor
    public let kind: ChessPieceKind

    public init(_ color: ChessColor, _ kind: ChessPieceKind) {
        self.color = color
        self.kind = kind
    }

    /// Dense 0...11 index (`color * 6 + kind`) for the 12 piece bitboards
    /// and for Zobrist's piece-square table.
    @inline(__always)
    public var index: Int { color.rawValue * 6 + kind.rawValue }

    /// Rebuild a piece from its dense 0...11 index.
    @inline(__always)
    public init(index: Int) {
        self.color = index < 6 ? .white : .black
        self.kind = ChessPieceKind(rawValue: index % 6)!
    }

    /// FEN representation — uppercase white, lowercase black.
    public var fenChar: Character {
        let letter = kind.fenLetter
        return color == .white ? letter : Character(letter.lowercased())
    }

    public init?(fenChar ch: Character) {
        guard let kind = ChessPieceKind(fenLetter: ch) else { return nil }
        self.kind = kind
        self.color = ch.isUppercase ? .white : .black
    }
}

// MARK: - Square

/// A square on the board, stored as a raw 0...63 LERF index.
///
/// See the file header for the index layout. `index` is deliberately an
/// `Int` (not `Int8`): it is used as an array subscript on nearly every
/// line of the engine, and paying the widening conversion once at
/// construction beats paying it a few million times a second.
public struct ChessSquare: Hashable, Sendable, Codable, CustomStringConvertible {
    public let index: Int

    @inline(__always)
    public init(index: Int) {
        assert((0..<64).contains(index), "square index out of range: \(index)")
        self.index = index
    }

    /// - Parameters:
    ///   - file: 0 = a … 7 = h
    ///   - rank: 0 = rank 1 … 7 = rank 8
    @inline(__always)
    public init(file: Int, rank: Int) {
        assert((0...7).contains(file) && (0...7).contains(rank),
               "file/rank out of range: \(file)/\(rank)")
        self.index = rank * 8 + file
    }

    /// Initialise from algebraic notation, e.g. "e4". Case-insensitive on
    /// the file letter. Returns nil for anything that isn't exactly one
    /// file letter followed by one rank digit.
    public init?(_ algebraic: String) {
        guard algebraic.count == 2 else { return nil }
        var iterator = algebraic.makeIterator()
        guard let fileChar = iterator.next(), let rankChar = iterator.next() else { return nil }
        guard let file = "abcdefgh".firstIndex(of: Character(fileChar.lowercased())) else { return nil }
        guard let rank = rankChar.wholeNumberValue, (1...8).contains(rank) else { return nil }
        self.index = (rank - 1) * 8 + "abcdefgh".distance(from: "abcdefgh".startIndex, to: file)
    }

    /// 0 = a … 7 = h
    @inline(__always)
    public var file: Int { index & 7 }

    /// 0 = rank 1 … 7 = rank 8
    @inline(__always)
    public var rank: Int { index >> 3 }

    /// The single-bit bitboard for this square.
    @inline(__always)
    public var bit: ChessBitboard { ChessBitboard(1 << UInt64(index)) }

    /// True when the square is a light square (h1, a8, … are light).
    ///
    /// Matches the prototype's `(file + rank) % 2 == 1` parity, so
    /// recognition code that reasons about light/dark baselines agrees
    /// with the engine about which squares are which.
    @inline(__always)
    public var isLight: Bool { (file + rank) % 2 == 1 }

    public var algebraic: String {
        let files = Array("abcdefgh")
        return "\(files[file])\(rank + 1)"
    }

    public var description: String { algebraic }

    /// All 64 squares, a1 first.
    public static let all: [ChessSquare] = (0..<64).map { ChessSquare(index: $0) }

    // Named squares the engine refers to by name — castling paths, rook
    // corners, and the two king homes.
    public static let a1 = ChessSquare(index: 0)
    public static let b1 = ChessSquare(index: 1)
    public static let c1 = ChessSquare(index: 2)
    public static let d1 = ChessSquare(index: 3)
    public static let e1 = ChessSquare(index: 4)
    public static let f1 = ChessSquare(index: 5)
    public static let g1 = ChessSquare(index: 6)
    public static let h1 = ChessSquare(index: 7)
    public static let a8 = ChessSquare(index: 56)
    public static let b8 = ChessSquare(index: 57)
    public static let c8 = ChessSquare(index: 58)
    public static let d8 = ChessSquare(index: 59)
    public static let e8 = ChessSquare(index: 60)
    public static let f8 = ChessSquare(index: 61)
    public static let g8 = ChessSquare(index: 62)
    public static let h8 = ChessSquare(index: 63)
}

// MARK: - Castling rights

/// The four castling rights as a 4-bit set.
///
/// Bit order matches FEN's "KQkq" so the FEN writer can walk the options
/// in declaration order and produce a canonical string.
public struct ChessCastlingRights: OptionSet, Hashable, Sendable, Codable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let whiteKingside  = ChessCastlingRights(rawValue: 1 << 0)
    public static let whiteQueenside = ChessCastlingRights(rawValue: 1 << 1)
    public static let blackKingside  = ChessCastlingRights(rawValue: 1 << 2)
    public static let blackQueenside = ChessCastlingRights(rawValue: 1 << 3)

    public static let none: ChessCastlingRights = []
    public static let all: ChessCastlingRights = [
        .whiteKingside, .whiteQueenside, .blackKingside, .blackQueenside
    ]

    @inline(__always)
    public static func kingside(_ color: ChessColor) -> ChessCastlingRights {
        color == .white ? .whiteKingside : .blackKingside
    }

    @inline(__always)
    public static func queenside(_ color: ChessColor) -> ChessCastlingRights {
        color == .white ? .whiteQueenside : .blackQueenside
    }

    /// Both rights belonging to one side — cleared wholesale when that
    /// side's king moves.
    @inline(__always)
    public static func both(_ color: ChessColor) -> ChessCastlingRights {
        color == .white ? [.whiteKingside, .whiteQueenside] : [.blackKingside, .blackQueenside]
    }

    /// FEN field: "KQkq", a subset thereof, or "-" when empty.
    public var fenField: String {
        var out = ""
        if contains(.whiteKingside)  { out.append("K") }
        if contains(.whiteQueenside) { out.append("Q") }
        if contains(.blackKingside)  { out.append("k") }
        if contains(.blackQueenside) { out.append("q") }
        return out.isEmpty ? "-" : out
    }

    /// Parse a FEN castling field. "-" (and the empty string) mean no
    /// rights; unrecognised characters are ignored rather than rejected,
    /// because we also feed this parser FENs assembled by the position
    /// editor from user toggles.
    public init(fenField: String) {
        var rights: ChessCastlingRights = []
        for ch in fenField {
            switch ch {
            case "K": rights.insert(.whiteKingside)
            case "Q": rights.insert(.whiteQueenside)
            case "k": rights.insert(.blackKingside)
            case "q": rights.insert(.blackQueenside)
            default: break
            }
        }
        self = rights
    }
}
