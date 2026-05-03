//
//  Platform.swift
//  Scan
//
//  Tiny runtime helpers for "where am I running?" decisions.
//
//  Scan is a single iOS app target that builds for iPhone + iPad and
//  runs on Mac (via Mac Catalyst) and Apple Vision Pro (via Designed
//  for iPad). All four destinations compile from the same SDK, so we
//  don't have a `#if os(visionOS)` to lean on — the runtime check is
//  the only way to tell, e.g., "the user is on Vision Pro and there
//  is no usable AVCaptureDevice".
//
//  Centralising the predicates here keeps platform branches readable
//  at call sites and gives us a single place to update if Apple ever
//  changes the surface (e.g. exposes the Vision Pro world camera to
//  general App Store apps and we can flip `isVisionOS` to also gate
//  on a feature check rather than the host platform).
//

import Foundation
import UIKit

enum Platform {
    /// True when the iOS app is running inside the visionOS "Designed
    /// for iPad" compatibility runtime on Apple Vision Pro.
    ///
    /// Apple does NOT expose Vision Pro's world cameras to third-party
    /// apps under standard App Store distribution — the entitlement
    /// that opens that door (`com.apple.developer.arkit.main-camera-access.allow`)
    /// is gated on an enterprise developer agreement and a managed
    /// device deployment. For Scan that means there is no live-camera
    /// path on Vision Pro, and we surface image-import (Photos / Files)
    /// as the primary affordance instead.
    ///
    /// Implementation note: there is no `ProcessInfo.isiOSAppOnVisionOS`
    /// (mirroring `isiOSAppOnMac`) — Apple ships the visionOS host
    /// signal through `UIDevice.userInterfaceIdiom == .vision` instead.
    /// The `.vision` case was added in visionOS 1.0, so a deployment
    /// target of iOS 17 or later is required for this property to
    /// resolve at compile time. Scan is iOS 26+ everywhere, so we're
    /// safely past that bar.
    static var isVisionOS: Bool {
        UIDevice.current.userInterfaceIdiom == .vision
    }

    /// True when the iOS app is running on macOS via Mac Catalyst.
    ///
    /// Camera access works on Catalyst once the App Sandbox
    /// `com.apple.security.device.camera` entitlement is set (see
    /// `Scan.entitlements`). The standard live-scanner path is the
    /// right default here — built-in webcams and Continuity Camera
    /// both surface as regular `AVCaptureDevice`s.
    static var isMacCatalyst: Bool {
        ProcessInfo.processInfo.isMacCatalystApp
    }

    /// True when the iOS app is running on an Apple Silicon Mac via
    /// the "Designed for iPad" / iPad-app-on-Mac compatibility runtime
    /// (NOT Catalyst — the unmodified iPad binary running in a Mac
    /// compatibility layer). Apple ships this destination automatically
    /// for iPad apps on the Mac App Store unless the developer opts out.
    static var isiOSAppOnMac: Bool {
        ProcessInfo.processInfo.isiOSAppOnMac
    }

    /// True when the iOS app is running on macOS via *any* path —
    /// Mac Catalyst OR Designed-for-iPad-on-Mac. Use this for
    /// behaviour that depends on host hardware rather than which
    /// compatibility layer Apple is using to bridge it: e.g. the
    /// camera-preview rotation fix, where Mac webcams deliver
    /// landscape frames natively under either runtime, so the
    /// iPhone-style 90° rotation is wrong in both cases.
    ///
    /// Detection strategy is layered because Apple's
    /// `ProcessInfo.isiOSAppOnMac` flag has been reported quiet under
    /// some Xcode / macOS combinations on the Designed-for-iPad-on-Mac
    /// runtime, and we'd rather catch the host correctly than rely on
    /// a single signal:
    ///
    ///   1. `isMacCatalystApp` — fires reliably for Catalyst.
    ///   2. `isiOSAppOnMac` — supposed to fire for iPad-on-Mac.
    ///   3. `NSApplication` class lookup — AppKit is loaded into the
    ///      process under both Mac runtimes (the system uses it for
    ///      window management even when the iOS app doesn't touch
    ///      AppKit directly), but it is never present in a real iOS
    ///      process. This is the catch-all that papers over (2)'s
    ///      flakiness.
    static var isMac: Bool {
        if isMacCatalyst { return true }
        if isiOSAppOnMac { return true }
        if NSClassFromString("NSApplication") != nil { return true }
        return false
    }
}
