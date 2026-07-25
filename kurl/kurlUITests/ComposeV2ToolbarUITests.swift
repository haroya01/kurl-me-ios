//
//  ComposeV2ToolbarUITests.swift
//  kurlUITests
//

import XCTest

/// WriteV2 서식 툴바 — 뷰포트 밖 도구는 화면에 그려지지 않고(클립), 스크롤로 닿는다.
/// 클립이 꺼져 있으면 오른쪽 도구들이 캡슐을 지나 화면 밖까지 그려졌다(스크린샷으로 육안 확인).
final class ComposeV2ToolbarUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// 끝 도구(표)는 처음엔 뷰포트 밖(비히터블), 툴바를 왼쪽으로 쓸면 닿는다.
    /// 캔버스에 포커스를 줘 키보드 위 실사용 상태로 만든다 — 키보드 없는 상태에선 툴바가
    /// 하단 탭바 뒤에 깔려 스와이프가 탭바에 먹힌다.
    func testOverflowToolsReachableByScroll() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write", "--open", "compose", "--editor", "v2"]
        app.launch()

        let runway = app.buttons["본문 이어 쓰기"].firstMatch
        XCTAssertTrue(runway.waitForExistence(timeout: 15), "본문 이어 쓰기 버튼이 없음")
        runway.tap()

        let bold = app.buttons.matching(NSPredicate(format: "label CONTAINS '굵게'")).firstMatch
        XCTAssertTrue(bold.waitForExistence(timeout: 12), "서식 툴바(굵게)가 없음")
        XCTAssertTrue(bold.isHittable, "굵게 버튼이 가려짐 — 툴바가 키보드 위로 안 떴음")
        shoot("v2-toolbar-rest")

        let table = app.buttons.matching(NSPredicate(format: "label == '표'")).firstMatch
        XCTAssertTrue(table.exists, "서식 툴바에 표 버튼이 없음")
        XCTAssertFalse(table.isHittable, "표 버튼이 스크롤 없이 닿음 — 툴바 레이아웃이 바뀌었으면 단언 갱신")

        bold.swipeLeft(velocity: .fast)
        if !table.isHittable { bold.swipeLeft(velocity: .fast) }
        XCTAssertTrue(table.isHittable, "툴바를 쓸어도 표 버튼에 닿지 않음")
        shoot("v2-toolbar-scrolled")
    }
}
