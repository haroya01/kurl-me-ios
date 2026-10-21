import XCTest

@testable import kurl

@MainActor
final class LoadStateStageTests: XCTestCase {
    func testOnlyTheKindOfStateCounts() {
        XCTAssertEqual(LoadState<Int>.idle.stage, LoadState<Int>.loading.stage)
        XCTAssertEqual(LoadState<Int>.loaded(1).stage, LoadState<Int>.loaded(2).stage)
        XCTAssertNotEqual(LoadState<Int>.loading.stage, LoadState<Int>.loaded(1).stage)
        XCTAssertNotEqual(LoadState<Int>.loaded(1).stage, LoadState<Int>.failed("x").stage)
    }
}
