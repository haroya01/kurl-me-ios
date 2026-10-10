//
//  ComposeEntryUITests.swift
//  kurlUITests
//

import XCTest

/// 쓰기 입구는 탭바 가운데 하나 — 누르면 노트 작성기가 열리고, "긴 글로 쓰기"가 쓰던 본문을
/// 블로그 에디터로 옮긴다. 노트 탭의 떠 있는 작성 버튼은 없다.
final class ComposeEntryUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func openComposer(_ app: XCUIApplication) -> XCUIElement {
        let center = app.buttons["글쓰기"]
        XCTAssertTrue(center.waitForExistence(timeout: 15), "탭바 가운데(글쓰기)가 없음")
        center.tap()
        let field = app.textFields["noteCompose.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "가운데 탭이 노트 작성기를 열지 않음")
        return field
    }

    func testTheCenterTabOpensTheNoteComposerOverTheCurrentTab() throws {
        let app = launch(["--mocks", "--screen", "none", "--tab", "notes"])
        XCTAssertTrue(app.buttons["notes.more"].waitForExistence(timeout: 15), "노트 탭이 열리지 않음")
        _ = openComposer(app)
        XCTAssertTrue(app.navigationBars["새 노트"].exists, "작성기가 새 노트가 아님")
        XCTAssertTrue(app.buttons["noteCompose.longForm"].exists, "작성기에 긴 글로 쓰기가 없음")
        attach("center-note-composer")

        app.navigationBars.buttons["취소"].tap()
        XCTAssertTrue(app.buttons["notes.more"].waitForExistence(timeout: 5), "작성기를 닫았는데 보던 노트 탭이 아님")
        XCTAssertFalse(app.buttons["글쓰기"].isSelected, "가운데가 탭처럼 선택됨")
    }

    func testLongFormCarriesTheNoteBodyIntoTheBlogEditor() throws {
        let app = launch(["--mocks", "--screen", "none", "--tab", "notes", "--editor", "v2", "--reset-recovery"])
        let field = openComposer(app)
        field.typeText("노트에서 시작한 긴 글 첫 문단")

        app.buttons["noteCompose.longForm"].tap()
        let move = app.buttons["긴 글로 옮기기"]
        XCTAssertTrue(move.waitForExistence(timeout: 4), "옮기기 전에 묻지 않음")
        attach("long-form-confirm")
        move.tap()

        XCTAssertTrue(app.navigationBars["새 글"].waitForExistence(timeout: 10), "블로그 에디터가 열리지 않음")
        let carried = app.textViews.matching(
            NSPredicate(format: "value CONTAINS %@", "노트에서 시작한 긴 글 첫 문단")).firstMatch
        XCTAssertTrue(carried.waitForExistence(timeout: 10), "노트 본문이 글 본문으로 옮겨지지 않음")
        XCTAssertFalse(app.textFields["noteCompose.text"].exists, "노트 작성기가 남아 있음")
        attach("long-form-editor")
    }

    func testAMovedBodyClosedWithoutATitleComesBackAsRecovery() throws {
        let app = launch(["--mocks", "--screen", "none", "--tab", "notes", "--editor", "v2", "--reset-recovery"])
        let field = openComposer(app)
        field.typeText("제목 없이 닫아도 남는 본문")
        app.buttons["noteCompose.longForm"].tap()
        let move = app.buttons["긴 글로 옮기기"]
        XCTAssertTrue(move.waitForExistence(timeout: 4), "옮기기 전에 묻지 않음")
        move.tap()

        let editor = app.navigationBars["새 글"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "블로그 에디터가 열리지 않음")
        editor.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["notes.more"].waitForExistence(timeout: 6), "에디터를 닫았는데 보던 노트 탭이 아님")

