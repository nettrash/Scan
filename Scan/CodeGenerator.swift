//
//  CodeGenerator.swift
//  Scan
//
//  Renders 1D / 2D codes from a string using Core Image's built-in
//  generator filters. No third-party dependencies.
//
//  As of 1.3 the renderer also takes foreground / background colours
//  and an optional centred logo image. Colours are applied via the
//  `CIFalseColor` filter (which maps black→color0 and white→color1
//  on the unscaled module bitmap), and the logo is composited on top
//  of the rasterised UIImage with a white punched-out background so
//  the QR error-correction bits below it stay correctable.
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

    /// Whether logo embedding is meaningful for this symbology. Logo
    /// embedding only really makes sense on QR (where Reed-Solomon
    /// recovery makes 22 % occlusion safe). The other codes either
    /// have no recovery (1D) or store data densely enough that a
    /// centred image would corrupt the payload.
    var supportsLogo: Bool { self == .qr }
}

/// QR error-correction levels exposed to the UI. The Core Image
/// generator takes these as one-letter strings.
enum QRErrorCorrection: String, CaseIterable, Identifiable {
    case low      = "L"     // ~7 % recovery
    case medium   = "M"     // ~15 %
    case quartile = "Q"     // ~25 %
    case high     = "H"     // ~30 %

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .low:      return "Low (7%)"
        case .medium:   return "Medium (15%)"
        case .quartile: return "Quartile (25%)"
        case .high:     return "High (30%)"
        }
    }
}

enum CodeGenerator {

