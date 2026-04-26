//
//  CodeGenerator.swift
//  Scan
//
//  Renders 1D / 2D codes from a string using Core Image's built-in
//  generator filters. No third-party dependencies.
//

import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Symbologies the app can *generate*. Strictly a subset of the symbologies
/// it can *scan* — limited to what Core Image ships natively.
enum GeneratableSymbology: String, CaseIterable, Identifiable {
    case qr      = "QR"
    case aztec   = "Aztec"
    case pdf417  = "PDF417"
    case code128 = "Code 128"

    var id: String { rawValue }

    var is2D: Bool { self != .code128 }

    /// Soft hint for the UI. Code 128 is a 1D byte-mode code with limited
    /// capacity; the 2D codes can hold large multi-line payloads.
    var maxRecommendedLength: Int {
        switch self {
        case .qr, .aztec, .pdf417: return 2048
        case .code128:             return 80
        }
    }
}

enum CodeGenerator {

    /// Render `content` into a sharp, integer-scaled UIImage.
    /// - Parameter scale: how many pixels each module / unit occupies.
    /// - Returns: nil if Core Image couldn't encode the content for the
    ///   selected symbology (e.g. content too long for Code 128).
    static func image(for content: String,
                      symbology: GeneratableSymbology,
                      scale: CGFloat = 10) -> UIImage? {
        guard !content.isEmpty else { return nil }
        // Try ISO Latin-1 first (Core Image's barcode filters expect a single-
        // byte encoding for Code 128, and accept UTF-8 bytes for the 2D codes).
        let data = content.data(using: .utf8) ?? Data()
        guard !data.isEmpty else { return nil }

        let outputImage: CIImage?
        switch symbology {
        case .qr:
            let f = CIFilter.qrCodeGenerator()
            f.message = data
            // M (~15% recovery) is the sweet spot for size vs. resilience.
            f.correctionLevel = "M"
            outputImage = f.outputImage

        case .aztec:
            let f = CIFilter.aztecCodeGenerator()
            f.message = data
            outputImage = f.outputImage

        case .pdf417:
            let f = CIFilter.pdf417BarcodeGenerator()
            f.message = data
            outputImage = f.outputImage

        case .code128:
            let f = CIFilter.code128BarcodeGenerator()
            f.message = data
            f.quietSpace = 7
            outputImage = f.outputImage
        }

        guard let raw = outputImage else { return nil }

        // Crisp scaling: integer scaleX/scaleY before rasterising avoids
        // blurry edges typical of barcode previews.
        let scaled = raw.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
