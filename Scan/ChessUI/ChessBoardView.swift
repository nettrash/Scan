//
//  ChessBoardView.swift
//  Scan
//
//  Draws a position, optionally with a move arrow, optionally editable.
//
//  ## Pieces are the *filled* Unicode glyphs, tinted
//
//  There are no chess pieces in SF Symbols, so the glyphs come from
//  Unicode. The subtlety is which half of the block to use. U+2654-2659
//  are nominally the "white" pieces and U+265A-265F the "black" ones —
//  but that naming describes ink, not chess: the first set are *outline*
//  drawings and the second are *solid*. Using them literally gives a
//  white king that is a thin outline, which disappears against a light
//  square and reads as a different piece entirely from its solid black
//  counterpart.
//
//  So both colours are drawn from the **solid** set (U+265A-265F) and
//  tinted, which is what chess UIs generally do. Measured on the Apple
//  font stack the solid glyphs carry roughly twice the ink of the outline
//  ones, and a contrasting rim keeps a white piece legible on a light
//  square and a black piece on a dark one.
//
//  Board orientation is a display concern only: `whiteAtBottom` flips
//  which squares are drawn where. The underlying `ChessPosition` is
//  always LERF and never mirrors — the one place the two conventions meet
//  is `layout(for:)`.
//

import SwiftUI

/// One square's visual state, beyond the piece standing on it.
public struct ChessSquareDecoration: Equatable, Sendable {
    /// Ring the square to flag a low-confidence recognition.
    public var isUncertain: Bool = false
    /// Highlight as the current editing target.
    public var isSelected: Bool = false
    /// Tint as part of the suggested move.
    public var isMoveEndpoint: Bool = false

    public init(isUncertain: Bool = false, isSelected: Bool = false,
                isMoveEndpoint: Bool = false) {
        self.isUncertain = isUncertain
        self.isSelected = isSelected
        self.isMoveEndpoint = isMoveEndpoint
    }
}

struct ChessBoardView: View {
    let placement: [ChessPiece?]
    var whiteAtBottom: Bool = true
    /// Drawn as an arrow from `from` to `to`.
    var arrow: (from: ChessSquare, to: ChessSquare)?
    var decorations: [Int: ChessSquareDecoration] = [:]
    /// Non-nil makes the board interactive.
    var onTap: ((ChessSquare) -> Void)?

    // Board colours. Chosen to stay legible against both the light and
    // dark app appearances rather than mimicking any particular set.
    private let lightSquare = Color(red: 0.93, green: 0.89, blue: 0.80)
    private let darkSquare = Color(red: 0.55, green: 0.44, blue: 0.33)

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let square = side / 8

