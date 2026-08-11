//
//  ChessSearch.swift
//  Scan
//
//  Alpha-beta search with iterative deepening.
//
//  ## Shape
//
//  Negamax with a fail-soft alpha-beta window, driven by iterative
//  deepening: search to depth 1, then 2, then 3… until the time budget
//  runs out. That sounds wasteful — and the re-searches really do repeat
//  work — but it pays for itself twice over. The shallow searches fill
//  the transposition table with good moves, so each deeper pass orders
//  its moves far better than it could from scratch; and it means the
//  clock can stop at *any* moment and still leave a complete, usable
//  answer from the last finished depth.
//
//  That second property is what the feature actually needs. A user
//  pointing a phone at a board wants an answer in about a second, and
//  "the best move found in the time available" is exactly the right
//  contract.
//
//  ## The trimmings, and why each is here
//
//  * **Transposition table** — the same position arrives by many move
//    orders; without it the branching factor stays near 35.
//  * **Move ordering** (TT move → captures by MVV-LVA → killers →
//    history) — alpha-beta's whole power comes from searching the best
//    move first. This matters far more than any evaluation term.
//  * **Quiescence** — stopping the search mid-capture-sequence produces
//    wildly wrong scores ("I'm a queen up!" one ply before it is
//    recaptured). Non-negotiable.
//  * **Null-move pruning** and **late-move reductions** — the two
//    cheapest ways to buy depth. Both are heuristics that can miss
//    things, so both are disabled in the situations where they are known
//    to be unsound (in check, and in zugzwang-prone pawn endings).
//
//  ## Cancellation
//
//  `stop()` is safe to call from any thread. The search checks it, and
//  the deadline, every 2048 nodes. Once aborted, the in-flight iteration's
//  result is **discarded** — a half-finished depth has searched only some
//  of the root moves and its "best" is meaningless.
//

import Foundation

public final class ChessSearch {

    // MARK: - Public shape

    public struct Limits {
        /// Wall-clock budget. The search returns as soon after this as it
        /// notices; it does not overshoot by more than a few milliseconds.
        public var thinkTime: TimeInterval
        /// Hard depth cap, mostly for tests that want determinism.
        public var maximumDepth: Int

        public init(thinkTime: TimeInterval = 1.0, maximumDepth: Int = ChessSearch.maximumPly - 8) {
            self.thinkTime = thinkTime
            self.maximumDepth = maximumDepth
        }
    }

    public struct Result {
        public var bestMove: ChessMove
        /// Centipawns from the searched side's point of view.
        public var score: Int
        /// Non-nil when the score is a forced mate. Positive = the side to
        /// move delivers mate in this many *moves*; negative = gets mated.
        public var mateInMoves: Int?
        public var principalVariation: [ChessMove]
        public var depth: Int
        public var nodes: Int
        public var elapsed: TimeInterval
    }

    public static let maximumPly = 64
    /// Comfortably beyond any real evaluation, so it can act as ±∞.
    static let infinity = 32_000
    /// Mate at ply 0. Mates found deeper score slightly less, so the
    /// search prefers the quickest one.
    static let mateScore = 30_000

    /// Scores at or beyond this magnitude encode a forced mate.
    @inline(__always)
    static func isMateScore(_ score: Int) -> Bool {
        abs(score) >= mateScore - maximumPly
    }

    // MARK: - Transposition table

    private enum Bound: UInt8 {
        /// The score is exact — this node's true value.
        case exact
        /// The search failed high; the true score is at least this.
        case lower
        /// The search failed low; the true score is at most this.
        case upper
    }

    private struct Entry {
        var key: UInt64 = 0
        var move: ChessMove = .none
        var score: Int32 = 0
        var depth: Int16 = -1
        var bound: Bound = .exact
    }

    /// 2^18 entries ≈ 6 MB. Big enough to matter at these depths, small
    /// enough that a phone analysing in the background is not a problem.
    private let tableSize = 1 << 18
    private var table: [Entry]

    // MARK: - Search state

    private var nodes = 0
    private var deadline = Date.distantFuture
    private var aborted = false

    private let stopLock = NSLock()
    private var stopRequested = false

    /// Two killer moves per ply: quiet moves that caused a cutoff at this
    /// depth elsewhere in the tree. Cheap, and startlingly effective.
    private var killers: [[ChessMove]]
    /// `history[colour][from][to]` — how often a quiet move has caused a
    /// cutoff anywhere. Orders the quiet moves that killers miss.
    private var history: [[[Int]]]

