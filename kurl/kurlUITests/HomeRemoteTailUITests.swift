import XCTest

final class HomeRemoteTailUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLatestRunsOnIntoOtherServersBelowKurl() {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--feed", "latest", "--short-latest"]
        app.launch()

        let heading = app.staticTexts["home.remoteTail"]
        _ = heading.waitForExistence(timeout: 12)
        for _ in 0..<6 where !(heading.exists && heading.frame.minX >= 0) { app.swipeUp() }
        XCTAssertTrue(heading.waitForExistence(timeout: 10), "최신 바닥에 다른 서버 최신 구분선이 없음")
        XCTAssertGreaterThanOrEqual(heading.frame.minX, 0, "구분선이 지금 보는 최신 탭이 아닌 옆 탭에 있음")

        func remoteRows() -> [XCUIElement] {
            app.descendants(matching: .any).matching(identifier: "trending.note").allElementsBoundByIndex
                .filter { $0.frame.minX >= 0 && $0.frame.minY > heading.frame.minY }
        }
        if remoteRows().isEmpty { app.swipeUp() }
        XCTAssertFalse(remoteRows().isEmpty, "구분선 아래로 다른 서버 행이 이어지지 않음")
    }

    func testSeenOtherServerPostsComeAfterTheUnseenUnderTheirOwnHeading() {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--feed", "latest", "--short-latest", "--mock-seen-latest", "2"]
        app.launch()

        let heading = app.staticTexts["home.remoteTail"]
        let seen = app.staticTexts["remote.seen"]
        _ = heading.waitForExistence(timeout: 12)
        for _ in 0..<12 where !(seen.exists && seen.frame.minX >= 0 && seen.isHittable) { app.swipeUp() }
        XCTAssertTrue(seen.waitForExistence(timeout: 10), "본 글 앞에 이미 본 글 구분선이 없음")

        func row(_ text: String) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: "trending.note")
                .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        }
        let newest = row("fediverse")
        if !(newest.exists && newest.isHittable) { app.swipeUp() }
        XCTAssertTrue(newest.waitForExistence(timeout: 5), "본 글이 구분선 아래로 이어지지 않음")
        XCTAssertGreaterThan(newest.frame.minY, seen.frame.maxY, "가장 최신 글이 본 글이면 구분선 아래에 와야 함")
        let oldestUnseen = row("Morning light")
        XCTAssertTrue(oldestUnseen.exists, "안 본 글 마지막 행이 없음")
        XCTAssertLessThan(oldestUnseen.frame.maxY, seen.frame.minY, "안 본 글은 구분선 위에 와야 함")
    }

    func testExploreOtherServersOpensOnForYouAndTheSwitchTurnsToLatest() {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "search", "--explore-lane", "remote"]
        app.launch()

        let feed = app.segmentedControls["remote.feed"]
        XCTAssertTrue(feed.waitForExistence(timeout: 12), "다른 서버 칸에 추천·최신 전환이 없음")
        XCTAssertTrue(feed.buttons.element(boundBy: 0).isSelected, "기본이 추천이 아님")
        let first = app.descendants(matching: .any).matching(identifier: "trending.note").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(first.label.contains("작은 서버"), "추천 첫 글이 아님: \(first.label)")

        feed.buttons.element(boundBy: 1).tap()
        let latest = NSPredicate(format: "label CONTAINS %@", "fediverse")
        expectation(for: latest, evaluatedWith: app.descendants(matching: .any).matching(identifier: "trending.note").firstMatch)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(feed.buttons.element(boundBy: 1).isSelected)
    }
}
