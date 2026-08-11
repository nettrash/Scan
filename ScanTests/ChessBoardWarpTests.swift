//
//  ChessBoardWarpTests.swift
//  ScanTests
//
//  The warp between the two models — Swift half of a two-language port.
//
//  `chess-vision/src/chess_vision/preprocess.py` is the reference and
//  `tests/test_preprocess.py` is its test. The values pinned here come
//  from that implementation, so a drift shows up as a failure rather than
//  as a model quietly being fed something it was never trained on.
//
//  The most valuable test is `testASynthesisedBoardWarpsBackToItsGrid`:
//  it builds a board with a marked square, warps it through the real
//  filter, and checks the mark comes back in that square's cell. That
//  closes the loop on the whole chain — homography, the top-left vs
//  bottom-left flip, the margin, and cell indexing — with an assertion
//  that cannot pass by coincidence.
//

import CoreImage
import XCTest
@testable import Scan

final class ChessBoardWarpTests: XCTestCase {

    private let size: CGFloat = 288

    // MARK: - The margin

    func testBoardIsInsetByTheMargin() {
        let corners = ChessBoardWarp.outputCorners(size: size, margin: 1.0)
        // 8 squares of board inside 10 squares of output: inset one tenth.
        XCTAssertEqual(corners[0].x, size * 0.1, accuracy: 1e-6)
        XCTAssertEqual(corners[0].y, size * 0.1, accuracy: 1e-6)
        XCTAssertEqual(corners[2].x, size * 0.9, accuracy: 1e-6)
        XCTAssertEqual(corners[2].y, size * 0.9, accuracy: 1e-6)
    }

    func testZeroMarginFillsTheOutput() {
        let corners = ChessBoardWarp.outputCorners(size: size, margin: 0)
        XCTAssertEqual(corners[0].x, 0, accuracy: 1e-6)
        XCTAssertEqual(corners[2].x, size, accuracy: 1e-6)
    }

    /// a8 is the board region's top-left cell and h1 its bottom-right —
    /// the same tiling `chess_vision.preprocess.square_cell_bounds` asserts.
    func testCellsTileTheBoardRegion() {
        let span = 8.0 + 2.0 * ChessBoardWarp.marginSquares
        let cell = size / span
        let a8 = ChessBoardWarp.cellBounds(for: ChessSquare("a8")!, size: size)
        let h1 = ChessBoardWarp.cellBounds(for: ChessSquare("h1")!, size: size)

        XCTAssertEqual(a8.minX, ChessBoardWarp.marginSquares * cell, accuracy: 1e-6)
        XCTAssertEqual(a8.minY, ChessBoardWarp.marginSquares * cell, accuracy: 1e-6)
        XCTAssertEqual(h1.maxX, (ChessBoardWarp.marginSquares + 8) * cell, accuracy: 1e-6)
        XCTAssertEqual(h1.maxY, (ChessBoardWarp.marginSquares + 8) * cell, accuracy: 1e-6)
    }

    func testCellsAreContiguous() {
        let a8 = ChessBoardWarp.cellBounds(for: ChessSquare("a8")!, size: size)
        let b8 = ChessBoardWarp.cellBounds(for: ChessSquare("b8")!, size: size)
        XCTAssertEqual(a8.maxX, b8.minX, accuracy: 1e-6, "no gap between adjacent files")
        let a7 = ChessBoardWarp.cellBounds(for: ChessSquare("a7")!, size: size)
        XCTAssertEqual(a8.maxY, a7.minY, accuracy: 1e-6, "no gap between adjacent ranks")
    }

    // MARK: - Homography

    func testHomographyMapsItsCorrespondencesExactly() {
        let source = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
                      CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        let destination = [CGPoint(x: 10, y: 20), CGPoint(x: 110, y: 5),
                           CGPoint(x: 130, y: 90), CGPoint(x: 0, y: 100)]
        let h = ChessBoardWarp.homography(from: source, to: destination)
        XCTAssertNotNil(h)
        for (from, to) in zip(source, destination) {
            let mapped = ChessBoardWarp.apply(h!, to: from)
            XCTAssertEqual(mapped!.x, to.x, accuracy: 1e-9)
            XCTAssertEqual(mapped!.y, to.y, accuracy: 1e-9)
        }
    }

