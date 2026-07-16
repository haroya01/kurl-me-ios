//
//  DialogPresentationUITests.swift
//  kurlUITests
//

import XCTest

/// 파괴·확인 다이얼로그(회원 탈퇴·신고·차단) 도달 스모크 + 표현 눈검증.
/// confirmationDialog 은 이 앱에서 세로·가로 모두 부리 팝오버로 바뀌어 트리거와 무관한 화면
/// 중앙에 붕 떴다 — 그 자리를 .alert(중앙 모달)·detent 시트로 바꿨다. 이 테스트는 세로·가로
/// 양쪽에서 각 플로우를 다이얼로그까지 몰아 스크린샷을 첨부한다(표현은 첨부로 눈 검증).
/// simctl 은 터치를 못 넣으니 XCUITest 가 유일한 경로다.
final class DialogPresentationUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func shot(_ name: String) {
        let s = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

    private func rotate(_ orientation: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = orientation
        Thread.sleep(forTimeInterval: 1.0)
    }

    // MARK: 회원 탈퇴 (계정 → 설정 → 회원 탈퇴)

    private func openAccountDeletion(_ app: XCUIApplication) {
        let settings = app.buttons["설정"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 15), "계정 탭에 설정 버튼이 없음")
        settings.tap()
        let withdraw = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '회원 탈퇴'")).firstMatch
        // 최하단 행 = 회원 탈퇴(App Store 5.1.1(v) 필수 진입점). 설정 본문은 LazyVStack 이라
        // 화면 밖 행은 a11y 트리에 없어(가로는 뷰포트가 낮아 더 심하다) 스크롤로 그려 낸 뒤 판정한다.
        // 커스텀 하단바가 설정 스택에서 접히지 않으면 이 행이 바 뒤에 갇혀 아무리 끌어올려도
        // hittable 위치로 안 올라온다 — 몇 번 스크롤해도 명중 못 하면 탭바 가림 회귀.
        let scroll = app.scrollViews.firstMatch
        var found = false
        for _ in 0..<10 {
            if withdraw.exists && withdraw.isHittable { found = true; break }
            if scroll.exists { scroll.swipeUp(velocity: .slow) } else { app.swipeUp() }
            Thread.sleep(forTimeInterval: 0.35)
        }
        shot("account-delete-after-scroll")
        XCTAssertTrue(found, "회원 탈퇴 행이 하단바에 가려 명중 불가(탭바 가림 회귀)")
        withdraw.tap()
        Thread.sleep(forTimeInterval: 0.9)
    }

    func testAccountDeletionPortrait() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "account"]
        app.launch()
        rotate(.portrait)
        openAccountDeletion(app)
        shot("account-delete-portrait")
    }

    func testAccountDeletionLandscape() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "account"]
        app.launch()
        rotate(.landscapeLeft)
        openAccountDeletion(app)
        shot("account-delete-landscape")
    }

    // MARK: 신고 (작가 페이지 → 더 보기 → 신고)

    private func openReport(_ app: XCUIApplication) {
        let more = app.buttons["더 보기"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 15), "작가 페이지에 더 보기 메뉴가 없음")
        more.tap()
        let report = app.buttons.matching(NSPredicate(format: "label CONTAINS '신고'")).firstMatch
        XCTAssertTrue(report.waitForExistence(timeout: 6), "메뉴에 신고 항목이 없음")
        report.tap()
        Thread.sleep(forTimeInterval: 0.9)
    }

    func testReportPortrait() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--author", "yuki_dev"]
        app.launch()
        rotate(.portrait)
        openReport(app)
        shot("report-portrait")
    }

    func testReportLandscape() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--author", "yuki_dev"]
        app.launch()
        rotate(.landscapeLeft)
        openReport(app)
        shot("report-landscape")
    }

    // MARK: 차단 (작가 페이지 → 더 보기 → 차단)

    func testBlockLandscape() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--author", "yuki_dev"]
        app.launch()
        rotate(.landscapeLeft)
        let more = app.buttons["더 보기"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 15), "작가 페이지에 더 보기 메뉴가 없음")
        more.tap()
        let block = app.buttons.matching(NSPredicate(format: "label CONTAINS '차단'")).firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: 6), "메뉴에 차단 항목이 없음")
        block.tap()
        Thread.sleep(forTimeInterval: 0.9)
        shot("block-landscape")
    }
}
