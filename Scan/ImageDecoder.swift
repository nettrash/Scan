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
import PDFKit

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
    /// document picker. Auto-detects PDFs by file extension and routes
    /// through `decode(pdfData:)` so multi-page boarding-pass /
    /// receipt PDFs don't fail the image-load path.
    static func decode(url: URL) async throws -> [ScannedCode] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DecodeError.loadFailed
        }
        if url.pathExtension.lowercased() == "pdf" {
            return try await decode(pdfData: data)
        }
        return try await decode(data: data)
    }

    /// Decode every page of a PDF. Each page is rasterised at 2× the
    /// page's natural point size before going through Vision —
    /// high-density-sized QR / Aztec inside boarding passes and
    /// receipts only resolve cleanly above the 1× threshold. Results
    /// are flattened across pages and de-duplicated on `value` so a
    /// repeated barcode (header / footer markers in some receipts)
    /// doesn't show up twice.
    static func decode(pdfData data: Data) async throws -> [ScannedCode] {
        guard let document = PDFDocument(data: data) else {
            throw DecodeError.loadFailed
        }
        var seen = Set<String>()
        var codes: [ScannedCode] = []
        for index in 0 ..< document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let pageRect = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2
            let renderSize = CGSize(width: pageRect.width * scale,
                                    height: pageRect.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)
            let image = renderer.image { ctx in
                // PDFKit pages are drawn from the current PDF
                // coordinate space (origin bottom-left, +y up). Flip
                // to UIKit's top-down before drawing the page.
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: renderSize))
                ctx.cgContext.translateBy(x: 0, y: renderSize.height)
                ctx.cgContext.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }
            let pageCodes = (try? await decode(image)) ?? []
            for code in pageCodes where seen.insert(code.value).inserted {
                codes.append(code)
            }
        }
        if codes.isEmpty {
            throw DecodeError.noBarcodeFound
        }
        return codes
    }

    /// Decode a list of file URLs (mixed images + PDFs) and aggregate.
    /// Failures on individual entries are swallowed so one bad input
    /// doesn't poison the whole batch — the caller sees at most one
    /// `DecodeError.noBarcodeFound` if nothing was readable across
    /// the whole list.
    static func decodeBatch(urls: [URL]) async throws -> [ScannedCode] {
        var seen = Set<String>()
        var codes: [ScannedCode] = []
        for url in urls {
            let partial = (try? await decode(url: url)) ?? []
            for code in partial where seen.insert(code.value).inserted {
                codes.append(code)
            }
        }
        if codes.isEmpty {
            throw DecodeError.noBarcodeFound
        }
        return codes
    }

    /// Decode an in-memory list of (Data, isPdf) tuples — the form
    /// the Share Extension hands us via `NSItemProvider`. Mirrors
    /// `decodeBatch(urls:)` but skips the file-system round-trip,
    /// which extensions are heavily memory-rate-limited on (iOS
    /// hard-caps share extensions at 120 MB on most devices).
    static func decodeBatch(items: [(data: Data, isPdf: Bool)]) async throws -> [ScannedCode] {
        var seen = Set<String>()
        var codes: [ScannedCode] = []
        for item in items {
            let partial = (try? await (item.isPdf
                ? decode(pdfData: item.data)
                : decode(data: item.data))) ?? []
            for code in partial where seen.insert(code.value).inserted {
                codes.append(code)
            }
        }
        if codes.isEmpty {
            throw DecodeError.noBarcodeFound
        }
        return codes
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
                        timestamp: Date(),
                        previewRect: nil
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
