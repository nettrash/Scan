//
//  ChessTrainingExportTests.swift
//  ScanTests
//
//  Writing a rectified board plus its position as a fine-tuning sample.
//
//  This is the path that breaks the chicken-and-egg: with corners placed
//  by hand, the app can produce labelled training data before either model
//  exists. Which means a bug here does not show up as a crash — it shows
//  up months later as a training set that cannot be used, so the parts
//  worth pinning are the ones a reader would otherwise have to trust: that
//  the labels round-trip to the same position, that the JSON schema is
//  what `chess-vision` expects, and that the files are actually on disk.
//

import CoreImage
import XCTest
@testable import Scan

final class ChessTrainingExportTests: XCTestCase {

    override func setUp() {
        super.setUp()
        try? ChessTrainingExport.removeAll()
    }

    override func tearDown() {
        try? ChessTrainingExport.removeAll()
        super.tearDown()
    }

    /// A stand-in for a warped board — the content does not matter here,
    /// only that a real CIImage renders and encodes.
    private var board: CIImage {
        CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 288, height: 288))
    }

    private let corners = [
        CGPoint(x: 184, y: 271), CGPoint(x: 783, y: 282),
        CGPoint(x: 864, y: 772), CGPoint(x: 160, y: 750),
    ]

    func testWritingASampleProducesAnImageAndItsLabels() throws {
        let url = try ChessTrainingExport.write(
            warped: board,
            position: .standard,
            corners: corners,
            cornerSource: .manual,
            sourceSize: CGSize(width: 1024, height: 1024)
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let json = url.deletingPathExtension().appendingPathExtension("json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: json.path))
        XCTAssertEqual(ChessTrainingExport.sampleCount, 1)
    }

    /// The labels must reconstruct the exact position they were made from.
    /// This is the whole value of a sample; if it does not hold, the set
    /// is training the model on the wrong answer.
    func testLabelsRoundTripToTheSamePosition() throws {
        let original = ChessPosition(
            fen: "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
        )!
        let url = try ChessTrainingExport.write(
            warped: board, position: original, corners: corners,
            cornerSource: .manual, sourceSize: CGSize(width: 800, height: 600)
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: url.deletingPathExtension()
            .appendingPathExtension("json"))
        let sample = try decoder.decode(ChessTrainingExport.Sample.self, from: data)

        XCTAssertEqual(sample.labels.count, 64)
        XCTAssertEqual(sample.placementFEN, original.placementFEN)

        // Rebuild the board from the labels alone and compare.
        let rebuilt = ChessPosition(placement: sample.labels.map { ChessSquareLabel.piece($0) })
        XCTAssertEqual(rebuilt.placementFEN, original.placementFEN)
    }

    /// The label scheme is the contract with `chess-vision`: `0` empty,
    /// otherwise `1 + ChessPiece.index`. A silent change here would be
    /// discovered only after a training run.
    func testLabelSchemeMatchesTheModels() throws {
        let url = try ChessTrainingExport.write(
            warped: board, position: .standard, corners: corners,
            cornerSource: .manual, sourceSize: .zero
        )
        let data = try Data(contentsOf: url.deletingPathExtension()
            .appendingPathExtension("json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sample = try decoder.decode(ChessTrainingExport.Sample.self, from: data)

        // a1 is a white rook: colour 0, kind rook (3) -> index 3 -> label 4.
        XCTAssertEqual(sample.labels[ChessSquare.a1.index], 4)
        // e8 is a black king: colour 1, kind king -> index 11 -> label 12.
        XCTAssertEqual(sample.labels[ChessSquare.e8.index], 12)
        // e4 is empty.
        XCTAssertEqual(sample.labels[ChessSquare("e4")!.index], 0)
    }

    /// Corners are kept in *source-image* pixels so the original can be
    /// re-warped later with a different margin if the pipeline changes.
    func testCornersAndProvenanceAreRecorded() throws {
        let url = try ChessTrainingExport.write(
            warped: board, position: .standard, corners: corners,
            cornerSource: .predictedThenAdjusted,
            sourceSize: CGSize(width: 1024, height: 768)
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sample = try decoder.decode(
            ChessTrainingExport.Sample.self,
            from: Data(contentsOf: url.deletingPathExtension().appendingPathExtension("json"))
        )

        XCTAssertEqual(sample.corners.count, 4)
        XCTAssertEqual(sample.corners[0][0], 184, accuracy: 0.001)
        XCTAssertEqual(sample.cornerSource, .predictedThenAdjusted)
        XCTAssertEqual(sample.sourceSize, [1024, 768])
    }

    /// The FEN is in the filename so a directory listing is browsable and
    /// a mislabelled sample can be spotted without opening anything. The
    /// slashes have to go — they are path separators.
    func testFilenameCarriesTheFENWithoutSlashes() throws {
        let url = try ChessTrainingExport.write(
            warped: board, position: .standard, corners: corners,
            cornerSource: .manual, sourceSize: .zero
        )
        let name = url.lastPathComponent
        XCTAssertTrue(name.contains("rnbqkbnr-pppppppp"), name)
        XCTAssertFalse(name.contains("/"))
    }

    func testSamplesAccumulate() throws {
        for _ in 0..<3 {
            _ = try ChessTrainingExport.write(
                warped: board, position: .standard, corners: corners,
                cornerSource: .manual, sourceSize: .zero
            )
            // The stem is second-resolution, so distinct writes need a gap
            // or they overwrite — which is itself worth knowing about.
            Thread.sleep(forTimeInterval: 1.05)
        }
        XCTAssertEqual(ChessTrainingExport.sampleCount, 3)
    }

    func testRemoveAllClearsTheDirectory() throws {
        _ = try ChessTrainingExport.write(
            warped: board, position: .standard, corners: corners,
            cornerSource: .manual, sourceSize: .zero
        )
        XCTAssertEqual(ChessTrainingExport.sampleCount, 1)
        try ChessTrainingExport.removeAll()
        XCTAssertEqual(ChessTrainingExport.sampleCount, 0)
    }
}
