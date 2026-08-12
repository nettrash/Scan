//
//  ChessCornerPlacementTests.swift
//  ScanTests
//
//  Guards the identity of the corner-placement cover's presentation item.
//
//  This looks like a trivia test about a two-line struct. It is not: it
//  pins the difference between a usable manual-corner screen and a dead
//  one, and the failure it guards against is invisible in code review.
//
//  `ChessScreen` presents `ChessCornerAdjustView` with
//  `fullScreenCover(item:)`, and builds the item inside the binding's
//  `get`. SwiftUI re-runs that closure on every `body` evaluation, and
//  dragging a corner mutates `pendingCorners`, which publishes, which
//  evaluates `body`. If the wrapper mints its id (`let id = UUID()`),
//  every drag update hands SwiftUI a *new* identity, so it tears the
//  sheet down and rebuilds it: `@State` reset, in-flight `DragGesture`
//  destroyed. The symptom is that exactly one corner can be nudged and
//  the screen then ignores touches.
//
//  Manual corners are the only way to rectify a board until the models
//  ship, so that bug takes the training-capture path with it.
//

import XCTest
@testable import Scan

final class ChessCornerPlacementTests: XCTestCase {

    /// Rebuilding the wrapper from the same image must not change identity.
    ///
    /// This is the assertion that fails with `let id = UUID()`.
    func testPresentationIdentityIsStableAcrossRebuilds() {
        let image = UIImage()

        // Exactly what the presentation binding's `get` does, twice —
        // standing in for two `body` evaluations during a drag.
        let first = IdentifiedImage(image: image)
        let second = IdentifiedImage(image: image)

        XCTAssertEqual(first.id, second.id,
                       "the corner cover is rebuilt mid-drag, killing the gesture")
    }

    /// ...but a genuinely different image must still re-present.
    ///
    /// Both images are held in locals on purpose. `ObjectIdentifier` is only
    /// unique among *live* objects, so comparing two temporaries can pass an
    /// address from the first to the second after it is deallocated — which
    /// is exactly what this test did on its first run. The real code holds
    /// the image in `pendingImage` for as long as the cover is presented, so
    /// the guarantee holds where it is relied upon.
    func testADifferentImageGetsADifferentIdentity() {
        let one = UIImage()
        let another = UIImage()

        XCTAssertNotEqual(IdentifiedImage(image: one).id,
                          IdentifiedImage(image: another).id)
    }
}
