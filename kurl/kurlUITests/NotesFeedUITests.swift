//
//  NotesFeedUITests.swift
//  kurlUITests
//

import XCTest

/// 노트 피드 — 스위처 진입, 목 피드 렌더, 컴포저 발행 왕복(맨 위 꽂힘)까지.
/// 좋아요·삭제는 단위 검증이 어려운 낙관 토글이라 여기선 발행 경로만 결정적으로 잡는다.
final class NotesFeedUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testNotesReachableFromAccountAndPublishes() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "account"]
        app.launch()

        // 노트는 1급 피드 탭에서 강등 — 내 계정의 서재(헤더 책 버튼) 안 목록으로 들어간다.
        let library = app.buttons["서재"].firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 12), "계정 탭에 서재 버튼이 없음")
        library.tap()

        let entry = app.buttons
            .matching(NSPredicate(format: "label CONTAINS '노트'")).firstMatch
        var tries = 0
        while entry.exists, !entry.isHittable, tries < 4 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "노트 진입 행 없음")
        entry.tap()

        // 목 피드의 첫 노트가 보이면 디코더·행 렌더까지 산 것.
        let seeded = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS '헥사고날 포트'")).firstMatch
        XCTAssertTrue(seeded.waitForExistence(timeout: 10), "노트 목 피드가 렌더되지 않음")

        // 목 모드 = 로그인 상태 — 키보드 위 유리 컴포저가 있어야 한다.
        let field = app.textFields["지금 떠오른 생각은…"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "노트 컴포저 바 없음")
        // 존재만으론 부족 — 떠 있는 탭바가 컴포저 바를 가리면 a11y 트리엔 있어도 화면에 안 그려져
        // 명중·포커스가 안 된다(첫 노트 못 씀). 명중 가능해야 탭이 키보드를 띄운다.
        XCTAssertTrue(field.isHittable, "노트 컴포저가 하단바에 가려 명중 불가(탭바 가림 회귀)")

        field.tap()
        field.typeText("uitest note round trip")
        app.buttons["노트 올리기"].tap()

        let published = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS 'uitest note round trip'")).firstMatch
        XCTAssertTrue(published.waitForExistence(timeout: 6), "발행한 노트가 맨 위에 안 꽂힘")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "notes-from-account"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testFollowingFeedRendersCards() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--feed", "following"]
        app.launch()

        // 구독함도 최신·인기와 같은 발견 카드 — 알림 같던 인박스 행을 걷어냈다. 목 팔로잉 피드의 글 제목이 선다.
        let row = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS '발행된 목 글'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "구독함 카드가 렌더되지 않음")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "following-cards"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
