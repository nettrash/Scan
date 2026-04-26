//
//  Symbology.swift
//  Scan
//
//  Maps AVFoundation metadata object types and Vision barcode symbologies
//  to human-readable names, and exposes the full set of 1D / 2D barcode
//  symbologies the app scans.
//

import AVFoundation
import Vision

enum Symbology: String, CaseIterable, Identifiable {
    // 2D
    case qr            = "QR"
    case aztec         = "Aztec"
    case pdf417        = "PDF417"
    case dataMatrix    = "Data Matrix"
    // 1D - retail
    case ean8          = "EAN-8"
    case ean13         = "EAN-13"
    case upce          = "UPC-E"
    // 1D - industrial
    case code39        = "Code 39"
    case code39Mod43   = "Code 39 mod 43"
    case code93        = "Code 93"
    case code128       = "Code 128"
    case itf14         = "ITF-14"
    case interleaved2of5 = "Interleaved 2 of 5"
    case codabar       = "Codabar"
    case gs1DataBar    = "GS1 DataBar"
    case unknown       = "Unknown"

    var id: String { rawValue }

    /// Display name shown in the UI.
    var displayName: String { rawValue }

    /// Whether this is a two-dimensional symbology.
    var is2D: Bool {
        switch self {
        case .qr, .aztec, .pdf417, .dataMatrix: return true
        default: return false
        }
    }

    /// Initialize from a Vision barcode symbology.
    /// Deployment target is iOS 16.4, so all current cases are available;
    /// `default` keeps the switch exhaustive for the underlying struct
    /// type and future additions.
    init(visionSymbology v: VNBarcodeSymbology) {
        switch v {
        case .qr, .microQR:                                 self = .qr
        case .aztec:                                        self = .aztec
        case .pdf417, .microPDF417:                         self = .pdf417
        case .dataMatrix:                                   self = .dataMatrix
        case .ean8:                                         self = .ean8
        case .ean13:                                        self = .ean13
        case .upce:                                         self = .upce
        case .code39, .code39FullASCII:                     self = .code39
        case .code39Checksum, .code39FullASCIIChecksum:     self = .code39Mod43
        case .code93, .code93i:                             self = .code93
        case .code128:                                      self = .code128
        case .itf14:                                        self = .itf14
        case .i2of5, .i2of5Checksum:                        self = .interleaved2of5
        case .codabar:                                      self = .codabar
        case .gs1DataBar, .gs1DataBarExpanded, .gs1DataBarLimited:
            self = .gs1DataBar
        default:
            self = .unknown
        }
    }

    /// Initialize from an AVFoundation metadata object type.
    init(_ avType: AVMetadataObject.ObjectType) {
        switch avType {
        case .qr:                   self = .qr
        case .aztec:                self = .aztec
        case .pdf417:               self = .pdf417
        case .dataMatrix:           self = .dataMatrix
        case .ean8:                 self = .ean8
        case .ean13:                self = .ean13
        case .upce:                 self = .upce
        case .code39:               self = .code39
        case .code39Mod43:          self = .code39Mod43
        case .code93:               self = .code93
        case .code128:              self = .code128
        case .itf14:                self = .itf14
        case .interleaved2of5:      self = .interleaved2of5
        case .codabar:              self = .codabar
        default:
            // GS1 DataBar variants exist on newer iOS with raw values like
            // "org.gs1.DataBar", "org.gs1.DataBar-Expanded", etc.
            if avType.rawValue.lowercased().contains("databar") {
                self = .gs1DataBar
            } else {
                self = .unknown
            }
        }
    }
}

/// All AV metadata object types the scanner asks for.
/// We deliberately add types defensively: types unsupported by the running OS
/// are filtered out at session-configure time.
enum SupportedSymbologies {
    static var all: [AVMetadataObject.ObjectType] {
        // Deployment target is iOS 16.4, so .codabar (iOS 15.4+) and the
        // GS1 DataBar family are always available — no #available gate
        // needed. Types unsupported by the *device* are filtered out at
        // session-configure time against `output.availableMetadataObjectTypes`.
        var types: [AVMetadataObject.ObjectType] = [
            .qr, .aztec, .pdf417, .dataMatrix,
            .ean8, .ean13, .upce,
            .code39, .code39Mod43, .code93, .code128,
            .itf14, .interleaved2of5,
            .codabar
        ]
        for raw in ["org.gs1.DataBar", "org.gs1.DataBar-Expanded", "org.gs1.DataBar-Limited"] {
            types.append(AVMetadataObject.ObjectType(rawValue: raw))
        }
        return types
    }
}
