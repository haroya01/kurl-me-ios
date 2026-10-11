//
//  HighlightReplyLikeNoticeUITests.swift
//  kurlUITests
//

import XCTest

final class HighlightReplyLikeNoticeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchInbox(language: String = "ko", locale: String = "ko_KR", bell: String = "알림") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "account", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launch()
        let button = app.buttons[bell].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 12), "계정 헤더에 알림 벨이 없음")
        button.tap()
        return app
    }

    private func row(_ app: XCUIApplication, contains label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }

    private func scrolledTo(_ app: XCUIApplication, _ element: XCUIElement) -> Bool {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists
    }

    func testAHighlightReplyLikeIsNotCalledACommentAndOpensItsThread() {
        let app = launchInbox()
        let single = row(app, contains: "haruka님이 하이라이트에 단 내 답글을 좋아해요")
        XCTAssertTrue(scrolledTo(app, single), "하이라이트 답글 좋아요 알림이 답글 문장으로 안 보임")
        let grouped = row(app, contains: "reader_kim님 외 1명이 하이라이트에 단 내 답글을 좋아해요")
        XCTAssertTrue(scrolledTo(app, grouped), "묶인 하이라이트 답글 좋아요 알림이 답글 문장으로 안 보임")
        XCTAssertFalse(row(app, contains: "haruka님이 내 댓글을 좋아해요").exists, "하이라이트 답글 좋아요를 댓글이라고 부름")
        XCTAssertTrue(scrolledTo(app, row(app, contains: "외 2명이 내 댓글을 좋아해요")), "진짜 댓글 좋아요 문장이 바뀜")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "highlight-reply-like-notices"
        shot.lifetime = .keepAlways
        add(shot)

        XCTAssertTrue(scrolledTo(app, single))
        single.tap()
        XCTAssertTrue(app.buttons["답글 보내기"].waitForExistence(timeout: 15), "알림을 눌러도 하이라이트 스레드가 안 열림")
    }

    func testJapaneseAndEnglishCallItAReplyOnAHighlight() {
        let cases = [
            ("ja", "ja_JP", "通知", "harukaさんがハイライトへのあなたの返信にいいねしました"),
            ("en", "en_US", "Notifications", "haruka liked your reply on a highlight"),
        ]
        for (language, locale, bell, text) in cases {
            let app = launchInbox(language: language, locale: locale, bell: bell)
            XCTAssertTrue(scrolledTo(app, row(app, contains: text)), "\(language): '\(text)' 가 없음")
        }
    }
}
