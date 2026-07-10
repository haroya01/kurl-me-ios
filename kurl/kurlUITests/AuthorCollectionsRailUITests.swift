//
//  AuthorCollectionsRailUITests.swift
//  kurlUITests
//

import XCTest

/// 작가 프로필의 "컬렉션" 레일 — 큐레이션(엮은 길)이 시리즈 레일과 같은 문법으로 프로필에 뜨고,
/// 카드를 탭하면 그 컬렉션 상세로 항해하는지 실기기 경로로 확인한다(목 공개 컬렉션).
final class AuthorCollectionsRailUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func shot(_ name: String) {
        let s = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

    private func label(containing text: String) -> XCUIElement {
        XCUIApplication().descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func testCollectionsRailRendersAndNavigates() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--author", "minji"]
        app.launch()

        // 컬렉션 레일 머릿글 + 공개 컬렉션 카드 두 개가 시리즈 아래에 뜬다.
        XCTAssertTrue(
            label(containing: "컬렉션").waitForExistence(timeout: 15),
            "컬렉션 레일 머릿글이 없음")
        XCTAssertTrue(
            label(containing: "느린 사고").waitForExistence(timeout: 5),
            "공개 컬렉션 카드가 없음")
        shot("1-collections-rail")

        // 카드 탭 → 그 컬렉션 상세로 항해(상세의 연결 블록이 보이면 열린 것).
        let card = app.buttons
            .matching(NSPredicate(format: "label CONTAINS '느린 사고'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "컬렉션 카드 버튼이 없음")
        card.tap()

        // 상세 = 큐레이터의 잇는 말(why) 한 줄이 보인다(느린 사고 컬렉션의 첫 연결).
        XCTAssertTrue(
            label(containing: "경계가 먼저라는 한 문장").waitForExistence(timeout: 10),
            "컬렉션 상세로 항해하지 못함")
        shot("2-collection-detail")
    }
}