    /// Render `content` into a sharp, integer-scaled UIImage with
    /// custom colours and an optional centred logo.
    ///
    /// - Parameters:
    ///   - scale: how many pixels each module / unit occupies.
    ///   - foreground: drawn in place of the "on" modules.
    ///   - background: drawn in place of the "off" modules.
    ///   - errorCorrection: QR-only. Ignored for non-QR symbologies.
    ///     Forced to `.high` whenever a logo is supplied (callers
    ///     don't have to know to do that).
    ///   - logo: optional image painted in the centre at ~22 % of the
    ///     QR canvas, with a white rounded background. Has no effect
    ///     on non-QR symbologies.
    /// - Returns: nil if Core Image couldn't encode the content for
    ///   the selected symbology (e.g. content too long for Code 128).
    static func image(
        for content: String,
        symbology: GeneratableSymbology,
        scale: CGFloat = 10,
        foreground: UIColor = .black,
        background: UIColor = .white,
        errorCorrection: QRErrorCorrection = .medium,
        logo: UIImage? = nil
    ) -> UIImage? {
        guard !content.isEmpty else { return nil }
        // Core Image's barcode filters accept UTF-8 bytes for the 2D
        // codes and fall back to ISO Latin-1 for Code 128 internally.
        let data = content.data(using: .utf8) ?? Data()
        guard !data.isEmpty else { return nil }

        // If a logo is requested, force max error-correction for QR.
        // Logo callers wouldn't typically pass H themselves and Q+L
        // can't recover from a 22 %-area occlusion.
        let effectiveCorrection: QRErrorCorrection =
            (symbology == .qr && logo != nil) ? .high : errorCorrection

        let outputImage: CIImage?
        switch symbology {
        case .qr:
            let f = CIFilter.qrCodeGenerator()
            f.message = data
            f.correctionLevel = effectiveCorrection.rawValue
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

        guard var coloured = outputImage else { return nil }

        // Recolour: CIFalseColor maps black → color0 and white → color1
        // on the module bitmap. This keeps the output crisp because
        // it's applied *before* we rasterise — pixel values remain
        // pure FG or pure BG, never antialiased greys.
        let recolour = CIFilter.falseColor()
        recolour.inputImage = coloured
        recolour.color0 = CIColor(color: foreground)
        recolour.color1 = CIColor(color: background)
        if let recoloured = recolour.outputImage {
            coloured = recoloured
        }

        // Crisp scaling: integer scaleX/scaleY before rasterising avoids
        // blurry edges typical of barcode previews.
        let scaled = coloured.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        let baseImage = UIImage(cgImage: cg)

        // No logo, no further work. Most generated codes don't have one.
        guard symbology.supportsLogo, let logo = logo else { return baseImage }
        return composite(logo: logo, on: baseImage, background: background)
    }

    // MARK: - Module matrix introspection

    /// One "on" / "off" bit per module of the underlying QR symbol.
    /// Computed by rasterising the *unscaled* CIQRCodeGenerator output
    /// (where each pixel is exactly one module) and reading the
    /// luminance back out. Used by `QRSvg` to emit a vector
    /// representation that's truly module-faithful, rather than
    /// re-tracing edges of a rasterised PNG.
    static func qrModuleMatrix(
        for content: String,
        errorCorrection: QRErrorCorrection = .medium
    ) -> ModuleMatrix? {
        let data = content.data(using: .utf8) ?? Data()
        guard !data.isEmpty else { return nil }

        let f = CIFilter.qrCodeGenerator()
        f.message = data
        f.correctionLevel = errorCorrection.rawValue
        guard let raw = f.outputImage else { return nil }

        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cg = context.createCGImage(raw, from: raw.extent) else { return nil }
        let w = cg.width
        let h = cg.height

        // Pull the raw bytes into a tight RGBA buffer; one byte per
        // channel. We only inspect the red channel — black modules
        // come back as 0 and white as 255.
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var bits = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let r = pixels[(y * w + x) * 4]
                bits[y * w + x] = r < 128 // black = on
            }
        }
        return ModuleMatrix(width: w, height: h, bits: bits)
    }

    struct ModuleMatrix {
        let width: Int
        let height: Int
        let bits: [Bool]
        @inlinable subscript(x: Int, y: Int) -> Bool {
            bits[y * width + x]
        }
    }

    // MARK: - Logo compositing

    /// Paint a white rounded "punch" behind the logo, then the logo on
    /// top. The "punch" overrides any background colour the user picked
    /// — at 22 % linear / ~5 % area we want the highest contrast
    /// possible against whatever's around, and forcing white keeps us
    /// honest about the scanability promise. If the user's background
    /// is white anyway, the punch is invisible.
    private static func composite(
        logo: UIImage,
        on base: UIImage,
        background: UIColor
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: base.size, format: format)

        return renderer.image { ctx in
            base.draw(at: .zero)

            // Logo rect: 22 % of the smaller side, centred.
            let logoSide = min(base.size.width, base.size.height) * 0.22
            let logoRect = CGRect(
                x: (base.size.width  - logoSide) / 2,
                y: (base.size.height - logoSide) / 2,
                width: logoSide, height: logoSide
            )

            // Punch background: 6 % padding around the logo, white,
            // rounded for less visual noise.
            let punchInset: CGFloat = -logoSide * 0.06
            let punch = logoRect.insetBy(dx: punchInset, dy: punchInset)
            let punchPath = UIBezierPath(roundedRect: punch, cornerRadius: punch.width * 0.18)
            UIColor.white.setFill()
            punchPath.fill()

            // Aspect-fit the logo inside its rect, preserving the
            // user's image proportions.
            drawAspectFit(image: logo, in: logoRect, context: ctx.cgContext)
        }
    }

    private static func drawAspectFit(image: UIImage, in rect: CGRect, context: CGContext) {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
        let drawRect = CGRect(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2,
            width: drawSize.width, height: drawSize.height
        )
        image.draw(in: drawRect)
    }
}

// MARK: - UIColor → CIColor convenience

private extension CIColor {
    /// Mirrors `CIColor(color:)` but tolerates colours expressed in
    /// non-RGB colour spaces (e.g. SwiftUI's display-P3 picker output)
    /// — the bare initialiser would fail there. Falls back to opaque
    /// black on extraction failure rather than returning nil so the
    /// pipeline doesn't have to thread an `Optional<CIColor>`.
    convenience init(color: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if color.getRed(&r, green: &g, blue: &b, alpha: &a) {
            self.init(red: r, green: g, blue: b, alpha: a)
        } else {
            self.init(red: 0, green: 0, blue: 0, alpha: 1)
        }
    }
}
