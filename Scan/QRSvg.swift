//
//  QRSvg.swift
//  Scan
//
//  Vector exports for QR codes — SVG and PDF — built off the module
//  matrix returned by `CodeGenerator.qrModuleMatrix`. SVG is emitted
//  as one `<rect>` per "on" run inside each row (run-length-encoded)
//  so the file size stays modest even for dense codes; PDF is drawn
//  with `UIGraphicsPDFRenderer` so the result is true vector that
//  scales cleanly when printed. Both honour the user-picked FG/BG
//  colours.
//
//  1.10: both also take the QR art studio's `QRStyle`. A styled export
//  draws the same three ink passes as the on-screen preview
//  (`QRGeometry.passes`) — module and eye shapes, the gradient as an SVG
//  `<linearGradient>` / a PDF shading, the trimmed 4-module quiet zone and
//  the centre logo — so the vector file is the code the user designed, not
//  a squared-off approximation of it. A nil or plain style emits exactly
//  the run-length `<rect>` form it always has.
//
//  Aztec / PDF417 / Code128 are deliberately *not* covered — Core
//  Image doesn't expose their unscaled module bitmaps in a stable
//  way and the use-case ("print me a vector code at any scale") is
//  overwhelmingly QR. Falling back to PNG for those is fine.
//

import Foundation
import UIKit

enum QRSvg {

    // MARK: - Public

    /// Render a QR module matrix as an SVG document. Foreground and
    /// background colours are baked in as hex literals on the root
    /// `<rect>` (background) and per-module `<rect>`s (foreground).
    ///
    /// - Parameter style: when non-nil and not `isPlain`, the document
    ///   carries the studio's shapes, inks, quiet zone and logo instead;
    ///   `foreground`, `background` and `margin` then come from the style.
    static func svg(
        for matrix: CodeGenerator.ModuleMatrix,
        foreground: UIColor,
        background: UIColor,
        moduleSize: Int = 10,
        margin: Int = 4,
        style: QRStyle? = nil
    ) -> String {
        if let style, !style.isPlain,
           let styled = styledSVG(for: matrix, style: style, moduleSize: moduleSize) {
            return styled
        }

        let totalW = (matrix.width + margin * 2) * moduleSize
        let totalH = (matrix.height + margin * 2) * moduleSize
        let fgHex = hexString(for: foreground)
        let bgHex = hexString(for: background)

        var out = ""
        out.reserveCapacity(matrix.width * matrix.height * 30)
        out += #"<?xml version="1.0" encoding="UTF-8"?>"#
        out += "\n"
        out += #"<svg xmlns="http://www.w3.org/2000/svg" "#
        out += #"viewBox="0 0 \#(totalW) \#(totalH)" "#
        out += #"width="\#(totalW)" height="\#(totalH)" "#
        out += #"shape-rendering="crispEdges">"#
        out += "\n"
        out += #"<rect width="\#(totalW)" height="\#(totalH)" fill="\#(bgHex)"/>"#
        out += "\n"

        // Run-length-encode each row so contiguous "on" modules become
        // one wide `<rect>`. A typical 33-module QR with margins emits
        // ~120 rects this way, vs. ~600 if every module got its own.
        for y in 0..<matrix.height {
            var x = 0
            while x < matrix.width {
                if !matrix[x, y] { x += 1; continue }
                let runStart = x
                while x < matrix.width && matrix[x, y] { x += 1 }
                let runLen = x - runStart
                let px = (margin + runStart) * moduleSize
                let py = (margin + y) * moduleSize
                let pw = runLen * moduleSize
                out += #"<rect x="\#(px)" y="\#(py)" width="\#(pw)" height="\#(moduleSize)" fill="\#(fgHex)"/>"#
                out += "\n"
            }
        }

        out += "</svg>\n"
        return out
    }

