//
//  QRStyle.swift
//  Scan
//
//  The QR art studio (1.10): module shape, finder-eye shape, gradient inks
//  and a preset library, drawn from the same `CodeGenerator.ModuleMatrix`
//  the PNG / SVG / PDF exports already consume.
//
//  Everything is drawn by hand from the module grid instead of asking Core
//  Image for a picture, because rounded modules, leaf corners and ring eyes
//  are vector decisions. One grid in, one set of paths out
//  (`QRGeometry.passes`), and every renderer — the preview / PNG here, the
//  SVG and the PDF in `QRSvg` — draws those same paths, so the outputs
//  cannot drift apart. The Android port (`generator/QRStyle.kt`) follows the
//  same three-pass recipe.
//
//  Rules that keep a "designer" code scannable, enforced here rather than
//  trusted to the user:
//
//    * Core Image's own one-module border is trimmed and a quiet zone of at
//      least 4 modules — the ISO/IEC 18004 minimum — is drawn instead;
//    * a finder eye is always three concentric shapes inscribed in the
//      7-, 5- and 3-module squares — ring, gap, centre — so a scan line
//      through its middle still reads dark-light-dark-light-dark at
//      1:1:3:1:1, which is what a reader locks onto. Only the three finder
//      squares are re-shaped: timing and alignment patterns stay ordinary
//      modules;
//    * non-square modules, non-square eyes or inset artwork raise the
//      error correction to High to pay back the module area they cost;
//    * the centre artwork is sized off the symbol, not the canvas, and
//      clears whole modules only — about 6 % of the symbol at most, well
//      inside what High error correction rebuilds.
//

import UIKit

// MARK: - Style

/// One studio look: shapes plus inks. A single ink is a flat fill; two or
/// more are a diagonal wash across the whole symbol.
struct QRStyle: Equatable {

    enum ModuleShape: String, CaseIterable, Identifiable {
        case square, rounded, dot, leaf, bars
        var id: String { rawValue }
        var label: String {
            switch self {
            case .square:  return "Square"
            case .rounded: return "Rounded"
            case .dot:     return "Dots"
            case .leaf:    return "Leaves"
            case .bars:    return "Bars"
            }
        }
        /// Non-square modules trade module area for looks.
        var needsExtraRedundancy: Bool { self != .square }
    }

    enum EyeShape: String, CaseIterable, Identifiable {
        case square, rounded, circle, ring
        var id: String { rawValue }
        var label: String {
            switch self {
            case .square:  return "Square"
            case .rounded: return "Rounded"
            case .circle:  return "Circle"
            case .ring:    return "Ring"
            }
        }
    }

    var moduleShape: ModuleShape = .square
    var eyeShape: EyeShape = .square
    /// One ink = flat fill; two or more = a diagonal gradient across the code.
    var inks: [UIColor] = [.black]
    var background: UIColor = .white
    /// Requested margin, in modules. Renderers draw `effectiveQuietZone`.
    var quietZone: Int = 4
    /// Artwork over the centre. Any logo at all makes the style non-plain:
    /// only the studio renderer knows how to clear modules for it.
    var logo: UIImage?

    static let standard = QRStyle()

    /// Nothing for the studio renderer to do: the plain Core Image path
    /// draws this exactly as it always has, byte for byte.
    var isPlain: Bool {
        moduleShape == .square && eyeShape == .square && inks.count <= 1 && logo == nil
    }

    var usesGradient: Bool { inks.count > 1 }

    var primaryInk: UIColor { inks.first ?? .black }

    /// The margin every renderer actually draws: clamped, never asked. A
    /// code a reader cannot find is worse than one the user did not fully
    /// customise.
    var effectiveQuietZone: Int { max(quietZone, 4) }

