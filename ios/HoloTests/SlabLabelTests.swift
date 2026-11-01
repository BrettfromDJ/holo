import XCTest
@testable import Holo

/// The CGC label's lines, stand-in cert and Pristine rule, the same as the website's graded.test.ts.
final class SlabLabelTests: XCTestCase {
    func testCGCLinesAreCardGameSetAndRarity() {
        let charizard = Product(id: "c", name: "Charizard V", setName: "Brilliant Stars", number: "154/172", kind: "single")
        XCTAssertEqual(Slab.cgcLines(charizard), ["Charizard V", "Pokémon", "Brilliant Stars - 154/172"])
        let pikachu = Product(id: "p", name: "Pikachu", number: "001", rarity: "Promo", kind: "single")
        XCTAssertEqual(Slab.cgcLines(pikachu), ["Pikachu", "Pokémon", "#001", "Promo"])
    }

    func testFallbackCertMatchesTheWebsite() {
        let charizard = Product(id: "c", name: "Charizard V", setName: "Brilliant Stars", number: "154/172", kind: "single")
        XCTAssertEqual(Slab.fallbackCert(charizard), "3113800001")
        XCTAssertEqual(Slab.fallbackCert(Product(id: "p", name: "Pikachu", kind: "single")), "8875520001")
    }

    func testOnlyACGCTenCanBePristine() {
        XCTAssertEqual(Slab.descriptor(company: "CGC", grade: "10"), "GEM MINT")
        XCTAssertEqual(Slab.descriptor(company: "BGS", grade: "10"), "PRISTINE")
        XCTAssertTrue(Slab.isCGCTen(company: "cgc", grade: "10"))
        XCTAssertFalse(Slab.isCGCTen(company: "CGC", grade: "9.5"))
        XCTAssertFalse(Slab.isCGCTen(company: "PSA", grade: "10"))
    }
}
