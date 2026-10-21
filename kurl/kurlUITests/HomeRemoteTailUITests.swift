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
}
