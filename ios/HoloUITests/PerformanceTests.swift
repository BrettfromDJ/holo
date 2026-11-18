import XCTest

/// Speed checks run on every push (CI's Performance step), on the demo collection. The numbers
/// land in perf.txt next to the screenshots, with a running history, so a change that makes
/// the app slower shows up. Simulator numbers: compare them run to run, not to a real phone.
///
/// - Sheet open / close and a tap inside a sheet: how long until the next screen is there.
/// - Idle CPU on Overview and under an open sheet: anything left animating shows up here.
/// - Scrolling Overview: time and CPU for a few swipes down and back.
/// - Launch: how long the app takes to open.
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

    /// Tap a card in Collection until its page is up (a card you own opens there now), then back
    /// until Collection is there again. (Kept under its old name so the history carries on.)
    func testOwnedSheetOpenClose() { runOwnedSheetOpenClose([]) }

    private func runOwnedSheetOpenClose(_ extra: [String]) {
        let app = launch(["-HoloTab", "collection"] + extra)
        let tile = app.buttons["holding-tile"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        measure(metrics: [XCTClockMetric()], options: options()) {
            tile.tap()
            let row = app.buttons["copy-row"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(tile.waitForExistence(timeout: 5))
            let gone = NSPredicate(format: "exists == false")
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: gone, object: row)], timeout: 5)
        }
    }

    /// Inside Owned (a copy's row on the card page): tap "What if I sell?" until its sheet is up, then close it.
    func testTapInsideSheet() { runTapInsideSheet([]) }

    private func runTapInsideSheet(_ extra: [String]) {
        let app = launch(["-HoloTab", "collection"] + extra)
        let tile = app.buttons["holding-tile"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        tile.tap()
        let row = app.buttons["copy-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
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
        let row = app.buttons["copy-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 5))
        sleep(2)
        measure(metrics: [XCTCPUMetric(application: app)], options: options(3)) { sleep(3) }
    }

    /// CPU while Overview sits still (the floating fan and ticker run here).
    func testIdleOverview() {
        let app = launch(["-HoloTab", "collection", "-HoloCollectionMode", "summary"])
        measure(metrics: [XCTCPUMetric(application: app)], options: options(3)) { sleep(3) }
    }

    /// CPU while Home sits still (the card of the day drifts, its rays turn and sparks rise here).
    func testIdleHome() {
        let app = launch([])
        measure(metrics: [XCTCPUMetric(application: app)], options: options(3)) { sleep(3) }
    }

    /// Launch time, cold start to first frame, on the demo (no network: app start only).
    func testLaunch() {
        measure(metrics: [XCTApplicationLaunchMetric()], options: options(3)) {
            let app = XCUIApplication()
            app.launchArguments = ["-HoloDemo", "-HoloDemoKind", "mixed"]
            app.launch()
        }
    }

    /// Three swipes down Overview and three back.
    func testScrollOverview() { runScrollOverview([]) }

    private func runScrollOverview(_ extra: [String]) {
        let app = launch(["-HoloTab", "collection", "-HoloCollectionMode", "summary"] + extra)
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(application: app)], options: options(3)) {
            for _ in 0 ..< 3 { app.swipeUp(velocity: .fast) }
            for _ in 0 ..< 3 { app.swipeDown(velocity: .fast) }
        }
    }

    // The same checks with one feature switched off (see Demo.perf* in the app), so a slowdown
    // can be pinned on the feature that caused it: compare each with its plain version.
    func testOwnedSheetOpenCloseNoThumbnails() { runOwnedSheetOpenClose(["-HoloPerfNoThumbnails"]) }
    func testOwnedSheetOpenCloseNoSellMeter() { runOwnedSheetOpenClose(["-HoloPerfNoSellMeter"]) }
    func testTapInsideSheetNoThumbnails() { runTapInsideSheet(["-HoloPerfNoThumbnails"]) }
    func testTapInsideSheetNoSellMeter() { runTapInsideSheet(["-HoloPerfNoSellMeter"]) }
    func testScrollOverviewNoThumbnails() { runScrollOverview(["-HoloPerfNoThumbnails"]) }
    func testScrollOverviewPlainCGC() { runScrollOverview(["-HoloPerfPlainCGC"]) }
}
