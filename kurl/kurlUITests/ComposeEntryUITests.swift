//
//  ComposeEntryUITests.swift
//  kurlUITests
//

import XCTest

/// 쓰기 입구는 탭바 가운데 하나 — 누르면 무엇을 쓸지 고르는 시트(노트·긴 글·이어 쓰기)가 뜬다.
/// 노트 작성기의 "긴 글로 옮기기"는 쓴 내용이 있을 때만 보이고, 본문을 블로그 에디터로 옮긴다.
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

    private func openChooser(_ app: XCUIApplication) {
        let center = app.buttons["글쓰기"]
        XCTAssertTrue(center.waitForExistence(timeout: 15), "탭바 가운데(글쓰기)가 없음")
        center.tap()
        XCTAssertTrue(app.buttons["compose.chooser.note"].waitForExistence(timeout: 5), "가운데 탭이 글쓰기 고르기를 열지 않음")
    }

    private func openNoteComposer(_ app: XCUIApplication) -> XCUIElement {
        openChooser(app)
        app.buttons["compose.chooser.note"].tap()
        let field = app.textFields["noteCompose.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "노트를 골랐는데 노트 작성기가 열리지 않음")
        return field
    }

    private func moveToLongPost(_ app: XCUIApplication) {
        let move = app.buttons["noteCompose.longForm"]
        XCTAssertTrue(move.waitForExistence(timeout: 4), "쓴 내용이 있는데 긴 글로 옮기기가 없음")
        move.tap()
        let confirm = app.buttons.matching(
            NSPredicate(format: "label == %@ AND identifier != %@", "긴 글로 옮기기", "noteCompose.longForm")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 4), "옮기기 전에 묻지 않음")
        attach("long-form-confirm")
        confirm.tap()
    }

    func testTheCenterTabOpensTheChooserOverTheCurrentTab() throws {
        let app = launch(["--mocks", "--screen", "none", "--tab", "notes"])
        XCTAssertTrue(app.buttons["notes.more"].waitForExistence(timeout: 15), "노트 탭이 열리지 않음")
        openChooser(app)
        XCTAssertTrue(app.buttons["compose.chooser.post"].exists, "고르기에 긴 글이 없음")
        attach("compose-chooser")

        app.buttons["compose.chooser.note"].swipeDown(velocity: .fast)
        XCTAssertTrue(app.buttons["notes.more"].waitForExistence(timeout: 5), "고르기를 닫았는데 보던 노트 탭이 아님")
        XCTAssertFalse(app.buttons["글쓰기"].isSelected, "가운데가 탭처럼 선택됨")
    }

    func testTheChooserStaysReadableAtTheLargestTextSize() throws {
        let app = launch([
            "--mocks", "--screen", "none", "--tab", "notes", "--many-drafts",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        openChooser(app)
        XCTAssertTrue(app.buttons["compose.chooser.note"].isHittable, "가장 큰 글자에서 노트를 누를 수 없음")
        XCTAssertTrue(app.buttons["compose.chooser.post"].isHittable, "가장 큰 글자에서 긴 글을 누를 수 없음")
        let all = app.buttons["compose.chooser.allDrafts"]
        XCTAssertTrue(all.waitForExistence(timeout: 8), "가장 큰 글자에서 모두 보기가 없음")
        XCTAssertTrue(all.isHittable, "가장 큰 글자에서 모두 보기를 누를 수 없음")
        attach("compose-chooser-axxxl")
    }

    func testNoteOpensTheNoteComposer() throws {
        let app = launch(["--mocks", "--screen", "none", "--tab", "notes"])
        _ = openNoteComposer(app)
        XCTAssertTrue(app.navigationBars["새 노트"].exists, "작성기가 새 노트가 아님")
        attach("center-note-composer")

        app.navigationBars.buttons["취소"].tap()
        XCTAssertTrue(app.buttons["notes.more"].waitForExistence(timeout: 5), "작성기를 닫았는데 보던 노트 탭이 아님")
    }

    func testLongPostOpensAnEmptyEditor() throws {
        let app = launch(["--mocks", "--screen", "none", "--tab", "notes", "--editor", "v2", "--reset-recovery"])
        openChooser(app)
        app.buttons["compose.chooser.post"].tap()

        XCTAssertTrue(app.navigationBars["새 글"].waitForExistence(timeout: 10), "긴 글을 골랐는데 새 글 에디터가 열리지 않음")
        let title = app.textFields["제목"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "에디터에 제목 칸이 없음")
        XCTAssertNotEqual(title.value as? String, "목 초안 — 헥사고날 정리", "새 글인데 초안이 열림")
        XCTAssertFalse(
            app.textViews.matching(NSPredicate(format: "value CONTAINS %@", "포트와 어댑터")).firstMatch.exists,
            "새 글인데 초안 본문이 들어 있음")
        attach("long-post-empty-editor")
    }

    func testASeededDraftOpensFromContinueWritingWithItsContent() throws {
        let app = launch(["--mocks", "--screen", "none", "--tab", "notes", "--editor", "v2", "--reset-recovery"])
        openChooser(app)
        let draft = app.buttons["compose.chooser.draft.9001"]
        XCTAssertTrue(draft.waitForExistence(timeout: 8), "이어 쓰기에 목 초안이 없음")
        XCTAssertTrue(draft.label.contains("목 초안 — 헥사고날 정리"), "이어 쓰기 행이 초안 제목을 보이지 않음")
        attach("compose-chooser-drafts")
        draft.tap()

        XCTAssertTrue(app.navigationBars["편집"].waitForExistence(timeout: 10), "초안을 골랐는데 에디터가 열리지 않음")
        XCTAssertEqual(app.textFields["제목"].value as? String, "목 초안 — 헥사고날 정리", "초안 제목이 아님")
        let body = app.textViews.matching(NSPredicate(format: "value CONTAINS %@", "포트와 어댑터")).firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 10), "초안 본문이 에디터에 없음")
        attach("draft-editor")
    }

    func testNoDraftsHidesContinueWriting() throws {
        let app = launch(["--mocks", "--screen", "none", "--tab", "notes", "--no-drafts"])
        openChooser(app)
        let anyDraft = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "compose.chooser.draft.")).firstMatch
        XCTAssertFalse(anyDraft.waitForExistence(timeout: 3), "초안이 없는데 이어 쓰기 행이 있음")
        XCTAssertFalse(app.staticTexts["이어 쓰기"].exists, "초안이 없는데 이어 쓰기 머리가 있음")
        attach("compose-chooser-no-drafts")
    }

    func testMoreThanThreeDraftsShowAllInsideTheSheetAndKeepTheTab() throws {
        let app = launch(["--mocks", "--screen", "none", "--tab", "notes", "--editor", "v2", "--reset-recovery", "--many-drafts"])
        XCTAssertTrue(app.buttons["notes.more"].waitForExistence(timeout: 15), "노트 탭이 열리지 않음")
        openChooser(app)
        let all = app.buttons["compose.chooser.allDrafts"]
        XCTAssertTrue(all.waitForExistence(timeout: 8), "초안이 넷 이상인데 모두 보기가 없음")
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "compose.chooser.draft."))
        XCTAssertEqual(rows.count, 3, "이어 쓰기는 최근 초안 셋까지")
        attach("compose-chooser-many-drafts")
        all.tap()

        XCTAssertTrue(app.navigationBars["임시저장"].waitForExistence(timeout: 5), "모두 보기가 시트 안에서 임시저장 목록을 열지 않음")
        XCTAssertFalse(app.navigationBars["스튜디오"].exists, "모두 보기가 계정 탭 스튜디오로 넘어감")
        let listed = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "compose.chooser.allDrafts."))
        XCTAssertEqual(listed.count, 5, "임시저장 목록에 초안이 다 보이지 않음")
        XCTAssertFalse(app.staticTexts["발행된 목 글"].exists, "임시저장 목록에 발행 글까지 보임")
        attach("compose-chooser-all-drafts")

        let oldest = app.buttons["compose.chooser.allDrafts.9203"]
        XCTAssertTrue(oldest.label.contains("목 초안 3"), "가장 오래된 초안이 목록 끝에 없음")
        oldest.tap()
        let editor = app.navigationBars["편집"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "임시저장 목록에서 고른 초안이 에디터로 열리지 않음")
        XCTAssertEqual(app.textFields["제목"].value as? String, "목 초안 3", "고른 초안이 아닌 글이 열림")

        editor.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["notes.more"].waitForExistence(timeout: 6), "에디터를 닫았는데 보던 노트 탭이 아님")
    }

    func testMoveToLongPostAppearsOnlyOnceTheNoteHasText() throws {
        let app = launch(["--mocks", "--screen", "none", "--tab", "notes"])
        let field = openNoteComposer(app)
        XCTAssertFalse(app.buttons["noteCompose.longForm"].exists, "빈 노트에 긴 글로 옮기기가 보임")
        field.typeText("a note that grows longer")
        let move = app.buttons["noteCompose.longForm"]
        XCTAssertTrue(move.waitForExistence(timeout: 3), "쓴 내용이 있는데 긴 글로 옮기기가 없음")
        XCTAssertEqual(move.label, "긴 글로 옮기기")
        attach("note-composer-move")
    }

    func testMovingCarriesTheNoteBodyIntoTheBlogEditor() throws {
        let app = launch(["--mocks", "--screen", "none", "--tab", "notes", "--editor", "v2", "--reset-recovery"])
        let field = openNoteComposer(app)
        field.typeText("first paragraph that started as a note")
        moveToLongPost(app)

        XCTAssertTrue(app.navigationBars["새 글"].waitForExistence(timeout: 10), "블로그 에디터가 열리지 않음")
        let carried = app.textViews.matching(
            NSPredicate(format: "value CONTAINS %@", "first paragraph that started as a note")).firstMatch
        XCTAssertTrue(carried.waitForExistence(timeout: 10), "노트 본문이 글 본문으로 옮겨지지 않음")
        XCTAssertFalse(app.textFields["noteCompose.text"].exists, "노트 작성기가 남아 있음")
        attach("long-form-editor")
    }

    func testAMovedBodyClosedWithoutATitleComesBackAsRecovery() throws {
        let app = launch(["--mocks", "--screen", "none", "--tab", "notes", "--editor", "v2", "--reset-recovery"])
        let field = openNoteComposer(app)
        field.typeText("body kept without a title")
        moveToLongPost(app)

        let editor = app.navigationBars["새 글"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "블로그 에디터가 열리지 않음")
        editor.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["notes.more"].waitForExistence(timeout: 6), "에디터를 닫았는데 보던 노트 탭이 아님")

        openChooser(app)
        app.buttons["compose.chooser.post"].tap()
        let recovery = app.alerts["저장되지 못한 본문이 있어요"]
        XCTAssertTrue(recovery.waitForExistence(timeout: 10), "옮긴 본문이 제목 없이 닫히자 사라짐")
        recovery.buttons["이어서 쓰기"].tap()
        let restored = app.textViews.matching(
            NSPredicate(format: "value CONTAINS %@", "body kept without a title")).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 10), "복구한 본문이 캔버스에 없음")
    }

    func testDroppingADragOnTheCenterOpensTheChooserAndKeepsTheTab() throws {
        let app = launch(["--mocks", "--screen", "none", "--tab", "search"])
        let searchTab = app.buttons["검색"]
        let center = app.buttons["글쓰기"]
        XCTAssertTrue(searchTab.waitForExistence(timeout: 15), "탭바가 없음")
        searchTab.press(forDuration: 0.15, thenDragTo: center, withVelocity: .slow, thenHoldForDuration: 0.3)
        let note = app.buttons["compose.chooser.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 5), "가운데에 끌어다 놓았는데 고르기가 안 열림")

        note.swipeDown(velocity: .fast)
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5), "고르기를 닫았는데 보던 검색 탭이 아님")
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
