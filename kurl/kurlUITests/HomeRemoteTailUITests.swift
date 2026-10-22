import XCTest

final class HomeRemoteTailUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLatestMixesInOtherServerPostsMarkedAsSuch() {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--feed", "latest"]
        app.launch()

        let mixed = app.descendants(matching: .any).matching(identifier: "trending.note")
            .matching(NSPredicate(format: "label CONTAINS %@", "다른 서버")).firstMatch
        for _ in 0..<6 where !(mixed.exists && mixed.frame.minX >= 0 && mixed.isHittable) { app.swipeUp() }
        XCTAssertTrue(mixed.waitForExistence(timeout: 10), "최신 피드 중간에 다른 서버 표시가 붙은 글이 없음")
        XCTAssertGreaterThanOrEqual(mixed.frame.minX, 0, "섞인 글이 지금 보는 최신 탭이 아닌 옆 탭에 있음")
    }

    func testSeenOtherServerPostsComeAfterTheUnseenOnceMyFeedRunsOut() {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--feed", "latest", "--short-latest", "--mock-seen-latest", "2"]
        app.launch()

        let seen = app.staticTexts["remote.seen"]
        _ = app.descendants(matching: .any).matching(identifier: "trending.note").firstMatch.waitForExistence(timeout: 12)
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

    func testExploreOtherServersIsForYouWithoutASwitch() {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "search", "--explore-lane", "remote"]
        app.launch()

        let first = app.descendants(matching: .any).matching(identifier: "trending.note").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 12))
        XCTAssertTrue(first.label.contains("작은 서버"), "맞춤 첫 글이 아님: \(first.label)")
        XCTAssertFalse(app.segmentedControls.firstMatch.exists, "다른 서버 칸에 전환이 남아 있음")
    }
}