    /// Error-correction level a matrix should be generated at for this
    /// style. A gradient alone does not raise it: what a wash costs is
    /// contrast, and the generator's contrast check measures every ink.
    var minimumErrorCorrection: QRErrorCorrection {
        (logo != nil || moduleShape.needsExtraRedundancy || eyeShape != .square) ? .high : .medium
    }

    /// The level to encode at: the user's pick, raised — never lowered — to
    /// High when this style needs it. Mirrors the Android port's
    /// `CodeGenerator.effectiveErrorCorrection`.
    func errorCorrection(raising requested: QRErrorCorrection) -> QRErrorCorrection {
        minimumErrorCorrection == .high ? .high : requested
    }

    /// Symbol sides (in modules) from which shaped modules stop scanning
    /// reliably. A shaped module keeps less of its square's area, which
    /// leaves a reader less margin, and a logo spends part of the error
    /// correction that margin relies on. Measured with Apple's own reader
    /// (Vision, what Scan's photo and file import uses) on rendered codes:
    ///
    ///   * dots keep under half of it: without a logo, coloured dots start
    ///     failing around version 18–20 and black ones by version 24–26; with
    ///     a logo, coloured dots fail from version 11 and black ones from 14;
    ///   * rounded, leaf and bar modules — Soft, Ink and Nature among the
    ///     presets — read through version 25 without a logo, but with one
    ///     they fail from version 13 to 20, depending on the artwork;
    ///   * square modules read through version 25 with or without a logo,
    ///     and the eye shape makes no difference.
    ///
    /// Each threshold sits a version or two below the first failures:
    /// version 16 (81 modules) for dots, version 10 (57 modules) for dots
    /// with a logo and version 12 (65 modules) for the other shapes with a
    /// logo. Not covered: artwork darker than a coloured ink — Sunset's dots
    /// with a dark logo already fail at versions 7–9.
    static let denseDotSymbolSide = 81
    static let denseDotWithLogoSymbolSide = 57
    static let nonSquareWithLogoSymbolSide = 65

    /// Whether a code of `symbolSide` modules is too dense for this style's
    /// modules to scan reliably — the generator says so rather than letting
    /// the user print it. Same rule and thresholds as the Android port's
    /// `QRStyle.isHardToScan`, so both warn on the same codes.
    func isHardToScan(symbolSide: Int) -> Bool {
        switch moduleShape {
        case .square:
            return false
        case .dot:
            return symbolSide >= (logo == nil ? Self.denseDotSymbolSide : Self.denseDotWithLogoSymbolSide)
        case .rounded, .leaf, .bars:
            return logo != nil && symbolSide >= Self.nonSquareWithLogoSymbolSide
        }
    }

    /// What the generator says under the preview when the code is hard to
    /// scan; nil when it isn't. With a logo, from version 12 up every shaped
    /// module is past its threshold, so the advice narrows to square modules
    /// or no logo. Same words as the Android port's `scannabilityWarning`.
    func scannabilityWarning(symbolSide: Int) -> String? {
        guard isHardToScan(symbolSide: symbolSide) else { return nil }
        if logo == nil {
            return "Dots get hard for cameras to read on a code this dense. Square, rounded, leaf or bar modules scan more reliably."
        }
        if moduleShape == .dot, symbolSide < Self.nonSquareWithLogoSymbolSide {
            return "Dots get hard for cameras to read on a code this dense with a logo. Square, rounded, leaf or bar modules — or no logo — scan more reliably."
        }
        return "Shaped modules with a logo get hard for cameras to read on a code this dense. Square modules — or no logo — scan more reliably."
    }

    // MARK: Presets

    /// A named studio look. Applying one moves shapes *and* inks.
    struct Preset: Identifiable, Equatable {
        let id: String
        let name: String
        let style: QRStyle
    }

    static func make(_ mutate: (inout QRStyle) -> Void) -> QRStyle {
        var style = QRStyle()
        mutate(&style)
        return style
    }

