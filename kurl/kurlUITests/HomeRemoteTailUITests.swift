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
        XCTAssertTrue(app.buttons["segment.blog"].exists, "홈 머리에 블로그가 없음")
        XCTAssertFalse(app.buttons["segment.trending"].exists, "인기 탭이 남아 있음")
        XCTAssertFalse(app.buttons["segment.latest"].exists, "최신 탭이 남아 있음")
        XCTAssertLessThan(forYou.frame.midX, app.buttons["segment.following"].frame.midX, "추천이 첫 탭이 아님")

        let remote = app.staticTexts["다른 서버"].firstMatch
        XCTAssertTrue(remote.waitForExistence(timeout: 10), "추천에 다른 서버 표시가 붙은 글이 없음")
        XCTAssertLessThan(remote.frame.minY, app.frame.height, "첫 화면에 다른 서버 글이 없음(한 줄 랭킹이 아님)")
    }

    func testSeenOtherServerPostsStayOutOfHomeAndTheEndSaysAllSeen() {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--feed", "latest", "--short-latest", "--mock-seen-latest", "2"]
        app.launch()

        func body(_ id: Int) -> XCUIElement { app.descendants(matching: .any)["note.body.\(id)"] }
        let end = app.buttons["home.allSeen.following"]
        XCTAssertTrue(body(9705).waitForExistence(timeout: 12), "추천 첫 글이 없음")
        for _ in 0..<12 where !(end.exists && end.isHittable) { app.swipeUp() }
        XCTAssertTrue(end.waitForExistence(timeout: 10), "목록 끝에 다 봤어요가 없음")
        XCTAssertTrue(body(9706).exists, "안 본 다른 서버 글이 빠짐")
        XCTAssertFalse(body(9700).exists, "본 다른 서버 글이 홈에 다시 나옴")
        XCTAssertFalse(body(9701).exists, "본 다른 서버 글이 홈에 다시 나옴")
        XCTAssertFalse(app.staticTexts["remote.seen"].exists, "홈에 이미 본 글 구분선이 나옴")
    }

    func testAnOtherServerPostOnAHashtagPageOpensItsNoteAndComesBackToThePage() {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tag", "아키텍처"]
        app.launch()

        let notes = app.buttons["tag.tab.notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 15), "태그 화면이 안 열림")
        notes.tap()
        XCTAssertTrue(app.buttons["note.menu.9501"].waitForExistence(timeout: 8), "태그 화면에 kurl 노트가 없음")
        let remote = app.descendants(matching: .any).matching(identifier: "trending.note")
            .matching(NSPredicate(format: "label CONTAINS %@", "화이트보드")).firstMatch
        XCTAssertTrue(remote.waitForExistence(timeout: 8), "태그 화면에 다른 서버 글이 없음")

        remote.tap()
        XCTAssertTrue(app.navigationBars["노트"].waitForExistence(timeout: 8), "다른 서버 글을 눌렀는데 노트가 안 열림")
        XCTAssertFalse(notes.exists, "노트 화면 밑에 태그 화면이 그대로 보임")
        app.navigationBars["노트"].buttons.firstMatch.tap()
        XCTAssertTrue(notes.waitForExistence(timeout: 8), "노트에서 돌아왔는데 태그 화면이 아님")
        XCTAssertTrue(notes.isSelected, "돌아온 태그 화면이 노트 탭이 아님")
    }
}
