//
//  ComposeImagePasteUITests.swift
//  kurlUITests
//

import XCTest

/// 본문 이미지 경로 — 그동안 어떤 테스트도 건드리지 않았다. 클립보드 이미지 붙여넣기(#94)는
/// 러너가 시스템 페이스트보드에 이미지를 심어 재현하고, 이미지 편집 바(폭·캡션·삭제)는 유효한
/// 이미지 줄에 커서를 놓아 재현한다. 사진 라이브러리 피커(프로세스 밖 PHPicker)는 여기서 다루지
/// 않는다 — WRITE_QA.md 의 수동 확인 항목.
final class ComposeImagePasteUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchFocusedEditor() -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write", "--open", "compose", "--focus", "editor"]
        app.launch()
        XCTAssertTrue(app.buttons["굵게"].waitForExistence(timeout: 12), "스니펫 바 안 뜸")
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3), "본문 캔버스 없음")
        editor.tap()
        return (app, editor)
    }

    private func value(_ editor: XCUIElement) -> String { (editor.value as? String) ?? "" }

    private func shot(_ name: String) {
        let s = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

    /// 클립보드 이미지 붙여넣기(#94) — 스크린샷·노션 등에서 복사한 이미지를 본문 `![](url)` 로.
    /// 러너가 채운 시스템 페이스트보드를 앱의 paste 오버라이드가 이미지로 읽어 업로드→삽입한다.
    func testPasteClipboardImageInsertsMarkdown() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48)).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
        }
        UIPasteboard.general.image = image

        // 다른 프로세스가 채운 보드라 붙여넣기 동의 알럿이 한 번 뜰 수 있다.
        addUIInterruptionMonitor(withDescription: "paste-consent") { alert in
            for label in ["Allow Paste", "붙여넣기 허용", "Paste", "허용", "Allow"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }

        let (app, editor) = launchFocusedEditor()
        editor.typeText("사진: ")

        editor.press(forDuration: 1.2)
        let pasteEN = app.menuItems["Paste"]
        let pasteKO = app.menuItems["붙여넣기"]
        XCTAssertTrue(
            pasteEN.waitForExistence(timeout: 5) || pasteKO.waitForExistence(timeout: 2),
            "붙여넣기 메뉴가 안 뜸")
        (pasteEN.exists ? pasteEN : pasteKO).tap()
        app.tap()  // 인터럽션 모니터가 동의 알럿을 처리하도록 한 번 건드린다.

        // 비동기 업로드→삽입을 기다린다(목 업로더는 실제 URL 을 돌려줘 마크다운이 완성된다).
        let inserted = NSPredicate(format: "value CONTAINS '![]('")
        expectation(for: inserted, evaluatedWith: editor, handler: nil)
        waitForExpectations(timeout: 15)

        XCTAssertTrue(value(editor).contains("![]("), "클립보드 이미지가 이미지 마크다운으로 안 들어감: \(value(editor))")
        shot("paste-image-inserted")
    }

    /// 이미지 줄에 커서가 놓이면 편집 바(기본·와이드·하프·캡션·삭제)가 뜬다 —
    /// 폭 '하프'는 마크다운에 폭 토큰을 붙이고 '기본'은 걷어내며, 캡션 시트는 따옴표 캡션을 붙인다.
    func testImageActionBarWidthAndCaption() throws {
        let (app, editor) = launchFocusedEditor()
        editor.typeText("![](https://example.com/photo.jpg)")

        let caption = app.buttons["캡션"]
        XCTAssertTrue(caption.waitForExistence(timeout: 4), "이미지 줄인데 편집 바가 안 뜸")
        for label in ["기본", "와이드", "하프", "삭제"] {
            XCTAssertTrue(app.buttons[label].exists, "이미지 편집 바에 '\(label)' 버튼이 없음")
        }

        app.buttons["하프"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertTrue(value(editor).contains("half"), "폭 '하프'가 마크다운에 반영 안 됨: \(value(editor))")

        app.buttons["기본"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertFalse(value(editor).contains("half"), "폭을 기본으로 되돌려도 폭 토큰이 남음: \(value(editor))")

        caption.tap()
        let captionField = app.textFields["이미지 설명"]
        XCTAssertTrue(captionField.waitForExistence(timeout: 4), "캡션 시트가 안 뜸")
        captionField.tap()
        captionField.typeText("바다 사진")
        app.navigationBars["캡션"].buttons["저장"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(value(editor).contains("바다 사진"), "캡션이 마크다운에 안 붙음: \(value(editor))")
    }
}
