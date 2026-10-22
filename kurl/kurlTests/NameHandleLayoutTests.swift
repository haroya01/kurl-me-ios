import XCTest

@testable import kurl

final class NameHandleLayoutTests: XCTestCase {

    private func widths(_ available: CGFloat, name: CGFloat, handle: CGFloat) -> (name: CGFloat, handle: CGFloat) {
        NameHandleLayout.widths(available: available, name: name, handle: handle, floor: 70, spacing: 4)
    }

    func testBothKeepTheirWidthWhenTheyFit() {
        let result = widths(300, name: 120, handle: 150)
        XCTAssertEqual(result.name, 120)
        XCTAssertEqual(result.handle, 150)
    }

    func testALongNameNoLongerSqueezesTheHandleBelowItsFloor() {
        let result = widths(240, name: 400, handle: 200)
        XCTAssertEqual(result.handle, 70)
        XCTAssertEqual(result.name, 166)
    }

    func testAShortHandleStaysWholeBesideALongName() {
        let result = widths(240, name: 400, handle: 50)
        XCTAssertEqual(result.handle, 50)
        XCTAssertEqual(result.name, 186)
    }

    func testTheHandleTruncatesFirstWhileTheNameFits() {
        let result = widths(240, name: 100, handle: 300)
        XCTAssertEqual(result.name, 100)
        XCTAssertEqual(result.handle, 136)
    }
}
