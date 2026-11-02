import XCTest
@testable import Holo

/// The on-device scan's text parsing and number matching (the lookup itself needs the network).
final class OnDeviceScanTests: XCTestCase {
    private func box(top: CGFloat) -> CGRect { CGRect(x: 0.1, y: top - 0.05, width: 0.6, height: 0.05) }

    func testReadsNameAndNumber() {
        let lines: [(String, CGRect)] = [
            ("BASIC", box(top: 0.97)),
            ("Umbreon VMAX HP310", box(top: 0.93)),
            ("Dark Signal", box(top: 0.5)),
            ("215/203", box(top: 0.05)),
        ]
        XCTAssertEqual(OnDeviceScan.parse(lines), OnDeviceScan.Reading(name: "Umbreon VMAX", number: "215/203"))
    }

    func testTrainerGalleryNumber() {
        let r = OnDeviceScan.parse([("Pikachu", box(top: 0.95)), ("TG05 / TG30", box(top: 0.04))])
        XCTAssertEqual(r?.number, "TG05/TG30")
    }

    func testNoNumberMeansNotSure() {
        XCTAssertNil(OnDeviceScan.parse([("Charizard", box(top: 0.95)), ("Fire Spin", box(top: 0.5))]))
    }

    func testSlabsGoToTheServer() {
        XCTAssertNil(OnDeviceScan.parse([("PSA GEM MT 10", box(top: 0.95)), ("215/203", box(top: 0.04))]))
    }

    func testNumberMatching() {
        XCTAssertTrue(OnDeviceScan.sameNumber("215/203", "215/203"))
        XCTAssertTrue(OnDeviceScan.sameNumber("005/102", "5/102"))
        XCTAssertTrue(OnDeviceScan.sameNumber("TG05/TG30", "TG5/TG30"))
        XCTAssertFalse(OnDeviceScan.sameNumber("215/198", "215/203"))
        XCTAssertFalse(OnDeviceScan.sameNumber("214/203", "215/203"))
        XCTAssertFalse(OnDeviceScan.sameNumber(nil, "215/203"))
    }
}
