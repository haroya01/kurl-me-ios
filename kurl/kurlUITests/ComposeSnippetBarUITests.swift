//
//  ComposeSnippetBarUITests.swift
//  kurlUITests
//

import XCTest

/// 에디터 유리 스니펫 바 — 포커스 시 등장 + 커서 기준 삽입 회귀 가드.
/// simctl 은 키보드/탭을 못 넣으니 이 경로의 자동화는 XCUITest 가 유일하다.
final class ComposeSnippetBarUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSnippetBarAppliesFormatting() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write", "--open", "compose", "--focus", "editor"]
        app.launch()

        let bold = app.buttons["굵게"]
        XCTAssertTrue(bold.waitForExistence(timeout: 10), "에디터 포커스에도 스니펫 바가 안 뜸")

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3), "본문 캔버스 없음")

        // Phase 1 WYSIWYG: 굵게/제목은 기호 없이 서식만(텍스트 불변), 리스트는 아직 평문 "- ".
        bold.tap()
        app.buttons["리스트"].tap()
        XCTAssertEqual(editor.value as? String, "- ", "리스트 평문 삽입 실패")

        app.buttons["키보드 내리기"].tap()
        XCTAssertTrue(bold.waitForNonExistence(timeout: 4), "포커스 해제에도 바가 남음")
    }
}
