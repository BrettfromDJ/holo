import XCTest
import UIKit
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
        let r = OnDeviceScan.parse(lines)
        XCTAssertEqual(r?.name, "Umbreon VMAX")
        XCTAssertEqual(r?.number, "215/203")
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
        XCTAssertTrue(OnDeviceScan.closeNumber("021/131", "021/137"))
    }

    func testFullNumberNeedsNoName() {
        XCTAssertTrue(OnDeviceScan.numberIsEnough("092/131"))
        XCTAssertFalse(OnDeviceScan.numberIsEnough("09/30"))
        XCTAssertFalse(OnDeviceScan.numberIsEnough("074"))
    }

    func testTotalReadNeedsATotal() {
        XCTAssertTrue(OnDeviceScan.strictNumber("074/131", "074/131"))
        XCTAssertFalse(OnDeviceScan.strictNumber("074", "074/131"))
        XCTAssertTrue(OnDeviceScan.strictNumber("074", "074"))
    }

    func testMisreadStageLabelIsNotAName() {
        XCTAssertTrue(OnDeviceScan.looksLikeStage("BASR"))
        XCTAssertTrue(OnDeviceScan.looksLikeStage("STAOEJ"))
        XCTAssertFalse(OnDeviceScan.looksLikeStage("Mewtwo"))
        XCTAssertFalse(OnDeviceScan.looksLikeStage("Seaking"))
        let r = OnDeviceScan.parse([("BASR", box(top: 0.97)), ("Mewtwo", box(top: 0.93)), ("063/128", box(top: 0.04))])
        XCTAssertEqual(r?.name, "Mewtwo")
    }

    func testPatternVersionsCountAsOneCard() {
        func hit(_ id: String, _ name: String) -> SearchHit {
            SearchHit(product: Product(id: id, name: name, setId: "pre", number: "021/131", kind: "single"))
        }
        let picked = OnDeviceScan.oneCard([hit("2", "Seaking (Poke Ball Pattern)"), hit("1", "Seaking"), hit("3", "Seaking (Master Ball Pattern)")])
        XCTAssertEqual(picked?.product.id, "1")
        XCTAssertNil(OnDeviceScan.oneCard([hit("1", "Seaking"), hit("4", "Goldeen")]))
    }

    func testPromoNumberInTheCorner() {
        let r = OnDeviceScan.parse([("Vaporeon", box(top: 0.95)), ("Spiral Drain 30", box(top: 0.5)), ("SVP EN 168", box(top: 0.06))])
        XCTAssertEqual(r?.number, "168")
        // Numbers higher up (HP, damage) aren't the card number.
        XCTAssertEqual(OnDeviceScan.parse([("Vaporeon", box(top: 0.95)), ("Fighting Whirlpool 90", box(top: 0.4))])?.number, "")
    }

    func testJapaneseCardIsMarked() {
        let r = OnDeviceScan.parse([("ホゲータex", box(top: 0.95)), ("124/103 SAR", box(top: 0.04))])
        XCTAssertEqual(r?.japanese, true)
        XCTAssertNil(r?.name)
        XCTAssertEqual(r?.number, "124/103")
    }

    func testStampedOdditiesGiveWay() {
        func hit(_ id: String, _ name: String, _ set: String) -> SearchHit {
            SearchHit(product: Product(id: id, name: name, setName: set, setId: set, number: "063/128", kind: "single"))
        }
        let kept = OnDeviceScan.realSets([hit("1", "Mewtwo - 063/128 (What's Your Favorite Stamp)", "Miscellaneous Cards & Products"), hit("2", "Mewtwo", "ME: 30th Celebration")])
        XCTAssertEqual(kept.map(\.product.id), ["2"])
    }

    func testNextLineCountsWhenTheFirstIsALabel() {
        let r = OnDeviceScan.parse([("HASG", box(top: 0.97)), ("Articuno", box(top: 0.93)), ("097", box(top: 0.04))])!
        XCTAssertTrue(OnDeviceScan.fits(r, "Articuno - 097 (30th Celebration)"))
        XCTAssertFalse(OnDeviceScan.fits(r, "Zapdos - 098 (30th Celebration)"))
    }

    func testExclusivesGiveWayToo() {
        func hit(_ id: String, _ name: String, _ set: String) -> SearchHit {
            SearchHit(product: Product(id: id, name: name, setName: set, setId: set, number: "028/088", kind: "single"))
        }
        let kept = OnDeviceScan.realSets([hit("1", "Luxray", "ME03: Perfect Order"), hit("2", "Luxray - 028/088 (Cosmos Holo)", "Blister Exclusives")])
        XCTAssertEqual(kept.map(\.product.id), ["1"])
    }

    func testEvolvesLineIsNotTheName() {
        // An evolved card's top line names the Pokémon it evolves from.
        let r = OnDeviceScan.parse([("Evolves from Ivysaur Put Venusaur on the Stage 1 card", box(top: 0.98)),
                                    ("Venusaur", box(top: 0.93)), ("15/102", box(top: 0.04))])!
        XCTAssertEqual(r.name, "Venusaur")
        // Misread title: the name in "Put … on the" still counts.
        let m = OnDeviceScan.parse([("Put Blastoise on the Sta", box(top: 0.98)), ("Blastoisa", box(top: 0.93))])!
        XCTAssertTrue(OnDeviceScan.fits(m, "Blastoise"))
    }

    func testLevelIsNotAPromoNumber() {
        let r = OnDeviceScan.parse([("Dark Gengar", box(top: 0.93)), ("LV. 32 #94", box(top: 0.06))])
        XCTAssertEqual(r?.number, "")
    }

    func testOriginalPrintBeatsReprints() {
        func hit(_ id: String, _ set: String) -> SearchHit {
            SearchHit(product: Product(id: id, name: "Venusaur", setName: set, setId: set, number: "15/102", kind: "single"))
        }
        let hits = [hit("1", "Base Set"), hit("2", "Base Set (Shadowless)"), hit("3", "Celebrations: Classic Collection")]
        let plain = OnDeviceScan.Reading(name: "Venusaur", number: "15/102")
        XCTAssertEqual(OnDeviceScan.commonPrints(hits, plain).map(\.product.id), ["1"])
        var reprint = plain
        reprint.reprint2021 = true
        XCTAssertEqual(OnDeviceScan.commonPrints(hits, reprint).map(\.product.id), ["3"])
        let copyright = OnDeviceScan.parse([("Venusaur", box(top: 0.93)), ("©2021 Pokémon / Nintendo 15/102", box(top: 0.04))])
        XCTAssertEqual(copyright?.reprint2021, true)
    }
}

