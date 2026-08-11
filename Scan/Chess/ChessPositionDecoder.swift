//
//  ChessPositionDecoder.swift
//  Scan
//
//  Turns 64 per-square probability distributions into the most probable
//  *legal* chess position.
//
//  ## Why this is not just `argmax` per square
//
//  Per-square accuracy compounds over 64 squares, and the compounding is
//  brutal:
//
//      per-square   whole board correct
//      99.0%        52%
//      99.5%        73%
//      99.9%        94%
//
//  So a classifier that looks excellent in a confusion matrix still gets
//  the *whole board* wrong about half the time — and a board that is
//  wrong anywhere is a wrong position and a wrong suggested move. Taking
//  the per-square argmax throws away the strongest prior available: the
//  answer has to be legal chess.
//
//  This spends that prior. It enforces exactly the constraints
//  `legalityProblems` checks, so anything decoded here is a position the
//  engine will accept:
//
//    * exactly one king per colour
//    * at most 8 pawns a side
//    * no pawn on rank 1 or 8
//    * at most 16 pieces a side
//    * promotions paid for by missing pawns
//
//  ## Approach
//
//  Not an exact optimiser. The exact problem is a small integer program;
//  solving it properly would be slower and much harder to keep identical
//  across Swift, Kotlin and the Python reference. Instead: start from the
//  per-square argmax, then repair each violated constraint with the
//  cheapest single-square changes that fix it, where "cheapest" is the
//  loss in log-probability.
//
//  Repair order is deliberate — kings first (tightest constraint, most
//  often violated), then back-rank pawns (a local fix that never
//  cascades), then the counting constraints. Fixing a cheap constraint
//  first can otherwise force an expensive one to be fixed badly.
//
//  ## This is a port
//
//  `chess-vision/src/chess_vision/decode.py` is the reference
//  implementation and `chess-vision/tests/test_decode.py` is the
//  specification. This file, that one, and the Kotlin port must agree
//  square for square. Change behaviour in all three or in none.
//

import Foundation

/// The decoder's alphabet: `0` = empty, otherwise `1 + ChessPiece.index`,
/// giving `wP=1 … wK=6, bP=7 … bK=12`.
///
/// The `1 +` offset is what makes decoding a square a one-liner, and it
/// is the same scheme the models are trained against — see
/// `chess_vision/squares.py`.
public enum ChessSquareLabel {
    public static let empty = 0
    public static let count = 13

    @inline(__always)
    public static func piece(_ label: Int) -> ChessPiece? {
        label == empty ? nil : ChessPiece(index: label - 1)
    }

    @inline(__always)
    public static func label(for piece: ChessPiece) -> Int { piece.index + 1 }

    /// Upper bound on repair rounds. Two is enough for every input
    /// tested; the cap exists so a future change cannot turn a bug into
    /// a hang.
    static let maximumRepairRounds = 4

    /// White's pawn and king class ids; Black's are these plus six.
    static let whitePawn = 1
    static let whiteKing = 6
    static let blackPawn = 7
    static let blackKing = 12
}

/// What the recogniser produced, after decoding.
public struct ChessRecognizedPosition: Sendable {
    /// 64 entries in LERF order, a1 first — the shape
    /// `ChessPosition(placement:)` takes.
    public var placement: [ChessPiece?]
    /// Probability of the chosen class, per square.
    public var confidence: [Double]
    /// One note per repair the decoder had to apply. Shown in the
    /// editor's "what was adjusted" disclosure so a surprising board is
    /// explainable rather than mysterious.
    public var repairs: [String]

    /// Squares ordered least-confident first.
    ///
    /// The editor rings the first few so the user proof-reads the shakiest
    /// squares rather than all sixty-four.
    public var weakestSquares: [ChessSquare] {
        (0..<64).sorted { confidence[$0] < confidence[$1] }
            .map { ChessSquare(index: $0) }
    }

    /// Build a position. Side to move, castling rights and the en-passant
    /// file are **not** set here — a photograph cannot show them, so they
    /// stay user input.
    public func position(sideToMove: ChessColor = .white) -> ChessPosition {
        ChessPosition(placement: placement, sideToMove: sideToMove)
    }
}

public enum ChessPositionDecoder {

