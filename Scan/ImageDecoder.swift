//
//  ImageDecoder.swift
//  Scan
//
//  Decodes 1D / 2D barcodes from a still image using Vision's
//  VNDetectBarcodesRequest. Used for the "import from photo library /
//  files" flow alongside live AVFoundation capture.
//

import Foundation
import Vision
import UIKit

enum ImageDecoder {

    enum DecodeError: LocalizedError {
        case loadFailed
        case noBarcodeFound
        case visionFailed(Error)

        var errorDescription: String? {
            switch self {
            case .loadFailed:        return "Couldn't read that file as an image."
            case .noBarcodeFound:    return "No barcodes were found in that image."
            case .visionFailed(let e): return "Couldn't analyze the image: \(e.localizedDescription)"
            }
        }
    }

    /// Decode every barcode Vision can find in a UIImage.
    static func decode(_ image: UIImage) async throws -> [ScannedCode] {
        guard let cgImage = image.cgImage ?? ciImageBacking(image)?.cgImageRepresentation() else {
            throw DecodeError.loadFailed
        }
        return try await runVision(on: cgImage, orientation: cgOrientation(from: image.imageOrientation))
    }

    /// Decode from raw image data (e.g. a Photos picker result).
    static func decode(data: Data) async throws -> [ScannedCode] {
        guard let image = UIImage(data: data) else {
            throw DecodeError.loadFailed
        }
        return try await decode(image)
    }

    /// Decode from a file URL, handling security-scoped resources from the
    /// document picker.
    static func decode(url: URL) async throws -> [ScannedCode] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DecodeError.loadFailed
        }
        return try await decode(data: data)
    }

    // MARK: - Internals

    private static func runVision(on cgImage: CGImage,
                                  orientation: CGImagePropertyOrientation) async throws -> [ScannedCode] {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                // Use Vision's default symbology set — it already covers
                // every barcode type the running OS supports.
                let request = VNDetectBarcodesRequest()

                let handler = VNImageRequestHandler(cgImage: cgImage,
                                                    orientation: orientation,
                                                    options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    cont.resume(throwing: DecodeError.visionFailed(error))
                    return
                }

                let results = request.results ?? []
                let codes: [ScannedCode] = results.compactMap { obs in
                    guard let value = obs.payloadStringValue, !value.isEmpty else { return nil }
                    return ScannedCode(
                        value: value,
                        symbology: Symbology(visionSymbology: obs.symbology),
                        avType: obs.symbology.rawValue,
                        timestamp: Date()
                    )
                }

                if codes.isEmpty {
                    cont.resume(throwing: DecodeError.noBarcodeFound)
                } else {
                    cont.resume(returning: codes)
                }
            }
        }
    }

    private static func cgOrientation(from ui: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch ui {
        case .up:            return .up
        case .upMirrored:    return .upMirrored
        case .down:          return .down
        case .downMirrored:  return .downMirrored
        case .left:          return .left
        case .leftMirrored:  return .leftMirrored
        case .right:         return .right
        case .rightMirrored: return .rightMirrored
        @unknown default:    return .up
        }
    }

    /// Fall back through CIImage if the UIImage didn't expose a CGImage
    /// directly (e.g. CIImage-backed images).
    private static func ciImageBacking(_ image: UIImage) -> CIImage? {
        image.ciImage
    }
}

private extension CIImage {
    /// Render this CIImage to a CGImage using a default context. Returns
    /// nil on failure.
    func cgImageRepresentation() -> CGImage? {
        let context = CIContext(options: nil)
        return context.createCGImage(self, from: extent)
    }
}