final class PrintMarksTests: XCTestCase {
    /// A plain green card, with the stamp and/or the Pikachu painted where they sit.
    private func card(stamp: Bool, pikachu: Bool) -> CGImage {
        let size = CGSize(width: 630, height: 880)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: 0.55, green: 0.78, blue: 0.55, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            if stamp {
                UIColor.black.setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 0.055 * size.width, y: 0.535 * size.height, width: 0.045 * size.width, height: 0.045 * size.width))
            }
            if pikachu {
                UIColor(red: 1, green: 0.85, blue: 0.05, alpha: 1).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 0.78 * size.width, y: 0.43 * size.height, width: 0.18 * size.width, height: 0.12 * size.height))
            }
        }
        return img.cgImage!
    }

    func testReadsTheStamp() {
        XCTAssertEqual(PrintMarks.read(card(stamp: true, pikachu: false))?.firstEdition, true)
        XCTAssertEqual(PrintMarks.read(card(stamp: false, pikachu: false))?.firstEdition, false)
    }

    func testFindsTheCardInsideAHolder() {
        // The card in a toploader: the photo has a margin around the card's yellow border.
        let inner = card(stamp: true, pikachu: false)
        let size = CGSize(width: 760, height: 1000)
        let holder = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: 0.75, green: 0.68, blue: 0.6, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.98, green: 0.82, blue: 0.2, alpha: 1).setFill()
            ctx.fill(CGRect(x: 70, y: 60, width: 630, height: 880))
            UIImage(cgImage: inner).draw(in: CGRect(x: 90, y: 80, width: 590, height: 840))
        }.cgImage!
        XCTAssertEqual(PrintMarks.read(holder)?.firstEdition, true)
    }

    func testReadsThePikachu() {
        XCTAssertEqual(PrintMarks.read(card(stamp: false, pikachu: true))?.celebrations, true)
        XCTAssertEqual(PrintMarks.read(card(stamp: false, pikachu: false))?.celebrations, false)
    }
}
