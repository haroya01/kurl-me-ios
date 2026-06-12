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

    func testDeckEmbedsDetailWithCollapsedComments() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "discover"]
        app.launch()

        // 덱에서는 댓글이 접힌 행("댓글 N")으로 시작한다 — 실서버 글이라
        // 길이가 제각각이니 보일 때까지 끌어내린다.
        let collapsed = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH '댓글'")).firstMatch
        _ = collapsed.waitForExistence(timeout: 15)
        var swipes = 0
        while !(collapsed.exists && collapsed.isHittable), swipes < 14 {
            app.swipeUp(velocity: .fast)
            swipes += 1
        }
        XCTAssertTrue(collapsed.exists, "덱 페이지에 접힌 댓글 행이 없음 — 상세 임베드 실패")

        let composer = app.textFields["댓글을 남겨보세요"].firstMatch
        XCTAssertFalse(composer.exists, "접힌 상태인데 컴포저가 이미 보임")

        // 펼치면 프롬프트 행이 서고, 탭해야 키보드 위 유리 바(진짜 입력)가 떠오른다.
        collapsed.tap()
        app.swipeUp(velocity: .slow)
        let prompt = app.buttons["댓글을 남겨보세요"].firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 5), "댓글 펼침 후 프롬프트가 없음")
        prompt.tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 5), "프롬프트 탭 후 유리 바 입력이 없음")

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "deck-comments-expanded"
        attachment.lifetime = .keepAlways
        add(attachment)

        // 다음 단계(당김 큐)를 위해 키보드·바를 물린다 — 빈 입력에서 블러면 바도 내려간다.
        app.swipeDown(velocity: .fast)
        Thread.sleep(forTimeInterval: 0.6)

        // 다음 글 큐(작가에게 다음 글이 있을 때만) — 탭 경로로 푸시를 결정적으로
        // 검증한다. 당김 제스처는 같은 showNext 를 쏘므로 경로 검증은 이걸로 충분.
        for _ in 0..<3 { app.swipeUp(velocity: .slow) }
        let cue = app.staticTexts["계속 당기면 다음 글"].firstMatch
        guard cue.exists, cue.isHittable else { return }
        cue.tap()
        // 푸시되면 "발견" 이 내비 타이틀(정적 텍스트)에서 back 버튼으로 바뀐다.
        let backToDeck = app.navigationBars.buttons["발견"].firstMatch
        XCTAssertTrue(backToDeck.waitForExistence(timeout: 6), "다음 글로 푸시되지 않음")

        let pushed = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        pushed.name = "deck-next-post-pushed"
        pushed.lifetime = .keepAlways
        add(pushed)
    }
}
