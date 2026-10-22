import SwiftUI
import XCTest

@testable import kurl

@MainActor
final class MotionTests: XCTestCase {
    func testReduceMotionDropsTheAnimation() {
        XCTAssertNil(Motion.animation(Motion.move, reduced: true))
        XCTAssertEqual(Motion.animation(Motion.move, reduced: false), Motion.move)
    }

    func testThreeLengthsOnOneCurve() {
        XCTAssertEqual(Motion.micro, .smooth(duration: 0.2))
        XCTAssertEqual(Motion.move, .smooth(duration: 0.28))
        XCTAssertEqual(Motion.stage, .smooth(duration: 0.45))
    }

    func testOnlyTheFirstScreenStaggers() {
        let start = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(QuietAppear.staggers(index: 0, at: start, burstStart: start))
        XCTAssertTrue(QuietAppear.staggers(index: 5, at: start.addingTimeInterval(0.2), burstStart: start))
        XCTAssertFalse(QuietAppear.staggers(index: 5, at: start.addingTimeInterval(1.2), burstStart: start))
        XCTAssertFalse(QuietAppear.staggers(index: 8, at: start, burstStart: start))
    }

    func testLoadTransitionKeysOnlyTheKindOfState() {
        XCTAssertEqual(LoadState<Int>.idle.stage, LoadState<Int>.loading.stage)
        XCTAssertEqual(LoadState<Int>.loaded(1).stage, LoadState<Int>.loaded(2).stage)
        XCTAssertNotEqual(LoadState<Int>.loading.stage, LoadState<Int>.loaded(1).stage)
        XCTAssertNotEqual(LoadState<Int>.loaded(1).stage, LoadState<Int>.failed("x").stage)
    }
}
