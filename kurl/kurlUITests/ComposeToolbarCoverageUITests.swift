//
//  ComposeToolbarCoverageUITests.swift
//  kurlUITests
//

import XCTest

/// 스니펫 바 회귀 가드의 빈칸을 메운다 — 기울임·인라인 코드·실행취소/다시실행·동영상 다이얼로그,
/// 그리고 목록/표에 커서가 놓였을 때만 뜨는 컨텍스트 바(들여쓰기·행/열 편집)까지.
/// simctl 은 키보드/탭을 못 넣으니 이 경로의 자동화는 XCUITest 가 유일하다.
final class ComposeToolbarCoverageUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 컴포즈를 열고 본문 캔버스에 포커스가 간(스니펫 바가 뜬) 상태로 만든다.
    private func launchFocusedEditor() -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        // 이 스위트는 레거시 마크다운 에디터(MarkdownTextView) 전용 — 이제 v2 가 default 라 명시로 고정.
        app.launchArguments = ["--mocks", "--tab", "write", "--open", "compose", "--focus", "editor", "--editor", "legacy"]
        app.launch()
        XCTAssertTrue(app.buttons["굵게"].waitForExistence(timeout: 12), "에디터 포커스에도 스니펫 바가 안 뜸")
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3), "본문 캔버스 없음")
        editor.tap()
        return (app, editor)
    }

    private func value(_ editor: XCUIElement) -> String { (editor.value as? String) ?? "" }

    /// 기울임은 토글이다 — 어절을 `*…*` 로 감싸고, 다시 누르면 벗긴다(굵게 `**` 와 겹치지 않는 단일 별표).
    func testItalicWrapsSingleAsterisk() throws {
        let (app, editor) = launchFocusedEditor()
        editor.typeText("term")

        let italic = app.buttons["기울임"]
        italic.tap()
        XCTAssertEqual(value(editor), "*term*", "기울임 감싸기 실패(단일 별표)")
        italic.tap()
        XCTAssertEqual(value(editor), "term", "기울임 토글 해제 실패")
    }

    /// 인라인 코드는 백틱 한 쌍으로 감싼다(코드 블록 펜스와 별개).
    func testInlineCodeWrapsBacktick() throws {
        let (app, editor) = launchFocusedEditor()
        editor.typeText("term")

        let code = app.buttons["코드"]
        code.tap()
        XCTAssertEqual(value(editor), "`term`", "인라인 코드 감싸기 실패")
        code.tap()
        XCTAssertEqual(value(editor), "term", "인라인 코드 토글 해제 실패")
    }

    /// 실행취소/다시실행 — 빈 본문에선 실행취소가 비활성이고, 한 동작 뒤 되돌리면 그 동작만
    /// 취소되며(직전 타이핑까지 쓸어가지 않음), 다시실행이 그대로 복원한다.
    func testUndoRedoRestoresLastEdit() throws {
        let (app, editor) = launchFocusedEditor()

        let undo = app.buttons["실행취소"]
        let redo = app.buttons["다시실행"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3), "실행취소 버튼 없음")
        XCTAssertFalse(undo.isEnabled, "빈 본문인데 실행취소가 활성(스택 비어야 함)")

        editor.typeText("term")
        app.buttons["굵게"].tap()
        XCTAssertEqual(value(editor), "**term**", "굵게 감싸기 실패")

        XCTAssertTrue(undo.isEnabled, "편집 뒤에도 실행취소가 비활성")
        undo.tap()
        XCTAssertEqual(value(editor), "term", "실행취소가 굵게 감싸기만 되돌리지 못함")

        XCTAssertTrue(redo.isEnabled, "되돌린 뒤 다시실행이 비활성")
        redo.tap()
        XCTAssertEqual(value(editor), "**term**", "다시실행이 굵게 감싸기를 복원하지 못함")
    }

    /// 동영상 = 본문에 `(url)` 리터럴을 두지 않고 다이얼로그로 주소만 받아 한 줄 임베드로 넣는다.
    func testVideoDialogInsertsEmbedURL() throws {
        let (app, editor) = launchFocusedEditor()
        editor.typeText("소개\n")

        app.buttons["동영상"].tap()
        let dialog = app.alerts["동영상 추가"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 5), "동영상 다이얼로그가 안 뜸")
        let field = dialog.textFields.firstMatch
        field.tap()
        field.typeText("https://youtu.be/abc123")
        dialog.buttons["추가"].tap()
        Thread.sleep(forTimeInterval: 0.5)

        let v = value(editor)
        XCTAssertTrue(v.contains("https://youtu.be/abc123"), "임베드 주소가 본문에 안 들어감: \(v)")
        XCTAssertFalse(v.contains("(url)"), "본문에 (url) 리터럴이 남음")
    }

    /// 목록에 커서가 놓이면 들여쓰기 바가 뜬다 — 들여쓰기는 2칸을 더하고, 내어쓰기는 도로 뺀다.
    func testListIndentOutdent() throws {
        let (app, editor) = launchFocusedEditor()
        editor.typeText("항목")
        app.buttons["목록"].tap()
        XCTAssertEqual(value(editor), "- 항목", "글머리 추가 실패")

        let indent = app.buttons["들여쓰기"]
        XCTAssertTrue(indent.waitForExistence(timeout: 3), "목록 줄인데 들여쓰기 바가 안 뜸")
        indent.tap()
        XCTAssertEqual(value(editor), "  - 항목", "들여쓰기가 2칸을 안 넣음")

        app.buttons["내어쓰기"].tap()
        XCTAssertEqual(value(editor), "- 항목", "내어쓰기가 들여쓰기를 못 되돌림")
    }

    /// 표에 커서가 놓이면 행/열 편집 바가 뜬다 — 행을 더하면 본문이 길어지고,
    /// 행을 지우면 '행을 지웠어요' 되돌리기 토스트가 뜬다(비가역처럼 보이는 삭제의 안전장치).
    func testTableRowAddThenDeleteToast() throws {
        let (app, editor) = launchFocusedEditor()
        editor.typeText("intro")
        app.buttons["표"].tap()

        for label in ["행 추가", "열 추가", "행 삭제", "열 삭제"] {
            XCTAssertTrue(app.buttons[label].waitForExistence(timeout: 3), "표 커서인데 '\(label)' 바 버튼이 없음")
        }

        let before = value(editor).count
        app.buttons["행 추가"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertGreaterThan(value(editor).count, before, "행 추가가 본문을 늘리지 못함")

        app.buttons["행 삭제"].tap()
        XCTAssertTrue(
            app.staticTexts["행을 지웠어요"].waitForExistence(timeout: 3),
            "행 삭제에 되돌리기 토스트가 안 뜸")
    }
}
