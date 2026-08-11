//
//  ChessBitboard.swift
//  Scan
//
//  64-bit board sets and the attack tables the move generator runs on.
//
//  ## Why classical ray attacks and not magic bitboards
//
//  Sliding-piece attacks here use the **classical** method: a precomputed
//  ray per (direction, square), masked against the occupancy, then the
//  first blocker's own ray XOR-ed back off. That is a handful of ops per
//  direction and four directions per slider — perhaps 2-3× slower than
//  magic bitboards.
//
//  We take that trade deliberately:
//
//  * Magics need a magic-number search (or a big table of constants
//    pasted in), and a wrong constant produces attacks that are correct
//    for *most* occupancies. That failure mode is exactly the one perft
//    catches late and painfully.
//  * The whole engine has to be written twice — Swift here, Kotlin in
//    Scan.Android — and the two must agree move for move. Classical rays
//    port across with no reinterpretation; PEXT/magics do not.
//  * At the 1-3 s/move budget this feature actually uses, move generation
//    is not the bottleneck; move ordering and pruning are.
//
//  If profiling later says otherwise, `ChessTables.bishopAttacks` /
//  `rookAttacks` are the only two functions that would change.
//
//  Square indexing is LERF — see the header of `ChessTypes.swift`.
//

import Foundation

// MARK: - Bitboard

/// A set of squares, one bit per square, indexed LERF (bit 0 = a1).
public struct ChessBitboard: Equatable, Hashable, Sendable {
    public var rawValue: UInt64

    @inline(__always) public init(_ rawValue: UInt64) { self.rawValue = rawValue }
    @inline(__always) public init() { self.rawValue = 0 }

    public static let empty = ChessBitboard(0)
    public static let full  = ChessBitboard(~0)

    @inline(__always) public var isEmpty: Bool { rawValue == 0 }
    @inline(__always) public var isNotEmpty: Bool { rawValue != 0 }

    /// Number of squares in the set.
    @inline(__always) public var count: Int { rawValue.nonzeroBitCount }

    /// Index of the least-significant set bit. Undefined (63) when empty —
    /// callers must check `isEmpty` first.
    @inline(__always) public var lsbIndex: Int { rawValue.trailingZeroBitCount }

    /// Index of the most-significant set bit. Undefined when empty.
    @inline(__always) public var msbIndex: Int { 63 - rawValue.leadingZeroBitCount }

    /// Remove and return the least-significant set square index.
    ///
    /// The canonical iteration idiom throughout the engine:
    ///
    ///     var bb = position.pieces(.white, .knight)
    ///     while bb.isNotEmpty {
    ///         let from = bb.popLsb()
    ///         …
    ///     }
    @inline(__always)
    public mutating func popLsb() -> Int {
        let index = rawValue.trailingZeroBitCount
        rawValue &= rawValue &- 1
        return index
    }

    @inline(__always)
    public func contains(_ square: ChessSquare) -> Bool {
        rawValue & (1 << UInt64(square.index)) != 0
    }

    @inline(__always)
    public func contains(index: Int) -> Bool {
        rawValue & (1 << UInt64(index)) != 0
    }

    @inline(__always)
    public mutating func set(_ index: Int) {
        rawValue |= (1 << UInt64(index))
    }

    @inline(__always)
    public mutating func clear(_ index: Int) {
        rawValue &= ~(1 << UInt64(index))
    }


    /// Every square in the set, a1-first. Allocates — for debugging,
    /// tests and UI only, never the search path (use `popLsb`).
    public var squares: [ChessSquare] {
        var out: [ChessSquare] = []
        out.reserveCapacity(count)
        var bb = self
        while bb.isNotEmpty { out.append(ChessSquare(index: bb.popLsb())) }
        return out
    }

    // Set algebra.
    @inline(__always) public static func & (l: Self, r: Self) -> Self { Self(l.rawValue & r.rawValue) }
    @inline(__always) public static func | (l: Self, r: Self) -> Self { Self(l.rawValue | r.rawValue) }
    @inline(__always) public static func ^ (l: Self, r: Self) -> Self { Self(l.rawValue ^ r.rawValue) }
    @inline(__always) public static prefix func ~ (b: Self) -> Self { Self(~b.rawValue) }
    @inline(__always) public static func &= (l: inout Self, r: Self) { l.rawValue &= r.rawValue }
    @inline(__always) public static func |= (l: inout Self, r: Self) { l.rawValue |= r.rawValue }
    @inline(__always) public static func ^= (l: inout Self, r: Self) { l.rawValue ^= r.rawValue }