    func testHomographyComposesWithItsInverse() {
        let unit = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
                    CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        let quad = [CGPoint(x: 3, y: 7), CGPoint(x: 200, y: 11),
                    CGPoint(x: 190, y: 150), CGPoint(x: -5, y: 160)]
        let forward = ChessBoardWarp.homography(from: unit, to: quad)!
        let back = ChessBoardWarp.homography(from: quad, to: unit)!

        for point in [CGPoint(x: 0.25, y: 0.5), CGPoint(x: 0.75, y: 0.125)] {
            let round = ChessBoardWarp.apply(back, to: ChessBoardWarp.apply(forward, to: point)!)!
            XCTAssertEqual(round.x, point.x, accuracy: 1e-9)
            XCTAssertEqual(round.y, point.y, accuracy: 1e-9)
        }
    }

    func testDegenerateCorrespondencesAreRejected() {
        let unit = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
                    CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        let collinear = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1),
                         CGPoint(x: 2, y: 2), CGPoint(x: 3, y: 3)]
        XCTAssertNil(ChessBoardWarp.homography(from: unit, to: collinear))
    }

    // MARK: - Quad validation

    func testUsableQuadAcceptsASensibleBoard() {
        XCTAssertTrue(ChessBoardWarp.isUsableQuad([
            CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 12),
            CGPoint(x: 115, y: 108), CGPoint(x: 8, y: 105),
        ]))
    }

    /// A drag that crosses two corners makes a bow-tie. It has area, so an
    /// area check alone passes it, and the warp then produces a folded
    /// image — hence the convexity test.
    func testUsableQuadRejectsABowTie() {
        XCTAssertFalse(ChessBoardWarp.isUsableQuad([
            CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
            CGPoint(x: 0, y: 100), CGPoint(x: 100, y: 100),
        ]))
    }

    func testUsableQuadRejectsACollapsedBoard() {
        XCTAssertFalse(ChessBoardWarp.isUsableQuad([
            CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 0),
            CGPoint(x: 3, y: 3), CGPoint(x: 0, y: 3),
        ]))
    }

    func testAreaIsOrientationIndependent() {
        let square = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0),
                      CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)]
        XCTAssertEqual(ChessBoardWarp.area(of: square), 100, accuracy: 1e-9)
        XCTAssertEqual(ChessBoardWarp.area(of: square.reversed()), 100, accuracy: 1e-9)
    }

    func testDefaultCornersAreUsable() {
        let corners = ChessBoardWarp.defaultCorners(in: CGSize(width: 400, height: 300))
        XCTAssertTrue(ChessBoardWarp.isUsableQuad(corners))
    }

    // MARK: - The round trip that matters

    /// Build a board with one marked square, warp it, and check the mark
    /// lands in that square's cell.
    ///
    /// The board is synthesised as a plain 8×8 checker with one bright
    /// cell, then placed into a larger frame under a known perspective —
    /// so the expected answer is known by construction rather than by
    /// eyeballing a photograph.
    func testASynthesisedBoardWarpsBackToItsGrid() throws {
        for name in ["a8", "h8", "a1", "h1", "d4", "f6"] {
            let target = ChessSquare(name)!
            let (image, corners) = try synthesiseBoard(marking: target)

            let warped = try XCTUnwrap(
                ChessBoardWarp.warp(image, corners: corners, size: size),
                "warp failed for \(name)"
            )

            let brightest = brightestCell(in: warped)
            XCTAssertEqual(brightest, target,
                           "mark on \(name) came back in \(brightest?.algebraic ?? "nowhere")")
        }
    }

    func testWarpRejectsDegenerateCorners() throws {
        let (image, _) = try synthesiseBoard(marking: ChessSquare("d4")!)
        let collapsed = Array(repeating: CGPoint(x: 5, y: 5), count: 4)
        XCTAssertNil(ChessBoardWarp.warp(image, corners: collapsed, size: size))
    }

    func testWarpOutputHasTheRequestedExtent() throws {
        let (image, corners) = try synthesiseBoard(marking: ChessSquare("e4")!)
        let warped = try XCTUnwrap(ChessBoardWarp.warp(image, corners: corners, size: size))
        XCTAssertEqual(warped.extent.width, size, accuracy: 1)
        XCTAssertEqual(warped.extent.height, size, accuracy: 1)
    }

    // MARK: - Helpers

    /// An 8×8 checkerboard with one cell painted bright, drawn into a
    /// larger frame under a mild perspective.
    ///
    /// Returns the image and the board's corners in **top-left-origin
    /// image coordinates**, board order — the same convention `BoardNet`
    /// emits and a drag gesture produces.
    private func synthesiseBoard(marking target: ChessSquare) throws -> (CIImage, [CGPoint]) {
        let boardSide = 256
        let cell = boardSide / 8
        var pixels = [UInt8](repeating: 0, count: boardSide * boardSide * 4)

        for row in 0..<8 {
            for column in 0..<8 {
                // Row 0 is rank 8, matching the renderer.
                let isTarget = (row == 7 - target.rank) && (column == target.file)
                let light = (row + column) % 2 == 1
                let value: UInt8 = isTarget ? 255 : (light ? 150 : 60)
                for y in (row * cell)..<((row + 1) * cell) {
                    for x in (column * cell)..<((column + 1) * cell) {
                        let offset = (y * boardSide + x) * 4
                        pixels[offset] = value
                        pixels[offset + 1] = value
                        pixels[offset + 2] = value
                        pixels[offset + 3] = 255
                    }
                }
            }
        }

        let data = Data(pixels)
        let board = CIImage(bitmapData: data,
                            bytesPerRow: boardSide * 4,
                            size: CGSize(width: boardSide, height: boardSide),
                            format: .RGBA8,
                            colorSpace: CGColorSpaceCreateDeviceRGB())

        // Place it in a bigger frame under a mild perspective: the far
        // edge narrower than the near one, which is what elevation does.
        let frame: CGFloat = 400
        let cornersTopLeft = [
            CGPoint(x: 90, y: 70),    // a8 far-left
            CGPoint(x: 310, y: 74),   // h8 far-right
            CGPoint(x: 350, y: 330),  // h1 near-right
            CGPoint(x: 55, y: 322),   // a1 near-left
        ]

        // Project the board into the frame. Core Image is bottom-left, and
        // the source is the image's own corners here, so this is the plain
        // forward case.
        let toCI = { (p: CGPoint) in ChessBoardWarp.flipped(p, in: frame) }
        let filter = CIFilter(name: "CIPerspectiveTransform")
        filter?.setValue(board, forKey: kCIInputImageKey)
        filter?.setValue(CIVector(cgPoint: toCI(cornersTopLeft[0])), forKey: "inputTopLeft")
        filter?.setValue(CIVector(cgPoint: toCI(cornersTopLeft[1])), forKey: "inputTopRight")
        filter?.setValue(CIVector(cgPoint: toCI(cornersTopLeft[2])), forKey: "inputBottomRight")
        filter?.setValue(CIVector(cgPoint: toCI(cornersTopLeft[3])), forKey: "inputBottomLeft")

        let placed = try XCTUnwrap(filter?.outputImage)
        let scene = placed.composited(over: CIImage(color: .black))
            .cropped(to: CGRect(x: 0, y: 0, width: frame, height: frame))
        return (scene, cornersTopLeft)
    }

    /// Which square's cell holds the brightest content.
    private func brightestCell(in warped: CIImage) -> ChessSquare? {
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        let width = Int(size), height = Int(size)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            context.render(warped,
                           toBitmap: buffer.baseAddress!,
                           rowBytes: width * 4,
                           bounds: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)),
                           format: .RGBA8,
                           colorSpace: CGColorSpaceCreateDeviceRGB())
        }

        var best: ChessSquare?
        var bestMean: Double = -1
        for index in 0..<64 {
            let square = ChessSquare(index: index)
            let bounds = ChessBoardWarp.cellBounds(for: square, size: size).insetBy(dx: 4, dy: 4)
            var total = 0.0
            var count = 0
            // Core Image rendered top-down here, so the bitmap's row 0 is
            // the output's y = 0.
            for y in Int(bounds.minY)..<Int(bounds.maxY) {
                for x in Int(bounds.minX)..<Int(bounds.maxX) {
                    guard x >= 0, y >= 0, x < width, y < height else { continue }
                    total += Double(pixels[(y * width + x) * 4])
                    count += 1
                }
            }
            guard count > 0 else { continue }
            let mean = total / Double(count)
            if mean > bestMean { bestMean = mean; best = square }
        }
        return best
    }
}