    /// Triangular principal-variation table. Reading the PV back out of
    /// the transposition table is the usual shortcut, but entries get
    /// overwritten mid-search and the PV comes back truncated or, worse,
    /// containing an illegal move from a colliding position. The UI
    /// displays this line, so it needs to be real.
    private var pvTable: [ChessMove]
    private var pvLength: [Int]

    /// Zobrist keys along the current path from the root, for repetition
    /// detection.
    private var pathKeys: [UInt64]

    public init() {
        table = [Entry](repeating: Entry(), count: tableSize)
        killers = [[ChessMove]](repeating: [.none, .none], count: Self.maximumPly)
        history = [[[Int]]](repeating: [[Int]](repeating: [Int](repeating: 0, count: 64), count: 64),
                            count: 2)
        pvTable = [ChessMove](repeating: .none, count: Self.maximumPly * Self.maximumPly)
        pvLength = [Int](repeating: 0, count: Self.maximumPly)
        pathKeys = [UInt64](repeating: 0, count: Self.maximumPly + 256)
    }

    /// Ask the search to stop. Safe from any thread.
    public func stop() {
        stopLock.lock()
        stopRequested = true
        stopLock.unlock()
    }

    private func clearStop() {
        stopLock.lock()
        stopRequested = false
        stopLock.unlock()
    }

    private var isStopRequested: Bool {
        stopLock.lock()
        defer { stopLock.unlock() }
        return stopRequested
    }

    // MARK: - Entry point

    /// Search `position` and return the best move found within `limits`.
    ///
    /// Returns nil only when the side to move has no legal move at all —
    /// checkmate or stalemate. Callers distinguish the two via
    /// `position.isInCheck`.
    public func search(_ position: ChessPosition, limits: Limits = Limits()) -> Result? {
        var root = position
        let rootMoves = ChessMoveGenerator.generateLegal(&root)
        guard rootMoves.count > 0 else { return nil }

        clearStop()
        aborted = false
        nodes = 0
        let started = Date()
        deadline = started.addingTimeInterval(limits.thinkTime)

        // History and killers persist across the iterative-deepening
        // passes of a single search (that is the point of them) but must
        // not leak between two unrelated positions.
        for ply in 0..<Self.maximumPly { killers[ply] = [.none, .none] }
        for color in 0..<2 {
            for from in 0..<64 {
                for to in 0..<64 { history[color][from][to] = 0 }
            }
        }

        // A legal move to fall back on if we are stopped before depth 1
        // completes.
        var best = Result(bestMove: rootMoves[0],
                          score: 0,
                          mateInMoves: nil,
                          principalVariation: [rootMoves[0]],
                          depth: 0,
                          nodes: 0,
                          elapsed: 0)

        let maximumDepth = min(limits.maximumDepth, Self.maximumPly - 8)
        for depth in 1...max(1, maximumDepth) {
            pathKeys[0] = root.key
            let score = alphaBeta(&root,
                                  depth: depth,
                                  alpha: -Self.infinity,
                                  beta: Self.infinity,
                                  ply: 0,
                                  allowNull: true)

            // A cut-off iteration has only looked at some root moves; its
            // "best" is not comparable with the completed depth below it.
            if aborted { break }

            let line = principalVariation()
            best = Result(bestMove: line.first ?? best.bestMove,
                          score: score,
                          mateInMoves: Self.mateDistance(from: score),
                          principalVariation: line,
                          depth: depth,
                          nodes: nodes,
                          elapsed: Date().timeIntervalSince(started))

            // A forced mate ends the useful search — but only once the
            // main search is deep enough to have actually walked the
            // mating line.
            //
            // Quiescence finds mates too (it generates every evasion when
            // in check), so a mate can surface at depth 1 with a correct
            // *score* and no line behind it: quiescence keeps no
            // principal variation. Stopping there would report "M3" next
            // to a one-move line and a search depth of 1. Deepening until
            // `depth` covers the mate distance puts the whole line inside
            // the main search, where the PV table is maintained.
            if Self.isMateScore(score) {
                let pliesToMate = Self.mateScore - abs(score)
                if depth >= pliesToMate { break }
            }
        }

        best.nodes = nodes
        best.elapsed = Date().timeIntervalSince(started)
        return best
    }

    /// Convert a mate-flavoured score into a move count, or nil.
    private static func mateDistance(from score: Int) -> Int? {
        guard isMateScore(score) else { return nil }
        let plies = mateScore - abs(score)
        // Plies to moves, rounding up: mate delivered on ply 1 is "mate
        // in 1", ply 2 and 3 are both "mate in 2".
        let moves = (plies + 1) / 2
        return score > 0 ? moves : -moves
    }

