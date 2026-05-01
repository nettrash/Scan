//
//  ScannedCode.swift
//  Scan
//
//  The single decoded-code value type, extracted from
//  `CameraScannerView.swift` so it can be cross-membered into the
//  share-extension target without dragging in AVCaptureSession (which
//  is the rest of CameraScannerView). The struct itself only depends
//  on `Foundation` + `Symbology`, both of which are extension-safe.
//

import Foundation

struct ScannedCode: Equatable, Identifiable {
    /// Stable per-instance ID so SwiftUI's `.sheet(item:)` distinguishes
    /// "same payload scanned again" from "still showing the previous one"
    /// — without an ID per instance, re-scanning the same value would
    /// not trigger a re-presentation.
    let id: UUID = UUID()
    let value: String
    let symbology: Symbology
    let avType: String
    let timestamp: Date
    /// Bounding rectangle of the detected code, expressed in the preview
    /// view's own coordinate system (top-left origin, points). `nil` when
    /// the code came from a still image rather than the live camera, so
    /// callers should treat its absence as "no on-screen position".
    let previewRect: CGRect?

    static func == (lhs: ScannedCode, rhs: ScannedCode) -> Bool {
        lhs.id == rhs.id
            && lhs.value == rhs.value
            && lhs.symbology == rhs.symbology
            && lhs.avType == rhs.avType
            && lhs.timestamp == rhs.timestamp
            && lhs.previewRect == rhs.previewRect
    }
}
