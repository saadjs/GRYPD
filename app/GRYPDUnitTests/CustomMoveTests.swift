import XCTest
@testable import GRYPD

final class CustomMoveTests: XCTestCase {
    /// The custom-move slug must match `pipeline/common.py: slugify` exactly, so a
    /// user-created move auto-merges with a future catalog move of the same name.
    func testSlugMatchesPipelineSlugify() {
        XCTAssertEqual(CustomMove.slug(from: "Hammer Curl"), "hammer-curl")
        XCTAssertEqual(CustomMove.slug(from: "Bicep Curls"), "bicep-curls")
        XCTAssertEqual(CustomMove.slug(from: "ROW"), "row")
        XCTAssertEqual(CustomMove.slug(from: "  Weird!!!Name  "), "weird-name")
        XCTAssertEqual(CustomMove.slug(from: "Split Squat (L)"), "split-squat-l")
        XCTAssertEqual(CustomMove.slug(from: "21s"), "21s")
    }

    /// Input with no letters or digits yields an empty slug; the picker rejects it.
    func testSlugIsEmptyWhenNoAlphanumerics() {
        XCTAssertEqual(CustomMove.slug(from: "!!!"), "")
        XCTAssertEqual(CustomMove.slug(from: "   "), "")
    }
}
