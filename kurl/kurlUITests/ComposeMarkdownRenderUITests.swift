//
//  ComposeMarkdownRenderUITests.swift
//  kurlUITests
//

import XCTest

/// 작성 화면 라이브 렌더 — 마크다운을 치면 그 자리에서 제목·굵게·인용·리스트·코드블록으로 입혀지고,
/// 코드블록은 한 번 탭으로 빠져나오며, 링크는 `(url)` 리터럴 없이 다이얼로그로 들어가는지
/// 실기기 경로로 확인하고 스크린샷을 남긴다(simctl 은 키보드를 못 넣으니 XCUITest 가 유일).
final class ComposeMarkdownRenderUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func shot(_ name: String) {
        let s = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

    func testMarkdownRendersWhileTyping() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write", "--open", "compose", "--focus", "editor"]
        app.launch()

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 12), "본문 캔버스 없음")
        editor.tap()

        // 1) 인라인/블록 렌더.
        editor.typeText("# 큰 제목입니다\n")
        editor.typeText("본문에서 **굵게**, *기울임*, 그리고 `코드` 가 바로 보입니다.\n\n")
        editor.typeText("> 인용한 문장도 인용으로.\n\n")
        editor.typeText("- 첫 번째 항목\n- 두 번째 항목\n\n")

        // 2) 코드블록 — 버튼으로 펜스 삽입 → 안에서 타이핑(어두운 박스로 보인다).
        app.buttons["코드 블록"].tap()
        editor.typeText("let sum = a + b\nprint(sum)")
        Thread.sleep(forTimeInterval: 0.7)
        shot("code-block-inside")

        // 3) 같은 버튼으로 코드블록 빠져나오기 → 밖에서 다시 본문.
        app.buttons["코드 블록"].tap()
        editor.typeText("블록 밖, 다시 본문입니다.")
        Thread.sleep(forTimeInterval: 0.5)
        shot("code-block-exited")

        // 4) 링크 — `(url)` 리터럴 대신 다이얼로그로 주소를 받아 넣는다.
        editor.typeText("\n")
        app.buttons["링크"].tap()
        let dialog = app.alerts["링크 추가"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 5), "링크 다이얼로그가 안 뜸")
        let field = dialog.textFields.firstMatch
        field.tap()
        field.typeText("kurl.me/blog")
        dialog.buttons["추가"].tap()
        Thread.sleep(forTimeInterval: 0.5)

        let value = (editor.value as? String) ?? ""
        XCTAssertTrue(value.contains("](https://kurl.me/blog)"), "링크 마크다운이 안 들어감: \(value)")
        XCTAssertFalse(value.contains("(url)"), "본문에 (url) 리터럴이 남음")
        shot("link-inserted")
    }

    /// 붙여넣은 외부 URL → kurl 단축링크 자동 변환.
    func testPasteUrlBecomesKurlShortLink() throws {
        UIPasteboard.general.string = "https://example.com/very/long/path?utm=abcdef123456"

        // 페이스트보드 동의 알럿이 뜨면 허용(다른 프로세스가 채운 보드라 한 번 물을 수 있다).
        addUIInterruptionMonitor(withDescription: "paste-consent") { alert in
            for label in ["Allow Paste", "붙여넣기 허용", "Paste", "허용", "Allow"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }

        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write", "--open", "compose", "--focus", "editor"]
        app.launch()

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 12), "본문 캔버스 없음")
        editor.tap()
        editor.typeText("링크: ")

        // 편집 메뉴에서 붙여넣기 — 길게 눌러 호출(로케일에 따라 라벨이 다름).
        editor.press(forDuration: 1.2)
        let pasteEN = app.menuItems["Paste"]
        let pasteKO = app.menuItems["붙여넣기"]
        XCTAssertTrue(
            pasteEN.waitForExistence(timeout: 5) || pasteKO.waitForExistence(timeout: 2),
            "붙여넣기 메뉴가 안 뜸")
        (pasteEN.exists ? pasteEN : pasteKO).tap()
        app.tap() // 인터럽션 모니터가 동의 알럿을 처리하도록 한 번 건드린다.

        // 비동기 단축 교체를 기다린다.
        let shortened = NSPredicate(format: "value CONTAINS 'kurl.me/'")
        expectation(for: shortened, evaluatedWith: editor, handler: nil)
        waitForExpectations(timeout: 10)

        let value = (editor.value as? String) ?? ""
        XCTAssertTrue(value.contains("kurl.me/"), "단축링크로 안 바뀜: \(value)")
        XCTAssertFalse(value.contains("example.com/very/long"), "원문 URL 이 남음: \(value)")
        shot("paste-shortened")
    }
}