    private func principalVariation() -> [ChessMove] {
        guard pvLength[0] > 0 else { return [] }
        return (0..<pvLength[0]).map { pvTable[$0] }
    }

    // MARK: - Time

    @inline(__always)
    private func checkTime() {
        if aborted { return }
        if Date() >= deadline || isStopRequested { aborted = true }
    }

    // MARK: - Alpha-beta

    private func alphaBeta(_ position: inout ChessPosition,
                           depth: Int,
                           alpha: Int,
                           beta: Int,
                           ply: Int,
                           allowNull: Bool) -> Int {
        var alpha = alpha
        pvLength[ply] = ply

        if aborted { return 0 }
        nodes += 1
        if nodes & 2047 == 0 { checkTime() }

        let isRoot = ply == 0
        let inCheck = position.isInCheck
        // A "PV node" is one searched with a real window rather than the
        // null window PVS uses for moves it expects to refute — these are
        // the nodes whose moves reach the principal variation.
        let isPrincipalVariationNode = beta - alpha > 1

        if !isRoot {
            // Draws. Checked before anything else so the search never
            // reports a won position it can only reach by repeating.
            if isRepetition(position, ply: ply)
                || position.halfmoveClock >= 100
                || position.hasInsufficientMaterial {
                return 0
            }

            // Mate-distance pruning: if we already have a mate faster than
            // anything this subtree could produce, stop looking.
            let mateAlpha = max(alpha, -Self.mateScore + ply)
            let mateBeta = min(beta, Self.mateScore - ply - 1)
            if mateAlpha >= mateBeta { return mateAlpha }
            alpha = mateAlpha
        }

        // Being in check is never a quiet position, so extend rather than
        // dropping into quiescence — otherwise the search happily walks
        // into forced mates it never sees.
        var depth = depth
        if inCheck { depth += 1 }

        if depth <= 0 {
            return quiescence(&position, alpha: alpha, beta: beta, ply: ply)
        }

        // --- Transposition table probe ---
        //
        // Same rule as above: take the score cutoff only at non-PV nodes,
        // but always keep the stored move for ordering. Since the table is
        // filled by the shallower iterative-deepening passes, an
        // unrestricted cutoff here truncates the line on nearly every
        // deep search. PV nodes are a vanishing fraction of the tree, so
        // the lost prunes cost very little.
        let index = Int(position.key % UInt64(tableSize))
        var ttMove = ChessMove.none
        let entry = table[index]
        if entry.key == position.key {
            ttMove = entry.move
            if !isRoot && !isPrincipalVariationNode && Int(entry.depth) >= depth {
                let score = scoreFromTable(Int(entry.score), ply: ply)
                switch entry.bound {
                case .exact: return score
                case .lower: if score >= beta { return score }
                case .upper: if score <= alpha { return score }
                }
            }
        }

        // --- Null-move pruning ---
        //
        // "If I pass and you still can't hurt me, this position is good
        // enough to cut." Unsound in zugzwang, where passing is better
        // than any real move — so it is disabled when the side to move
        // has only pawns left, which is where zugzwang lives.
        if allowNull && !inCheck && !isRoot && depth >= 3 && beta < Self.mateScore - Self.maximumPly {
            let us = position.sideToMove
            let heavyMaterial = position.pieces(us).count - position.pieces(us, .pawn).count - 1
            if heavyMaterial > 0 {
                let reduction = 2 + depth / 6
                let undo = position.makeNull()
                pathKeys[ply + 1] = position.key
                let score = -alphaBeta(&position,
                                       depth: depth - 1 - reduction,
                                       alpha: -beta,
                                       beta: -beta + 1,
                                       ply: ply + 1,
                                       allowNull: false)
                position.unmakeNull(undo)
                if aborted { return 0 }
                if score >= beta {
                    // Don't return a mate score discovered through a null
                    // move — the "mate" may depend on the free tempo.
                    return Self.isMateScore(score) ? beta : score
                }
            }
        }

        var moves = ChessMoveGenerator.generateLegal(&position)
        if moves.count == 0 {
            // Mate scores shrink with depth so a mate in 2 beats a mate
            // in 4; stalemate is a plain draw.
            return inCheck ? -Self.mateScore + ply : 0
        }

        var scores = [Int](repeating: 0, count: moves.count)
        for i in 0..<moves.count {
            scores[i] = orderingScore(moves[i], position: position, ttMove: ttMove, ply: ply)
        }

        var bestScore = -Self.infinity
        var bestMove = ChessMove.none
        var bound = Bound.upper

        for i in 0..<moves.count {
            selectNext(i, &moves, &scores)
            let move = moves[i]

            let undo = position.make(move)
            pathKeys[ply + 1] = position.key

            var score: Int
            if i == 0 {
                // The first move gets the full window — it is our best
                // guess at the PV and deserves an exact score.
                score = -alphaBeta(&position, depth: depth - 1,
                                   alpha: -beta, beta: -alpha,
                                   ply: ply + 1, allowNull: true)
            } else {
                // --- Late-move reductions ---
                //
                // Moves this far down a well-ordered list are rarely best.
                // Search them shallower first; if one surprises us by
                // beating alpha, re-search it properly.
                var reduction = 0
                if depth >= 3 && i >= 4 && !inCheck
                    && !move.isCapture && !move.isPromotion
                    && !position.isInCheck {
                    reduction = 1 + (depth >= 6 && i >= 8 ? 1 : 0)
                }

                score = -alphaBeta(&position, depth: depth - 1 - reduction,
                                   alpha: -alpha - 1, beta: -alpha,
                                   ply: ply + 1, allowNull: true)

                // Re-search at full depth/window if the null-window probe
                // suggests this move is actually good.
                if score > alpha && reduction > 0 {
                    score = -alphaBeta(&position, depth: depth - 1,
                                       alpha: -alpha - 1, beta: -alpha,
                                       ply: ply + 1, allowNull: true)
                }
                if score > alpha && score < beta {
                    score = -alphaBeta(&position, depth: depth - 1,
                                       alpha: -beta, beta: -alpha,
                                       ply: ply + 1, allowNull: true)
                }
            }

            position.unmake(move, undo)
            if aborted { return 0 }

            if score > bestScore {
                bestScore = score
                bestMove = move

                if score > alpha {
                    alpha = score
                    bound = .exact
                    updatePrincipalVariation(move, ply: ply)

                    if score >= beta {
                        // Beta cutoff. Remember quiet moves that cause
                        // cutoffs — they tend to do it again elsewhere.
                        if !move.isCapture {
                            if killers[ply][0] != move {
                                killers[ply][1] = killers[ply][0]
                                killers[ply][0] = move
                            }
                            history[position.sideToMove.rawValue][move.fromIndex][move.toIndex]
                                += depth * depth
                        }
                        bound = .lower
                        break
                    }
                }
            }
        }

        store(index: index, key: position.key, move: bestMove,
              score: bestScore, depth: depth, bound: bound, ply: ply)
        return bestScore
    }

