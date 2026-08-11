//
//  ChessBoardWarp.swift
//  Scan
//
//  Rectifying a photographed board into the square image `PieceNet` reads.
//
//  Port of `chess-vision/src/chess_vision/preprocess.py`, which is the
//  reference and is tested there. The two must agree: this is the step
//  between the two models, and a warp that differs by half a square
//  between training and inference feeds the model something it never saw.
//
//  ## The margin, and why it is not zero
//
//  The obvious warp maps the playing surface onto the output exactly.
//  That is wrong for a photographed board, because a standing piece is
//  *taller than its square*: a king on e8 seen from a low angle occupies
//  a tall sliver of image extending well past the surface's far edge.
//  Warp the surface exactly and every back-rank piece is decapitated.
//
//  So the crop is expanded by `marginSquares` on each side — one square's
//  worth — and the model is trained on that framing. The output is
//  therefore **not** an 8×8 grid: it is a (8 + 2·margin) square region
//  with the playing surface inset, which is what `cellBounds(for:)`
//  exists to account for.
//
//  ## Two coordinate systems meet here
//
//  Corners arrive in **image coordinates, origin top-left** — what
//  `BoardNet` predicts and what a drag gesture produces. Core Image works
//  **origin bottom-left**. Every conversion is funnelled through
//  `flipped(_:in:)` rather than being done at call sites, because getting
//  it wrong produces a vertically-mirrored board that still looks like a
//  chess board, and the labels are then wrong in a way nothing catches.
//

import CoreGraphics
import CoreImage
import Foundation

public enum ChessBoardWarp {

    /// How far outside the playing surface the crop reaches, in squares.
    /// Must match `chess_vision.preprocess.MARGIN_SQUARES`.
    public static let marginSquares: CGFloat = 1.0

    /// The resolution `PieceNet` consumes. Must match `models/nets.py`.
    public static let pieceNetInput: CGFloat = 288

    // MARK: - Geometry

    /// Where the playing surface's corners land in the warped output.
    ///
    /// With a one-square margin the board occupies 8/10 of the output,
    /// inset by 1/10. Returned in canonical board order (a8, h8, h1, a1),
    /// origin top-left, so it pairs directly with a prediction.
    public static func outputCorners(size: CGFloat,
                                     margin: CGFloat = marginSquares) -> [CGPoint] {
        let span = 8.0 + 2.0 * margin
        let low = margin / span * size
        let high = (margin + 8.0) / span * size
        return [
            CGPoint(x: low, y: low),    // a8
            CGPoint(x: high, y: low),   // h8
            CGPoint(x: high, y: high),  // h1
            CGPoint(x: low, y: high),   // a1
        ]
    }

    /// Pixel bounds of one square's cell in the warped output.
    ///
    /// Used by the training-data exporter to label crops and by debugging
    /// overlays — never by the model, which reads the whole board at once.
    public static func cellBounds(for square: ChessSquare,
                                  size: CGFloat = pieceNetInput,
                                  margin: CGFloat = marginSquares,
                                  whiteAtBottom: Bool = true) -> CGRect {
        // Board-order corners mean the warp always puts a8 at the output's
        // top-left, so `whiteAtBottom` is true for anything coming out of
        // `warp(_:corners:)`. The parameter exists for callers laying out
        // a board for display, where orientation is a free choice.
        let row = whiteAtBottom ? 7 - square.rank : square.rank
        let column = whiteAtBottom ? square.file : 7 - square.file

        let span = 8.0 + 2.0 * margin
        let cell = size / span
        return CGRect(x: (margin + CGFloat(column)) * cell,
                      y: (margin + CGFloat(row)) * cell,
                      width: cell, height: cell)
    }

    /// Solve the 3×3 homography with `destination ~ H · source`.
    ///
    /// Direct linear transform: each correspondence contributes two rows
    /// of an 8×8 system with `h33` fixed at 1. Four non-collinear points
    /// determine it exactly, so there is no over-determined case and no
    /// need for anything fancier.
    ///
    /// Returns nil when the points are degenerate — three collinear, or
    /// duplicated — which means the caller built a board with no area.
    static func homography(from source: [CGPoint], to destination: [CGPoint]) -> [Double]? {
        guard source.count == 4, destination.count == 4 else { return nil }

        var a = [Double](repeating: 0, count: 64)
        var b = [Double](repeating: 0, count: 8)
        for i in 0..<4 {
            let x = Double(source[i].x), y = Double(source[i].y)
            let u = Double(destination[i].x), v = Double(destination[i].y)
            let r0 = 2 * i, r1 = 2 * i + 1
            a[r0 * 8 + 0] = x;  a[r0 * 8 + 1] = y;  a[r0 * 8 + 2] = 1
            a[r0 * 8 + 6] = -u * x; a[r0 * 8 + 7] = -u * y
            a[r1 * 8 + 3] = x;  a[r1 * 8 + 4] = y;  a[r1 * 8 + 5] = 1
            a[r1 * 8 + 6] = -v * x; a[r1 * 8 + 7] = -v * y
            b[r0] = u; b[r1] = v
        }

        guard var h = solve(a, b, size: 8) else { return nil }
        h.append(1.0)
        return h
    }

    /// Map a point through a homography.
    static func apply(_ h: [Double], to point: CGPoint) -> CGPoint? {
        let x = Double(point.x), y = Double(point.y)
        let w = h[6] * x + h[7] * y + h[8]
        guard abs(w) > 1e-12 else { return nil }
        return CGPoint(x: (h[0] * x + h[1] * y + h[2]) / w,
                       y: (h[3] * x + h[4] * y + h[5]) / w)
    }

