//
//  HeaderActionsLayoutTests.swift
//  kurlTests
//

import XCTest

@testable import kurl

@MainActor
final class HeaderActionsLayoutTests: XCTestCase {

    private let follow = CGSize(width: 100, height: 33)
    private let counts = CGSize(width: 150, height: 16)
    private let card = CGSize(width: 80, height: 44)

    func testEverythingOnOneRowWhenItFits() {
        let result = HeaderActionsLayout.arrange(sizes: [follow, counts, card], width: 362, spacing: 10)
        XCTAssertEqual(result.size, CGSize(width: 362, height: 44))
        XCTAssertEqual(result.frames[0], CGRect(x: 0, y: 5.5, width: 100, height: 33))
        XCTAssertEqual(result.frames[1], CGRect(x: 110, y: 14, width: 150, height: 16))
        XCTAssertEqual(result.frames[2], CGRect(x: 282, y: 0, width: 80, height: 44))
    }

    func testMiddleDropsToSecondRowWhenTooNarrow() {
        let result = HeaderActionsLayout.arrange(sizes: [follow, counts, card], width: 300, spacing: 10)
        XCTAssertEqual(result.frames[0], CGRect(x: 0, y: 5.5, width: 100, height: 33))
        XCTAssertEqual(result.frames[2], CGRect(x: 220, y: 0, width: 80, height: 44))
        XCTAssertEqual(result.frames[1], CGRect(x: 0, y: 54, width: 150, height: 16))
        XCTAssertEqual(result.size, CGSize(width: 300, height: 70))
        XCTAssertFalse(result.frames[0].intersects(result.frames[1]))
        XCTAssertFalse(result.frames[1].intersects(result.frames[2]))
    }

    func testSecondRowNeverWiderThanTheRow() {
        let wide = CGSize(width: 400, height: 16)
        let result = HeaderActionsLayout.arrange(sizes: [follow, wide, card], width: 300, spacing: 10)
        XCTAssertEqual(result.frames[1].width, 300)
    }

    func testHiddenMiddleTakesNoSpace() {
        let result = HeaderActionsLayout.arrange(sizes: [follow, .zero, card], width: 362, spacing: 10)
        XCTAssertEqual(result.size.height, 44)
        XCTAssertEqual(result.frames[2].maxX, 362)
    }

    func testTwoItemsKeepTrailingAtTheEdge() {
        let result = HeaderActionsLayout.arrange(sizes: [counts, card], width: 362, spacing: 10)
        XCTAssertEqual(result.frames[1].maxX, 362)
        XCTAssertEqual(result.size.height, 44)
    }

    func testWithoutMiddleTheTrailingItemDropsInsteadOfOverlapping() {
        let longCounts = CGSize(width: 240, height: 16)
        let result = HeaderActionsLayout.arrange(sizes: [longCounts, card], width: 300, spacing: 10)
        XCTAssertEqual(result.frames[0], CGRect(x: 0, y: 0, width: 240, height: 16))
        XCTAssertEqual(result.frames[1], CGRect(x: 220, y: 26, width: 80, height: 44))
        XCTAssertEqual(result.size, CGSize(width: 300, height: 70))
        XCTAssertFalse(result.frames[0].intersects(result.frames[1]))
    }
}
