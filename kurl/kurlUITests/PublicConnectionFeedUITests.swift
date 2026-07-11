//
//  PublicConnectionFeedUITests.swift
//  kurlUITests
//
//  비로그인 첫 피드(최신)에 인터리브되는 공개 연결 흐름("지금 이어지는 것들")을 XCUITest 로
//  도달해 캡처한다 — simctl 로는 웰컴 게이트 통과·스크롤이 안 되기 때문. 연결 이벤트는 목이
//  내주고(공개 엔드포인트), 최신 글 카드는 공개 피드라 실서버로 흐른다.
//

import XCTest

final class PublicConnectionFeedUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testPublicConnectionInterleave() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--logged-out", "--feed", "recent"]
        app.launch()

        // 첫 실행이면 웰컴 막이 뜬다 — "로그인 없이 둘러보기"로 통과(로그아웃 피드로).
        let guest = app.buttons["로그인 없이 둘러보기"].firstMatch
        if guest.waitForExistence(timeout: 6) {
            guest.tap()
        }

        // 최신 세그먼트가 뜰 때까지(피드 진입 확인).
        _ = app.buttons["최신"].firstMatch.waitForExistence(timeout: 12)

        // 연결 흐름 머릿글은 6번째 글 뒤(index 5)라 몇 번 스크롤해야 보인다.
        let heading = app.staticTexts["지금 이어지는 것들"].firstMatch
        var found = false
        for _ in 0..<8 {
            if heading.exists && heading.isHittable { found = true; break }
            app.swipeUp()
        }
        XCTAssertTrue(found || heading.exists, "인터리브된 '지금 이어지는 것들' 머릿글을 못 찾음")
        shoot("public-connection-interleave")
    }
}
