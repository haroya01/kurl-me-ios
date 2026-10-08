//
//  GraphNotificationsUITests.swift
//  kurlUITests
//

import XCTest

/// 연결 그래프 알림(CONNECTED·PATH_GREW) 검증 — 인박스 렌더, 컬렉션 딥링크, 선호 토글.
/// `simctl` 로는 탭이 안 되는 경로(인박스 도달·행 탭·설정 진입)를 XCUITest 로 밟아 스크린샷 첨부.
///
/// 실행:
///   xcodebuild test -scheme kurl -only-testing:kurlUITests/GraphNotificationsUITests \
///     -destination 'platform=iOS Simulator,id=<udid>'
///
/// `--mocks` 면 MockBackend 가 CONNECTED(컬렉션 101)·PATH_GREW(PATH 104) 픽스처를 내주므로
/// 실서버 없이 결정론적으로 렌더된다.
final class GraphNotificationsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func rowButton(_ app: XCUIApplication, contains label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }

    /// 계정 탭에서 알림 인박스로 — 헤더의 벨(값 기반 링크)을 눌러 연다. 값 링크로 밀어야 인박스
    /// 안의 딥링크(글·컬렉션)가 같은 스택에서 이어 밀린다(디버그 `--open` 은 isPresented 라 딥링크 불가).
    private func launchInbox() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "account"]
        app.launch()
        let bell = app.buttons["알림"].firstMatch
        XCTAssertTrue(bell.waitForExistence(timeout: 12), "계정 헤더에 알림 벨이 없음")
        bell.tap()
        return app
    }

    /// 인박스에 두 그래프 알림이 선다 — CONNECTED(회원 글이 컬렉션에 엮임)·PATH_GREW(엮인 길에 새 글).
    func testGraphNotificationsRender() throws {
        let app = launchInbox()

        let connected = app.buttons
            .matching(NSPredicate(format: "label CONTAINS '엮었어요'")).firstMatch
        XCTAssertTrue(connected.waitForExistence(timeout: 12), "인박스에 CONNECTED 알림이 없음")
        if !connected.isHittable { app.swipeUp() }

        let pathGrew = app.buttons
            .matching(NSPredicate(format: "label CONTAINS '이어졌어요'")).firstMatch
        XCTAssertTrue(pathGrew.waitForExistence(timeout: 8), "인박스에 PATH_GREW 알림이 없음")

        // 컬렉션 이름이 문장에 박혀 온다 — 카피가 collectionName 을 실제로 끼웠는지 확인.
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS '느린 사고'")).firstMatch.exists,
            "CONNECTED 카피에 컬렉션 이름이 없음")
        shoot("graph-notifications-inbox")
    }

    /// CONNECTED 행 탭 = 컬렉션 상세로 딥링크(글·작가가 아니라 엮인 맥락으로).
    func testConnectedDeepLinksToCollection() throws {
        let app = launchInbox()

        let connected = app.buttons
            .matching(NSPredicate(format: "label CONTAINS '엮었어요'")).firstMatch
        XCTAssertTrue(connected.waitForExistence(timeout: 12), "인박스에 CONNECTED 알림이 없음")
        connected.tap()

        // CollectionDetailView 도달 — 컬렉션 설명·연결 이유는 상세에만 있다(인박스 행엔 없어
        // 오탐 없이 항해를 증명한다). 컬렉션 101 "느린 사고"의 설명 문장으로 단언.
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS '빨리 답하지 않고'"))
                .firstMatch.waitForExistence(timeout: 8),
            "CONNECTED 탭이 컬렉션 상세로 딥링크되지 않음(설명이 안 보임)")
        shoot("graph-notification-collection-deeplink")
    }

    /// 선호 화면에 그래프 토글 2종이 선다(기본 켜짐) — 계정 톱니 → 알림 종류.
    func testGraphPreferenceToggles() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "account"]
        app.launch()

        let gear = app.buttons["설정"].firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 12), "계정 탭에 설정 버튼이 없음")
        gear.tap()

        let row = rowButton(app, contains: "알림 종류")
        XCTAssertTrue(row.waitForExistence(timeout: 8), "설정에 '알림 종류' 행이 없음")
        if !row.isHittable { app.swipeUp() }
        row.tap()

        let connectedToggle = app.switches
            .matching(NSPredicate(format: "label CONTAINS '컬렉션에 엮'")).firstMatch
        XCTAssertTrue(connectedToggle.waitForExistence(timeout: 8), "CONNECTED 토글이 없음")
        if !connectedToggle.isHittable { app.swipeUp() }
        let pathToggle = app.switches
            .matching(NSPredicate(format: "label CONTAINS '새 글이 이어질'")).firstMatch
        for _ in 0..<6 where !pathToggle.isHittable { app.swipeUp() }
        XCTAssertTrue(pathToggle.waitForExistence(timeout: 4), "PATH_GREW 토글이 없음")

        // 두 그래프 토글은 목 기본값 = 켜짐(on).
        XCTAssertEqual(connectedToggle.value as? String, "1", "CONNECTED 토글 기본값이 on 이 아님")
        XCTAssertEqual(pathToggle.value as? String, "1", "PATH_GREW 토글 기본값이 on 이 아님")
        shoot("graph-notification-preferences")
    }

    func testLikeNotificationOpensMyPost() throws {
        let app = launchInbox()
        let like = rowButton(app, contains: "글을 좋아해요")
        XCTAssertTrue(like.waitForExistence(timeout: 12), "인박스에 좋아요 알림이 없음")
        like.tap()
        let markAll = app.buttons["모두 읽음"].firstMatch
        XCTAssertTrue(markAll.waitForNonExistence(timeout: 10), "좋아요 알림을 누르면 인박스에서 넘어가야 함")
        let readingTime = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '읽는 시간'")).firstMatch
        XCTAssertTrue(readingTime.waitForExistence(timeout: 10), "좋아요 알림을 누르면 내 글로 가야 함")
        XCTAssertFalse(app.buttons["팔로우"].exists, "좋아요한 사람 프로필로 빠지면 안 됨")
        shoot("like-opens-post")
    }

    func testCommentNotificationOpensMyPost() throws {
        let app = launchInbox()
        shoot("inbox-with-push-prompt")
        let comment = rowButton(app, contains: "댓글을 남겼어요")
        XCTAssertTrue(comment.waitForExistence(timeout: 12), "인박스에 댓글 알림이 없음")
        comment.tap()
        XCTAssertTrue(app.buttons["모두 읽음"].firstMatch.waitForNonExistence(timeout: 10), "댓글 알림을 누르면 인박스에서 넘어가야 함")
        let target = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH '어댑터를 바깥으로 미는 순서가'")).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10), "댓글 알림을 누르면 그 댓글이 있는 글로 가야 함")
        XCTAssertTrue(waitUntilOnScreen(target, in: app), "댓글 알림을 누르면 그 댓글 위치로 스크롤돼야 함")
        XCTAssertFalse(app.buttons["팔로우"].exists, "댓글 단 사람 프로필로 빠지면 안 됨")
        shoot("comment-opens-at-comment")
    }

    func testAMentionInACommentOpensThatMembersPosts() throws {
        let app = launchInbox()
        let comment = rowButton(app, contains: "댓글을 남겼어요")
        XCTAssertTrue(comment.waitForExistence(timeout: 12), "인박스에 댓글 알림이 없음")
        comment.tap()
        let mention = app.links["@yuki_dev"].firstMatch
        XCTAssertTrue(mention.waitForExistence(timeout: 10), "댓글의 회원 멘션이 링크가 아님")
        XCTAssertFalse(app.links["@nobody_here"].exists, "회원이 아닌 @이름이 링크가 됨")
        shoot("comment-mention")
        mention.tap()
        XCTAssertTrue(app.buttons["author.tab.posts"].waitForExistence(timeout: 10), "멘션한 회원의 프로필이 안 열림")
        XCTAssertTrue(app.buttons["author.tab.posts"].isSelected, "글에서 연 프로필이 글 탭이 아님")
    }

    func testReplyingToAReplyCallsItsAuthorInTheSameThread() throws {
        let app = launchInbox()
        let comment = rowButton(app, contains: "댓글을 남겼어요")
        XCTAssertTrue(comment.waitForExistence(timeout: 12), "인박스에 댓글 알림이 없음")
        comment.tap()
        let reply = app.buttons["comment.reply.507"]
        XCTAssertTrue(reply.waitForExistence(timeout: 10), "답글에 답글 버튼이 없음")
        for _ in 0..<4 where !reply.isHittable { app.swipeUp(velocity: .slow) }
        reply.tap()
        XCTAssertTrue(app.staticTexts["reader_kim님에게 답글"].waitForExistence(timeout: 6), "누구에게 답하는지 안 보임")
        let input = app.descendants(matching: .any).matching(identifier: "comment.input").firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 4), "답글 입력칸이 없음")
        XCTAssertEqual(input.value as? String, "@reader_kim ", "답글 단 사람을 @로 부르지 않음")
        shoot("reply-to-reply")
    }

    func testTypingAnAtSignInACommentOffersPeopleAndFillsTheHandle() throws {
        let app = launchInbox()
        let comment = rowButton(app, contains: "댓글을 남겼어요")
        XCTAssertTrue(comment.waitForExistence(timeout: 12), "인박스에 댓글 알림이 없음")
        comment.tap()
        let reply = app.buttons["comment.reply.506"]
        XCTAssertTrue(reply.waitForExistence(timeout: 10), "댓글 답글 버튼이 없음")
        for _ in 0..<4 where !reply.isHittable { app.swipeUp(velocity: .slow) }
        reply.tap()
        let input = app.descendants(matching: .any).matching(identifier: "comment.input").firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 4), "댓글 입력칸이 없음")
        XCTAssertTrue(app.buttons["댓글을 남겨보세요"].waitForNonExistence(timeout: 3), "답글 바가 떠 있는데 본문 끝 입력 줄도 그대로 보임")
        shoot("reply-target-marked")
        input.typeText("@")
        XCTAssertTrue(app.buttons["mention.yuki_dev"].waitForExistence(timeout: 4), "@만 쳤는데 팔로우한 사람이 안 뜸")
        XCTAssertFalse(app.buttons["mention.haruka"].exists, "@만 쳤는데 팔로우하지 않은 사람이 뜸")
        input.typeText("ha")
        let haruka = app.buttons["mention.haruka"]
        XCTAssertTrue(haruka.waitForExistence(timeout: 4), "글자를 쳐도 맞는 사람이 안 뜸")
        shoot("comment-mention-suggestions")
        haruka.tap()
        XCTAssertEqual(input.value as? String, "@haruka ", "고른 사람의 @이름으로 바뀌지 않음")
        XCTAssertFalse(app.buttons["mention.haruka"].exists, "이름을 넣은 뒤에도 후보가 남음")
    }

    func testAPostQuotedInNotesShowsANotesTabBesideItsComments() throws {
        let app = launchInbox()
        let comment = rowButton(app, contains: "댓글을 남겼어요")
        XCTAssertTrue(comment.waitForExistence(timeout: 12), "인박스에 댓글 알림이 없음")
        comment.tap()
        let notesTab = app.buttons["discussion.notes"]
        XCTAssertTrue(notesTab.waitForExistence(timeout: 10), "노트가 인용한 글인데 노트 탭이 없음")
        XCTAssertTrue(notesTab.label.contains("노트 1"), "노트 탭에 인용 수가 없음")
        for _ in 0..<4 where !notesTab.isHittable { app.swipeDown(velocity: .slow) }
        notesTab.tap()
        XCTAssertTrue(app.buttons["note.body.9520"].waitForExistence(timeout: 6), "노트 탭에 이 글을 인용한 노트가 없음")
        XCTAssertFalse(app.buttons["comment.reply.506"].exists, "노트 탭인데 댓글이 그대로 보임")
        shoot("post-quoting-notes")
        app.buttons["노트로 인용"].firstMatch.tap()
        let field = app.textFields["noteCompose.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "노트 탭에서 인용 작성기가 안 열림")
        field.typeText("uitest post quote")
        app.buttons["noteCompose.post"].tap()
        let notice = app.alerts.firstMatch
        if notice.waitForExistence(timeout: 4) { notice.buttons["알겠어요, 올릴게요"].tap() }
        let mine = app.buttons.matching(NSPredicate(format: "label CONTAINS 'uitest post quote'")).firstMatch
        XCTAssertTrue(mine.waitForExistence(timeout: 8), "방금 올린 인용 노트가 이 글의 노트 목록에 안 보임")
        XCTAssertTrue(notesTab.label.contains("노트 2"), "방금 올린 인용이 노트 수에 안 더해짐")
        app.buttons["discussion.comments"].tap()
        XCTAssertTrue(app.buttons["comment.reply.506"].waitForExistence(timeout: 4), "댓글 탭으로 돌아오지 못함")
    }

    func testHighlightMentionOpensItsConversation() throws {
        let app = launchInbox()
        let mention = app.buttons
            .matching(NSPredicate(format: "label CONTAINS '나를 언급했어요' AND NOT label CONTAINS '노트에서'"))
            .firstMatch
        XCTAssertTrue(mention.waitForExistence(timeout: 12), "인박스에 언급 알림이 없음")
        let clearOfTabBar = app.windows.firstMatch.frame.maxY - 120
        for _ in 0..<4 where !(mention.isHittable && mention.frame.maxY < clearOfTabBar) {
            app.swipeUp(velocity: .slow)
        }
        mention.tap()
        let reply = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH '저도요. 작게 시작했어야'")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 12), "하이라이트 언급을 누르면 그 메모 대화가 열려야 함")
        shoot("highlight-mention-opens-thread")

        XCTAssertTrue(app.links["@minji"].firstMatch.waitForExistence(timeout: 8), "메모 대화의 회원 멘션이 링크가 아님")
        app.buttons["닫기"].firstMatch.tap()
    }

    private func waitUntilOnScreen(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        let screen = app.windows.firstMatch.frame
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            let frame = element.frame
            if element.exists, !frame.isEmpty, screen.contains(CGPoint(x: frame.midX, y: frame.midY)) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    func testActorAvatarOpensProfile() throws {
        let app = launchInbox()
        let avatar = app.buttons["reader_kim 프로필"].firstMatch
        XCTAssertTrue(avatar.waitForExistence(timeout: 12), "좋아요한 사람 아바타 링크가 없음")
        avatar.tap()
        XCTAssertTrue(app.buttons["모두 읽음"].firstMatch.waitForNonExistence(timeout: 10), "아바타를 누르면 인박스에서 넘어가야 함")
        XCTAssertTrue(app.buttons["팔로우"].firstMatch.waitForExistence(timeout: 10), "아바타는 그 사람 프로필로 가야 함")
        shoot("actor-opens-profile")
    }
}
