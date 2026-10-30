import XCTest

/// Opens the app in demo mode on each main screen and saves full-page screenshots, scrolling
/// down a screen at a time, into $SCREENSHOT_DIR (set by CI). Not a pass/fail check of the
/// design: it produces pictures to look at.
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    func testHome() { capture("home", args: [], pages: 7) }
    func testCollection() { capture("collection", args: ["-HoloTab", "collection"], pages: 3) }
    func testCardPage() { capture("card-single", args: ["-HoloProduct", "sample:umbreon-vmax-alt"], pages: 4) }
    func testSealedPage() { capture("card-sealed", args: ["-HoloProduct", "sample:es-bb"], pages: 3) }
    func testDeal() { capture("deal", args: ["-HoloTab", "deal"], pages: 1) }
    // Graded slabs: Home, Collection and a slab's card page in the graded demo.
    func testGradedHome() { capture("graded-home", args: ["-HoloDemoKind", "graded"], pages: 6) }
    func testGradedCollection() { capture("graded-collection", args: ["-HoloDemoKind", "graded", "-HoloTab", "collection"], pages: 2) }
    func testGradedCardPage() { capture("graded-card", args: ["-HoloDemoKind", "graded", "-HoloProduct", "sample:pikachu-ex-ss"], pages: 2) }

    private func capture(_ name: String, args: [String], pages: Int) {
        let app = XCUIApplication()
        app.launchArguments = ["-HoloDemo"] + args
        app.launch()
        // Let pictures load and entrance animations settle.
        sleep(4)
        for page in 0 ..< pages {
            save(app.screenshot(), "\(name)-\(page)")
            app.swipeUp(velocity: .slow)
            sleep(2)
        }
    }

    private func save(_ shot: XCUIScreenshot, _ name: String) {
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
