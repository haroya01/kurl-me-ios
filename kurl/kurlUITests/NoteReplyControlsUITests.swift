//
//  NoteReplyControlsUITests.swift
//  kurlUITests
//
//  노트 답글 제어 — 작성기의 답글 권한, 내 노트 ⋯의 답글 권한, 답할 수 없는 스레드의 답 칸,
//  보내는 사이 막힌 답글, 스레드 작성자의 숨기기·숨김 해제·삭제.
//

import XCTest

final class NoteReplyControlsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(note id: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--push", #"{"noteId":\#(id)}"#]
        app.launch()
        return app
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func composerText(_ app: XCUIApplication) -> XCUIElement {
        app.textViews["noteCompose.text"].exists ? app.textViews["noteCompose.text"] : app.textFields["noteCompose.text"]
    }

    private func confirmFederationNoticeIfShown(_ app: XCUIApplication) {
        let notice = app.alerts.firstMatch
        if notice.waitForExistence(timeout: 4) {
            notice.buttons["알겠어요, 올릴게요"].tap()
        }
    }

    private func sawToast(_ app: XCUIApplication, _ text: String) -> Bool {
        let toast = app.staticTexts.matching(NSPredicate(format: "label == %@", text)).firstMatch
        for _ in 0..<30 {
            if toast.exists { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    private func openReplyPolicy(_ app: XCUIApplication, note id: Int) {
        let menu = app.buttons["note.menu.\(id)"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "노트 \(id)의 ⋯가 없음")
        menu.tap()
        let policy = app.buttons["note.replyPolicy.\(id)"]
        XCTAssertTrue(policy.waitForExistence(timeout: 4), "내 노트 ⋯에 답글 권한이 없음")
        policy.tap()
    }

    func testTheComposerSendsTheChosenReplyPolicy() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()

        let compose = app.buttons["글쓰기"]
        XCTAssertTrue(compose.waitForExistence(timeout: 12), "탭바 가운데 글쓰기가 없음")
        compose.tap()
        let chooseNote = app.buttons["compose.chooser.note"]
        XCTAssertTrue(chooseNote.waitForExistence(timeout: 5), "글쓰기 고르기 시트가 뜨지 않음")
        chooseNote.tap()

        let policy = app.buttons["noteCompose.replyPolicy"]
        XCTAssertTrue(policy.waitForExistence(timeout: 6), "작성기에 답글 권한이 없음")
        XCTAssertTrue(policy.label.contains("답글: 모두"), "답글 권한의 기본값이 모두가 아님: \(policy.label)")
        policy.tap()

        let hint = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "내가 멘션한 사람은 언제나 답글을 달 수 있어요")).firstMatch
        XCTAssertTrue(hint.waitForExistence(timeout: 4), "답글 권한 메뉴에 멘션 안내가 없음")
        XCTAssertTrue(app.buttons["모두"].firstMatch.exists)
        XCTAssertTrue(app.buttons["내가 팔로우하는 사람"].firstMatch.exists)
        attach("compose-reply-policy-menu")
        app.buttons["내가 멘션한 사람만"].firstMatch.tap()
        XCTAssertTrue(policy.label.contains("답글: 내가 멘션한 사람만"), "고른 답글 권한이 버튼에 안 보임: \(policy.label)")

        let text = composerText(app)
        text.tap()
        text.typeText("멘션한 사람만 답하는 노트")
        attach("compose-reply-policy-picked")
        app.buttons["noteCompose.post"].tap()
        confirmFederationNoticeIfShown(app)

        let posted = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '멘션한 사람만 답하는 노트'")).firstMatch
        XCTAssertTrue(posted.waitForExistence(timeout: 8), "올린 노트가 피드에 없음")
        openReplyPolicy(app, note: 9600)
        let mentioned = app.buttons["내가 멘션한 사람만"].firstMatch
        XCTAssertTrue(mentioned.waitForExistence(timeout: 4))
        XCTAssertTrue(mentioned.isSelected, "올린 노트의 답글 권한이 내가 멘션한 사람만이 아님 — 요청에 실리지 않음")
    }

    func testTheWriterChangesWhoCanReplyFromTheNoteMenu() throws {
        let app = launch(note: 9570)

        openReplyPolicy(app, note: 9570)
        XCTAssertTrue(app.buttons["모두"].firstMatch.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["모두"].firstMatch.isSelected, "지금 답글 권한(모두)에 체크가 없음")
        attach("note-menu-reply-policy")
        app.buttons["내가 팔로우하는 사람"].firstMatch.tap()
        XCTAssertTrue(sawToast(app, "답글 권한을 바꿨어요"), "답글 권한을 바꾼 뒤 토스트가 안 뜸")

        openReplyPolicy(app, note: 9570)
        let following = app.buttons["내가 팔로우하는 사람"].firstMatch
        XCTAssertTrue(following.waitForExistence(timeout: 4))
        XCTAssertTrue(following.isSelected, "바꾼 답글 권한이 메뉴에 반영되지 않음")
    }

    func testAThreadClosedToTheViewerShowsWhyInPlaceOfTheReplyBar() throws {
        let app = launch(note: 9560)

        let closed = app.descendants(matching: .any)["note.replyClosed"]
        XCTAssertTrue(closed.waitForExistence(timeout: 12), "답할 수 없는 스레드에 이유가 안 보임")
        XCTAssertTrue(closed.label.contains("작성자가 멘션한 사람만 답글을 달 수 있어요"), "이유 문구가 다름: \(closed.label)")
        XCTAssertFalse(app.buttons["note.reply"].exists, "답할 수 없는데 답 칸이 열려 있음")
        attach("thread-reply-closed")
    }

    func testARefusedReplyKeepsTheDraftAndSaysWhy() throws {
        let app = launch(note: 9561)

        let reply = app.buttons["note.reply"]
        XCTAssertTrue(reply.waitForExistence(timeout: 12), "팔로우한 사람만 스레드인데 답 칸이 없음(독자는 답할 수 있음)")
        reply.tap()
        let text = composerText(app)
        XCTAssertTrue(text.waitForExistence(timeout: 6), "답글 작성기가 안 열림")
        XCTAssertFalse(app.buttons["noteCompose.replyPolicy"].exists, "답글 작성기에 답글 권한이 보임")
        text.typeText("주말 산책 같이 가요")
        app.buttons["noteCompose.post"].tap()
        confirmFederationNoticeIfShown(app)

        let error = app.staticTexts["noteCompose.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 8), "서버가 막은 답글에 이유가 안 보임")
        XCTAssertEqual(error.label, "작성자가 팔로우하거나 멘션한 사람만 답글을 달 수 있어요")
        XCTAssertTrue(
            (composerText(app).value as? String)?.contains("주말 산책 같이 가요") == true,
            "막힌 뒤 쓴 답글이 사라짐")
        attach("reply-refused-keeps-draft")
    }

    func testTheThreadWriterHidesAReplyAndBringsItBack() throws {
        let app = launch(note: 9570)

        let hiddenRow = app.buttons["note.hiddenReplies"]
        XCTAssertTrue(hiddenRow.waitForExistence(timeout: 12), "숨긴 답글이 있는데 보기 줄이 없음")
        XCTAssertTrue(hiddenRow.label.contains("숨긴 답글 1개 보기"), hiddenRow.label)
        XCTAssertFalse(app.buttons["note.body.9572"].exists, "숨긴 답글이 스레드에 보임")

        let menu = app.buttons["note.menu.9571"]
        XCTAssertTrue(menu.waitForExistence(timeout: 6), "남의 답글에 ⋯가 없음")
        menu.tap()
        let hide = app.buttons["note.hideReply.9571"]
        XCTAssertTrue(hide.waitForExistence(timeout: 4), "스레드 작성자의 ⋯에 숨기기가 없음")
        XCTAssertTrue(app.buttons["note.removeReply.9571"].exists, "스레드 작성자의 ⋯에 삭제가 없음")
        attach("thread-writer-reply-menu")
        hide.tap()
        XCTAssertTrue(sawToast(app, "답글을 숨겼어요"), "숨긴 뒤 토스트가 안 뜸")
        XCTAssertFalse(app.buttons["note.body.9571"].waitForExistence(timeout: 2), "숨긴 답글이 스레드에 남음")
        XCTAssertTrue(hiddenRow.label.contains("숨긴 답글 2개 보기"), hiddenRow.label)
        attach("thread-hidden-row")

        hiddenRow.tap()
        XCTAssertTrue(app.buttons["note.body.9571"].waitForExistence(timeout: 8), "숨긴 답글 목록에 방금 숨긴 답글이 없음")
        XCTAssertTrue(app.buttons["note.body.9572"].exists, "숨긴 답글 목록에 원래 숨긴 답글이 없음")
        attach("hidden-replies-list")
        app.buttons["note.menu.9572"].tap()
        let unhide = app.buttons["note.hideReply.9572"]
        XCTAssertTrue(unhide.waitForExistence(timeout: 4))
        XCTAssertEqual(unhide.label, "숨김 해제")
        unhide.tap()
        XCTAssertTrue(sawToast(app, "답글을 다시 보여요"), "숨김 해제 뒤 토스트가 안 뜸")
        XCTAssertFalse(app.buttons["note.body.9572"].waitForExistence(timeout: 2), "숨김을 푼 답글이 숨긴 목록에 남음")

        app.buttons["뒤로"].firstMatch.tap()
        XCTAssertTrue(app.buttons["note.body.9572"].waitForExistence(timeout: 6), "숨김을 푼 답글이 스레드로 돌아오지 않음")
        XCTAssertTrue(hiddenRow.label.contains("숨긴 답글 1개 보기"), hiddenRow.label)
    }

    func testTheThreadWriterDeletesSomeoneElsesReplyAfterConfirming() throws {
        let app = launch(note: 9570)

        let menu = app.buttons["note.menu.9571"]
        XCTAssertTrue(menu.waitForExistence(timeout: 12), "남의 답글에 ⋯가 없음")
        menu.tap()
        let remove = app.buttons["note.removeReply.9571"]
        XCTAssertTrue(remove.waitForExistence(timeout: 4))
        remove.tap()

        let confirm = app.alerts["이 답글을 스레드에서 지울까요?"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 4), "지우기 전에 묻지 않음")
        attach("thread-writer-delete-confirm")
        confirm.buttons["지우기"].tap()
        XCTAssertFalse(app.buttons["note.body.9571"].waitForExistence(timeout: 3), "지운 답글이 스레드에 남음")
    }

    func testTheThreadWriterModeratesRepliesDeeperThanTheFirstNotesChildren() throws {
        let app = launch(note: 9573)

        let deepMenu = app.buttons["note.menu.9574"]
        XCTAssertTrue(deepMenu.waitForExistence(timeout: 12), "깊은 답글에 ⋯가 없음")
        deepMenu.tap()
        let hide = app.buttons["note.hideReply.9574"]
        XCTAssertTrue(hide.waitForExistence(timeout: 4), "첫 노트의 손자 아래 답글에 숨기기가 없음 — 서버의 viewerCanModerate 를 안 씀")
        XCTAssertTrue(app.buttons["note.removeReply.9574"].exists)
        hide.tap()
        XCTAssertTrue(sawToast(app, "답글을 숨겼어요"))
        XCTAssertFalse(app.buttons["note.body.9574"].waitForExistence(timeout: 2), "숨긴 답글이 스레드에 남음")
        let hiddenRow = app.buttons["note.hiddenReplies"]
        XCTAssertTrue(hiddenRow.waitForExistence(timeout: 4), "숨긴 뒤 보기 줄이 생기지 않음")
        XCTAssertTrue(hiddenRow.label.contains("숨긴 답글 1개 보기"), hiddenRow.label)

        app.buttons["note.menu.9573"].tap()
        XCTAssertTrue(
            app.buttons["note.hideReply.9573"].waitForExistence(timeout: 4), "연 답글 자신에 스레드 작성자의 숨기기가 없음")
        attach("deep-reply-writer-menu")
    }

    func testSomeoneElsesThreadOffersNoModeration() throws {
        let app = launch(note: 9501)

        let menu = app.buttons["note.menu.9551"]
        XCTAssertTrue(menu.waitForExistence(timeout: 12), "남의 스레드 답글에 ⋯가 없음")
        menu.tap()
        XCTAssertTrue(app.buttons["note.report.9551"].waitForExistence(timeout: 4), "⋯ 메뉴가 안 열림")
        XCTAssertFalse(app.buttons["note.hideReply.9551"].exists, "남의 스레드에서 숨기기가 보임")
        XCTAssertFalse(app.buttons["note.removeReply.9551"].exists, "남의 스레드에서 삭제가 보임")
        XCTAssertFalse(app.buttons["note.hiddenReplies"].exists, "숨긴 답글이 없는데 보기 줄이 있음")
    }
}