    /// Render the same matrix as a single-page PDF. Width / height
    /// pulled directly off the matrix at the requested point size
    /// per module — a 10 pt module + 4-module margin produces a
    /// tidy ~370 × 370 pt page for a typical 33-module QR.
    ///
    /// - Parameter style: as for `svg` — a styled page is drawn by
    ///   `QRStyledRenderer.draw`, the very routine behind the preview.
    static func pdfData(
        for matrix: CodeGenerator.ModuleMatrix,
        foreground: UIColor,
        background: UIColor,
        moduleSize: CGFloat = 10,
        margin: Int = 4,
        style: QRStyle? = nil
    ) -> Data {
        if let style, !style.isPlain,
           let layout = QRStyledRenderer.layout(matrix: matrix, style: style,
                                                moduleSize: moduleSize) {
            let page = CGRect(x: 0, y: 0, width: layout.side, height: layout.side)
            return UIGraphicsPDFRenderer(bounds: page).pdfData { ctx in
                ctx.beginPage()
                QRStyledRenderer.draw(layout, style: style, in: ctx.cgContext)
            }
        }

        let totalW = CGFloat(matrix.width + margin * 2) * moduleSize
        let totalH = CGFloat(matrix.height + margin * 2) * moduleSize

        let bounds = CGRect(x: 0, y: 0, width: totalW, height: totalH)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { ctx in
            ctx.beginPage()
            let cg = ctx.cgContext

            // Background fill.
            cg.setFillColor(background.cgColor)
            cg.fill(bounds)

            // Foreground modules: same row-RLE as SVG.
            cg.setFillColor(foreground.cgColor)
            for y in 0..<matrix.height {
                var x = 0
                while x < matrix.width {
                    if !matrix[x, y] { x += 1; continue }
                    let runStart = x
                    while x < matrix.width && matrix[x, y] { x += 1 }
                    let runLen = x - runStart
                    let rect = CGRect(
                        x: CGFloat(margin + runStart) * moduleSize,
                        y: CGFloat(margin + y) * moduleSize,
                        width: CGFloat(runLen) * moduleSize,
                        height: moduleSize
                    )
                    cg.fill(rect)
                }
            }
        }
    }

    // MARK: - File-system helpers

