//
//  ComposeReproShotsUITests.swift
//  kurlUITests
//
//  사용자 신고 재현 캡처(일회성 진단 레인) — ① 글머리/번호 토글 직후 캐럿이 한 줄 아래로 보임
//  ② 발행 폼 '이렇게 보여요' 카드의 커버 자리 이상. 단언 없이 화면만 남긴다(눈 검증용).
//

import XCTest

final class ComposeReproShotsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let s = XCTAttachment(screenshot: app.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

    func testReproShots() throws {
        // 커버 자동설정 재현용 — 클립보드에 이미지를 심어 붙여넣기로 본문 이미지→커버를 만든다.
        let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 200)).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 320, height: 200))
        }
        UIPasteboard.general.image = image
        addUIInterruptionMonitor(withDescription: "paste-consent") { alert in
            for label in ["Allow Paste", "붙여넣기 허용", "Paste", "허용", "Allow"]
            where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }

        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write", "--open", "compose", "--editor", "v2"]
        app.launch()

        let title = app.textFields["제목"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        title.typeText("Repro")

        // ① 빈 문단에서 글머리 토글 — 캐럿 위치 캡처.
        let runway = app.buttons["본문 이어 쓰기"].firstMatch
        if runway.waitForExistence(timeout: 4), runway.isHittable { runway.tap() }
        Thread.sleep(forTimeInterval: 0.6)
        app.buttons["글머리"].tap()
        Thread.sleep(forTimeInterval: 0.8)
        shot(app, "repro-01-bullet-empty-caret")
        app.typeText("항목")
        Thread.sleep(forTimeInterval: 0.5)
        shot(app, "repro-02-bullet-typed")
        app.buttons["글머리"].tap()  // 문단으로 되돌림
        Thread.sleep(forTimeInterval: 0.4)
        app.buttons["번호"].tap()
        Thread.sleep(forTimeInterval: 0.8)
        shot(app, "repro-03-numbered-caret")

        // 본문 이미지 붙여넣기 → 첫 이미지가 커버로 자동 설정된다.
        app.typeText("\n")
        Thread.sleep(forTimeInterval: 0.5)
        let block = app.textViews.firstMatch
        block.press(forDuration: 1.2)
        let pasteEN = app.menuItems["Paste"]
        let pasteKO = app.menuItems["붙여넣기"]
        if pasteEN.waitForExistence(timeout: 5) || pasteKO.waitForExistence(timeout: 2) {
            (pasteEN.exists ? pasteEN : pasteKO).tap()
            app.tap()
        }
        _ = app.textFields["대체 텍스트"].waitForExistence(timeout: 20)

        // ② 발행 폼 — '이렇게 보여요' 카드 캡처(커버 자동설정 상태).
        app.buttons["발행"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.2)
        shot(app, "repro-04-publish-sheet")
    }
}
