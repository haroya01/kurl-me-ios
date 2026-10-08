import XCTest
@testable import kurl

final class ContentTabBarTests: XCTestCase {

    func testLabelsThatFitTheirSlotsKeepEqualWidths() {
        let widths = TabStripWidths.widths(labels: [17, 34, 53, 51, 51], available: 362)
        XCTAssertEqual(widths, Array(repeating: 362 / 5, count: 5))
    }

    func testALongLabelTakesItsShareWhenTheRowStillFits() throws {
        let widths = try XCTUnwrap(TabStripWidths.widths(labels: [20, 20, 120], available: 240))
        XCTAssertEqual(widths.reduce(0, +), 240, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(widths[2], 120 + TabStripWidths.gap)
        XCTAssertEqual(widths[0], widths[1], accuracy: 0.001)
    }

    func testLabelsThatCannotFitScrollInsteadOfTruncating() {
        XCTAssertNil(TabStripWidths.widths(labels: [40, 60, 120, 95, 95], available: 362))
    }
}
