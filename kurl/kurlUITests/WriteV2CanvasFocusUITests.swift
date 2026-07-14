//
//  WriteV2CanvasFocusUITests.swift
//  kurlUITests
//
//  캔버스 탭-포커스 회귀 — "제목만 눌리고 본문은 안 눌림"(V2 첫 출고의 사망 원인) 재발 방지.
//  빈 캔버스의 블록 밖 영역(이어 쓰기 활주로)을 탭하면 포커스·키보드가 서고 타이핑이 블록으로
//  들어가야 한다. simctl 은 탭/키보드를 못 넣으니 XCUITest 가 유일한 실동작 경로다.
//

import XCTest

final class WriteV2CanvasFocusUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func shot(_ name: String) {
        let s = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

    func testTapEmptyCanvasStartsWriting() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write", "--editor", "v2", "--open", "compose"]
        app.launch()

        let canvas = app.scrollViews.firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 15), "V2 캔버스 미표시")

        // 블록 밖 빈 영역 = 이어 쓰기 활주로. 접근성 요소로 잡히면 그걸, 아니면 캔버스 하단 좌표를 탭.
        let runway = app.buttons["본문 이어 쓰기"].firstMatch
        if runway.waitForExistence(timeout: 4), runway.isHittable {
            runway.tap()
        } else {
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).tap()
        }
        Thread.sleep(forTimeInterval: 0.8)
        shot("v2-canvas-tapped")

        // 포커스가 섰다면 타이핑이 본문 블록으로 들어간다 — 제목이 아니라 캔버스 텍스트뷰에.
        app.typeText("tap-to-write")
        let typed = app.textViews.containing(
            NSPredicate(format: "value CONTAINS %@", "tap-to-write")).firstMatch
        XCTAssertTrue(
            typed.waitForExistence(timeout: 8),
            "빈 캔버스 탭 후 타이핑이 본문 블록에 안 들어감 — 이어 쓰기 포커스(focusTail) 실패")
        shot("v2-canvas-typed")
    }
}
