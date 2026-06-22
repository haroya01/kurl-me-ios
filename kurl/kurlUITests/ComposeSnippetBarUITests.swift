//
//  ComposeSnippetBarUITests.swift
//  kurlUITests
//

import XCTest

/// 에디터 유리 스니펫 바 — 포커스 시 등장 + 커서 기준 삽입·토글 회귀 가드.
/// simctl 은 키보드/탭을 못 넣으니 이 경로의 자동화는 XCUITest 가 유일하다.
final class ComposeSnippetBarUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 컴포즈를 열고 본문 캔버스에 포커스가 간(스니펫 바가 뜬) 상태로 만든다.
    private func launchFocusedEditor() -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write", "--open", "compose", "--focus", "editor"]
        app.launch()
        XCTAssertTrue(app.buttons["굵게"].waitForExistence(timeout: 12), "에디터 포커스에도 스니펫 바가 안 뜸")
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3), "본문 캔버스 없음")
        editor.tap()
        return (app, editor)
    }

    private func value(_ editor: XCUIElement) -> String { (editor.value as? String) ?? "" }

    func testSnippetBarInsertsMarkdown() throws {
        let (app, editor) = launchFocusedEditor()
        let bold = app.buttons["굵게"]

        // 빈 본문에서 굵게 = 쌍 삽입. 빈 선택이면 자리표시자를 넣고 선택해 둔다("**…**").
        // 자리표시자 문자열(로케일)에 묶이지 않게 결과를 그대로 들고 제목 단계만 검증한다.
        bold.tap()
        let afterBold = value(editor)
        XCTAssertTrue(afterBold.hasPrefix("**") && afterBold.hasSuffix("**"), "굵게 쌍 삽입 실패: \(afterBold)")

        // 제목 버튼은 한 줄에서 단계를 순환한다 — 본문 → # → ## → ### → 본문.
        // 예전엔 매 탭이 무턱대고 "# "를 덧붙여 "# # …"가 쌓이고 H2·H3가 끝내 안 만들어졌다.
        let heading = app.buttons["제목"]
        heading.tap()
        XCTAssertEqual(value(editor), "# \(afterBold)", "H1 삽입 실패")
        heading.tap()
        XCTAssertEqual(value(editor), "## \(afterBold)", "H2로 올라가지 못함(단계 중복 prepend 회귀)")
        heading.tap()
        XCTAssertEqual(value(editor), "### \(afterBold)", "H3로 올라가지 못함")
        heading.tap()
        XCTAssertEqual(value(editor), afterBold, "###에서 본문으로 해제되지 못함")

        app.buttons["키보드 내리기"].tap()
        XCTAssertTrue(bold.waitForNonExistence(timeout: 4), "포커스 해제에도 바가 남음")
    }

    /// 인용·글머리·번호 줄머리는 토글이다 — 다시 누르면 꺼지고, 다른 줄머리를 누르면 바뀐다.
    /// 예전엔 무조건 앞에 덧대 "> > " · "- - " · "1. 1. "가 쌓이고, 끌 수도 바꿀 수도 없었다.
    func testLinePrefixToggleAndSwap() throws {
        let (app, editor) = launchFocusedEditor()
        editor.typeText("text")

        let list = app.buttons["목록"]
        list.tap()
        XCTAssertEqual(value(editor), "- text", "글머리 추가 실패")
        list.tap()
        XCTAssertEqual(value(editor), "text", "글머리 토글 해제 실패(중복 '- - ' 회귀)")

        let quote = app.buttons["인용"]
        quote.tap()
        XCTAssertEqual(value(editor), "> text", "인용 추가 실패")

        // 인용 → 번호으로 '바꾸기'(쌓기 아님): "1. text" 이어야 한다("1. > text" 면 회귀).
        app.buttons["번호"].tap()
        XCTAssertEqual(value(editor), "1. text", "줄머리 교체 실패(마커가 쌓임)")
        app.buttons["번호"].tap()
        XCTAssertEqual(value(editor), "text", "번호 토글 해제 실패")
    }

    /// 굵게·취소선은 토글이다 — 감싼 뒤 다시 누르면 벗겨진다. 예전엔 마커가 겹쳐
    /// "**term**" → "****term****"(에디터 깨짐) · "~~x~~" → "~~~~x~~~~"(취소선 렌더 안 됨)가 났다.
    func testEmphasisToggleOff() throws {
        let (app, editor) = launchFocusedEditor()

        // 선택이 없어도 캐럿이 닿은 단어(어절)를 감싼다.
        editor.typeText("term")
        let bold = app.buttons["굵게"]
        bold.tap()
        XCTAssertEqual(value(editor), "**term**", "단어 굵게 감싸기 실패")
        bold.tap()
        XCTAssertEqual(value(editor), "term", "굵게 토글 해제 실패('****term****' 회귀)")

        let strike = app.buttons["취소선"]
        strike.tap()
        XCTAssertEqual(value(editor), "~~term~~", "취소선 감싸기 실패")
        strike.tap()
        XCTAssertEqual(value(editor), "term", "취소선 토글 해제 실패('~~~~term~~~~' 회귀)")
    }

    /// 표는 앞뒤가 빈 줄로 격리돼야 한다 — 안 그러면 표 다음 산문이 GFM 파서에서 표의 유령 행으로
    /// 빨려 들어가 에디터(평문)와 발행본(표 안 행)이 어긋난다.
    func testTableIsolatedByBlankLines() throws {
        let (app, editor) = launchFocusedEditor()
        editor.typeText("intro")
        app.buttons["표"].tap()

        let v = value(editor)
        XCTAssertTrue(v.contains("\n\n| 제목 | 제목 |"), "표 앞에 빈 줄이 없음: \(v)")
        XCTAssertTrue(v.contains("| 내용 | 내용 |\n\n") || v.hasSuffix("| 내용 | 내용 |\n"),
            "표 뒤에 빈 줄이 없음: \(v)")
    }

    /// 목록에서 Enter = 다음 항목 자동(번호는 +1), 빈 항목에서 Enter = 목록 종료.
    /// 일반 사용자가 매번 도구 막대를 다시 누르지 않고 목록을 만들 수 있어야 한다.
    func testReturnContinuesList() throws {
        let (app, editor) = launchFocusedEditor()
        editor.typeText("사과")
        app.buttons["목록"].tap()
        XCTAssertEqual(value(editor), "- 사과", "글머리 추가 실패")
        editor.typeText("\n")
        XCTAssertEqual(value(editor), "- 사과\n- ", "Enter 가 다음 글머리를 안 만듦")
        editor.typeText("바나나\n")
        XCTAssertEqual(value(editor), "- 사과\n- 바나나\n- ", "둘째 항목 후 Enter 실패")
        editor.typeText("\n")
        XCTAssertEqual(value(editor), "- 사과\n- 바나나\n", "빈 항목 Enter 가 목록을 안 끝냄")

        // 번호 목록은 다음 항목이 +1 로.
        app.buttons["번호"].tap()
        editor.typeText("하나\n")
        XCTAssertTrue(value(editor).hasSuffix("1. 하나\n2. "), "번호 목록 자동 증가 실패: \(value(editor))")
    }
}
