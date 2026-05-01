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
    static func svg(
        for matrix: CodeGenerator.ModuleMatrix,
        foreground: UIColor,
        background: UIColor,
        moduleSize: Int = 10,
        margin: Int = 4
    ) -> String {
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
    static func pdfData(
        for matrix: CodeGenerator.ModuleMatrix,
        foreground: UIColor,
        background: UIColor,
        moduleSize: CGFloat = 10,
        margin: Int = 4
    ) -> Data {
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
