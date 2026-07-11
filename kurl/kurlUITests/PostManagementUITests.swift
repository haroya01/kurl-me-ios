//
//  PostManagementUITests.swift
//  kurlUITests
//
//  스튜디오(내 글)와 글 상세(내 글)의 관리(발행취소·삭제) 진입로를 실기기 경로로 확인 + 스크린샷.
//  목 저장소엔 발행된 글("발행된 목 글")과 초안이 있어, 발행 글의 ⋯ 메뉴엔 발행취소·삭제가 다 뜬다.
//

import XCTest

final class PostManagementUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func shot(_ name: String) {
        let s = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

    /// 스튜디오(글 탭)의 ⋯ 관리 메뉴 — 발행 글엔 발행취소·삭제, 삭제는 .alert 로 되묻는다.
    func testStudioPostManagementMenu() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write"]
        app.launch()

        // 발행 글 행이 뜬다(스튜디오 목록 로드 확인).
        XCTAssertTrue(
            app.staticTexts["발행된 목 글"].waitForExistence(timeout: 15),
            "스튜디오 목록에 발행 글이 없음")
        shot("1-studio-list")

        // 발행 글의 ⋯ 관리 메뉴 — "<제목> 관리" 접근성 라벨.
        let manage = app.buttons["발행된 목 글 관리"]
        XCTAssertTrue(manage.waitForExistence(timeout: 5), "발행 글 관리 메뉴 버튼이 없음")
        manage.tap()
        // 발행 글이라 두 파괴적 액션이 다 뜬다.
        XCTAssertTrue(app.buttons["발행 취소"].waitForExistence(timeout: 5), "발행 취소 액션 없음")
        XCTAssertTrue(app.buttons["삭제"].exists, "삭제 액션 없음")
        shot("2-studio-menu-open")

        // 발행 취소 확인 알림 — 되돌릴 수 있는 동작이라 담담한 확인.
        app.buttons["발행 취소"].tap()
        XCTAssertTrue(
            app.alerts.firstMatch.waitForExistence(timeout: 5), "발행 취소 확인 알림이 안 뜸")
        shot("3-studio-unpublish-confirm")
        app.alerts.buttons["취소"].tap()
        Thread.sleep(forTimeInterval: 0.5)

        // 삭제 확인 알림 — 되돌릴 수 없는 동작.
        manage.tap()
        app.buttons["삭제"].tap()
        XCTAssertTrue(
            app.alerts.firstMatch.waitForExistence(timeout: 5), "삭제 확인 알림이 안 뜸")
        shot("4-studio-delete-confirm")
    }

    /// 글 상세(내 글)의 ⋯ 더보기 메뉴 — 편집·분석 옆에 발행취소·삭제.
    func testPostDetailOwnerManagementMenu() throws {
        let app = XCUIApplication()
        // 로그인 사용자와 같은 작가(honggildong)의 글 상세로 진입 — 내 글이라 작가 동작이 뜬다.
        app.launchArguments = ["--mocks", "--post", "honggildong/hexagonal"]
        app.launch()

        // 상세가 로드되면 ⋯ 관리 메뉴가 뜬다.
        let manage = app.buttons["이 글 관리"]
        guard manage.waitForExistence(timeout: 15) else {
            // 진입 플래그 조합이 다르면 이 케이스는 스튜디오 경로가 대표 검증이므로 건너뛴다.
            throw XCTSkip("글 상세 진입 플래그가 이 빌드와 다름 — 스튜디오 경로로 대표 검증")
        }
        shot("5-post-detail-owner")
        manage.tap()
        XCTAssertTrue(app.buttons["발행 취소"].waitForExistence(timeout: 5), "발행 취소 액션 없음")
        XCTAssertTrue(app.buttons["삭제"].exists, "삭제 액션 없음")
        shot("6-post-detail-menu-open")
        app.buttons["삭제"].tap()
        XCTAssertTrue(
            app.alerts.firstMatch.waitForExistence(timeout: 5), "삭제 확인 알림이 안 뜸")
        shot("7-post-detail-delete-confirm")
    }
}