    // MARK: - Quiescence

    /// Search only the "loud" moves until the position is quiet enough to
    /// evaluate — otherwise every score is an artefact of where the clock
    /// happened to stop.
    private func quiescence(_ position: inout ChessPosition,
                            alpha: Int,
                            beta: Int,
                            ply: Int) -> Int {
        var alpha = alpha

        if aborted { return 0 }
        nodes += 1
        if nodes & 2047 == 0 { checkTime() }
        if ply >= Self.maximumPly - 1 { return ChessEvaluation.evaluate(position) }

        let inCheck = position.isInCheck

        // In check there is no such thing as standing pat — every evasion
        // must be considered or the search can miss being mated.
        if !inCheck {
            let standPat = ChessEvaluation.evaluate(position)
            if standPat >= beta { return standPat }
            if standPat > alpha { alpha = standPat }
        }

        var moves = ChessMoveGenerator.generateLegal(
            &position, mode: inCheck ? .all : .capturesAndPromotions)

        if moves.count == 0 {
            // Only meaningful when in check: no evasions means mate.
            return inCheck ? -Self.mateScore + ply : ChessEvaluation.evaluate(position)
        }

        var scores = [Int](repeating: 0, count: moves.count)
        for i in 0..<moves.count {
            scores[i] = orderingScore(moves[i], position: position, ttMove: .none, ply: ply)
        }

        var bestScore = inCheck ? -Self.infinity : ChessEvaluation.evaluate(position)

        for i in 0..<moves.count {
            selectNext(i, &moves, &scores)
            let move = moves[i]

            let undo = position.make(move)
            let score = -quiescence(&position, alpha: -beta, beta: -alpha, ply: ply + 1)
            position.unmake(move, undo)
            if aborted { return 0 }

            if score > bestScore {
                bestScore = score
                if score > alpha { alpha = score }
                if score >= beta { break }
            }
        }

        return bestScore
    }

