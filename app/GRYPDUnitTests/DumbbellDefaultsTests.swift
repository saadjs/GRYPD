import XCTest
@testable import GRYPD

final class DumbbellDefaultsTests: XCTestCase {
    private let defaults = DumbbellDefaults(light: 10, medium: 15, heavy: 25, unit: .lb)

    func testClassifyBucketsRepresentativeMoves() {
        XCTAssertEqual(DumbbellTier.classify("squat"), .heavy)
        XCTAssertEqual(DumbbellTier.classify("lunge"), .heavy)
        XCTAssertEqual(DumbbellTier.classify("chest-press"), .heavy)
        XCTAssertEqual(DumbbellTier.classify("overhead-press"), .medium)
        XCTAssertEqual(DumbbellTier.classify("curl"), .medium)
        XCTAssertEqual(DumbbellTier.classify("lateral-raise"), .light)
        XCTAssertEqual(DumbbellTier.classify("front-raise"), .light)
        XCTAssertEqual(DumbbellTier.classify("tricep-extension"), .light)
    }

    func testClassifyReturnsNilForBodyweightMoves() {
        XCTAssertNil(DumbbellTier.classify("plank"))
        XCTAssertNil(DumbbellTier.classify("burpee"))
        XCTAssertNil(DumbbellTier.classify("mountain-climbers"))
        XCTAssertNil(DumbbellTier.classify("not-a-real-move"))
    }

    func testWeightForMoveSlugUsesBucket() {
        XCTAssertEqual(defaults.weight(forMoveSlug: "squat"), 25)          // heavy
        XCTAssertEqual(defaults.weight(forMoveSlug: "overhead-press"), 15) // medium
        XCTAssertEqual(defaults.weight(forMoveSlug: "lateral-raise"), 10)  // light
        XCTAssertNil(defaults.weight(forMoveSlug: "plank"))                // bodyweight
        XCTAssertNil(defaults.weight(forMoveSlug: nil))
    }

    func testNearestOptionSnapsToPickerGrid() {
        XCTAssertEqual(DumbbellDefaults.nearestOption(11.3, for: .lb), 12.5)
        XCTAssertEqual(DumbbellDefaults.nearestOption(11.34, for: .kg), 11)
    }

    func testOptionsAreUnitSpecific() {
        XCTAssertTrue(DumbbellDefaults.options(for: .kg).contains(7))
        XCTAssertTrue(DumbbellDefaults.options(for: .kg).contains(11))
        XCTAssertFalse(DumbbellDefaults.options(for: .kg).contains(200))
        XCTAssertTrue(DumbbellDefaults.options(for: .lb).contains(12.5))
        XCTAssertFalse(DumbbellDefaults.options(for: .lb).contains(200))
    }

    func testFormatDropsTrailingZero() {
        XCTAssertEqual(DumbbellDefaults.format(25, unit: .lb), "25 lb")
        XCTAssertEqual(DumbbellDefaults.format(12.5, unit: .kg), "12.5 kg")
    }
}