    /// Fixed sRGB literals, shared with the Android port, rather than
    /// `UIColor.systemGreen` and friends. System colours are dynamic: they
    /// would resolve to a different shade in Dark Mode, so the same preset
    /// would print a different code depending on the phone's appearance.
    ///
    /// Every preset ink clears the generator's own 3:1 contrast floor
    /// against its background, or applying the preset would raise the
    /// contrast warning. That is why Nature and Sunset start from the
    /// increased-contrast variants of system green (#248A3D, 4.4:1) and
    /// system orange (#C93400, 5.0:1) rather than the standard ones (2.2:1
    /// and 2.1:1).
    private static func srgb(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }

    static let presets: [Preset] = [
        Preset(id: "classic", name: "Classic", style: .standard),
        Preset(id: "soft", name: "Soft", style: make {
            $0.moduleShape = .rounded
            $0.eyeShape = .rounded
        }),
        Preset(id: "dots", name: "Dots", style: make {
            $0.moduleShape = .dot
            $0.eyeShape = .circle
        }),
        Preset(id: "nature", name: "Nature", style: make {
            $0.moduleShape = .leaf
            $0.eyeShape = .ring
            $0.inks = [srgb(0x248A3D), srgb(0x216B40)]
        }),
        Preset(id: "ink", name: "Ink", style: make {
            $0.moduleShape = .rounded
            $0.eyeShape = .ring
            $0.inks = [srgb(0x141A33), srgb(0x5933A6)]
        }),
        Preset(id: "sunset", name: "Sunset", style: make {
            $0.moduleShape = .dot
            $0.eyeShape = .circle
            $0.inks = [srgb(0xC93400), srgb(0xFF2D55)]
            $0.background = srgb(0xFCF7ED)
        }),
    ]
}

// MARK: - Geometry

/// One place decides where ink goes. Every renderer consumes it.
enum QRGeometry {