    /// Decode 64 per-square distributions into a legal position.
    ///
    /// - Parameter probabilities: 64 arrays of `ChessSquareLabel.count`
    ///   probabilities, in LERF order (a1 first).
    public static func decode(probabilities: [[Double]]) -> ChessRecognizedPosition {
        precondition(probabilities.count == 64, "expected 64 squares")

        let logs = probabilities.map { row -> [Double] in
            precondition(row.count == ChessSquareLabel.count, "expected 13 classes")
            return row.map { Foundation.log(Swift.max($0, 1e-12)) }
        }

        var labels = (0..<64).map { square in
            (0..<ChessSquareLabel.count).max { logs[square][$0] < logs[square][$1] } ?? 0
        }
        var repairs: [String] = []

        // Repair to a fixed point. Each pass is designed not to create
        // work for the others, but that is an argument, not a proof — and
        // the cost of being wrong is an illegal position reaching the
        // engine. Iterating until nothing changes turns the argument into
        // a guarantee; in practice the second round is a no-op.
        for _ in 0..<ChessSquareLabel.maximumRepairRounds {
            let before = labels
            repairKings(&labels, logs, &repairs)
            repairBackRankPawns(&labels, logs, &repairs)
            repairCounts(&labels, logs, &repairs)
            if labels == before { break }
        }

        return ChessRecognizedPosition(
            placement: labels.map { ChessSquareLabel.piece($0) },
            confidence: (0..<64).map { probabilities[$0][labels[$0]] },
            repairs: repairs
        )
    }

    // MARK: - Repairs

    /// Log-probability given up by relabelling one square.
    @inline(__always)
    private static func cost(_ logs: [[Double]], _ square: Int,
                             from current: Int, to target: Int) -> Double {
        logs[square][current] - logs[square][target]
    }

    /// Best class for `square` that isn't excluded.
    ///
    /// **Kings are always excluded**, on top of whatever the caller asks
    /// for. This is not a nicety: every caller runs *after* `repairKings`
    /// has settled the king count, so relabelling a square as a king here
    /// would silently break that invariant — nothing re-checks it, and a
    /// board comes out with seven white kings.
    ///
    /// Uniform-noise input never exposes this (with all classes equal the
    /// maximum lands on `empty`); genuinely random per-class
    /// probabilities expose it immediately, which is what a real
    /// classifier produces.
    private static func cheapestOther(_ logs: [[Double]], _ square: Int,
                                      excluding excluded: Set<Int>) -> Int {
        let forbidden = excluded.union([ChessSquareLabel.whiteKing, ChessSquareLabel.blackKing])
        return (0..<ChessSquareLabel.count)
            .filter { !forbidden.contains($0) }
            .max { logs[square][$0] < logs[square][$1] } ?? ChessSquareLabel.empty
    }

    /// Force exactly one king per colour.
    ///
    /// The two directions are asymmetric. Too many kings: demote the
    /// extras to their next-best non-king class. Too few: promote whichever
    /// square is *least* reluctant to become one — usually a square where
    /// the model already ranked king second.
    private static func repairKings(_ labels: inout [Int], _ logs: [[Double]],
                                    _ repairs: inout [String]) {
        for (kingClass, name) in [(ChessSquareLabel.whiteKing, "White"),
                                  (ChessSquareLabel.blackKing, "Black")] {
            let squares = (0..<64).filter { labels[$0] == kingClass }

            if squares.count > 1 {
                // Keep the most confident; demote the rest.
                let ranked = squares.sorted { logs[$0][kingClass] > logs[$1][kingClass] }
                for square in ranked.dropFirst() {
                    labels[square] = cheapestOther(logs, square, excluding: [kingClass])
                }
                repairs.append("\(name) had \(squares.count) kings — kept the most confident.")

            } else if squares.isEmpty {
                // Never take the square the *other* king is standing on.
                // Without this, a read with no kings at all promotes
                // White's king onto the cheapest square and then Black's
                // onto the same one — the cost function has no idea it was
                // just claimed — and the board comes back with one king.
                // Uniform-noise input hits this every time, because every
                // square costs exactly the same.
                let otherKing = kingClass == ChessSquareLabel.whiteKing
                    ? ChessSquareLabel.blackKing : ChessSquareLabel.whiteKing
                let candidates = (0..<64).filter { labels[$0] != otherKing }
                if let best = candidates.min(by: {
                    cost(logs, $0, from: labels[$0], to: kingClass)
                        < cost(logs, $1, from: labels[$1], to: kingClass)
                }) {
                    labels[best] = kingClass
                    repairs.append("\(name) had no king — added one where it fit best.")
                }
            }
        }
    }

