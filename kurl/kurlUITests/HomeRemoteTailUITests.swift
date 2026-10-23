import XCTest

final class HomeRemoteTailUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHomeIsForYouThenFollowingWithKurlAndOtherServerPostsInOneList() {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--feed", "latest"]
        app.launch()

        let forYou = app.buttons["segment.for-you"]
        XCTAssertTrue(forYou.waitForExistence(timeout: 12), "홈 머리에 추천이 없음")
        XCTAssertTrue(forYou.isSelected, "옛 최신 값이 추천으로 열리지 않음")
        XCTAssertTrue(app.buttons["segment.following"].exists, "홈 머리에 팔로잉이 없음")
        XCTAssertFalse(app.buttons["segment.trending"].exists, "인기 탭이 남아 있음")
        XCTAssertFalse(app.buttons["segment.latest"].exists, "최신 탭이 남아 있음")
        XCTAssertLessThan(forYou.frame.midX, app.buttons["segment.following"].frame.midX, "추천이 첫 탭이 아님")

        let remote = app.descendants(matching: .any).matching(identifier: "trending.note")
            .matching(NSPredicate(format: "label CONTAINS %@", "다른 서버")).firstMatch
        XCTAssertTrue(remote.waitForExistence(timeout: 10), "추천에 다른 서버 표시가 붙은 글이 없음")
        XCTAssertLessThan(remote.frame.minY, app.frame.height, "첫 화면에 다른 서버 글이 없음(한 줄 랭킹이 아님)")
    }

    func testSeenOtherServerPostsStayOutOfHomeAndTheEndSaysAllSeen() {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--feed", "latest", "--short-latest", "--mock-seen-latest", "2"]
        app.launch()

        func row(_ text: String) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: "trending.note")
                .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        }
        let end = app.buttons["home.allSeen.following"]
        XCTAssertTrue(row("작은 서버").waitForExistence(timeout: 12), "맞춤 첫 글이 없음")
        for _ in 0..<12 where !(end.exists && end.isHittable) { app.swipeUp() }
        XCTAssertTrue(end.waitForExistence(timeout: 10), "목록 끝에 다 봤어요가 없음")
        XCTAssertTrue(row("Morning light").exists, "안 본 다른 서버 글이 빠짐")
        XCTAssertFalse(row("fediverse").exists, "본 다른 서버 글이 홈에 다시 나옴")
        XCTAssertFalse(app.staticTexts["remote.seen"].exists, "홈에 이미 본 글 구분선이 나옴")
    }

    func testExploreOtherServersIsForYouWithoutASwitch() {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "search", "--explore-lane", "remote"]
        app.launch()

        func row(_ text: String) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: "trending.note")
                .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        }
        let top = row("작은 서버")
        let later = row("紫陽花")
        XCTAssertTrue(top.waitForExistence(timeout: 12), "맞춤 첫 글이 없음")
        XCTAssertTrue(later.waitForExistence(timeout: 5))
        XCTAssertLessThan(top.frame.minY, later.frame.minY, "맞춤 순서가 아님(최신이면 はな 글이 먼저)")
        XCTAssertFalse(app.segmentedControls.firstMatch.exists, "다른 서버 칸에 전환이 남아 있음")
    }
}
