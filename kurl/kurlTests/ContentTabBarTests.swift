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

final class PullTriggerTests: XCTestCase {

    func testHoldingAPullFiresOnceEvenAfterTheRefreshEnds() {
        var trigger = PullTrigger()
        XCTAssertFalse(trigger.fires(overpull: 40, refreshing: false))
        XCTAssertTrue(trigger.fires(overpull: 90, refreshing: false))
        XCTAssertFalse(trigger.fires(overpull: 120, refreshing: true))
        XCTAssertFalse(trigger.fires(overpull: 120, refreshing: false))
    }

    func testLettingGoReArmsTheNextPull() {
        var trigger = PullTrigger()
        XCTAssertTrue(trigger.fires(overpull: 90, refreshing: false))
        XCTAssertFalse(trigger.fires(overpull: 30, refreshing: false))
        XCTAssertFalse(trigger.fires(overpull: 90, refreshing: false))
        XCTAssertFalse(trigger.fires(overpull: 0, refreshing: false))
        XCTAssertTrue(trigger.fires(overpull: 90, refreshing: false))
    }
}

@MainActor
final class TabBarVisibilityTests: XCTestCase {
    private static var alive: [TabBarVisibility] = []

    private func make() -> TabBarVisibility {
        let visibility = TabBarVisibility()
        Self.alive.append(visibility)
        return visibility
    }

    func testReadingDownHidesAndScrollingUpBringsTheBarBack() {
        let visibility = make()
        let reader = UUID()
        visibility.report(offset: 0, from: reader)
        visibility.report(offset: 300, from: reader)
        XCTAssertTrue(visibility.scrollHidden)
        visibility.report(offset: 240, from: reader)
        XCTAssertFalse(visibility.scrollHidden)
    }

    func testAfterATabSwitchTheScrolledReaderReportingAgainKeepsTheBar() {
        let visibility = make()
        let reader = UUID()
        visibility.report(offset: 0, from: reader)
        visibility.report(offset: 1500, from: reader)
        XCTAssertTrue(visibility.scrollHidden)
        visibility.reset()
        visibility.report(offset: 1500, from: reader)
        XCTAssertFalse(visibility.scrollHidden)
        visibility.report(offset: 1560, from: reader)
        XCTAssertTrue(visibility.scrollHidden)
    }

    func testComingBackFromAnotherScreenKeepsTheBarWhereItWas() {
        let visibility = make()
        let reader = UUID()
        let author = UUID()
        visibility.report(offset: 0, from: reader)
        visibility.report(offset: 1500, from: reader)
        visibility.report(offset: 1400, from: reader)
        XCTAssertFalse(visibility.scrollHidden)
        visibility.report(offset: 0, from: author)
        visibility.report(offset: 20, from: author)
        visibility.report(offset: 1400, from: reader)
        XCTAssertFalse(visibility.scrollHidden)
    }
}