    /// Bounding box of the inked modules, in matrix modules.
    /// `CIQRCodeGenerator` returns the symbol inside a one-module light
    /// border; the finder patterns sit on three corners of the symbol, so
    /// the bounding box of the ink *is* the symbol. That is what lets the
    /// renderers trim Core Image's border and draw their own quiet zone.
    static func symbolArea(of matrix: CodeGenerator.ModuleMatrix) -> CGRect? {
        var minX = matrix.width, minY = matrix.height, maxX = -1, maxY = -1
        for y in 0..<matrix.height {
            for x in 0..<matrix.width where matrix[x, y] {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// A QR symbol is 21 + 4·(version − 1) modules a side. Anything else is
    /// not a QR code, and the finder positions below would be wrong for it.
    static func isQRSymbolSide(_ side: Int) -> Bool {
        side >= 21 && side <= 177 && (side - 21) % 4 == 0
    }

    /// Finder-eye squares of a symbol, in module units (top-left origin).
    static func eyeRects(width: Int, height: Int) -> [CGRect] {
        [
            CGRect(x: 0, y: 0, width: 7, height: 7),
            CGRect(x: width - 7, y: 0, width: 7, height: 7),
            CGRect(x: 0, y: height - 7, width: 7, height: 7),
        ]
    }

    static func isInEye(x: Int, y: Int, eyes: [CGRect]) -> Bool {
        let point = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
        return eyes.contains { $0.contains(point) }
    }

    /// One data module, in module units at the origin.
    static func modulePath(shape: QRStyle.ModuleShape) -> CGPath {
        switch shape {
        case .square:
            return CGPath(rect: CGRect(x: 0, y: 0, width: 1, height: 1), transform: nil)
        case .rounded:
            return roundedRect(CGRect(x: 0.06, y: 0.06, width: 0.88, height: 0.88), radius: 0.26)
        case .dot:
            return CGPath(ellipseIn: CGRect(x: 0.12, y: 0.12, width: 0.76, height: 0.76),
                          transform: nil)
        case .leaf:
            return roundedRect(CGRect(x: 0.04, y: 0.04, width: 0.92, height: 0.92),
                               radius: 0.46, corners: [.topLeft, .bottomRight])
        case .bars:
            return roundedRect(CGRect(x: 0.16, y: 0, width: 0.68, height: 1), radius: 0.34)
        }
    }

    /// The three concentric pieces of a finder eye, in module units.
    struct EyePieces {
        /// Ink, inscribed in the eye's 7 × 7 square.
        let ring: CGPath
        /// Background, inscribed in the 5 × 5 square one module in.
        let gap: CGPath
        /// Ink, inscribed in the 3 × 3 square two modules in.
        let centre: CGPath
    }

    /// Every shape touches the midpoints of its square's sides, so the scan
    /// lines through the centre — the ones a reader samples — keep the
    /// 1:1:3:1:1 finder ratio exactly, whatever the corners do.
    static func eyePieces(shape: QRStyle.EyeShape, eye: CGRect) -> EyePieces {
        let outer = eye
        let gap = eye.insetBy(dx: 1, dy: 1)
        let centre = eye.insetBy(dx: 2, dy: 2)
        switch shape {
        case .square:
            return EyePieces(ring: CGPath(rect: outer, transform: nil),
                             gap: CGPath(rect: gap, transform: nil),
                             centre: CGPath(rect: centre, transform: nil))
        case .rounded:
            return EyePieces(ring: roundedRect(outer, radius: 2),
                             gap: roundedRect(gap, radius: 1.3),
                             centre: roundedRect(centre, radius: 0.9))
        case .circle:
            return EyePieces(ring: CGPath(ellipseIn: outer, transform: nil),
                             gap: CGPath(ellipseIn: gap, transform: nil),
                             centre: CGPath(ellipseIn: centre, transform: nil))
        case .ring:
            // Square frame, round interior — reads as a ring, stays boxy
            // enough for a reader to find the three-to-one ratio.
            return EyePieces(ring: roundedRect(outer, radius: 1.8),
                             gap: CGPath(ellipseIn: gap, transform: nil),
                             centre: CGPath(ellipseIn: centre, transform: nil))
        }
    }

    /// Rounded rectangle with per-corner control. Core Graphics only offers
    /// all-corners-or-none, and the leaf module needs a mix.
    static func roundedRect(_ rect: CGRect, radius: CGFloat,
                            corners: UIRectCorner = .allCorners) -> CGPath {
        let radius = min(radius, min(rect.width, rect.height) / 2)
        func r(_ corner: UIRectCorner) -> CGFloat { corners.contains(corner) ? radius : 0 }
        let tl = r(.topLeft), tr = r(.topRight), br = r(.bottomRight), bl = r(.bottomLeft)

        let path = CGMutablePath()
        let x0 = rect.minX, y0 = rect.minY, x1 = rect.maxX, y1 = rect.maxY
        path.move(to: CGPoint(x: x0 + tl, y: y0))
        path.addLine(to: CGPoint(x: x1 - tr, y: y0))
        if tr > 0 { path.addArc(tangent1End: CGPoint(x: x1, y: y0),
                                tangent2End: CGPoint(x: x1, y: y0 + tr), radius: tr) }
        path.addLine(to: CGPoint(x: x1, y: y1 - br))
        if br > 0 { path.addArc(tangent1End: CGPoint(x: x1, y: y1),
                                tangent2End: CGPoint(x: x1 - br, y: y1), radius: br) }
        path.addLine(to: CGPoint(x: x0 + bl, y: y1))
        if bl > 0 { path.addArc(tangent1End: CGPoint(x: x0, y: y1),
                                tangent2End: CGPoint(x: x0, y: y1 - bl), radius: bl) }
        path.addLine(to: CGPoint(x: x0, y: y0 + tl))
        if tl > 0 { path.addArc(tangent1End: CGPoint(x: x0, y: y0),
                                tangent2End: CGPoint(x: x0 + tl, y: y0), radius: tl) }
        path.closeSubpath()
        return path
    }

    // MARK: Ink passes

    /// The three passes a styled code is drawn in, in module units of the
    /// trimmed symbol (origin at its top-left corner): ink — every data
    /// module plus each eye's ring — then the background gap of each eye,
    /// then the ink centres. Drawing the eyes in three passes is what stops
    /// a gradient smearing across an eye's gap.
    struct Passes {
        /// Modules per side of the symbol, Core Image's border excluded.
        let side: Int
        let ink: CGPath
        let gap: CGPath
        let centre: CGPath
    }

    /// Nil when the matrix is not a QR symbol (or carries no ink at all).
    static func passes(matrix: CodeGenerator.ModuleMatrix, style: QRStyle) -> Passes? {
        guard let area = symbolArea(of: matrix) else { return nil }
        let side = Int(area.width)
        guard Int(area.height) == side, isQRSymbolSide(side) else { return nil }
        let originX = Int(area.minX), originY = Int(area.minY)
        let eyes = eyeRects(width: side, height: side)
        let cleared = style.logo == nil ? CGRect.null : logoLayout(side: side).cleared

        // Eyes get their own shapes below; skipping their modules here keeps
        // a square module from squaring off a round eye. Modules under the
        // logo are left out rather than painted over, so no sliver of one
        // peeks out from behind the artwork.
        func isDataInk(_ x: Int, _ y: Int) -> Bool {
            guard matrix[originX + x, originY + y], !isInEye(x: x, y: y, eyes: eyes) else { return false }
            return !cleared.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5))
        }

        let ink = CGMutablePath()
        if style.moduleShape == .square {
            // Square modules merge into one rectangle per horizontal run:
            // the same picture with a fraction of the subpaths, which keeps
            // the SVG and PDF small.
            for y in 0..<side {
                var x = 0
                while x < side {
                    guard isDataInk(x, y) else { x += 1; continue }
                    let start = x
                    while x < side, isDataInk(x, y) { x += 1 }
                    ink.addRect(CGRect(x: start, y: y, width: x - start, height: 1))
                }
            }
        } else {
            // Move a copy of the module, then append it untransformed:
            // `addPath(_:transform:)` costs time in proportion to the path it
            // appends *to*, which made this loop quadratic — seconds for a
            // dense code on every preview refresh. The points come out the
            // same, to within an ulp (QRStudioTests checks).
            let module = modulePath(shape: style.moduleShape)
            for y in 0..<side {
                for x in 0..<side where isDataInk(x, y) {
                    var offset = CGAffineTransform(translationX: CGFloat(x), y: CGFloat(y))
                    if let moved = module.copy(using: &offset) { ink.addPath(moved) }
                }
            }
        }

        let gap = CGMutablePath(), centre = CGMutablePath()
        for eye in eyes {
            let pieces = eyePieces(shape: style.eyeShape, eye: eye)
            ink.addPath(pieces.ring)
            gap.addPath(pieces.gap)
            centre.addPath(pieces.centre)
        }
        return Passes(side: side, ink: ink, gap: gap, centre: centre)
    }

    // MARK: Logo

    /// Where the centre logo goes, in module units of the symbol.
    struct LogoLayout {
        /// Whole modules left blank under the artwork. Their data is lost
        /// either way; error correction rebuilds it.
        let cleared: CGRect
        /// Where the artwork is aspect-fitted, padded inside `cleared`.
        let artwork: CGRect
    }

    /// Proportions of the plain generator's logo (`CodeGenerator.composite`):
    /// artwork 22 % of the side, padded by 6 % of itself on every side.
    private static let artworkFraction: CGFloat = 0.22
    private static let artworkPadding: CGFloat = 0.06

    /// Sized off the *symbol*, never off the canvas, and snapped to whole
    /// modules: the cleared square is the largest odd number of modules
    /// that fits the plain generator's proportions, centred on the middle
    /// module (a symbol side is always odd), so its edges fall on module
    /// boundaries. What it wipes is therefore exact: at most about 6 % of
    /// the symbol, well inside what High error correction rebuilds even on
    /// the smallest versions, where its share of the codewords is largest.
    ///
    /// The first and last nine rows and columns hold the finders, their
    /// separators, the timing patterns and both copies of the format
    /// information; the cleared square never reaches them. Only version 1
    /// is small enough for that to bind (3 modules instead of 5). On larger
    /// versions it can cover alignment patterns near the centre, as any
    /// centred logo does.
    static func logoLayout(side: Int) -> LogoLayout {
        let proportional = CGFloat(side) * artworkFraction * (1 + 2 * artworkPadding)
        var modules = min(Int(proportional.rounded(.down)), side - 18)
        if modules.isMultiple(of: 2) { modules -= 1 }
        modules = max(modules, 1)
        let origin = CGFloat(side - modules) / 2
        let cleared = CGRect(x: origin, y: origin, width: CGFloat(modules), height: CGFloat(modules))
        let artworkSide = cleared.width / (1 + 2 * artworkPadding)
        let inset = (cleared.width - artworkSide) / 2
        return LogoLayout(cleared: cleared, artwork: cleared.insetBy(dx: inset, dy: inset))
    }

    /// `size` aspect-fitted and centred in `rect`.
    static func aspectFit(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}

// MARK: - Renderer

/// Draws a styled code for the preview / PNG, and — through `draw` — for the
/// PDF export, so both are the same picture.
enum QRStyledRenderer {

    /// Points (= pixels) per module of the preview and the shared PNG; the
    /// Android port's default too.
    static let defaultModuleSize: CGFloat = 12

    /// Hard ceiling on canvas size — a runaway module size must not
    /// allocate a giant bitmap. (A version-40 code at 12 pt is 2220 pt.)
    private static let maxCanvasSide: CGFloat = 12_000

    /// Where everything goes on the canvas.
    struct Layout {
        let passes: QRGeometry.Passes
        /// Quiet zone actually drawn, in modules.
        let margin: Int
        /// Points per module.
        let moduleSize: CGFloat
        /// Canvas side, in points.
        var side: CGFloat { CGFloat(passes.side + 2 * margin) * moduleSize }
    }

    static func layout(matrix: CodeGenerator.ModuleMatrix,
                       style: QRStyle,
                       moduleSize: CGFloat) -> Layout? {
        guard moduleSize > 0,
              let passes = QRGeometry.passes(matrix: matrix, style: style) else { return nil }
        let layout = Layout(passes: passes, margin: style.effectiveQuietZone, moduleSize: moduleSize)
        guard layout.side <= maxCanvasSide else { return nil }
        return layout
    }

    /// The styled code as a bitmap. Nil when the matrix is not a QR symbol.
    static func image(matrix: CodeGenerator.ModuleMatrix,
                      style: QRStyle,
                      moduleSize: CGFloat = defaultModuleSize) -> UIImage? {
        guard let layout = layout(matrix: matrix, style: style, moduleSize: moduleSize) else {
            return nil
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1                    // 1 point = 1 pixel: module edges on whole pixels
        format.opaque = true                // the background is always painted
        format.preferredRange = .standard   // 8-bit sRGB, the colours the SVG's hex literals name
        let size = CGSize(width: layout.side, height: layout.side)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            draw(layout, style: style, in: context.cgContext)
        }
    }

    /// Draw the whole code — background, the three ink passes, the logo —
    /// into a UIKit renderer context (y-down, origin top-left, one unit per
    /// point). UIKit's image and PDF renderers are both y-down already, so
    /// nothing here flips.
    static func draw(_ layout: Layout, style: QRStyle, in cg: CGContext) {
        let passes = layout.passes
        cg.saveGState()
        defer { cg.restoreGState() }

        cg.setFillColor(style.background.cgColor)
        cg.fill(CGRect(x: 0, y: 0, width: layout.side, height: layout.side))

        // Module units from here on: past the quiet zone, then scaled.
        let offset = CGFloat(layout.margin) * layout.moduleSize
        cg.translateBy(x: offset, y: offset)
        cg.scaleBy(x: layout.moduleSize, y: layout.moduleSize)
        let symbol = CGRect(x: 0, y: 0, width: passes.side, height: passes.side)

        // Pass 1 — data modules plus the ring of every eye.
        fillInk(passes.ink, in: cg, style: style, symbol: symbol)

        // Pass 2 — the gap between ring and centre, in background.
        cg.setFillColor(style.background.cgColor)
        cg.addPath(passes.gap)
        cg.fillPath()

        // Pass 3 — the centres, against the same gradient anchor so every
        // eye reads with the same wash as the data modules.
        fillInk(passes.centre, in: cg, style: style, symbol: symbol)

        // The modules under the logo were never drawn (`QRGeometry.passes`
        // leaves them out), so the artwork sits on clean background.
        if let logo = style.logo {
            let box = QRGeometry.logoLayout(side: passes.side)
            // `UIImage.draw` targets UIKit's current context; push ours so
            // the logo cannot land anywhere else.
            UIGraphicsPushContext(cg)
            logo.draw(in: QRGeometry.aspectFit(logo.size, in: box.artwork))
            UIGraphicsPopContext()
        }
    }

    /// A logo ready to embed: upright (any EXIF orientation baked in) and at
    /// most `maxPixels` on its long side. A camera-roll photo is 12 MP;
    /// redrawn on every preview refresh, or inlined into an SVG as base64,
    /// that would cost tens of milliseconds and tens of megabytes for a
    /// picture that ends up a few hundred pixels wide.
    static func preparedLogo(_ image: UIImage, maxPixels: CGFloat = 1024) -> UIImage {
        let pixels = CGSize(width: image.size.width * image.scale,
                            height: image.size.height * image.scale)
        let longest = max(pixels.width, pixels.height)
        guard longest > 0 else { return image }
        if image.imageOrientation == .up, image.scale == 1, longest <= maxPixels { return image }

        let factor = min(1, maxPixels / longest)
        let target = CGSize(width: max(1, (pixels.width * factor).rounded()),
                            height: max(1, (pixels.height * factor).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false               // logos are often cut-outs
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    // MARK: Filling

    /// Flat fill for a single ink, clipped gradient for a multi-ink style.
    /// The gradient is anchored to the symbol — top-left to bottom-right, in
    /// module units — so several inks read as one wash across the whole code
    /// rather than per module, and the clip keeps it on the ink: the
    /// background between modules is never tinted.
    private static func fillInk(_ path: CGPath, in cg: CGContext, style: QRStyle, symbol: CGRect) {
        guard !path.isEmpty else { return }
        guard style.usesGradient, let gradient = gradient(for: style.inks) else {
            cg.setFillColor(style.primaryInk.cgColor)
            cg.addPath(path)
            cg.fillPath()
            return
        }
        cg.saveGState()
        cg.addPath(path)
        cg.clip()
        cg.drawLinearGradient(gradient,
                              start: CGPoint(x: symbol.minX, y: symbol.minY),
                              end: CGPoint(x: symbol.maxX, y: symbol.maxY),
                              options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        cg.restoreGState()
    }

    /// Evenly spaced stops in sRGB — the space SVG interpolates a
    /// `<linearGradient>` in, so the vector export washes identically.
    private static func gradient(for inks: [UIColor]) -> CGGradient? {
        guard inks.count >= 2, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let colors = inks.map(\.cgColor) as CFArray
        let last = CGFloat(inks.count - 1)
        let locations: [CGFloat] = (0..<inks.count).map { CGFloat($0) / last }
        return CGGradient(colorsSpace: space, colors: colors, locations: locations)
    }
}