    // MARK: - Move ordering

    /// Rank a move without searching it. The single highest-leverage
    /// function in the file: alpha-beta prunes in proportion to how often
    /// the best move is tried first.
    private func orderingScore(_ move: ChessMove,
                               position: ChessPosition,
                               ttMove: ChessMove,
                               ply: Int) -> Int {
        // The table's move already proved good in a previous iteration.
        if move == ttMove { return 10_000_000 }

        if move.isPromotion {
            let kind = move.promotionKind ?? .queen
            return 8_000_000 + ChessEvaluation.captureValue[kind.rawValue]
        }

        if move.isCapture {
            // MVV-LVA: grab the most valuable victim with the least
            // valuable attacker. Multiplying the victim by 16 keeps the
            // victim dominant while the attacker breaks ties.
            let victim: Int
            if move.isEnPassant {
                victim = ChessEvaluation.captureValue[ChessPieceKind.pawn.rawValue]
            } else if let piece = position.piece(at: move.toIndex) {
                victim = ChessEvaluation.captureValue[piece.kind.rawValue]
            } else {
                victim = 0
            }
            let attacker = position.piece(at: move.fromIndex)
                .map { ChessEvaluation.captureValue[$0.kind.rawValue] } ?? 0
            return 5_000_000 + victim * 16 - attacker
        }

        if move == killers[ply][0] { return 4_000_000 }
        if move == killers[ply][1] { return 3_900_000 }

        return history[position.sideToMove.rawValue][move.fromIndex][move.toIndex]
    }

    /// Selection sort, one move at a time.
    ///
    /// Cheaper than sorting the whole list up front, because a beta
    /// cutoff usually arrives within the first few moves and the rest are
    /// never looked at.
    @inline(__always)
    private func selectNext(_ index: Int, _ moves: inout ChessMoveList, _ scores: inout [Int]) {
        var best = index
        for candidate in (index + 1)..<moves.count where scores[candidate] > scores[best] {
            best = candidate
        }
        if best != index {
            moves.swapAt(index, best)
            scores.swapAt(index, best)
        }
    }

    // MARK: - Bookkeeping

    private func updatePrincipalVariation(_ move: ChessMove, ply: Int) {
        pvTable[ply * Self.maximumPly + ply] = move
        if pvLength[ply + 1] > ply + 1 {
            for next in (ply + 1)..<pvLength[ply + 1] {
                pvTable[ply * Self.maximumPly + next] = pvTable[(ply + 1) * Self.maximumPly + next]
            }
        }
        pvLength[ply] = max(pvLength[ply + 1], ply + 1)
        // Note the root's line needs no special handling: at ply 0 the
        // row offset is zero, so it already lives at pvTable[0...],
        // which is where `principalVariation()` reads it from.
    }

    private func isRepetition(_ position: ChessPosition, ply: Int) -> Bool {
        guard ply > 0 else { return false }
        // Only positions since the last irreversible move can repeat, and
        // the halfmove clock tells us exactly how far back that is.
        let reach = min(ply, position.halfmoveClock)
        guard reach >= 2 else { return false }
        var back = 2
        while back <= reach {
            if pathKeys[ply - back] == position.key { return true }
            back += 2   // only same-side-to-move positions can repeat
        }
        return false
    }

    /// Mate scores are stored relative to the node they were found at, so
    /// the same entry means the same thing wherever it is probed from.
    private func scoreForTable(_ score: Int, ply: Int) -> Int {
        if score >= Self.mateScore - Self.maximumPly { return score + ply }
        if score <= -Self.mateScore + Self.maximumPly { return score - ply }
        return score
    }

    private func scoreFromTable(_ score: Int, ply: Int) -> Int {
        if score >= Self.mateScore - Self.maximumPly { return score - ply }
        if score <= -Self.mateScore + Self.maximumPly { return score + ply }
        return score
    }

    private func store(index: Int, key: UInt64, move: ChessMove,
                       score: Int, depth: Int, bound: Bound, ply: Int) {
        // Depth-preferred replacement: a deeper result is worth more than
        // a more recent one, but always take the slot if it belongs to a
        // different position.
        let existing = table[index]
        if existing.key == key && Int(existing.depth) > depth { return }
        table[index] = Entry(key: key,
                             move: move,
                             score: Int32(scoreForTable(score, ply: ply)),
                             depth: Int16(depth),
                             bound: bound)
    }
}