    /// Write SVG to a temporary URL the share sheet can pick up.
    /// Stable filename so the share-sheet target sees a friendly name.
    static func writeSVG(
        _ svg: String,
        baseName: String = "qr"
    ) throws -> URL {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("\(baseName).svg")
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        try svg.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    static func writePDF(
        _ data: Data,
        baseName: String = "qr"
    ) throws -> URL {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("\(baseName).pdf")
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Styled SVG

    /// Id of the `<linearGradient>` a styled export emits; every inked
    /// `<path>` references it. The Android port uses the same id.
    private static let gradientID = "scan-ink"

    /// Long side of the logo inlined into an SVG. The artwork covers a few
    /// dozen modules, so this is ample for print while keeping the base64
    /// payload to a few hundred kilobytes at most.
    private static let svgLogoPixels: CGFloat = 512

    /// Vector form of a styled code: the same three passes the preview
    /// fills, in module units inside one scaled group — ink (data modules
    /// plus eye rings), the background gaps, the eye centres — then the
    /// logo artwork. The gradient runs top-left to bottom-right across the
    /// symbol in those same units, exactly as the bitmap's does.
    ///
    /// Nil when the matrix is not a QR symbol, so the caller falls back to
    /// the plain form.
    private static func styledSVG(
        for matrix: CodeGenerator.ModuleMatrix,
        style: QRStyle,
        moduleSize: Int
    ) -> String? {
        guard moduleSize > 0,
              let passes = QRGeometry.passes(matrix: matrix, style: style) else { return nil }
        let margin = style.effectiveQuietZone
        let total = (passes.side + margin * 2) * moduleSize
        let bgHex = hexString(for: style.background)
        let inkFill = style.usesGradient ? "url(#\(gradientID))" : hexString(for: style.primaryInk)
        let logoPNG = style.logo.flatMap {
            QRStyledRenderer.preparedLogo($0, maxPixels: svgLogoPixels).pngData()
        }

        var out = ""
        out += #"<?xml version="1.0" encoding="UTF-8"?>"#
        out += "\n"
        out += #"<svg xmlns="http://www.w3.org/2000/svg" "#
        if logoPNG != nil {
            out += #"xmlns:xlink="http://www.w3.org/1999/xlink" "#
        }
        out += #"viewBox="0 0 \#(total) \#(total)" "#
        out += #"width="\#(total)" height="\#(total)" "#
        // crispEdges would facet the rounded and circular shapes.
        out += #"shape-rendering="geometricPrecision">"#
        out += "\n"

        if style.usesGradient {
            out += "<defs>\n"
            out += #"<linearGradient id="\#(gradientID)" gradientUnits="userSpaceOnUse" "#
            out += #"x1="0" y1="0" x2="\#(passes.side)" y2="\#(passes.side)">"#
            out += "\n"
            let last = CGFloat(style.inks.count - 1)
            for (index, ink) in style.inks.enumerated() {
                out += #"<stop offset="\#(number(CGFloat(index) / last))" "#
                out += #"stop-color="\#(hexString(for: ink))"/>"#
                out += "\n"
            }
            out += "</linearGradient>\n</defs>\n"
        }

        out += #"<rect width="\#(total)" height="\#(total)" fill="\#(bgHex)"/>"#
        out += "\n"

        // Module units inside the group; the transform maps them onto the
        // canvas past the (trimmed, then re-applied) quiet zone.
        let offset = margin * moduleSize
        out += #"<g transform="translate(\#(offset),\#(offset)) scale(\#(moduleSize))">"#
        out += "\n"
        appendPass(passes.ink, fill: inkFill, to: &out)
        appendPass(passes.gap, fill: bgHex, to: &out)
        appendPass(passes.centre, fill: inkFill, to: &out)

        // The passes already left the modules under the logo out, so the
        // artwork needs no backing patch.
        if let logoPNG {
            let a = QRGeometry.logoLayout(side: passes.side).artwork
            // `xlink:href` alone: every SVG 1.1 and SVG 2 reader resolves
            // it, and repeating the base64 under `href` would double the
            // file for nothing.
            out += #"<image x="\#(number(a.minX))" y="\#(number(a.minY))" "#
            out += #"width="\#(number(a.width))" height="\#(number(a.height))" "#
            out += #"preserveAspectRatio="xMidYMid meet" "#
            out += #"xlink:href="data:image/png;base64,\#(logoPNG.base64EncodedString())"/>"#
            out += "\n"
        }

        out += "</g>\n"
        out += "</svg>\n"
        return out
    }

    private static func appendPass(_ path: CGPath, fill: String, to out: inout String) {
        guard !path.isEmpty else { return }
        out += #"<path fill="\#(fill)" fill-rule="nonzero" d="\#(svgPathData(path))"/>"#
        out += "\n"
    }

    /// SVG path data for `path`, in absolute commands. Core Graphics keeps
    /// arcs and ellipses as cubic Béziers, so walking the path traces the
    /// very curves the bitmap and the PDF fill rather than a second
    /// approximation of them.
    private static func svgPathData(_ path: CGPath) -> String {
        var d = ""
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            let p = element.points
            switch element.type {
            case .moveToPoint:
                d += "M" + coordinate(p[0])
            case .addLineToPoint:
                d += "L" + coordinate(p[0])
            case .addQuadCurveToPoint:
                d += "Q" + coordinate(p[0]) + " " + coordinate(p[1])
            case .addCurveToPoint:
                d += "C" + coordinate(p[0]) + " " + coordinate(p[1]) + " " + coordinate(p[2])
            case .closeSubpath:
                d += "Z"
            @unknown default:
                break
            }
        }
        return d
    }

    private static func coordinate(_ point: CGPoint) -> String {
        number(point.x) + "," + number(point.y)
    }

    /// Compact, locale-independent number: at most three decimals (1/1000
    /// of a module), trailing zeros dropped, never "-0".
    private static func number(_ value: CGFloat) -> String {
        let thousandths = Int((value * 1000).rounded())
        let magnitude = abs(thousandths)
        let whole = String(magnitude / 1000)
        let sign = thousandths < 0 ? "-" : ""
        let fraction = magnitude % 1000
        guard fraction != 0 else { return sign + whole }
        var digits = String(fraction)
        digits = String(repeating: "0", count: 3 - digits.count) + digits
        while digits.hasSuffix("0") { digits.removeLast() }
        return sign + whole + "." + digits
    }

    // MARK: - Internal

    /// `#RRGGBB`. Alpha is dropped — SVG `fill="#abcdef88"` works in
    /// modern viewers but breaks older renderers, and the QR rendering
    /// pipeline only ever passes opaque colours anyway.
    private static func hexString(for color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return "#000000"
        }
        let ri = Int((r * 255).rounded()).clamped(to: 0...255)
        let gi = Int((g * 255).rounded()).clamped(to: 0...255)
        let bi = Int((b * 255).rounded()).clamped(to: 0...255)
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
