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

        let newest = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'fediverse'")).firstMatch
        if !(newest.exists && newest.isHittable) { app.swipeUp() }
        XCTAssertTrue(newest.waitForExistence(timeout: 5), "본 글이 구분선 아래로 이어지지 않음")
        XCTAssertGreaterThan(newest.frame.minY, seen.frame.maxY, "가장 최신 글이 본 글이면 구분선 아래에 와야 함")
    }
}