            ZStack(alignment: .topLeading) {
                squares(square: square)
                pieces(square: square)
                if let arrow {
                    ChessMoveArrow(from: layout(for: arrow.from),
                                   to: layout(for: arrow.to),
                                   square: square)
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Layers

    private func squares(square: CGFloat) -> some View {
        ForEach(0..<64, id: \.self) { index in
            let chessSquare = ChessSquare(index: index)
            let (row, column) = layout(for: chessSquare)
            let decoration = decorations[index] ?? ChessSquareDecoration()

            Rectangle()
                .fill(chessSquare.isLight ? lightSquare : darkSquare)
                .overlay {
                    if decoration.isMoveEndpoint {
                        Rectangle().fill(Color.accentColor.opacity(0.35))
                    }
                    if decoration.isSelected {
                        Rectangle().strokeBorder(Color.accentColor, lineWidth: square * 0.07)
                    }
                    if decoration.isUncertain {
                        // A dashed ring rather than a fill: it has to
                        // survive being drawn over a piece.
                        Rectangle()
                            .strokeBorder(Color.orange,
                                          style: StrokeStyle(lineWidth: square * 0.06,
                                                             dash: [square * 0.14]))
                    }
                }
                .frame(width: square, height: square)
                .offset(x: CGFloat(column) * square, y: CGFloat(row) * square)
                .contentShape(Rectangle())
                .onTapGesture { onTap?(chessSquare) }
                // A bare `Rectangle` is decorative as far as SwiftUI is
                // concerned, so it needs promoting to a real element or
                // VoiceOver skips the whole board — and the pieces are
                // drawn in a separate layer, so they cannot carry the
                // labels themselves.
                .accessibilityElement()
                .accessibilityIdentifier(chessSquare.algebraic)
                .accessibilityLabel(accessibilityLabel(for: chessSquare))
                .accessibilityAddTraits(onTap == nil ? [] : .isButton)
        }
    }

    private func pieces(square: CGFloat) -> some View {
        ForEach(0..<64, id: \.self) { index in
            if let piece = placement[index] {
                let (row, column) = layout(for: ChessSquare(index: index))
                let isWhite = piece.color == .white
                Text(Self.glyph(for: piece.kind))
                    .font(.system(size: square * 0.76))
                    .foregroundStyle(isWhite ? Color.white : Color.black)
                    // Rim in the opposite tone. Without it a white piece
                    // on a light square and a black piece on a dark one
                    // both lose their silhouette.
                    .shadow(color: isWhite ? .black.opacity(0.95) : .white.opacity(0.75),
                            radius: 0.5)
                    .shadow(color: isWhite ? .black.opacity(0.55) : .white.opacity(0.4),
                            radius: 1.4)
                    .frame(width: square, height: square)
                    .offset(x: CGFloat(column) * square, y: CGFloat(row) * square)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Geometry

    /// LERF square → the grid cell it occupies on screen.
    ///
    /// The single place the board's storage order and the screen's
    /// top-left origin meet. Everything else — arrows, decorations, taps
    /// — routes through it, so flipping the board is one change.
    private func layout(for square: ChessSquare) -> (row: Int, column: Int) {
        whiteAtBottom
            ? (7 - square.rank, square.file)
            : (square.rank, 7 - square.file)
    }

    private func accessibilityLabel(for square: ChessSquare) -> String {
        guard let piece = placement[square.index] else {
            return "\(square.algebraic), empty"
        }
        return "\(square.algebraic), \(piece.color.displayName) \(piece.kind.displayName)"
    }

    /// The solid Unicode glyph for a kind — see the file header for why
    /// both colours use this half of the block.
    ///
    /// Every glyph carries **U+FE0E**, the text-presentation variation
    /// selector, and it is load-bearing for exactly one of them. U+265F
    /// (the pawn) is also an emoji — ♟️ — and without the selector the
    /// system renders it in *colour* presentation. A colour emoji ignores
    /// `foregroundStyle` entirely, so every white pawn came out as a
    /// glossy black one while the rooks and queens tinted correctly: a
    /// board that looks almost right, with eight pieces the wrong colour.
    ///
    /// The selector is applied to all six rather than just the pawn, so a
    /// future Unicode revision promoting another of these to emoji cannot
    /// reintroduce the bug.
    static func glyph(for kind: ChessPieceKind) -> String {
        let base: String
        switch kind {
        case .king:   base = "\u{265A}"
        case .queen:  base = "\u{265B}"
        case .rook:   base = "\u{265C}"
        case .bishop: base = "\u{265D}"
        case .knight: base = "\u{265E}"
        case .pawn:   base = "\u{265F}"
        }
        return base + "\u{FE0E}"
    }
}

// MARK: - Move arrow

/// The suggested move, drawn over the board.
///
/// A tapered arrow rather than a plain line: at board sizes on a phone a
/// uniform stroke reads as a highlight, not a direction, and the whole
/// point is to show *which way* the piece goes.
private struct ChessMoveArrow: View {
    let from: (row: Int, column: Int)
    let to: (row: Int, column: Int)
    let square: CGFloat

    var body: some View {
        let start = centre(of: from)
        let end = centre(of: to)

        Path { path in
            let angle = atan2(end.y - start.y, end.x - start.x)
            let headLength = square * 0.44
            let headWidth = square * 0.34
            let shaftWidth = square * 0.13

            // Stop the shaft short so the head's point lands on the
            // destination square's centre rather than past it.
            let shaftEnd = CGPoint(x: end.x - cos(angle) * headLength,
                                   y: end.y - sin(angle) * headLength)
            let normal = CGPoint(x: -sin(angle), y: cos(angle))

            path.move(to: offset(start, normal, shaftWidth / 2))
            path.addLine(to: offset(shaftEnd, normal, shaftWidth / 2))
            path.addLine(to: offset(shaftEnd, normal, headWidth / 2))
            path.addLine(to: end)
            path.addLine(to: offset(shaftEnd, normal, -headWidth / 2))
            path.addLine(to: offset(shaftEnd, normal, -shaftWidth / 2))
            path.addLine(to: offset(start, normal, -shaftWidth / 2))
            path.closeSubpath()
        }
        .fill(Color.accentColor.opacity(0.85))
        .shadow(color: .black.opacity(0.35), radius: 1)
        .allowsHitTesting(false)
    }

    private func centre(of cell: (row: Int, column: Int)) -> CGPoint {
        CGPoint(x: (CGFloat(cell.column) + 0.5) * square,
                y: (CGFloat(cell.row) + 0.5) * square)
    }

    private func offset(_ point: CGPoint, _ normal: CGPoint, _ distance: CGFloat) -> CGPoint {
        CGPoint(x: point.x + normal.x * distance, y: point.y + normal.y * distance)
    }
}

// MARK: - Display names

extension ChessPieceKind {
    /// Spoken and written name, for VoiceOver and the piece palette.
    public var displayName: String {
        switch self {
        case .pawn:   return "pawn"
        case .knight: return "knight"
        case .bishop: return "bishop"
        case .rook:   return "rook"
        case .queen:  return "queen"
        case .king:   return "king"
        }
    }
}

#Preview("Starting position") {
    ChessBoardView(placement: ChessPosition.standard.placement,
                   arrow: (from: ChessSquare.e1, to: ChessSquare.e8))
        .padding()
}
