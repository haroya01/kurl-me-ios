import XCTest

final class ExploreFirstRowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "search"] + extra
        app.launch()
        return app
    }

    private func post(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "trending.note")
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func testTheFirstTopicOpensItsLinkPageFromTheTopOfItsRow() throws {
        let app = launch()

        let heading = app.staticTexts["지금 도는 이야기"]
        XCTAssertTrue(heading.waitForExistence(timeout: 15), "트렌드에 도는 이야기 머리말이 없음")
        let row = app.buttons["topic.link:https://news.example/library-night"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "첫 화제 행이 없음")
        XCTAssertTrue(row.label.contains("31명이 이야기 중"), row.label)
        XCTAssertLessThan(heading.frame.minY, row.frame.minY)

        row.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.05)).tap()

        let header = app.buttons["linkNotes.open"]
        XCTAssertTrue(header.waitForExistence(timeout: 8), "첫 행 윗부분을 눌렀는데 링크 화면이 안 열림")
        XCTAssertTrue(header.label.contains("동네 도서관"), header.label)
        let said = post(app, containing: "퇴근하고도 들를 수 있겠다")
        XCTAssertTrue(said.waitForExistence(timeout: 8), "링크 화면에 이 기사를 이야기하는 다른 서버 글이 없음")
        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "news.example,")).firstMatch
        let onlyTheLink = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "@nara@byeol.example")).firstMatch
        XCTAssertTrue(card.exists, "링크만 올린 글에 카드가 없음")
        XCTAssertGreaterThan(card.frame.minY, onlyTheLink.frame.minY, "말을 덧붙인 글이 머리의 링크 카드를 다시 그림")

        said.tap()
        XCTAssertTrue(app.navigationBars["노트"].waitForExistence(timeout: 8), "링크 화면의 다른 서버 글을 눌렀는데 노트가 안 열림")
        XCTAssertTrue(
            app.descendants(matching: .any)["note.linkCard.7131"].waitForExistence(timeout: 5),
            "노트 화면에서는 링크 카드가 보여야 함")
    }

    func testOtherLanguageTopicsFollowUnderTheirHeadingAndPopularPostsComeLast() throws {
        let app = launch()

        let lastOwn = app.buttons["topic.link:https://dongne.example/flea-market"]
        let firstOther = app.buttons["topic.tag:朝の一枚"]
        let other = app.staticTexts["다른 언어"]
        let popular = app.staticTexts["인기 글"]
        XCTAssertTrue(app.staticTexts["지금 도는 이야기"].waitForExistence(timeout: 15), "트렌드에 도는 이야기 머리말이 없음")
        for _ in 0..<4 where !firstOther.exists { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(firstOther.exists, "다른 언어 화제가 없음")
        XCTAssertTrue(other.exists, "다른 언어 화제 앞에 머리말이 없음")
        XCTAssertTrue(lastOwn.label.hasPrefix("6"), lastOwn.label)
        XCTAssertTrue(firstOther.label.hasPrefix("7"), "순위가 두 묶음을 이어서 세지 않음: \(firstOther.label)")
        XCTAssertTrue(firstOther.label.contains("일본어"), firstOther.label)
        XCTAssertLessThan(lastOwn.frame.minY, other.frame.minY, "읽는 사람 언어의 화제가 먼저가 아님")
        XCTAssertLessThan(other.frame.minY, firstOther.frame.minY)

        let more = app.buttons["topic.more"]
        let clearOfTabBar = app.frame.height - 160
        for _ in 0..<10 where !(more.exists && more.isHittable && more.frame.maxY < clearOfTabBar) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
        }
        XCTAssertTrue(more.exists, "열 개를 넘는데 더 보기가 없음")
        XCTAssertTrue(popular.exists, "화제 아래에 인기 글 머리말이 없음")
        XCTAssertLessThan(more.frame.minY, popular.frame.minY)
        more.tap()

        XCTAssertTrue(app.navigationBars["지금 도는 이야기"].waitForExistence(timeout: 8), "더 보기를 눌렀는데 전체 목록이 안 열림")
        let beyondTen = app.buttons["topic.link:https://kurashi.example/ketsuro"]
        for _ in 0..<8 where !beyondTen.exists { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(beyondTen.exists, "전체 목록에 열 번째 뒤 화제가 없음")
        XCTAssertTrue(beyondTen.label.hasPrefix("14"), beyondTen.label)
    }

    func testATagTopicOpensItsNotesUnderRelatedArticles() throws {
        let app = launch()

        let row = app.buttons["topic.tag:첫눈"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "태그 화제 행이 없음")
        row.tap()

        let notes = app.buttons["tag.tab.notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 8), "태그 화면이 안 열림")
        XCTAssertTrue(notes.isSelected, "화제 태그가 노트 탭으로 열리지 않음")
        let related = app.staticTexts["관련 기사"]
        XCTAssertTrue(related.waitForExistence(timeout: 8), "관련 기사가 없음")
        let article = app.descendants(matching: .any)["topic.related.0"]
        XCTAssertTrue(article.label.contains("첫눈 예보"), article.label)
        let first = post(app, containing: "눈 온다, 진짜로")
        XCTAssertTrue(first.waitForExistence(timeout: 8), "태그 화면에 다른 서버 글이 없음")
        XCTAssertLessThan(related.frame.minY, first.frame.minY, "관련 기사가 글 목록 위에 있지 않음")

        first.tap()
        XCTAssertTrue(app.navigationBars["노트"].waitForExistence(timeout: 8), "태그 화면의 다른 서버 글을 눌렀는데 노트가 안 열림")
        app.navigationBars["노트"].buttons.firstMatch.tap()
        XCTAssertTrue(related.waitForExistence(timeout: 8), "노트에서 돌아왔는데 태그 화면이 아님")
    }

    func testWithoutTopicsTheFirstPopularPostOpensItsAuthorFromTheAvatar() throws {
        let app = launch(["--mock-topics", "empty"])

        let first = post(app, containing: "Hello from the fediverse")
        XCTAssertTrue(first.waitForExistence(timeout: 15), "화제가 없을 때 인기 글이 바로 나오지 않음")
        XCTAssertFalse(app.staticTexts["지금 도는 이야기"].exists, "화제가 없는데 머리말이 남음")
        XCTAssertFalse(app.staticTexts["인기 글"].exists, "인기 글만 있는데 머리말이 붙음")

        let avatar = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "님 프로필")).firstMatch
        XCTAssertTrue(avatar.waitForExistence(timeout: 5), "첫 행에 아바타가 없음")
        avatar.tap()
        XCTAssertTrue(
            app.navigationBars["@mina@mastodon.social"].waitForExistence(timeout: 8),
            "첫 행 아바타를 눌렀는데 계정 화면이 안 열림")
    }
}
