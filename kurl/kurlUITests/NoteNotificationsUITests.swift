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

    func testANewNoteNoticeOpensThatNote() throws {
        let app = launchInbox()

        let posted = row(app, contains: "새 노트를 올렸어요")
        XCTAssertTrue(posted.waitForExistence(timeout: 12), "종을 켠 작가의 새 노트 알림이 없음")
        XCTAssertTrue(posted.label.contains("yuki_dev"), "새 노트 알림의 보낸 사람이 작가가 아님")
        posted.tap()
        let note = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '헥사고날 포트 이름'")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 8), "새 노트 알림이 그 노트를 열지 않음")
    }

    func testTheBellBesideFollowingTurnsOnNewNoteNoticesAndLeavesWithTheFollow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--author", "yuki_dev"]
        app.launch()

        let bell = app.buttons["follow.bell"]
        XCTAssertTrue(bell.waitForExistence(timeout: 15), "팔로잉 중인 작가 머리에 종이 없음")
        XCTAssertEqual(bell.value as? String, "꺼짐")
        bell.tap()
        let on = expectation(for: NSPredicate(format: "value == '켜짐'"), evaluatedWith: bell)
        wait(for: [on], timeout: 5)
        XCTAssertEqual(bell.value as? String, "켜짐")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "author-bell-on"
        shot.lifetime = .keepAlways
        add(shot)

        app.buttons["팔로잉"].firstMatch.tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: bell)
        wait(for: [gone], timeout: 5)
        app.buttons["팔로우"].firstMatch.tap()
        XCTAssertTrue(bell.waitForExistence(timeout: 5), "다시 팔로우했는데 종이 없음")
        XCTAssertEqual(bell.value as? String, "꺼짐", "언팔로우가 종을 끄지 않음")
    }
}
