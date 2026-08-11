//
//  ChessTrainingExport.swift
//  Scan
//
//  Saving a rectified board plus its true position, as fine-tuning data.
//
//  ## Why the app collects its own training data
//
//  `chess-vision` trains on synthetic boards, and its model card is
//  explicit about where that distribution falls short: procedural piece
//  silhouettes rather than real sets, no cast shadows between pieces,
//  blob occluders rather than hands. Closing those gaps needs real
//  photographs of real boards — and the most valuable ones are the ones
//  taken with *this* camera, through *this* warp, because that is exactly
//  the distribution the model meets at inference.
//
//  The chicken-and-egg is broken by manual corner placement: the user
//  supplies what `BoardNet` would, the warp runs, and the position they
//  name in the editor is the label. No model required to produce data for
//  training the model.
//
//  ## What is written
//
//  Into `Documents/ChessTraining/`, retrievable over USB or via the Files
//  app (`UIFileSharingEnabled` is already set for the scanner's exports):
//
//      <timestamp>-<fen>.jpg     the warped 288×288 board
//      <timestamp>-<fen>.json    labels + provenance
//
//  The FEN is in the filename as well as the JSON so a directory listing
//  is browsable and a mislabelled sample can be spotted and deleted
//  without opening anything.
//
//  ## This is off by default and hidden
//
//  It exists to build a training set, not for users. Whether it is on is
//  the *caller's* decision — `ChessScreenModel` reads
//  `ScanSettingsKey.chessExportTrainingSquares` — deliberately not this
//  type's, so `Scan/Chess/` stays free of app settings and keeps
//  compiling outside Xcode for `Tools/run-perft.sh`.
//

import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ChessTrainingExport {

    /// Where samples land. Created on first write.
    public static var directory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory,
                                                 in: .userDomainMask)[0]
        return documents.appendingPathComponent("ChessTraining", isDirectory: true)
    }

    /// How the corners for this sample were obtained. Recorded because a
    /// hand-placed corner and a predicted one have very different error
    /// characteristics, and a fine-tune wants to know which it is looking
    /// at.
    public enum CornerSource: String, Codable {
        case manual
        case predicted
        case predictedThenAdjusted
    }

    public struct Sample: Codable {
        /// 64 class labels in LERF order, a1 first — the same scheme the
        /// models are trained against (`0` empty, else `1 + piece index`).
        public var labels: [Int]
        public var placementFEN: String
        /// Board corners in source-image pixels, board order, so the
        /// original photograph can be re-warped later with a different
        /// margin if the pipeline changes.
        public var corners: [[Double]]
        public var cornerSource: CornerSource
        /// Pixel size of the source photograph.
        public var sourceSize: [Int]
        public var capturedAt: Date
        public var appVersion: String
    }

    public enum ExportError: Error {
        case renderFailed
        case encodeFailed
    }

    /// Write one sample. Returns the JPEG's URL.
    ///
    /// - Parameters:
    ///   - warped: the rectified board, as produced by `ChessBoardWarp`.
    ///   - position: the position the user confirmed — the label.
    ///   - corners: the corners used, in source-image pixels.
    @discardableResult
    public static func write(warped: CIImage,
                             position: ChessPosition,
                             corners: [CGPoint],
                             cornerSource: CornerSource,
                             sourceSize: CGSize,
                             context: CIContext = CIContext()) throws -> URL {
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)

        guard let cgImage = context.createCGImage(warped, from: warped.extent) else {
            throw ExportError.renderFailed
        }
        // Encoded through ImageIO rather than `UIImage.jpegData`, so this
        // file needs no UIKit. That is not fussiness: `Scan/Chess/` is
        // compiled outside Xcode by `Tools/run-perft.sh`, where UIKit does
        // not exist, and a stray import there breaks the perft gate.
        //
        // Quality 95 rather than lossless: the model sees camera JPEGs at
        // inference, so training on perfect crops would be a small domain
        // mismatch in the wrong direction.
        let jpegData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            jpegData, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw ExportError.encodeFailed
        }
        CGImageDestinationAddImage(destination, cgImage, [
            kCGImageDestinationLossyCompressionQuality: 0.95,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.encodeFailed
        }
        let jpeg = jpegData as Data

        let fen = position.placementFEN
        let stem = "\(Int(Date().timeIntervalSince1970))-\(fen.replacingOccurrences(of: "/", with: "-"))"

        let sample = Sample(
            labels: position.placement.map { $0.map { ChessSquareLabel.label(for: $0) } ?? 0 },
            placementFEN: fen,
            corners: corners.map { [Double($0.x), Double($0.y)] },
            cornerSource: cornerSource,
            sourceSize: [Int(sourceSize.width), Int(sourceSize.height)],
            capturedAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let imageURL = directory.appendingPathComponent("\(stem).jpg")
        try jpeg.write(to: imageURL)
        try encoder.encode(sample).write(to: directory.appendingPathComponent("\(stem).json"))
        return imageURL
    }

    /// How many samples have been collected. Shown in the debug UI so the
    /// count toward a usable fine-tune set is visible.
    public static var sampleCount: Int {
        (try? FileManager.default.contentsOfDirectory(at: directory,
                                                      includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" }.count ?? 0
    }

    /// Delete everything collected so far.
    public static func removeAll() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }
}
