//
//  ConversationRowsUITests.swift
//  kurlUITests
//

import XCTest

/// 대화 세 표면(글 댓글·하이라이트 답글·노트 답글)이 한 행 문법을 쓴다 — 이름 줄(표시 이름 · @아이디 · 시간),
/// 아바타 36/28, 좋아요 수, 답글·⋯, 그리고 댓글·하이라이트 답글이 같은 작성기를 쓴다.
final class ConversationRowsUITests: XCTestCase {

    private let post = ["--post", "honggildong/hexagonal-after-3-months"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, tries: Int = 14) {
        var n = 0
        while !(element.exists && element.isHittable), n < tries {
            app.swipeUp(velocity: .slow)
            n += 1
        }
    }

    private func waitForValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 4) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func closeMenu(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
    }

    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 12) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func openComments(_ app: XCUIApplication) {
        let reply = app.buttons["comment.reply.501"]
        scrollTo(reply, in: app)
        XCTAssertTrue(reply.exists && reply.isHittable, "댓글 목록까지 내려가지 못함")
    }

    private func openHighlightThread(_ app: XCUIApplication) {
        let paragraph = app.textViews.containing(NSPredicate(format: "value CONTAINS %@", "돌아가라면")).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 15), "하이라이트가 칠해진 첫 문단이 없음")
        XCTAssertTrue(
            app.tapHighlight(in: paragraph, at: [CGVector(dx: 0.55, dy: 0.16), CGVector(dx: 0.5, dy: 0.1)]),
            "하이라이트 탭으로 카드가 안 뜸")
        XCTAssertTrue(app.openConversationFromCard(), "카드에서 대화가 안 열림")
    }

    private func openNoteReplies(_ app: XCUIApplication) {
        let replies = app.buttons["note.replies.9501"]
        XCTAssertTrue(replies.waitForExistence(timeout: 12), "노트 답글 버튼이 없음")
        replies.tap()
        XCTAssertTrue(app.navigationBars["노트"].waitForExistence(timeout: 8), "노트 상세가 열리지 않음")
        app.swipeUp(velocity: .slow)
    }

    func testCaptureConversationSurfaces() throws {
        var app = launch(["--mocks"] + post)
        openComments(app)
        attach("comments")

        app.terminate()
        app = launch(["--mocks"] + post)
        openHighlightThread(app)
        Thread.sleep(forTimeInterval: 0.6)
        attach("highlight-thread")

        app.terminate()
        app = launch(["--mocks", "--tab", "notes"])
        openNoteReplies(app)
        Thread.sleep(forTimeInterval: 0.6)
        attach("note-replies")
    }

    /// 이름 줄 — 표시 이름이 있으면 "이름 @아이디", 없으면 "@아이디"만. 좋아요는 수와 함께, 0이면 하트만.
    func testCommentRowsShowTheNameLineAndLikeCounts() throws {
        let app = launch(["--mocks"] + post)
        openComments(app)
        XCTAssertTrue(app.buttons["@haruka"].exists, "표시 이름이 없는 사람이 @아이디로 안 보임")
        let liked = app.buttons["comment.like.501"]
        XCTAssertEqual(liked.value as? String, "2", "좋아요 수가 안 보임")
        XCTAssertEqual(app.buttons["comment.like.502"].value as? String ?? "", "", "좋아요 0인데 수가 보임")

        let kim = app.buttons["comment.like.507"]
        scrollTo(kim, in: app)
        let named = app.buttons.matching(NSPredicate(
            format: "label CONTAINS '김독자' AND label CONTAINS '@reader_kim'")).firstMatch
        XCTAssertTrue(named.exists, "표시 이름과 @아이디가 한 줄에 안 보임")

        let yuki = app.buttons["comment.like.506"]
        XCTAssertEqual(yuki.value as? String, "5")
        yuki.tap()
        XCTAssertTrue(waitForValue(yuki, "6"), "좋아요를 눌러도 수가 안 오름")
        XCTAssertTrue(yuki.isSelected, "좋아요한 상태가 안 보임")
        attach("comments-liked")
    }

    /// ⋯ 은 남의 댓글에만 — 차단·신고. 내 댓글은 같은 자리에 휴지통.
    func testOthersCommentsOfferBlockAndReportMineOfferDelete() throws {
        let app = launch(["--mocks", "--my-comment-thread"] + post)
        openComments(app)
        let more = app.buttons["comment.more.501"]
        XCTAssertTrue(waitUntilHittable(more), "남의 댓글에 ⋯ 이 없음")
        more.tap()
        XCTAssertTrue(app.buttons["차단"].waitForExistence(timeout: 4), "⋯ 에 차단이 없음")
        XCTAssertTrue(app.buttons["신고"].exists, "⋯ 에 신고가 없음")
        closeMenu(app)

        let delete = app.buttons["comment.delete.508"]
        scrollTo(delete, in: app)
        XCTAssertTrue(delete.exists, "내 댓글에 휴지통이 없음")
        XCTAssertFalse(app.buttons["comment.more.508"].exists, "내 댓글에 ⋯ 이 붙음")
    }

    /// 답글 칩은 "@아이디에게 답글" — 답글에 단 답글만 본문 앞에 @아이디를 채우고, 취소하면 함께 걷힌다.
    func testReplyChipNamesTheHandleAndCancelTakesTheHandleBack() throws {
        let app = launch(["--mocks"] + post)
        openComments(app)
        app.buttons["comment.reply.501"].tap()
        XCTAssertTrue(app.staticTexts["@haruka에게 답글"].waitForExistence(timeout: 6), "답글 칩이 없음")
        let input = element(app, "comment.input")
        XCTAssertFalse((input.value as? String ?? "").contains("@haruka"), "맨 위 댓글 답글에 @아이디를 채움")

        let nested = app.buttons["comment.reply.507"]
        scrollTo(nested, in: app, tries: 4)
        nested.tap()
        XCTAssertTrue(app.staticTexts["@reader_kim에게 답글"].waitForExistence(timeout: 6), "칩이 새 대상으로 안 바뀜")
        XCTAssertEqual(input.value as? String, "@reader_kim ", "답글의 답글에 @아이디를 안 채움")
        attach("reply-chip")

        app.buttons["답글 취소"].tap()
        XCTAssertTrue(app.staticTexts["@reader_kim에게 답글"].waitForNonExistence(timeout: 4), "취소해도 칩이 남음")
        XCTAssertFalse((input.value as? String ?? "").contains("@reader_kim"), "취소해도 채운 @아이디가 남음")
    }

    /// 지운 댓글은 답글이 남으면 자리로 — 답글은 그대로, 답글 버튼만 없다. 수에서는 빠진다.
    func testADeletedCommentWithRepliesStaysAsAPlaceholder() throws {
        let app = launch(["--mocks", "--comment-tombstone"] + post)
        let stone = element(app, "comment.tombstone.504")
        scrollTo(stone, in: app)
        XCTAssertTrue(stone.exists, "지운 댓글의 자리가 없음")
        XCTAssertTrue(stone.label.contains("삭제된 댓글이에요"), "자리 문구가 다름: \(stone.label)")
        XCTAssertTrue(app.buttons["comment.like.505"].exists, "자리 밑 답글이 사라짐")
        XCTAssertFalse(app.buttons["comment.reply.505"].exists, "지운 댓글 밑 답글에 답글 버튼이 남음")
        XCTAssertFalse(app.buttons["comment.like.504"].exists, "자리에 좋아요가 붙음")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(NSPredicate(format: "label == '댓글 6'")).firstMatch.exists,
            "지운 댓글까지 셈")
        attach("tombstone")
    }

    /// 답글이 달린 내 댓글을 지우면 자리만 남고 답글은 그대로다.
    func testDeletingMyCommentWithRepliesLeavesItsPlace() throws {
        let app = launch(["--mocks", "--my-comment-thread"] + post)
        let delete = app.buttons["comment.delete.508"]
        scrollTo(delete, in: app)
        XCTAssertTrue(waitUntilHittable(delete), "내 댓글에 휴지통이 없음")
        delete.tap()
        let confirm = app.alerts.buttons["삭제"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 4), "삭제 확인이 없음")
        confirm.tap()
        XCTAssertTrue(element(app, "comment.tombstone.508").waitForExistence(timeout: 8), "지운 자리가 안 남음")
        XCTAssertTrue(app.buttons["comment.like.509"].exists, "내 댓글을 지우자 남의 답글도 사라짐")
        XCTAssertFalse(app.buttons["comment.reply.509"].exists, "지운 댓글 밑 답글에 답글 버튼이 남음")
    }

    /// 하이라이트 답글 — 남의 답글엔 답글(@아이디 채움)과 ⋯(차단·신고), 내 답글엔 휴지통. 칩은 없다.
    func testHighlightRepliesOfferReplyBlockAndReport() throws {
        let app = launch(["--mocks"] + post)
        openHighlightThread(app)
        let reply = app.buttons["highlightReply.reply.7002"]
        XCTAssertTrue(reply.waitForExistence(timeout: 6), "남의 하이라이트 답글에 답글 버튼이 없음")
        XCTAssertFalse(app.buttons["highlightReply.reply.7001"].exists, "내 답글에 답글 버튼이 붙음")
        XCTAssertTrue(app.buttons["highlightReply.delete.7001"].exists, "내 답글에 휴지통이 없음")

        XCTAssertFalse(app.buttons["highlightReply.more.7001"].exists, "내 답글에 ⋯ 이 붙음")
        app.buttons["highlightReply.more.7002"].tap()
        XCTAssertTrue(app.buttons["차단"].waitForExistence(timeout: 4), "⋯ 에 차단이 없음")
        XCTAssertTrue(app.buttons["신고"].exists, "⋯ 에 신고가 없음")
        closeMenu(app)
        XCTAssertTrue(app.navigationBars["대화"].waitForExistence(timeout: 4), "메뉴를 닫다 시트가 닫힘")

        reply.tap()
        let input = element(app, "highlightReply.field")
        XCTAssertTrue(input.waitForExistence(timeout: 4), "공용 작성기가 없음")
        XCTAssertEqual(input.value as? String, "@reader_kim ", "답글 대상을 @로 안 부름")
        XCTAssertFalse(element(app, "conversation.replyChip").exists, "평평한 하이라이트 답글에 칩이 뜸")
        reply.tap()
        XCTAssertEqual(input.value as? String, "@reader_kim ", "같은 사람을 두 번 부름")
        attach("highlight-reply")
    }

    /// 하이라이트 답글 좋아요 — 수와 함께 바로 오르내리고, 내 답글에도 누를 수 있다.
    func testHighlightReplyLikesCountUpAndDown() throws {
        let app = launch(["--mocks"] + post)
        openHighlightThread(app)
        let theirs = app.buttons["highlightReply.like.7002"]
        XCTAssertTrue(theirs.waitForExistence(timeout: 6), "하이라이트 답글에 좋아요가 없음")
        XCTAssertEqual(theirs.value as? String, "3", "좋아요 수가 안 보임")
        theirs.tap()
        XCTAssertTrue(waitForValue(theirs, "4"), "좋아요를 눌러도 수가 안 오름")
        XCTAssertTrue(theirs.isSelected, "좋아요한 상태가 안 보임")
        attach("highlight-reply-liked")
        theirs.tap()
        XCTAssertTrue(waitForValue(theirs, "3"), "좋아요를 거둬도 수가 안 내려감")

        let mine = app.buttons["highlightReply.like.7001"]
        XCTAssertTrue(mine.exists, "내 답글에 좋아요가 없음")
        mine.tap()
        XCTAssertTrue(waitForValue(mine, "1"), "내 답글 좋아요가 안 오름")
    }

    /// 좋아요가 서버에서 실패하면 수와 상태를 되돌리고 시트 안에서 알린다.
    func testAFailedHighlightReplyLikeRevertsAndSaysSo() throws {
        let app = launch(["--mocks", "--fail-reply-like"] + post)
        openHighlightThread(app)
        let like = app.buttons["highlightReply.like.7002"]
        XCTAssertTrue(like.waitForExistence(timeout: 6), "하이라이트 답글에 좋아요가 없음")
        like.tap()
        XCTAssertTrue(app.staticTexts["좋아요를 반영하지 못했어요"].waitForExistence(timeout: 6), "실패를 알리지 않음")
        attach("highlight-reply-like-failed")
        XCTAssertTrue(waitForValue(like, "3"), "실패했는데 수가 안 돌아옴")
        XCTAssertFalse(like.isSelected, "실패했는데 좋아요한 상태로 남음")
    }

    /// 로그아웃이면 하트는 그 자리에서 로그인을 묻고, ⋯ 에는 신고만 남는다.
    func testSignedOutHighlightReplyLikeAsksToSignInAndReportStays() throws {
        let app = launch(["--mocks", "--logged-out"] + post)
        openHighlightThread(app)
        let like = app.buttons["highlightReply.like.7002"]
        XCTAssertTrue(like.waitForExistence(timeout: 6), "로그아웃에서 좋아요가 안 보임")
        like.tap()
        XCTAssertTrue(app.staticTexts["좋아요를 누르려면 로그인하세요"].waitForExistence(timeout: 6), "로그인을 안 물음")
        element(app, "login.sheet").swipeDown(velocity: .fast)
        XCTAssertTrue(app.staticTexts["좋아요를 누르려면 로그인하세요"].waitForNonExistence(timeout: 6), "로그인 시트가 안 닫힘")
        XCTAssertTrue(app.navigationBars["대화"].exists, "로그인을 묻다 대화 시트가 닫힘")
        XCTAssertEqual(like.value as? String, "3", "로그인 안 했는데 수가 바뀜")

        XCTAssertFalse(app.buttons["highlightReply.reply.7002"].exists, "로그아웃에 답글 버튼이 보임")
        app.buttons["highlightReply.more.7002"].tap()
        let report = app.buttons["신고"]
        XCTAssertTrue(report.waitForExistence(timeout: 4), "로그아웃 ⋯ 에 신고가 없음")
        XCTAssertFalse(app.buttons["차단"].exists, "로그아웃 ⋯ 에 차단이 보임")
        report.tap()
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '이 답글을 신고합니다'")).firstMatch
                .waitForExistence(timeout: 6),
            "답글 신고 시트가 안 뜸")
        attach("highlight-reply-report")
    }

    /// 로그인 안 한 채 하이라이트 답글을 보내면 시트를 닫지 않고 그 자리에서 로그인을 묻고, 쓴 글은 남는다.
    func testSignedOutHighlightReplyAsksToSignInInPlace() throws {
        let app = launch(["--mocks", "--logged-out"] + post)
        openHighlightThread(app)
        let input = element(app, "highlightReply.field")
        XCTAssertTrue(input.waitForExistence(timeout: 6), "작성기가 없음")
        input.tap()
        input.typeText("hello there")
        app.buttons["highlightReply.send"].tap()
        XCTAssertTrue(app.staticTexts["답글을 달려면 로그인하세요"].waitForExistence(timeout: 6), "로그인 안내가 안 뜸")
        attach("highlight-signin")
        element(app, "login.sheet").swipeDown(velocity: .fast)
        XCTAssertTrue(app.staticTexts["답글을 달려면 로그인하세요"].waitForNonExistence(timeout: 6), "로그인 시트가 안 닫힘")
        XCTAssertTrue(app.navigationBars["대화"].exists, "로그인을 묻다 대화 시트가 닫힘")
        XCTAssertEqual(input.value as? String, "hello there", "쓴 답글이 사라짐")
    }

    /// VoiceOver 에서는 행 하나가 한 요소 — 이름·시간·본문·좋아요 수를 한 번에 읽고, 동작은 행에 붙는다.
    func testRowsReadAsOneElementWithVoiceOverGrouping() throws {
        var app = launch(["--mocks", "--a11y-group"] + post)
        let row = element(app, "comment.row.501")
        scrollTo(row, in: app)
        XCTAssertTrue(row.exists, "댓글 행이 한 요소로 안 묶임")
        XCTAssertTrue(row.label.hasPrefix("haruka, "), "이름부터 안 읽음: \(row.label)")
        XCTAssertTrue(row.label.contains("경계를 먼저 긋는다는"), "본문을 안 읽음: \(row.label)")
        XCTAssertEqual(
            row.descendants(matching: .button).matching(identifier: "comment.reply.501").count, 1,
            "답글 버튼이 행 요소 밖에 있음 — VoiceOver 가 행을 한 번에 못 읽음")
        XCTAssertTrue(app.buttons["haruka님 프로필"].exists, "아바타 링크에 이름이 없음")
        let kim = element(app, "comment.row.507")
        scrollTo(kim, in: app, tries: 6)
        XCTAssertTrue(kim.label.hasPrefix("김독자, "), "표시 이름으로 안 읽음: \(kim.label)")

        app.terminate()
        app = launch(["--mocks", "--a11y-group"] + post)
        openHighlightThread(app)
        let highlightRow = element(app, "highlightReply.7002")
        XCTAssertTrue(highlightRow.waitForExistence(timeout: 6), "하이라이트 답글이 한 요소로 안 묶임")
        XCTAssertTrue(highlightRow.label.contains("첫 두 주 비용"), "하이라이트 답글 본문을 안 읽음")

        app.terminate()
        app = launch(["--mocks", "--a11y-group", "--tab", "notes"])
        let note = element(app, "note.row.9501")
        XCTAssertTrue(note.waitForExistence(timeout: 12), "노트 행이 한 요소로 안 묶임")
        XCTAssertTrue(note.label.contains("헥사고날 포트 이름"), "노트 본문을 안 읽음: \(note.label)")
        XCTAssertTrue(app.buttons["note.replies.9501"].exists, "노트 상세로 가는 답글 버튼이 묶임에 갇힘")
        XCTAssertTrue(app.buttons["note.menu.9501"].exists, "노트 메뉴가 묶임에 갇힘")
    }

    /// 노트 답글도 같은 이름 줄 — 표시 이름이 있으면 "이름 @아이디", 없으면 "@아이디".
    func testNoteRowsUseTheSameNameLine() throws {
        let app = launch(["--mocks", "--tab", "notes"])
        XCTAssertTrue(app.buttons["note.replies.9501"].waitForExistence(timeout: 12), "노트 피드가 안 뜸")
        XCTAssertTrue(app.buttons["@yuki_dev"].firstMatch.exists, "표시 이름이 없는 작가가 @아이디로 안 보임")
        openNoteReplies(app)
        let named = app.buttons.matching(NSPredicate(
            format: "label CONTAINS '김독자' AND label CONTAINS '@reader_kim'")).firstMatch
        XCTAssertTrue(named.waitForExistence(timeout: 6), "노트 답글 이름 줄이 댓글과 다름")
    }

    /// 큰 글자에서 아바타가 글자를 따라 커진다(상한 1.8배). 대화 행 아바타는 노트 피드 첫 행과 같은 컴포넌트다.
    func testAvatarsGrowWithLargerText() throws {
        var app = launch(["--mocks", "--tab", "notes"])
        var avatar = app.buttons["yuki_dev님 프로필"].firstMatch
        XCTAssertTrue(avatar.waitForExistence(timeout: 12), "아바타 링크가 없음")
        let base = avatar.frame.width

        app.terminate()
        app = launch(["--mocks", "--tab", "notes", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        avatar = app.buttons["yuki_dev님 프로필"].firstMatch
        XCTAssertTrue(avatar.waitForExistence(timeout: 12), "큰 글자에서 아바타 링크가 없음")
        XCTAssertGreaterThan(avatar.frame.width, base * 1.5, "큰 글자에서도 아바타가 그대로: \(base) → \(avatar.frame.width)")
        attach("notes-ax")
    }
}
