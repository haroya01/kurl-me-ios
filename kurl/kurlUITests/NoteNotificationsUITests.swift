//
//  NoteNotificationsUITests.swift
//  kurlUITests
//

import XCTest

final class NoteNotificationsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchInbox() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "account"]
        app.launch()
        let bell = app.buttons["알림"].firstMatch
        XCTAssertTrue(bell.waitForExistence(timeout: 12), "계정 헤더에 알림 벨이 없음")
        bell.tap()
        return app
    }

    private func row(_ app: XCUIApplication, contains label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }

    func testGroupedNoteLikesAndARepliesOpenTheirNotes() throws {
        let app = launchInbox()

        let likes = row(app, contains: "외 3명이 내 노트를 좋아해요")
        XCTAssertTrue(likes.waitForExistence(timeout: 12), "묶인 노트 좋아요 알림이 없음")
        XCTAssertTrue(likes.label.contains("alice@mastodon.social"), "묶음의 최신 보낸 사람이 다른 서버 핸들이 아님")
        XCTAssertTrue(row(app, contains: "다른 서버에서 나를 팔로우했어요").exists, "원격 팔로우 알림이 없음")
        XCTAssertTrue(row(app, contains: "노트에서 나를 언급했어요").exists, "노트 멘션 알림이 없음")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "note-notifications"
        shot.lifetime = .keepAlways
        add(shot)

        likes.tap()
        let liked = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '생각 조각을 둘 곳'")).firstMatch
        XCTAssertTrue(liked.waitForExistence(timeout: 8), "좋아요 알림이 내 노트를 열지 않음")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let reply = row(app, contains: "내 노트에 답글을 남겼어요")
        XCTAssertTrue(reply.waitForExistence(timeout: 8), "노트 답글 알림이 없음")
        XCTAssertTrue(reply.label.contains("오래 남을 것 같아요"), "답글 알림 부제가 답글 첫 줄이 아님")
        reply.tap()
        let replied = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '이름이 경계라는 말'")).firstMatch
        XCTAssertTrue(replied.waitForExistence(timeout: 8), "답글 알림이 그 답글을 열지 않음")
    }
}
