//
//  ChessNotation.swift
//  Scan
//
//  Standard Algebraic Notation — "Nf3", "exd5", "O-O", "Qxh7#".
//
//  The engine speaks UCI internally ("g1f3") because it is unambiguous
//  without a position. SAN is what a person reads, so every move the UI
//  shows goes through here.
//
//  SAN cannot be produced from a move alone: "Nf3" is only correct if no
//  *other* knight could also reach f3, and the check/mate suffix depends
//  on the resulting position. So each function takes the position the
//  move is played in.
//

import Foundation

extension ChessPosition {

    /// SAN for `move`, which must be legal in this position.
    ///
    /// Follows the usual rules: piece letter (omitted for pawns), the
    /// minimum disambiguation needed, "x" for captures, the destination,
    /// "=Q" for promotions, and "+" / "#" for check and mate.
    public func san(for move: ChessMove) -> String {
        guard let moving = piece(at: move.fromIndex) else { return move.uci }

        if move.isCastle {
            return decorate(move, base: move.flag == .castleKingside ? "O-O" : "O-O-O")
        }

        var text = ""
        let destination = ChessSquare(index: move.toIndex).algebraic

        if moving.kind == .pawn {
            // A capturing pawn is identified by its file: "exd5".
            if move.isCapture {
                text += String(Array("abcdefgh")[move.fromIndex & 7]) + "x"
            }
            text += destination
            if let promotion = move.promotionKind {
                text += "=" + String(promotion.fenLetter)
            }
        } else {
            text += String(moving.kind.fenLetter)
            text += disambiguation(for: move, moving: moving)
            if move.isCapture { text += "x" }
            text += destination
        }

        return decorate(move, base: text)
    }

    /// The smallest file/rank hint that identifies which piece moved.
    ///
    /// Standard precedence: if the origin file alone is unique use that,
    /// else the rank, else both. The candidates considered are only
    /// *legal* movers — a knight that is pinned cannot reach the square,
    /// so it does not create ambiguity and must not force a hint.
    private func disambiguation(for move: ChessMove, moving: ChessPiece) -> String {
        var rivals: [Int] = []
        var scratch = self
        let legal = ChessMoveGenerator.generateLegal(&scratch)
        for index in 0..<legal.count {
            let other = legal[index]
            guard other.toIndex == move.toIndex,
                  other.fromIndex != move.fromIndex,
                  piece(at: other.fromIndex) == moving else { continue }
            rivals.append(other.fromIndex)
        }
        guard !rivals.isEmpty else { return "" }

        let files = Array("abcdefgh")
        let fromFile = move.fromIndex & 7
        let fromRank = move.fromIndex >> 3

        if !rivals.contains(where: { $0 & 7 == fromFile }) {
            return String(files[fromFile])
        }
        if !rivals.contains(where: { $0 >> 3 == fromRank }) {
            return String(fromRank + 1)
        }
        return String(files[fromFile]) + String(fromRank + 1)
    }

    /// Append "+" or "#" by playing the move and looking.
    private func decorate(_ move: ChessMove, base: String) -> String {
        var next = self
        next.make(move)
        guard next.isInCheck else { return base }
        var scratch = next
        let replies = ChessMoveGenerator.generateLegal(&scratch)
        return base + (replies.count == 0 ? "#" : "+")
    }

    /// SAN for a whole line, numbered as it would appear in a game score:
    /// "15. Nf3 Bd6 16. O-O".
    ///
    /// - Parameter line: moves to play in sequence from this position.
    ///   Stops early at the first illegal move rather than producing
    ///   nonsense, which matters because a truncated principal variation
    ///   is a normal thing to be handed.
    public func sanLine(_ line: [ChessMove]) -> String {
        var position = self
        var parts: [String] = []

        for move in line {
            var scratch = position
            let legal = ChessMoveGenerator.generateLegal(&scratch).asArray
            guard legal.contains(move) else { break }

            if position.sideToMove == .white {
                parts.append("\(position.fullmoveNumber).")
            } else if parts.isEmpty {
                // A line that starts with Black's move needs the "15..."
                // form so the numbering reads correctly.
                parts.append("\(position.fullmoveNumber)...")
            }
            parts.append(position.san(for: move))
            position.make(move)
        }

        return parts.joined(separator: " ")
    }

    /// Find the legal move matching a UCI string, or nil.
    ///
    /// Goes through the legal move list rather than trusting
    /// `ChessMove(uci:)` directly, because the UCI text carries no
    /// capture/en-passant/castling flags — only the position knows those,
    /// and a move with the wrong flags would corrupt `make`.
    public func move(uci: String) -> ChessMove? {
        guard let parsed = ChessMove(uci: uci) else { return nil }
        var scratch = self
        let legal = ChessMoveGenerator.generateLegal(&scratch)
        for index in 0..<legal.count {
            let candidate = legal[index]
            if candidate.fromIndex == parsed.fromIndex,
               candidate.toIndex == parsed.toIndex,
               candidate.promotionKind == parsed.promotionKind {
                return candidate
            }
        }
        return nil
    }
}
