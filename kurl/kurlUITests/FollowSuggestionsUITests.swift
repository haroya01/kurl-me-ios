//
//  FollowSuggestionsUITests.swift
//  kurlUITests
//

import XCTest

final class FollowSuggestionsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSuggestionsOfferAFollowAndCanBeSetAside() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "search"]
        app.launch()

        let haneul = app.descendants(matching: .any)["suggestion.haneul"]
        XCTAssertTrue(haneul.waitForExistence(timeout: 15), "검색 탭에 팔로우 추천이 없음")
        XCTAssertTrue(
            haneul.staticTexts.matching(NSPredicate(format: "label CONTAINS '3명이 팔로우'")).firstMatch.exists,
            "추천 이유가 안 보임")
        XCTAssertTrue(
            app.descendants(matching: .any)["suggestion.narae"].staticTexts["요즘 많이 팔로우해요"].exists,
            "인기 추천 이유가 안 보임")
        XCTAssertFalse(app.staticTexts["작가"].exists, "로그인했는데 익명 작가 레일이 함께 섬")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "follow-suggestions"
        shot.lifetime = .keepAlways
        add(shot)

        let minji = app.descendants(matching: .any)["suggestion.minji"]
        app.buttons["suggestion.dismiss.minji"].tap()
        XCTAssertTrue(minji.waitForNonExistence(timeout: 8), "지운 추천이 남아 있음")

        let follow = haneul.buttons["follow.button"]
        follow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(
            haneul.buttons.matching(NSPredicate(format: "label CONTAINS '요청함'")).firstMatch
                .waitForExistence(timeout: 8),
            "잠긴 계정 추천을 팔로우했는데 요청함이 아님")
    }
}
