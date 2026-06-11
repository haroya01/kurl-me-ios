//
//  DiscoverDeckUITests.swift
//  kurlUITests
//

import XCTest

/// 발견 덱 = 열린 글 검증 — 본문이 서고, 반응 바의 댓글 버튼이 시트를 띄우는지.
final class DiscoverDeckUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDeckShowsFullPostAndCommentsSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "discover"]
        app.launch()

        // 본문(반응 바)이 설 때까지 — 덱은 실서버 글이라 네트워크 대기.
        let comments = app.buttons["댓글"].firstMatch
        var hittable = comments.waitForExistence(timeout: 15)
        // 긴 글이면 반응 바가 접혀 있다 — 본문을 끌어내려 끝까지 간다.
        var swipes = 0
        while (!hittable || !comments.isHittable), swipes < 12 {
            app.swipeUp(velocity: .fast)
            swipes += 1
            hittable = comments.exists
        }
        XCTAssertTrue(comments.isHittable, "덱 페이지에 댓글 버튼이 없음 — 본문이 서지 않았나")

        comments.tap()
        // 시트 제목 "댓글 N" — 정확한 수는 모르니 내비바 존재로 판정.
        let sheetBar = app.navigationBars.matching(
            NSPredicate(format: "identifier BEGINSWITH '댓글'")).firstMatch
        XCTAssertTrue(sheetBar.waitForExistence(timeout: 10), "댓글 시트가 뜨지 않음")

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "deck-comments-sheet"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