    /// No pawn may stand on rank 1 or 8.
    ///
    /// A purely local fix, and done *before* the counting pass: a
    /// hallucinated back-rank pawn would otherwise be counted against the
    /// pawn budget and push a legitimate pawn out instead.
    private static func repairBackRankPawns(_ labels: inout [Int], _ logs: [[Double]],
                                            _ repairs: inout [String]) {
        for square in 0..<64 {
            let rank = square >> 3
            guard rank == 0 || rank == 7 else { continue }
            guard labels[square] == ChessSquareLabel.whitePawn
                    || labels[square] == ChessSquareLabel.blackPawn else { continue }

            labels[square] = cheapestOther(
                logs, square,
                excluding: [ChessSquareLabel.whitePawn, ChessSquareLabel.blackPawn]
            )
            repairs.append(
                "A pawn on \(ChessSquare(index: square).algebraic) can't exist — relabelled it."
            )
        }
    }

    /// Pawn, piece and promotion budgets, per colour.
    ///
    /// Surplus squares are set to **empty**, never relabelled to the
    /// next-best class. Relabelling looks smarter and is not: the
    /// replacement is free to be a back-rank pawn, or a piece of the
    /// *other* colour whose budget was settled on the previous pass, so
    /// each fix quietly creates work for a pass that has already run.
    /// Emptying is monotone — it can only reduce counts — which is what
    /// makes this pass end in a legal position rather than merely a
    /// different one.
    private static func repairCounts(_ labels: inout [Int], _ logs: [[Double]],
                                     _ repairs: inout [String]) {
        // Starting complement per kind, indexed by ChessPieceKind.rawValue.
        let startingCount = [8, 2, 2, 2, 1, 1]

        for colour in 0..<2 {
            let base = 1 + colour * 6          // this colour's pawn class
            let name = colour == 0 ? "White" : "Black"

            // Squares holding `kind`, least confident first.
            func squares(of kind: Int) -> [Int] {
                let target = base + kind
                return (0..<64).filter { labels[$0] == target }
                    .sorted { logs[$0][labels[$0]] < logs[$1][labels[$1]] }
            }

            // 1. at most 8 pawns
            var pawns = squares(of: 0)
            while pawns.count > 8 {
                let square = pawns.removeFirst()
                labels[square] = ChessSquareLabel.empty
                repairs.append("\(name) had too many pawns — removed the least certain.")
            }

            // 2. promotions must be affordable: every piece above the
            //    starting complement costs one missing pawn.
            for kind in [4, 3, 2, 1] {   // queens first: the commonest misread
                while true {
                    let pawnCount = squares(of: 0).count
                    let extras = [1, 2, 3, 4].reduce(0) {
                        $0 + Swift.max(0, squares(of: $1).count - startingCount[$1])
                    }
                    if extras <= 8 - pawnCount { break }

                    let candidates = squares(of: kind)
                    if candidates.count <= startingCount[kind] { break }
                    let square = candidates[0]
                    labels[square] = ChessSquareLabel.empty
                    repairs.append(
                        "\(name) had more promoted pieces than missing pawns — removed one."
                    )
                }
            }

            // 3. at most 16 pieces
            while true {
                let owned = (0..<64).filter { labels[$0] >= base && labels[$0] <= base + 5 }
                if owned.count <= 16 { break }
                // Never remove the king — mandatory, and already unique.
                let removable = owned.filter { labels[$0] != base + 5 }
                guard let square = removable.min(by: {
                    logs[$0][labels[$0]] < logs[$1][labels[$1]]
                }) else { break }
                labels[square] = ChessSquareLabel.empty
                repairs.append("\(name) had too many pieces — cleared the least certain square.")
            }
        }
    }

    /// Softmax, for callers holding raw model output.
    public static func probabilities(fromLogits logits: [[Double]]) -> [[Double]] {
        logits.map { row in
            let peak = row.max() ?? 0
            let exponentials = row.map { Foundation.exp($0 - peak) }
            let total = exponentials.reduce(0, +)
            return exponentials.map { $0 / total }
        }
    }
}
