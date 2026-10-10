//
//  PeopleAndMentionsUITests.swift
//  kurlUITests
//

import XCTest

final class PeopleAndMentionsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func search(_ text: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "search"]
        app.launch()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 12))
        field.tap()
        field.typeText(text)
        return app
    }

    func testPostResultsLeadWithUpToThreePeopleAndThePeopleScopeFollows() throws {
        let app = search("han")

        let typeahead = app.buttons["search.person.haneul"]
        XCTAssertTrue(typeahead.waitForExistence(timeout: 15), "글 결과 위에 사람이 없음")
        XCTAssertTrue(app.buttons["search.person.hanbit"].exists)
        shoot("search-posts-with-people")

        let peopleScope = app.segmentedControls.buttons["사람"].firstMatch
        XCTAssertTrue(peopleScope.waitForExistence(timeout: 6), "검색 범위에 사람이 없음")
        peopleScope.tap()
        let haneul = app.descendants(matching: .any)["person.haneul"]
        XCTAssertTrue(haneul.waitForExistence(timeout: 10), "사람 범위에 결과가 없음")
        XCTAssertTrue(haneul.staticTexts["하늘"].exists)
        XCTAssertTrue(haneul.staticTexts["@haneul"].exists)
        XCTAssertTrue(haneul.staticTexts["프로덕트 디자이너"].exists)
        XCTAssertFalse(
            app.descendants(matching: .any)["person.hanbit"].staticTexts["@hanbit"].exists,
            "표시 이름이 없는데 핸들을 두 번 씀")
        shoot("search-people-scope")

        let follow = haneul.buttons["follow.button"]
        follow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(
            haneul.buttons.matching(NSPredicate(format: "label CONTAINS '요청함'")).firstMatch
                .waitForExistence(timeout: 8),
            "잠긴 계정을 팔로우했는데 요청함이 아님")
    }

    func testThePeopleScopeAsksForTwoLetters() throws {
        let app = search("h")

        let scope = app.segmentedControls.buttons["사람"].firstMatch
        XCTAssertTrue(scope.waitForExistence(timeout: 6))
        scope.tap()
        XCTAssertTrue(
            app.staticTexts["두 글자 이상 입력하면 사람을 찾아요"].waitForExistence(timeout: 8),
            "한 글자에 안내가 없음")
    }

    func testTheInboxNarrowsToMentionsAndRepliesAndStartsOnEverything() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "account"]
        app.launch()
        let bell = app.buttons["알림"].firstMatch
        XCTAssertTrue(bell.waitForExistence(timeout: 12), "계정 헤더에 알림 벨이 없음")
        bell.tap()

        let like = app.buttons.matching(NSPredicate(format: "label CONTAINS '글을 좋아해요'")).firstMatch
        XCTAssertTrue(like.waitForExistence(timeout: 12), "전체에 좋아요 알림이 없음")
        let mentions = app.buttons["멘션"].firstMatch
        XCTAssertTrue(mentions.exists, "전체 | 멘션 세그먼트가 없음")
        mentions.tap()

        let mention = app.buttons.matching(NSPredicate(format: "label CONTAINS '나를 언급했어요'")).firstMatch
        XCTAssertTrue(mention.waitForExistence(timeout: 10), "멘션 탭에 멘션이 없음")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS '답글을 남겼어요'")).firstMatch.exists)
        XCTAssertFalse(like.exists, "멘션 탭에 좋아요가 섞임")
        XCTAssertFalse(app.buttons["notifications.followRequests"].exists, "멘션 탭에 팔로우 요청 줄이 섬")
        shoot("inbox-mentions")

        app.terminate()
        app.launch()
        let bellAgain = app.buttons["알림"].firstMatch
        XCTAssertTrue(bellAgain.waitForExistence(timeout: 12))
        bellAgain.tap()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS '글을 좋아해요'")).firstMatch
                .waitForExistence(timeout: 12),
            "다시 열었는데 전체가 아님")
    }
}
