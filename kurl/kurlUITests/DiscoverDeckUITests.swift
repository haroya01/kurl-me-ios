//
//  DiscoverDeckUITests.swift
//  kurlUITests
//

import XCTest

/// 발견 덱 = 글 상세보기 임베드 검증 — 본문이 서고, 끝까지 내리면
/// 상세와 동일한 인라인 댓글 컴포저가 있는지.
final class DiscoverDeckUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDeckEmbedsFullPostDetail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "discover"]
        app.launch()

        // 상세와 동일한 댓글 컴포저(placeholder)가 본문 끝에 있다 — 실서버 글이라
        // 길이가 제각각이니 보일 때까지 끌어내린다.
        let composer = app.textFields["댓글을 남겨보세요"].firstMatch
        _ = composer.waitForExistence(timeout: 15)
        var swipes = 0
        while !(composer.exists && composer.isHittable), swipes < 14 {
            app.swipeUp(velocity: .fast)
            swipes += 1
        }
        XCTAssertTrue(composer.exists, "덱 페이지에 인라인 댓글 컴포저가 없음 — 상세 임베드 실패")

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "deck-embedded-detail-bottom"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
