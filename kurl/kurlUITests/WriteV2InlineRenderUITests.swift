//
//  WriteV2InlineRenderUITests.swift
//  kurlUITests
//
//  WriteV2 인라인 라이브 렌더 — 볼드·이탤릭·링크·인라인코드가 마크다운 원문이 아니라 최종 모습으로
//  보이고(마커 은닉), 캐럿을 넣으면 그 마크업만 반개봉되는지 실기기(sim) 경로로 캡처한다.
//  `--screen editor2` 하네스로 단독 실행(EditorSample 이 볼드/이탤릭/링크/코드/구분선/표를 담는다).
//  simctl 은 탭/키보드를 못 넣으니 XCUITest 로 텍스트뷰 탭 + swipeUp.
//

import XCTest

final class WriteV2InlineRenderUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func shot(_ name: String) {
        let s = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

    func testInlineLiveRenderAndReveal() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--screen", "editor2"]
        app.launch()

        // 하네스가 떴는지 — 블록은 UITextView 로 렌더되므로 스크롤뷰/텍스트뷰 존재로 판정.
        let canvasReady = app.scrollViews.firstMatch.waitForExistence(timeout: 15)
            || app.textViews.firstMatch.waitForExistence(timeout: 5)
        XCTAssertTrue(canvasReady, "하네스 미표시")
        Thread.sleep(forTimeInterval: 1.0)

        // 정적(비포커스) — 볼드·이탤릭·링크·인라인코드가 전부 마커 없이 최종 모습. 링크는 파란 라벨만.
        shot("inline-01-final-look")

        // 마크업이 든 문단을 탭해 포커스 → 캐럿이 걸친 마크업의 마커가 반개봉된다.
        let textViews = app.textViews
        if textViews.count > 1 {
            // 두 번째 텍스트뷰 = "링크도 원문이 아니라 [최종 모습](…)으로 …" 문단(샘플 순서).
            textViews.element(boundBy: 1).tap()
            Thread.sleep(forTimeInterval: 0.9)
            shot("inline-02-link-paragraph-revealed")
        } else if textViews.count > 0 {
            textViews.firstMatch.tap()
            Thread.sleep(forTimeInterval: 0.9)
            shot("inline-02-paragraph-revealed")
        }

        // 첫 문단(볼드·이탤릭·인라인코드) 안, 마크업이 든 지점을 좌표로 콕 찍어 마커 반개봉을 캡처한다
        // (단순 tap 은 문단 시작(캐럿 0)에 떨어져 마크업 밖이라 안 열린다 — 마크업 위를 직접 눌러야 열림).
        if textViews.count > 1 {
            let bodyParagraph = textViews.element(boundBy: 1)  // "이 문단은 **볼드**와 *이탤릭*…"
            // 문단 앞쪽 30% 지점(대략 "볼드" 부근)을 눌러 캐럿을 그 마크업 안에 놓는다.
            bodyParagraph.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.35)).tap()
            Thread.sleep(forTimeInterval: 0.9)
            shot("inline-03-bold-italic-code-revealed")
        }

        // 키보드를 내리고(스크롤 확보) 구분선·리스트를 캡처.
        let canvas = app.scrollViews.firstMatch
        if canvas.exists {
            canvas.swipeUp()
            Thread.sleep(forTimeInterval: 0.5)
            shot("inline-04-divider-list")

            canvas.swipeUp()
            Thread.sleep(forTimeInterval: 0.5)
            shot("inline-05-image-table")

            canvas.swipeUp()
            Thread.sleep(forTimeInterval: 0.5)
            shot("inline-06-quote-code")
        }

        // 마크다운 보기 — 블록→마크다운 왕복(저장 계약)이 마커 은닉과 무관하게 원문을 지키는지 대조.
        let toggle = app.buttons["마크다운 보기"]
        if toggle.waitForExistence(timeout: 4) {
            toggle.tap()
            Thread.sleep(forTimeInterval: 0.6)
            shot("inline-07-markdown-roundtrip")
        }
    }
}
