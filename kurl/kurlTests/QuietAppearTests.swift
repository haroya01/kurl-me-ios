import XCTest

@testable import kurl

@MainActor
final class QuietAppearTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1000)

    func testTheFirstScreenStaggers() {
        XCTAssertTrue(QuietAppear.staggers(index: 0, at: start, burstStart: start))
        XCTAssertTrue(QuietAppear.staggers(index: 5, at: start.addingTimeInterval(0.2), burstStart: start))
    }

    func testRowsMetByScrollingDoNotWait() {
        XCTAssertFalse(QuietAppear.staggers(index: 5, at: start.addingTimeInterval(1.2), burstStart: start))
    }

    func testOnlyTheFirstEightEverStagger() {
        XCTAssertFalse(QuietAppear.staggers(index: 8, at: start, burstStart: start))
    }
}
