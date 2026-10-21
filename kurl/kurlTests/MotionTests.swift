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
}
