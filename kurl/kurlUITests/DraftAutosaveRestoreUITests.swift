//
//  DraftAutosaveRestoreUITests.swift
//  kurlUITests
//
//  임시저장 → 리비전 롤백의 앱 실동작 — 기존 초안을 열어 본문을 고치고(자동저장), 리비전
//  시트에서 복원해 캔버스가 그 시점 본문으로 되돌아오는지까지 실제 터치로 밟는다.
//  simctl 은 탭/키보드를 못 넣으니 XCUITest 가 유일한 실동작 경로다(목 백엔드 왕복).
//

import XCTest

final class DraftAutosaveRestoreUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let s = XCTAttachment(screenshot: app.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

    func testEditAutosaveThenRestoreRevision() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write", "--editor", "v2"]
        app.launch()

        // 기존 초안을 연다 — 서버 본문(# 헥사고날 / 포트와 어댑터.)이 블록으로 렌더된다.
        let draftRow = app.staticTexts["목 초안 — 헥사고날 정리"]
        XCTAssertTrue(draftRow.waitForExistence(timeout: 15), "스튜디오에 목 초안이 안 보임")
        draftRow.tap()

        let paragraph = app.textViews.containing(
            NSPredicate(format: "value == %@", "포트와 어댑터.")).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 12), "초안 본문 로드/렌더 실패")

        // 본문을 고친다 → 디바운스 자동저장이 목 백엔드로 왕복하고 저장 배지가 선다(임시저장 실동작).
        paragraph.tap()
        app.typeText(" 그리고 리비전.")
        let statusBadge = app.buttons["저장 상태 보기"]
        XCTAssertTrue(statusBadge.waitForExistence(timeout: 15), "자동저장 배지가 안 뜸(임시저장 실패 의심)")
        shot(app, "restore-01-autosaved")

        // ⋯ 메뉴 → 리비전 시트 — 목이 v2·v1 두 장을 준다.
        app.buttons["더 보기"].firstMatch.tap()
        let revisionsItem = app.buttons["리비전…"]
        XCTAssertTrue(revisionsItem.waitForExistence(timeout: 5), "리비전 메뉴 항목이 없음")
        revisionsItem.tap()

        let v1Row = app.staticTexts["v1 — 첫 저장"]
        XCTAssertTrue(v1Row.waitForExistence(timeout: 10), "리비전 목록(v1)이 안 보임")
        shot(app, "restore-02-revision-sheet")

        // v1 복원 — 시트의 두 '복원' 중 아래(v1) 버튼.
        let restoreButtons = app.buttons.matching(identifier: "복원")
        XCTAssertTrue(restoreButtons.count >= 2, "복원 버튼이 리비전 수만큼 없음")
        restoreButtons.element(boundBy: 1).tap()

        // 캔버스가 복원 본문으로 되돌아온다 — 제목 블록은 마커 없이 최종 모습으로.
        let restoredHeading = app.textViews.containing(
            NSPredicate(format: "value == %@", "복원된 본문 v1")).firstMatch
        XCTAssertTrue(restoredHeading.waitForExistence(timeout: 12), "복원 본문이 캔버스에 반영 안 됨")
        let restoredBody = app.textViews.containing(
            NSPredicate(format: "value == %@", "리비전에서 돌아왔다.")).firstMatch
        XCTAssertTrue(restoredBody.exists, "복원 본문 문단이 안 보임")
        shot(app, "restore-03-restored")

        // 복원 직후 서명이 '저장됨'으로 맞춰져(복원본문+옛메타 재저장 창 닫힘) 배지가 유지된다.
        XCTAssertTrue(app.buttons["저장 상태 보기"].exists, "복원 후 저장 배지 사라짐")
    }
}