    /// Gaussian elimination with partial pivoting.
    ///
    /// Eight unknowns — small enough that pulling in Accelerate for this
    /// would cost more in ceremony than it saves in cycles.
    private static func solve(_ matrix: [Double], _ rhs: [Double], size n: Int) -> [Double]? {
        var a = matrix, b = rhs
        for column in 0..<n {
            var pivot = column
            for row in (column + 1)..<n where abs(a[row * n + column]) > abs(a[pivot * n + column]) {
                pivot = row
            }
            guard abs(a[pivot * n + column]) > 1e-12 else { return nil }
            if pivot != column {
                for k in 0..<n { a.swapAt(column * n + k, pivot * n + k) }
                b.swapAt(column, pivot)
            }
            let diagonal = a[column * n + column]
            for row in (column + 1)..<n {
                let factor = a[row * n + column] / diagonal
                guard factor != 0 else { continue }
                for k in column..<n { a[row * n + k] -= factor * a[column * n + k] }
                b[row] -= factor * b[column]
            }
        }

        var solution = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var sum = b[row]
            for k in (row + 1)..<n { sum -= a[row * n + k] * solution[k] }
            solution[row] = sum / a[row * n + row]
        }
        return solution
    }

    /// Convert between top-left-origin and bottom-left-origin coordinates.
    ///
    /// The single place this flip happens. Doing it at call sites is how
    /// you end up with a vertically-mirrored board that still looks like a
    /// chess board — and labels that are wrong in a way nothing catches.
    @inline(__always)
    static func flipped(_ point: CGPoint, in height: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: height - point.y)
    }

    // MARK: - Warping

    /// Rectify the board, with headroom for standing pieces.
    ///
    /// - Parameters:
    ///   - image: the source photograph.
    ///   - corners: the playing surface's four corners in **image pixels,
    ///     origin top-left**, in board order (a8, h8, h1, a1).
    ///   - size: output edge length.
    /// - Returns: a `size × size` rectified image, or nil if the corners
    ///   are degenerate.
    public static func warp(_ image: CIImage,
                            corners: [CGPoint],
                            size: CGFloat = pieceNetInput,
                            margin: CGFloat = marginSquares) -> CIImage? {
        guard corners.count == 4 else { return nil }
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        let destination = outputCorners(size: size, margin: margin)

        // Everything below is done in Core Image's bottom-left space.
        let sourceCI = corners.map { flipped($0, in: extent.height) }
        let destinationCI = destination.map { flipped($0, in: size) }

        guard let h = homography(from: sourceCI, to: destinationCI) else { return nil }

        // `CIPerspectiveTransform` specifies where the *image's own*
        // corners go, not arbitrary points — so push the extent's corners
        // through the homography and hand those over.
        let imageCorners = [
            CGPoint(x: extent.minX, y: extent.maxY),
            CGPoint(x: extent.maxX, y: extent.maxY),
            CGPoint(x: extent.maxX, y: extent.minY),
            CGPoint(x: extent.minX, y: extent.minY),
        ]
        var mapped: [CGPoint] = []
        for corner in imageCorners {
            guard let point = apply(h, to: corner) else { return nil }
            mapped.append(point)
        }

        let filter = CIFilter(name: "CIPerspectiveTransform")
        filter?.setValue(image, forKey: kCIInputImageKey)
        filter?.setValue(CIVector(cgPoint: mapped[0]), forKey: "inputTopLeft")
        filter?.setValue(CIVector(cgPoint: mapped[1]), forKey: "inputTopRight")
        filter?.setValue(CIVector(cgPoint: mapped[2]), forKey: "inputBottomRight")
        filter?.setValue(CIVector(cgPoint: mapped[3]), forKey: "inputBottomLeft")
        guard let transformed = filter?.outputImage else { return nil }

        // Crop to the output square and rebase to the origin, so the
        // result's extent is exactly (0, 0, size, size) whatever the
        // source's was.
        return transformed
            .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
            .transformed(by: CGAffineTransform(translationX: -0, y: -0))
    }

    /// Are these four points usable as a board?
    ///
    /// Rejects the degenerate quads a drag gesture can produce — a
    /// collapsed edge, a bow-tie from crossing two corners — before they
    /// reach the solver and come back as a nil nobody can explain.
    public static func isUsableQuad(_ corners: [CGPoint], minimumArea: CGFloat = 100) -> Bool {
        guard corners.count == 4 else { return false }
        guard area(of: corners) >= minimumArea else { return false }
        return isConvex(corners)
    }

    /// Shoelace area, always positive.
    public static func area(of corners: [CGPoint]) -> CGFloat {
        var total: CGFloat = 0
        for i in 0..<corners.count {
            let a = corners[i], b = corners[(i + 1) % corners.count]
            total += a.x * b.y - b.x * a.y
        }
        return abs(total) / 2
    }

    /// A self-intersecting quad has cross products of mixed sign.
    private static func isConvex(_ corners: [CGPoint]) -> Bool {
        var sign = 0
        for i in 0..<4 {
            let a = corners[i], b = corners[(i + 1) % 4], c = corners[(i + 2) % 4]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            if abs(cross) < 1e-9 { continue }
            let current = cross > 0 ? 1 : -1
            if sign == 0 { sign = current } else if sign != current { return false }
        }
        return sign != 0
    }

    /// Four corners covering the middle of a frame — the starting handles
    /// for manual placement, so the user drags rather than taps blind.
    public static func defaultCorners(in size: CGSize, inset: CGFloat = 0.15) -> [CGPoint] {
        let x0 = size.width * inset, x1 = size.width * (1 - inset)
        let y0 = size.height * inset, y1 = size.height * (1 - inset)
        return [CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0),
                CGPoint(x: x1, y: y1), CGPoint(x: x0, y: y1)]
    }
}
