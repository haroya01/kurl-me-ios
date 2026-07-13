//
//  WriteV2HarnessUITests.swift
//  kurlUITests
//
//  격리 WYSIWYG 에디터(Phase 2) 하네스 스크린샷 — 구분선·리스트·이미지·표가 최종 모습으로
//  렌더되는지 실기기(sim) 경로로 확인하고 캡처한다. `--screen editor2` 로 하네스만 단독 실행한다
//  (다른 UI 를 안 태운다). simctl 은 스크롤/탭을 못 넣으니 XCUITest 로 swipeUp + 마크다운 토글.
//

import XCTest

final class WriteV2HarnessUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func shot(_ name: String) {
        let s = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

    func testWysiwygBlocksRenderAndRoundTrip() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--screen", "editor2"]
        app.launch()

        // 하네스가 떴는지 — 블록은 UITextView 로 렌더되므로 스크롤뷰/텍스트뷰 존재로 판정.
        let canvasReady = app.scrollViews.firstMatch.waitForExistence(timeout: 12)
            || app.textViews.firstMatch.waitForExistence(timeout: 4)
        XCTAssertTrue(canvasReady, "하네스 미표시")
        Thread.sleep(forTimeInterval: 0.8)
        shot("wysiwyg-01-overview")   // 구분선 + 리스트(중첩·번호) + 이미지 상단

        // 표까지 스크롤 — 이미지·표(격자)를 화면에 올린다.
        let canvas = app.scrollViews.firstMatch
        canvas.swipeUp()
        Thread.sleep(forTimeInterval: 0.5)
        shot("wysiwyg-02-image-table")

        canvas.swipeUp()
        Thread.sleep(forTimeInterval: 0.5)
        shot("wysiwyg-03-table-quote-code")

        // 마크다운 보기 — 블록→마크다운 왕복 직렬화 결과를 눈으로 대조.
        let toggle = app.buttons["마크다운 보기"]
        if toggle.waitForExistence(timeout: 4) {
            toggle.tap()
            Thread.sleep(forTimeInterval: 0.5)
            shot("wysiwyg-04-markdown-roundtrip")
        }
    }
}
