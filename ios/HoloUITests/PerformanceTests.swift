import XCTest

/// Speed checks run on every push (CI's Performance step), on the demo collection. The numbers
/// land in perf.txt next to the screenshots, with a running history, so a change that makes
/// the app slower shows up. Simulator numbers: compare them run to run, not to a real phone.
///
/// - Sheet open / close and a tap inside a sheet: how long until the next screen is there.
/// - Idle CPU on Overview and under an open sheet: anything left animating shows up here.
/// - Scrolling Overview: time and CPU for a few swipes down and back.
final class PerformanceTests: XCTestCase {
    private func options(_ n: Int = 4) -> XCTMeasureOptions {
        let o = XCTMeasureOptions()
        o.iterationCount = n
        return o
    }

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-HoloDemo", "-HoloDemoKind", "mixed"] + args
        app.launch()
        sleep(4)
        return app
    }

    /// Tap a card in Collection until Owned is up, then Done until it's gone.
    func testOwnedSheetOpenClose() {
        let app = launch(["-HoloTab", "collection"])
        let tile = app.buttons["holding-tile"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        measure(metrics: [XCTClockMetric()], options: options()) {
            tile.tap()
            XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 5))
            app.buttons["Done"].firstMatch.tap()
            let gone = NSPredicate(format: "exists == false")
            let wait = XCTNSPredicateExpectation(predicate: gone, object: app.buttons["Done"].firstMatch)
            XCTWaiter().wait(for: [wait], timeout: 5)
        }
    }

    /// Inside Owned: tap "What if I sell?" until its sheet is up, then close it.
    func testTapInsideSheet() {
        let app = launch(["-HoloTab", "collection"])
        let tile = app.buttons["holding-tile"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        tile.tap()
        let whatIf = app.buttons["What if I sell?"].firstMatch
        XCTAssertTrue(whatIf.waitForExistence(timeout: 5))
        measure(metrics: [XCTClockMetric()], options: options()) {
            whatIf.tap()
            let close = app.buttons["Close"].firstMatch
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            close.tap()
            let gone = NSPredicate(format: "exists == false")
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: gone, object: close)], timeout: 5)
        }
    }

    /// CPU while Owned sits open doing nothing. Should be near zero: nothing loops under or on it.
    func testIdleUnderSheet() {
        let app = launch(["-HoloTab", "collection"])
        let tile = app.buttons["holding-tile"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        tile.tap()
        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 5))
        sleep(2)
        measure(metrics: [XCTCPUMetric(application: app)], options: options(3)) { sleep(3) }
    }

    /// CPU while Overview sits still (the floating fan and ticker run here).
    func testIdleOverview() {
        let app = launch([])
        measure(metrics: [XCTCPUMetric(application: app)], options: options(3)) { sleep(3) }
    }

    /// Three swipes down Overview and three back.
    func testScrollOverview() {
        let app = launch([])
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(application: app)], options: options(3)) {
            for _ in 0 ..< 3 { app.swipeUp(velocity: .fast) }
            for _ in 0 ..< 3 { app.swipeDown(velocity: .fast) }
        }
    }
}