    // Whole-board shifts. Safe only when the caller has masked off the
    // wrapping file — see `ChessBitboard.notFileA` / `.notFileH`.
    @inline(__always) public static func << (b: Self, n: Int) -> Self { Self(b.rawValue << UInt64(n)) }
    @inline(__always) public static func >> (b: Self, n: Int) -> Self { Self(b.rawValue >> UInt64(n)) }

    // Common masks.
    public static let fileA = ChessBitboard(0x0101_0101_0101_0101)
    public static let fileH = ChessBitboard(0x8080_8080_8080_8080)
    public static let notFileA = ChessBitboard(~0x0101_0101_0101_0101)
    public static let notFileH = ChessBitboard(~0x8080_8080_8080_8080)
    public static let rank1 = ChessBitboard(0x0000_0000_0000_00FF)
    public static let rank8 = ChessBitboard(0xFF00_0000_0000_0000)

    /// Mask of one file, 0 = a … 7 = h.
    @inline(__always)
    public static func file(_ index: Int) -> ChessBitboard {
        ChessBitboard(0x0101_0101_0101_0101 << UInt64(index))
    }

    /// Mask of one rank, 0 = rank 1 … 7 = rank 8.
    @inline(__always)
    public static func rank(_ index: Int) -> ChessBitboard {
        ChessBitboard(0xFF << UInt64(index * 8))
    }

}

// MARK: - Attack tables

/// Precomputed attack tables. All `static let`, so each is built once on
/// first touch (Swift makes that thread-safe) and then read-only forever.
public enum ChessTables {

    /// The eight ray directions, as (file delta, rank delta).
    ///
    /// Split into positive (index grows) and negative (index shrinks)
    /// halves because the blocker scan differs: positive rays take the
    /// *least*-significant blocker, negative rays the *most*-significant.
    private static let directions: [(df: Int, dr: Int)] = [
        (0, 1),   // 0 N  (+8)
        (1, 1),   // 1 NE (+9)
        (1, 0),   // 2 E  (+1)
        (1, -1),  // 3 SE (-7)
        (0, -1),  // 4 S  (-8)
        (-1, -1), // 5 SW (-9)
        (-1, 0),  // 6 W  (-1)
        (-1, 1),  // 7 NW (+7)
    ]

    private static let north = 0, northEast = 1, east = 2, southEast = 3
    private static let south = 4, southWest = 5, west = 6, northWest = 7

    /// `rays[direction][square]` — every square from `square` outward in
    /// `direction`, exclusive of `square` itself, ignoring occupancy.
    ///
    /// Built by walking file/rank rather than by shifting indices, which
    /// is what makes edge wraparound structurally impossible instead of
    /// something a mask has to catch.
    private static let rays: [[ChessBitboard]] = {
        var table = [[ChessBitboard]](repeating: [ChessBitboard](repeating: .empty, count: 64),
                                      count: 8)
        for direction in 0..<8 {
            let (df, dr) = directions[direction]
            for square in 0..<64 {
                var bb = ChessBitboard.empty
                var file = (square & 7) + df
                var rank = (square >> 3) + dr
                while (0...7).contains(file) && (0...7).contains(rank) {
                    bb.set(rank * 8 + file)
                    file += df
                    rank += dr
                }
                table[direction][square] = bb
            }
        }
        return table
    }()

    /// Ray attacks in a direction whose index *increases* (N, NE, E, NW):
    /// the nearest blocker is the least-significant one.
    @inline(__always)
    private static func positiveRay(_ direction: Int, _ square: Int, _ occupancy: ChessBitboard) -> ChessBitboard {
        let ray = rays[direction][square]
        let blockers = ray & occupancy
        guard blockers.isNotEmpty else { return ray }
        return ray ^ rays[direction][blockers.lsbIndex]
    }