        _ = openComposer(app)
        app.buttons["noteCompose.longForm"].tap()
        let recovery = app.alerts["저장되지 못한 본문이 있어요"]
        XCTAssertTrue(recovery.waitForExistence(timeout: 10), "옮긴 본문이 제목 없이 닫히자 사라짐")
        recovery.buttons["이어서 쓰기"].tap()
        let restored = app.textViews.matching(
            NSPredicate(format: "value CONTAINS %@", "제목 없이 닫아도 남는 본문")).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 10), "복구한 본문이 캔버스에 없음")
    }

    func testAnEmptyNoteSwitchesToTheBlogEditorWithoutAsking() throws {
        let app = launch(["--mocks", "--screen", "none", "--tab", "notes", "--editor", "v2", "--reset-recovery"])
        _ = openComposer(app)
        app.buttons["noteCompose.longForm"].tap()

        XCTAssertTrue(app.navigationBars["새 글"].waitForExistence(timeout: 10), "빈 노트에서 블로그 에디터가 열리지 않음")
        XCTAssertFalse(app.buttons["긴 글로 옮기기"].exists, "옮길 본문이 없는데 물음")
    }

    func testDroppingADragOnTheCenterOpensTheComposerAndKeepsTheTab() throws {
        let app = launch(["--mocks", "--screen", "none", "--tab", "search"])
        let searchTab = app.buttons["검색"]
        let center = app.buttons["글쓰기"]
        XCTAssertTrue(searchTab.waitForExistence(timeout: 15), "탭바가 없음")
        searchTab.press(forDuration: 0.15, thenDragTo: center, withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(app.textFields["noteCompose.text"].waitForExistence(timeout: 5), "가운데에 끌어다 놓았는데 작성기가 안 열림")

        app.navigationBars.buttons["취소"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5), "작성기를 닫았는데 보던 검색 탭이 아님")
        XCTAssertFalse(app.buttons["글쓰기"].isSelected, "끌어다 놓은 가운데가 선택된 탭이 됨")
    }

    func testTheAccountToolbarOpensTheStudio() throws {
        let app = launch(["--mocks", "--screen", "none", "--tab", "account"])
        let studio = app.buttons["account.studio"]
        XCTAssertTrue(studio.waitForExistence(timeout: 15), "계정 툴바에 스튜디오가 없음")
        attach("account-toolbar")
        studio.tap()

        XCTAssertTrue(app.navigationBars["스튜디오"].waitForExistence(timeout: 8), "스튜디오가 열리지 않음")
        XCTAssertTrue(app.buttons["새 글 쓰기"].firstMatch.exists, "스튜디오에 새 글 쓰기가 없음")
        XCTAssertTrue(app.buttons["분석"].exists, "스튜디오에 글·시리즈·분석 스위처가 없음")
        attach("studio-from-account")

        app.navigationBars["스튜디오"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(studio.waitForExistence(timeout: 5), "스튜디오에서 뒤로 가도 계정 탭이 아님")
    }

    func testTheAnalyticsWidgetLinkOpensTheStudioOnAnalytics() throws {
        let app = launch(["--mocks", "--screen", "none", "--widget", "kurlwidget://analytics"])
        XCTAssertTrue(app.navigationBars["스튜디오"].waitForExistence(timeout: 15), "분석 위젯 링크가 스튜디오를 열지 않음")
        let analytics = app.buttons["분석"]
        XCTAssertTrue(analytics.waitForExistence(timeout: 5), "스튜디오 스위처가 없음")
        XCTAssertTrue(analytics.isSelected, "분석 위젯 링크인데 분석 분면이 아님")
        XCTAssertTrue(app.buttons["내 계정"].isSelected, "스튜디오가 계정 탭 위에 열리지 않음")
        attach("studio-from-widget")
    }

    func testTheNotesTabHasNoFloatingComposeButton() throws {
        let app = launch(["--mocks", "--screen", "none", "--tab", "notes"])
        XCTAssertTrue(app.buttons["notes.more"].waitForExistence(timeout: 15), "노트 탭이 열리지 않음")
        XCTAssertFalse(app.buttons["notes.fab"].exists, "노트 탭에 떠 있는 작성 버튼이 남아 있음")
        XCTAssertFalse(app.buttons["노트 쓰기"].exists, "노트 탭에 노트 쓰기 버튼이 남아 있음")
        attach("notes-tab-no-fab")
    }
}
