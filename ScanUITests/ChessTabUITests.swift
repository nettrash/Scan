//
//  ChessTabUITests.swift
//  ScanUITests
//
//  A smoke test for the Chess tab.
//
//  The unit tests cover the engine, the decoder and the board
//  conventions; none of them prove the tab *renders*. This does — it taps
//  through to Chess, sets up a position, and waits for the engine to
//  produce a move for both sides. That exercises the one path no unit
//  test reaches: SwiftUI actually laying out the board, and the analysis
//  task hopping off and back onto the main actor without deadlocking.
//
//  Deliberately shallow. UI tests are slow and brittle in proportion to
//  how much they assert, so this checks the things that would be
//  embarrassing to ship broken and nothing more.
//

import XCTest

final class ChessTabUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        // Skip the What's-New sheet, which otherwise covers the tab bar on
        // a fresh install.
        app.launchArguments += ["-\(UITestFlags.skipWhatsNew)", "YES"]
        app.launch()

        // The scanner tab asks for the camera on appear. Dismiss it rather
        // than pre-granting, so this also proves a denied camera does not
        // block the Chess tab.
        let denyCamera = app.alerts.buttons["Don't Allow"]
        if denyCamera.waitForExistence(timeout: 3) {
            denyCamera.tap()
        }
        return app
    }

    func testChessTabShowsABoardAndAnalysesBothSides() throws {
        let app = launch()

        let chessTab = app.tabBars.buttons["Chess"]
        XCTAssertTrue(chessTab.waitForExistence(timeout: 5), "Chess tab should exist")
        chessTab.tap()

        XCTAssertTrue(app.navigationBars["Chess"].waitForExistence(timeout: 3))

        // Set up the starting position from the board menu.
        app.navigationBars["Chess"].buttons["Board"].tap()
        app.buttons["Set up starting position"].tap()

        // Each square is its own accessibility element, identified by its
        // algebraic name, so a known square proves the position actually
        // reached the view.
        let e1 = app.descendants(matching: .any).matching(identifier: "e1").firstMatch
        XCTAssertTrue(e1.waitForExistence(timeout: 5), "the board should expose square e1")
        XCTAssertEqual(e1.label, "e1, White king",
                       "the starting position should put a white king on e1")

        // Both sides should get a move. A `.standard` think time searches
        // twice, so allow generously.
        XCTAssertTrue(app.staticTexts["White"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Black"].waitForExistence(timeout: 20))

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "chess-tab"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testTappingASquareOpensThePiecePalette() throws {
        let app = launch()
        app.tabBars.buttons["Chess"].tap()
        XCTAssertTrue(app.navigationBars["Chess"].waitForExistence(timeout: 3))

        // An empty board starts out with every square empty; tapping one
        // must offer the palette so a position can be built by hand — the
        // path users take while the models are still being trained.
        let d4 = app.descendants(matching: .any).matching(identifier: "d4").firstMatch
        XCTAssertTrue(d4.waitForExistence(timeout: 5))
        d4.tap()
        XCTAssertTrue(app.staticTexts["What's on d4?"].waitForExistence(timeout: 3))
    }
}

/// Launch-argument flags understood by the app.
///
/// A UI test bundle is black-box — it cannot import `Scan` — so this key
/// is necessarily duplicated: the reader is the literal
/// `"uitest.skipWhatsNew"` in `ContentView.onAppear`. Naming it here at
/// least makes the pairing greppable from both ends.
enum UITestFlags {
    static let skipWhatsNew = "uitest.skipWhatsNew"
}
