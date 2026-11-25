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

    func testNoNumberKeepsTheNameForPictures() {
        // Only the name could be read: no number, so pictures decide between that Pokémon's cards.
        let r = OnDeviceScan.parse([("Charizard", box(top: 0.95)), ("Fire Spin", box(top: 0.5))])
        XCTAssertEqual(r?.name, "Charizard")
        XCTAssertEqual(r?.number, "")
    }

    func testNothingReadMeansNotSure() {
        XCTAssertNil(OnDeviceScan.parse([("Basic", box(top: 0.95))]))
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

    func testSubsetNumberBesideTheRealOne() {
        // 30th Celebration cards print "031/128 09/30": the set's own number wins.
        let r = OnDeviceScan.parse([("Pikachu", box(top: 0.95)), ("031/128 09/30", box(top: 0.04))])
        XCTAssertEqual(r?.number, "031/128")
    }

    func testNameMustFitTheCard() {
        XCTAssertTrue(OnDeviceScan.nameAgrees("PASIC TerapagoseX", "Terapagos ex - 092/131"))
        XCTAssertTrue(OnDeviceScan.nameAgrees("Pikachu", "Pikachu - 031/128"))
        XCTAssertTrue(OnDeviceScan.nameAgrees(nil, "Seaking"))
        XCTAssertFalse(OnDeviceScan.nameAgrees("A SIC", "Basic Grass Energy - 009 (30th Celebration)"))
    }

    func testTotalOneOff() {
        XCTAssertTrue(OnDeviceScan.closeNumber("021/131", "021/130"))
        XCTAssertFalse(OnDeviceScan.closeNumber("021/131", "021/131"))
        XCTAssertFalse(OnDeviceScan.closeNumber("022/131", "021/130"))
        XCTAssertFalse(OnDeviceScan.closeNumber("021/142", "021/130"))
    }

    func testFullNumberNeedsNoName() {
        XCTAssertTrue(OnDeviceScan.numberIsEnough("092/131"))
        XCTAssertFalse(OnDeviceScan.numberIsEnough("09/30"))
        XCTAssertFalse(OnDeviceScan.numberIsEnough("074"))
    }
}
