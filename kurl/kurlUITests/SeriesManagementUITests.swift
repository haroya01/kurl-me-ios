//
//  SeriesManagementUITests.swift
//  kurlUITests
//
//  주인 시리즈 상세의 관리(수정·순서 편집·삭제) 진입로를 실기기 경로로 확인 + 스크린샷.
//  목 상세(honggildong/hexagonal, id 7)는 로그인 사용자와 같은 작가라 관리 메뉴가 뜬다.
//

import XCTest

final class SeriesManagementUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func shot(_ name: String) {
        let s = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

    private func launched() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--series", "honggildong/hexagonal"]
        app.launch()
        return app
    }

    func testOwnerManagementMenuAndSheets() throws {
        let app = launched()

        // 마스트헤드가 뜬다(주인 시리즈 상세 로드 확인).
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS '헥사고날 전환기'")).firstMatch
                .waitForExistence(timeout: 15),
            "시리즈 마스트헤드가 없음")
        shot("1-series-owner-detail")

        // 우상단 관리 메뉴 — "시리즈 관리" 접근성 라벨의 버튼.
        let manage = app.buttons["시리즈 관리"]
        XCTAssertTrue(manage.waitForExistence(timeout: 5), "관리 메뉴 버튼이 없음(주인 아님?)")
        manage.tap()
        // 메뉴가 열려 세 액션이 보인다.
        XCTAssertTrue(app.buttons["수정"].waitForExistence(timeout: 5), "수정 액션 없음")
        XCTAssertTrue(app.buttons["순서 편집"].exists, "순서 편집 액션 없음")
        XCTAssertTrue(app.buttons["시리즈 삭제"].exists, "삭제 액션 없음")
        shot("2-manage-menu-open")

        // 수정 시트 — 이름·주소 입력.
        app.buttons["수정"].tap()
        XCTAssertTrue(
            app.staticTexts["시리즈 수정"].waitForExistence(timeout: 5), "수정 시트가 안 뜸")
        shot("3-edit-sheet")

        // 시트 닫기(드래그 인디케이터 아래로 스와이프).
        app.swipeDown(velocity: .fast)
        Thread.sleep(forTimeInterval: 0.6)

        // 순서 편집 시트 — 회차가 순번과 함께 뜬다.
        manage.tap()
        app.buttons["순서 편집"].tap()
        XCTAssertTrue(
            app.navigationBars["순서 편집"].waitForExistence(timeout: 8), "순서 편집 시트가 안 뜸")
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS '포트와 어댑터'")).firstMatch
                .waitForExistence(timeout: 8),
            "순서 편집에 회차가 없음")
        shot("4-reorder-sheet")

        // 취소로 닫고 삭제 확인 알림까지 — 파괴적 액션은 .alert 로 되묻는다.
        app.buttons["취소"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        manage.tap()
        app.buttons["시리즈 삭제"].tap()
        XCTAssertTrue(
            app.alerts.firstMatch.waitForExistence(timeout: 5), "삭제 확인 알림이 안 뜸")
        shot("5-delete-confirm-alert")
    }
}
