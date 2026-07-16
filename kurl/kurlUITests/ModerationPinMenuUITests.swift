//
//  ModerationPinMenuUITests.swift
//  kurlUITests
//
//  새 관리 진입로 두 곳의 실동작 — ① 스튜디오 발행 글 ⋯ 메뉴의 프로필 고정 토글
//  ② 타인 글 ⋯ 메뉴의 관리자 섹션(목 me = ADMIN). 메뉴가 열리고 항목이 실제로 놓이는지 본다.
//

import XCTest

final class ModerationPinMenuUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testStudioPinToggleOnPublishedPost() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write"]
        app.launch()

        let manage = app.buttons["발행된 목 글 관리"]
        XCTAssertTrue(manage.waitForExistence(timeout: 15), "스튜디오 발행 글 관리 메뉴 미표시")
        manage.tap()

        let pin = app.buttons["프로필에 고정"]
        let unpin = app.buttons["프로필 고정 해제"]
        XCTAssertTrue(
            pin.waitForExistence(timeout: 5) || unpin.exists,
            "발행 글 메뉴에 프로필 고정 토글이 없음")
        (pin.exists ? pin : unpin).tap()
        // 목 PUT ack → 토스트 문구 중 하나가 떠야 한다(고정/해제 어느 쪽이든). 토스트는 ~2.4s 만
        // 유지되는 짧은 전이라 waitForExistence 스냅샷 지연에 놓치기 쉽다 — 탭 직후 빠르게 폴링한다.
        let toast = app.staticTexts.matching(
            NSPredicate(format:
                "label CONTAINS '고정했어요' OR label CONTAINS '고정을 해제했어요'")).firstMatch
        var appeared = false
        for _ in 0..<20 {
            if toast.exists { appeared = true; break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(appeared, "고정 토글 후 확인 토스트가 안 뜸")
    }

    func testAdminSectionOnOthersPost() throws {
        let app = XCUIApplication()
        // honggildong 은 목 me(id 1) — 타인 글이 되도록 다른 작가(haruka→id 2)로 연다.
        app.launchArguments = ["--mocks", "--post", "haruka/hexagonal-after-3-months"]
        app.launch()

        let more = app.buttons["더 보기"]
        XCTAssertTrue(more.waitForExistence(timeout: 15), "타인 글 더 보기 메뉴 미표시")
        more.tap()

        XCTAssertTrue(
            app.buttons["제목·태그 편집"].waitForExistence(timeout: 5),
            "관리자 섹션(제목·태그 편집)이 메뉴에 없음")
        XCTAssertTrue(app.buttons["영구 삭제"].exists, "관리자 영구 삭제가 메뉴에 없음")

        // 편집 시트 — 현재 제목이 프리필되고 저장이 살아 있다.
        app.buttons["제목·태그 편집"].tap()
        let titleField = app.textFields["제목"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 6), "관리자 편집 시트 미표시")
        let saveButton = app.buttons["저장"]
        XCTAssertTrue(saveButton.isEnabled, "프리필 제목인데 저장이 비활성")
    }
}