    /// Ray attacks in a direction whose index *decreases* (S, SW, W, SE):
    /// the nearest blocker is the most-significant one.
    @inline(__always)
    private static func negativeRay(_ direction: Int, _ square: Int, _ occupancy: ChessBitboard) -> ChessBitboard {
        let ray = rays[direction][square]
        let blockers = ray & occupancy
        guard blockers.isNotEmpty else { return ray }
        return ray ^ rays[direction][blockers.msbIndex]
    }

    /// Rook attacks from `square` given `occupancy`.
    ///
    /// Includes the blocking squares themselves — the caller masks off
    /// its own pieces. That convention is shared by every `…Attacks`
    /// function here and is what lets `attackersTo` treat all kinds
    /// uniformly.
    @inline(__always)
    public static func rookAttacks(_ square: Int, _ occupancy: ChessBitboard) -> ChessBitboard {
        positiveRay(north, square, occupancy)
            | positiveRay(east, square, occupancy)
            | negativeRay(south, square, occupancy)
            | negativeRay(west, square, occupancy)
    }

    /// Bishop attacks from `square` given `occupancy`.
    @inline(__always)
    public static func bishopAttacks(_ square: Int, _ occupancy: ChessBitboard) -> ChessBitboard {
        positiveRay(northEast, square, occupancy)
            | positiveRay(northWest, square, occupancy)
            | negativeRay(southEast, square, occupancy)
            | negativeRay(southWest, square, occupancy)
    }

    /// Queen attacks from `square` given `occupancy`.
    @inline(__always)
    public static func queenAttacks(_ square: Int, _ occupancy: ChessBitboard) -> ChessBitboard {
        rookAttacks(square, occupancy) | bishopAttacks(square, occupancy)
    }

    /// Attacks for a slider of the given kind. Non-sliders return empty —
    /// callers that might pass one are expected to have handled it.
    @inline(__always)
    public static func sliderAttacks(_ kind: ChessPieceKind, _ square: Int, _ occupancy: ChessBitboard) -> ChessBitboard {
        switch kind {
        case .bishop: return bishopAttacks(square, occupancy)
        case .rook:   return rookAttacks(square, occupancy)
        case .queen:  return queenAttacks(square, occupancy)
        default:      return .empty
        }
    }

    /// `knightAttacks[square]` — the up-to-8 knight destinations.
    public static let knightAttacks: [ChessBitboard] = leaperTable(
        offsets: [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
    )

    /// `kingAttacks[square]` — the up-to-8 adjacent squares.
    public static let kingAttacks: [ChessBitboard] = leaperTable(
        offsets: [(0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1)]
    )

    /// `pawnAttacks[colour][square]` — the two diagonal capture squares
    /// (one on the a/h files). Note this is what a pawn *attacks*, which
    /// is not the same as where it can move; pushes are generated
    /// separately by the move generator.
    public static let pawnAttacks: [[ChessBitboard]] = {
        var table = [[ChessBitboard]](repeating: [ChessBitboard](repeating: .empty, count: 64),
                                      count: 2)
        for color in [ChessColor.white, .black] {
            let dr = color == .white ? 1 : -1
            for square in 0..<64 {
                var bb = ChessBitboard.empty
                let file = square & 7
                let rank = square >> 3
                for df in [-1, 1] {
                    let f = file + df
                    let r = rank + dr
                    if (0...7).contains(f) && (0...7).contains(r) { bb.set(r * 8 + f) }
                }
                table[color.rawValue][square] = bb
            }
        }
        return table
    }()

    /// Build a jumping-piece table from (file, rank) offsets, dropping any
    /// that fall off an edge.
    private static func leaperTable(offsets: [(Int, Int)]) -> [ChessBitboard] {
        var table = [ChessBitboard](repeating: .empty, count: 64)
        for square in 0..<64 {
            var bb = ChessBitboard.empty
            let file = square & 7
            let rank = square >> 3
            for (df, dr) in offsets {
                let f = file + df
                let r = rank + dr
                if (0...7).contains(f) && (0...7).contains(r) { bb.set(r * 8 + f) }
            }
            table[square] = bb
        }
        return table
    }
}
