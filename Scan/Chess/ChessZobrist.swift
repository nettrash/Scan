//
//  ChessZobrist.swift
//  Scan
//
//  Zobrist hashing — the incremental 64-bit position key used by the
//  transposition table and by repetition detection.
//
//  The random numbers come from a **fixed-seed xorshift64\*** generator
//  rather than from `SystemRandomNumberGenerator`. Two reasons, both of
//  which matter more than the entropy quality:
//
//  1. The Kotlin port must produce byte-identical keys, so that a
//     recorded transposition-table fixture or a debug key printed on one
//     platform means something on the other. A named algorithm with a
//     named seed is reproducible; a system RNG is not.
//  2. A run-to-run stable key means a hash collision, if we ever hit one,
//     is reproducible rather than a heisenbug.
//
//  xorshift64* is more than good enough here: we need ~800 well-spread
//  64-bit constants, not cryptographic randomness.
//

import Foundation

public enum ChessZobrist {

    /// xorshift64\* — Marsaglia's xorshift64 with a multiplying output
    /// scramble. Deterministic given the seed, and trivially portable:
    /// Kotlin's `Long` arithmetic wraps identically to `UInt64`'s `&*`.
    private struct SplitMix: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state ^= state >> 12
            state ^= state << 25
            state ^= state >> 27
            return state &* 2685821657736338717
        }
    }

    /// The seed. Arbitrary, but *fixed* — changing it invalidates nothing
    /// persisted (we never write keys to disk) yet would silently break
    /// cross-platform key comparisons, so treat it as a constant of the
    /// format rather than a tunable.
    private static let seed: UInt64 = 0x9E37_79B9_7F4A_7C15

    /// All the random constants, drawn in one deterministic pass so the
    /// draw order is part of the spec:
    ///   1. 12 × 64 piece-square keys, piece index major
    ///   2. 1 side-to-move key
    ///   3. 16 castling-rights keys (indexed by the raw 4-bit set)
    ///   4. 8 en-passant *file* keys
    private static let tables: (pieceSquare: [[UInt64]],
                                sideToMove: UInt64,
                                castling: [UInt64],
                                enPassantFile: [UInt64]) = {
        var rng = SplitMix(state: seed)

        var pieceSquare = [[UInt64]](repeating: [UInt64](repeating: 0, count: 64), count: 12)
        for piece in 0..<12 {
            for square in 0..<64 {
                pieceSquare[piece][square] = rng.next()
            }
        }
        let sideToMove = rng.next()
        var castling = [UInt64](repeating: 0, count: 16)
        for i in 0..<16 { castling[i] = rng.next() }
        var enPassantFile = [UInt64](repeating: 0, count: 8)
        for i in 0..<8 { enPassantFile[i] = rng.next() }

        return (pieceSquare, sideToMove, castling, enPassantFile)
    }()

    /// Key contribution of `piece` standing on `square`.
    @inline(__always)
    public static func piece(_ piece: ChessPiece, _ square: Int) -> UInt64 {
        tables.pieceSquare[piece.index][square]
    }

    /// Key contribution of the same, addressed by dense piece index.
    @inline(__always)
    public static func piece(index: Int, square: Int) -> UInt64 {
        tables.pieceSquare[index][square]
    }

    /// XOR-ed in whenever it is Black's turn, so the same arrangement of
    /// pieces hashes differently depending on who is to move.
    @inline(__always)
    public static var sideToMove: UInt64 { tables.sideToMove }

    /// Key contribution of a castling-rights set, addressed by its raw
    /// 4-bit value — one key per combination rather than one per right,
    /// which makes updating rights a single XOR-out/XOR-in pair.
    @inline(__always)
    public static func castling(_ rights: ChessCastlingRights) -> UInt64 {
        tables.castling[Int(rights.rawValue)]
    }

    /// Key contribution of an en-passant target.
    ///
    /// Keyed by **file only**, not by square: the rank is implied by the
    /// side to move, so including it would just be a constant offset, and
    /// file-only keeps the table at 8 entries and matches how FEN-derived
    /// positions compare.
    @inline(__always)
    public static func enPassantFile(_ file: Int) -> UInt64 {
        tables.enPassantFile[file]
    }
}
