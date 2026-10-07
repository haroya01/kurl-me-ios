//
//  NotesFeedUITests.swift
//  kurlUITests
//

import XCTest

/// 노트 — 노트 탭, 목 피드 렌더, 작성 시트 → 첫 노트 연합 안내 → 맨 위 꽂힘, 답글 화면까지.
final class NotesFeedUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func openNotes(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["notes.compose"].waitForExistence(timeout: 12), "노트 탭이 열리지 않음")
    }

    func testNotesTabPublishes() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks"]
        app.launch()
        let tab = app.buttons["노트"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 12), "탭바에 노트가 없음")
        tab.tap()
        openNotes(app)

        let seeded = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '헥사고날 포트'")).firstMatch
        XCTAssertTrue(seeded.waitForExistence(timeout: 10), "노트 목 피드가 렌더되지 않음")

        let compose = app.buttons["notes.compose"]
        XCTAssertTrue(compose.waitForExistence(timeout: 5), "노트 쓰기 버튼 없음")
        compose.tap()

        let field = app.textFields["noteCompose.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "작성 시트의 입력란 없음")
        field.typeText("uitest note round trip https://kurl.me")
        app.buttons["noteCompose.post"].tap()

        // 첫 노트는 연합 안내를 한 번 확인받는다 — 확인해야 올라간다.
        let notice = app.alerts.firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 6), "첫 노트 연합 안내가 뜨지 않음")
        XCTAssertTrue(notice.staticTexts["노트는 다른 서버에도 전해져요"].exists)
        notice.buttons["알겠어요, 올릴게요"].tap()

        let published = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'uitest note round trip'")).firstMatch
        XCTAssertTrue(published.waitForExistence(timeout: 8), "발행한 노트가 맨 위에 안 꽂힘")
        XCTAssertFalse(app.textFields["noteCompose.text"].exists, "올린 뒤 시트가 닫히지 않음")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "notes-tab"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testTappingTheNotesTabAgainSwitchesTheFeed() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)
        XCTAssertTrue(app.buttons["note.menu.9503"].waitForExistence(timeout: 10), "모든 노트에 reader_kim 노트가 없음")

        let menu = app.buttons["tab.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "선택된 노트 탭이 메뉴가 아님")
        menu.tap()
        let trending = app.buttons["인기"]
        XCTAssertTrue(trending.waitForExistence(timeout: 5), "탭 위로 피드 메뉴가 열리지 않음")
        let opened = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        opened.name = "notes-feed-menu"
        opened.lifetime = .keepAlways
        add(opened)
        trending.tap()

        XCTAssertTrue(app.navigationBars["인기"].waitForExistence(timeout: 5), "제목이 인기로 안 바뀜")
        let top = app.buttons["note.menu.9502"]
        let newest = app.buttons["note.menu.9501"]
        XCTAssertTrue(top.waitForExistence(timeout: 8) && newest.waitForExistence(timeout: 2), "인기 피드가 안 그려짐")
        XCTAssertLessThan(top.frame.minY, newest.frame.minY, "좋아요 11개 노트가 최신 노트보다 위에 있지 않음")

        menu.tap()
        app.buttons["팔로잉"].tap()
        XCTAssertTrue(app.navigationBars["팔로잉"].waitForExistence(timeout: 5), "제목이 팔로잉으로 안 바뀜")
        XCTAssertTrue(app.buttons["note.menu.9501"].waitForExistence(timeout: 8), "팔로잉 피드가 안 그려짐")
        XCTAssertTrue(app.buttons["note.menu.9503"].waitForExistence(timeout: 4), "팔로우한 사람의 리포스트가 팔로잉에 안 흐름")
        let reposted = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'yuki_dev님이 리포스트함'")).firstMatch
        XCTAssertTrue(reposted.exists, "리포스트로 들어온 노트에 리포스트한 사람이 안 붙음")
        XCTAssertLessThan(reposted.frame.minY, app.buttons["note.menu.9503"].frame.minY, "리포스트 머리줄이 그 노트 위에 있지 않음")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "notes-following"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testABookmarkFromTheDetailShowsInTheBookmarksFeedAndQuotesOpenFromTheDetail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        let replies = app.buttons["note.replies.9501"]
        XCTAssertTrue(replies.waitForExistence(timeout: 10), "답글 버튼 없음")
        replies.tap()

        let bookmark = app.buttons["note.bookmark.9501"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 8), "상세 수치 줄에 북마크가 없음")
        bookmark.tap()
        XCTAssertTrue(bookmark.isSelected, "북마크가 켜지지 않음")

        let quotes = app.buttons["note.quotes.9501"]
        XCTAssertTrue(quotes.waitForExistence(timeout: 4), "인용 줄이 없음")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "note-detail-bookmark-quotes"
        shot.lifetime = .keepAlways
        add(shot)
        quotes.tap()
        XCTAssertTrue(app.navigationBars["인용한 노트"].waitForExistence(timeout: 6), "인용 목록이 안 열림")
        XCTAssertTrue(app.buttons["note.menu.9505"].waitForExistence(timeout: 6), "인용한 노트가 목록에 없음")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let menu = app.buttons["tab.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 6), "노트 탭 메뉴가 없음")
        menu.tap()
        app.buttons["북마크한 노트"].tap()
        XCTAssertTrue(app.buttons["note.menu.9501"].waitForExistence(timeout: 8), "북마크한 노트가 북마크 피드에 없음")
    }

    func testRepostsHideForTheWholeFollowingFeedAndForOnePerson() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        let menu = app.buttons["tab.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 6), "노트 탭 메뉴가 없음")
        menu.tap()
        app.buttons["팔로잉"].tap()
        let header = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'yuki_dev님이 리포스트함'")).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 8), "팔로잉에 리포스트가 없음")

        menu.tap()
        let showReposts = menuItem(app, "리포스트 보기")
        XCTAssertTrue(showReposts.waitForExistence(timeout: 4), "팔로잉 메뉴에 리포스트 보기가 없음")
        attach(app, "notes-following-menu-reposts")
        showReposts.tap()
        XCTAssertTrue(header.waitForNonExistence(timeout: 8), "리포스트를 끄고도 리포스트가 남음")

        menu.tap()
        menuItem(app, "리포스트 보기").tap()
        XCTAssertTrue(header.waitForExistence(timeout: 8), "리포스트를 다시 켜도 안 돌아옴")

        let name = app.buttons["yuki_dev"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 6))
        name.tap()
        let more = app.buttons["더 보기"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 10), "프로필 더 보기 메뉴가 없음")
        more.tap()
        let hide = app.buttons["리포스트 숨기기"].firstMatch
        XCTAssertTrue(hide.waitForExistence(timeout: 6), "팔로우한 사람의 메뉴에 리포스트 숨기기가 없음")
        attach(app, "author-menu-hide-reposts")
        hide.tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(header.waitForNonExistence(timeout: 8), "숨긴 사람의 리포스트가 팔로잉에 남음")
        XCTAssertTrue(app.buttons["note.menu.9501"].exists, "숨긴 건 리포스트뿐인데 그 사람 노트까지 사라짐")
    }

    private func menuItem(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ AND (elementType == %d OR elementType == %d)",
            label, XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.switch.rawValue
        )).firstMatch
    }

    func testAHashtagOpensTheTagOnItsNotesTabBesideItsPosts() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        let tag = app.links["#아키텍처"].firstMatch
        XCTAssertTrue(tag.waitForExistence(timeout: 10), "노트 본문의 해시태그가 링크가 아님")
        tag.tap()

        let tabs = app.segmentedControls["tag.tabs"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 8), "태그 화면이 안 열림")
        XCTAssertTrue(tabs.buttons["노트"].isSelected, "노트에서 연 태그가 노트 탭으로 열리지 않음")
        XCTAssertTrue(app.buttons["note.menu.9501"].waitForExistence(timeout: 8), "태그의 노트가 안 보임")
        attach(app, "tag-notes")

        tabs.buttons["글"].tap()
        XCTAssertTrue(tabs.buttons["글"].isSelected, "글 탭으로 바뀌지 않음")
        XCTAssertTrue(app.buttons["note.menu.9501"].waitForNonExistence(timeout: 6), "글 탭에 노트가 남음")
    }

    func testAMentionOfAMemberOpensTheirProfile() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        let replies = app.buttons["note.replies.9501"]
        XCTAssertTrue(replies.waitForExistence(timeout: 10), "답글 버튼 없음")
        replies.tap()

        let mention = app.links["@yuki_dev"].firstMatch
        XCTAssertTrue(mention.waitForExistence(timeout: 8), "답글의 @멘션이 링크가 아님")
        attach(app, "note-mention")
        mention.tap()
        XCTAssertTrue(app.buttons["author.tab.notes"].waitForExistence(timeout: 10), "멘션한 회원의 프로필이 안 열림")
        XCTAssertTrue(app.buttons["author.tab.notes"].isSelected, "노트에서 연 프로필이 노트 탭이 아님")
    }

    func testAWarnedNoteFoldsUntilRevealedAndASensitivePhotoStaysCovered() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        let warning = app.descendants(matching: .any)["note.warning.9506"]
        for _ in 0..<8 where !warning.exists { app.swipeUp() }
        XCTAssertTrue(warning.waitForExistence(timeout: 6), "열람 주의 노트가 안 보임")
        let spoiler = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '돌아오지 않는다'")).firstMatch
        XCTAssertFalse(spoiler.exists, "펼치기 전에 본문이 보임")
        let cover = app.buttons["note.sensitive.9507"]
        for _ in 0..<4 where !cover.exists { app.swipeUp() }
        XCTAssertTrue(cover.waitForExistence(timeout: 6), "민감한 사진이 가려지지 않음")
        attach(app, "note-warning-and-sensitive")

        cover.tap()
        XCTAssertTrue(cover.waitForNonExistence(timeout: 4), "눌러도 사진이 안 보임")
        let reveal = app.buttons["note.reveal.9506"]
        for _ in 0..<4 where !reveal.isHittable { app.swipeDown() }
        reveal.tap()
        XCTAssertTrue(spoiler.waitForExistence(timeout: 4), "내용 보기를 눌러도 본문이 안 펼쳐짐")
    }

    func testTheComposerSendsAContentWarning() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        let fab = app.buttons["notes.fab"]
        XCTAssertTrue(fab.waitForExistence(timeout: 8))
        fab.tap()
        let text = app.textViews["noteCompose.text"].exists ? app.textViews["noteCompose.text"] : app.textFields["noteCompose.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 6))
        text.typeText("범인은 집사였다")
        app.buttons["noteCompose.warningToggle"].tap()
        let field = app.textViews["noteCompose.warning"].exists ? app.textViews["noteCompose.warning"] : app.textFields["noteCompose.warning"]
        XCTAssertTrue(field.waitForExistence(timeout: 4), "열람 주의 칸이 안 열림")
        field.tap()
        field.typeText("추리소설 결말")
        attach(app, "note-compose-warning")
        app.buttons["noteCompose.post"].tap()
        let notice = app.alerts.firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 6), "첫 노트 연합 안내가 뜨지 않음")
        notice.buttons["알겠어요, 올릴게요"].tap()

        let posted = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '추리소설 결말'")).firstMatch
        XCTAssertTrue(posted.waitForExistence(timeout: 10), "올린 노트에 열람 주의 문구가 없음")
        let body = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '범인은 집사였다'")).firstMatch
        XCTAssertFalse(body.exists, "열람 주의 노트의 본문이 펼쳐진 채 올라옴")
    }

    func testPinningANoteMovesItToTheTopOfMyProfileUnderAPinnedLine() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        let name = app.buttons["honggildong"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        let older = app.buttons["note.menu.9504"]
        XCTAssertTrue(older.waitForExistence(timeout: 10), "내 프로필 노트 탭에 노트가 없음")
        older.tap()
        let pin = app.buttons["프로필에 고정"]
        XCTAssertTrue(pin.waitForExistence(timeout: 4), "내 노트 메뉴에 프로필에 고정이 없음")
        pin.tap()

        let pinnedLine = app.descendants(matching: .any)["note.pinned.9504"]
        XCTAssertTrue(pinnedLine.waitForExistence(timeout: 8), "고정된 노트에 고정됨 줄이 없음")
        let newest = app.buttons["note.menu.9505"]
        XCTAssertTrue(newest.waitForExistence(timeout: 4))
        XCTAssertLessThan(older.frame.minY, newest.frame.minY, "고정한 노트가 맨 위로 오지 않음")
        attach(app, "profile-pinned-note")
    }

    func testAnEditedNoteOpensItsEditHistoryFromTheDetail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        let body = app.buttons["note.body.9505"]
        XCTAssertTrue(body.waitForExistence(timeout: 10))
        body.tap()
        let edited = app.buttons["note.history.9505"]
        XCTAssertTrue(edited.waitForExistence(timeout: 8), "상세의 고침이 눌리지 않음")
        edited.tap()
        XCTAssertTrue(app.navigationBars["수정 기록"].waitForExistence(timeout: 6), "수정 기록이 안 열림")
        let earlier = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '싸게 먹힌 거다.' AND NOT (label CONTAINS '일주일')")).firstMatch
        XCTAssertTrue(earlier.waitForExistence(timeout: 6), "이전 판이 없음")
        attach(app, "note-edit-history")
    }

    func testPrivateMentionsHaveTheirOwnFeedAndTheComposerChoosesAVisibility() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        let menu = app.buttons["tab.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 6))
        menu.tap()
        app.buttons["개인 멘션"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["개인 멘션"].waitForExistence(timeout: 6), "개인 멘션 피드로 안 바뀜")
        let dm = app.descendants(matching: .any)["note.visibility.9508"].firstMatch
        XCTAssertTrue(dm.waitForExistence(timeout: 8), "개인 멘션 노트에 범위 표시가 없음")
        XCTAssertEqual(app.descendants(matching: .any)["note.repost.9508"].firstMatch.label, "리포스트할 수 없는 노트",
                       "멘션한 사람만 보는 노트를 리포스트할 수 있음")
        attach(app, "notes-direct-feed")

        app.buttons["notes.fab"].tap()
        let text = app.textFields["noteCompose.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 6))
        text.typeText("팔로워에게만")
        app.buttons["noteCompose.visibility"].tap()
        app.buttons["팔로워만"].firstMatch.tap()
        attach(app, "note-compose-visibility")
        app.buttons["noteCompose.post"].tap()
        let notice = app.alerts.firstMatch
        if notice.waitForExistence(timeout: 4) { notice.buttons["알겠어요, 올릴게요"].tap() }
        XCTAssertTrue(app.descendants(matching: .any)["note.visibility.9600"].firstMatch.waitForExistence(timeout: 8),
                      "팔로워만 보는 노트에 범위 표시가 없음")
    }

    func testAPersonAddedToAListShowsUpInThatListsFeed() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        let name = app.buttons["yuki_dev"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        name.tap()
        let more = app.buttons["더 보기"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        more.tap()
        app.buttons["리스트에 추가…"].firstMatch.tap()
        let title = app.textFields["noteList.membership.newTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 6), "리스트에 추가 시트가 안 열림")
        title.tap()
        title.typeText("동료")
        app.buttons["noteList.membership.create"].tap()
        let row = app.buttons["noteList.membership.700"]
        XCTAssertTrue(row.waitForExistence(timeout: 6), "새 리스트가 안 생김")
        XCTAssertTrue(row.isSelected, "만든 리스트에 담기지 않음")
        attach(app, "note-list-membership")
        app.buttons["완료"].firstMatch.tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let menu = app.buttons["tab.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 6))
        menu.tap()
        app.buttons["동료"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["동료"].waitForExistence(timeout: 6), "리스트 피드로 안 바뀜")
        XCTAssertTrue(app.buttons["note.menu.9501"].waitForExistence(timeout: 8), "담은 사람의 노트가 리스트에 없음")
        XCTAssertFalse(app.buttons["note.menu.9503"].exists, "담지 않은 사람의 노트가 리스트에 있음")
        attach(app, "note-list-feed")
    }

    func testMutingSomeoneFromTheirProfileTakesTheirNotesOutOfTheFeed() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        XCTAssertTrue(app.buttons["note.menu.9501"].waitForExistence(timeout: 8), "yuki_dev의 노트가 피드에 없음")
        app.buttons["yuki_dev"].firstMatch.tap()
        let more = app.buttons["더 보기"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        more.tap()
        app.buttons["뮤트…"].firstMatch.tap()

        let confirm = app.buttons["mute.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 6), "뮤트 시트가 안 열림")
        attach(app, "mute-sheet")
        confirm.tap()

        more.tap()
        XCTAssertTrue(app.buttons["뮤트 해제"].firstMatch.waitForExistence(timeout: 4), "메뉴가 뮤트 해제로 안 바뀜")
        app.buttons["뮤트 해제"].firstMatch.tap()
        more.tap()
        app.buttons["뮤트…"].firstMatch.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 6))
        confirm.tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["note.menu.9502"].waitForExistence(timeout: 8), "피드로 안 돌아옴")
        XCTAssertTrue(
            app.buttons["note.menu.9501"].waitForNonExistence(timeout: 6), "뮤트한 사람의 노트가 피드에 남음")
        attach(app, "muted-feed")
    }

    func testANotesRepliesOpenFromItsRow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        let replies = app.buttons["note.replies.9501"]
        XCTAssertTrue(replies.waitForExistence(timeout: 10), "답글 버튼 없음")
        replies.tap()

        let reply = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '이름이 경계라는 말'")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 8), "노트 상세에 답글이 안 보임")
        XCTAssertTrue(app.buttons["note.reply"].waitForExistence(timeout: 3), "답글 달기 버튼 없음")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "note-thread"
        shot.lifetime = .keepAlways
        add(shot)

        app.buttons["note.reply"].tap()
        let field = app.textFields["noteCompose.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "아래 답글 줄을 눌러도 답글 시트가 안 열림")
        XCTAssertTrue(app.navigationBars["답글"].exists, "답글 시트 제목이 답글이 아님")
        app.navigationBars.buttons["취소"].tap()
        XCTAssertFalse(field.waitForExistence(timeout: 2), "빈 답글 시트가 취소로 닫히지 않음")

        let replyThread = app.buttons["note.replies.9551"]
        XCTAssertTrue(replyThread.waitForExistence(timeout: 5), "답글 행에 답글 버튼이 없음")
        replyThread.tap()
        let parent = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '헥사고날 포트'")).firstMatch
        XCTAssertTrue(parent.waitForExistence(timeout: 8), "답글 상세 위에 원글이 안 보임")
        attach(app, "note-thread-parent")
    }

    func testADraftIsKeptUntilDiscardedAndPhotosOpenLarge() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        app.buttons["notes.compose"].tap()
        let field = app.textFields["noteCompose.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("버릴지 묻는 노트")
        app.navigationBars.buttons["취소"].tap()

        let discard = app.alerts.firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 4), "쓰던 노트를 취소해도 묻지 않음")
        attach(app, "note-discard-alert")
        discard.buttons["계속 쓰기"].tap()
        XCTAssertEqual(field.value as? String, "버릴지 묻는 노트", "계속 쓰기 뒤 내용이 사라짐")

        app.navigationBars.buttons["취소"].tap()
        app.alerts.firstMatch.buttons["버리기"].tap()
        XCTAssertFalse(field.waitForExistence(timeout: 2), "버리기 뒤에도 시트가 남음")

        let photo = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == '비 오는 창밖'")).firstMatch
        var tries = 0
        while !photo.isHittable, tries < 5 { app.swipeUp(); tries += 1 }
        attach(app, "notes-photo-and-quote")
        photo.tap()
        let caption = app.staticTexts["비 오는 창밖"].firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 5), "사진을 눌러도 크게 열리지 않음")
        attach(app, "note-photo-lightbox")
    }

    func testRowCarriesMenuShareAndAltLikeThreads() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        let share = app.buttons["note.share.9504"]
        var tries = 0
        while !share.isHittable, tries < 6 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(share.isHittable, "노트 행에 공유 버튼이 없음")

        let alt = app.buttons["사진 설명 보기"].firstMatch
        XCTAssertTrue(alt.waitForExistence(timeout: 5), "대체 텍스트가 있는 사진에 ALT 배지가 없음")
        alt.tap()
        XCTAssertTrue(app.staticTexts["비 오는 창밖"].firstMatch.waitForExistence(timeout: 3), "ALT 를 눌러도 설명이 안 뜸")
        attach(app, "note-row-threads")

        let menu = app.buttons["note.menu.9504"]
        tries = 0
        while !menu.isHittable, tries < 4 {
            app.swipeDown(velocity: .slow)
            tries += 1
        }
        menu.tap()
        XCTAssertTrue(app.buttons["고치기"].waitForExistence(timeout: 3), "내 노트 더보기 메뉴에 고치기가 없음")
        attach(app, "note-row-menu")
    }

    func testFloatingPlusOpensComposer() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        let fab = app.buttons["notes.fab"]
        XCTAssertTrue(fab.waitForExistence(timeout: 5), "노트 탭에 떠 있는 작성 버튼이 없음")
        attach(app, "notes-fab")
        fab.tap()
        let field = app.textFields["noteCompose.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "작성 버튼이 시트를 열지 않음")
        field.typeText("스레드처럼 가볍게 쓰는 창")
        XCTAssertTrue(app.staticTexts["누구나 볼 수 있어요"].exists, "작성 시트 아래 공개 범위 줄이 없음")
        attach(app, "note-compose-sheet")
        app.navigationBars.buttons["취소"].tap()
        app.alerts.firstMatch.buttons["버리기"].tap()
        XCTAssertTrue(fab.waitForExistence(timeout: 4), "시트를 닫은 뒤 작성 버튼이 사라짐")
    }

    func testNoteAuthorOpensTheirProfileOnTheNotesTab() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        let name = app.buttons["yuki_dev"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 8), "노트 행의 작가 이름이 링크가 아님")
        name.tap()

        let notesTab = app.buttons["author.tab.notes"]
        XCTAssertTrue(notesTab.waitForExistence(timeout: 10), "프로필에 노트 탭이 없음")
        XCTAssertTrue(notesTab.isSelected, "노트에서 들어온 프로필이 노트 탭으로 열리지 않음")
        let note = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '헥사고날 포트'")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 8), "프로필 노트 탭에 그 작가의 노트가 없음")
        attach(app, "author-notes-tab")
        XCTAssertFalse(app.buttons["notes.fab"].exists, "프로필로 들어가도 노트 작성 버튼이 남아 있음")

        app.buttons["author.tab.posts"].tap()
        XCTAssertTrue(app.buttons["author.tab.posts"].isSelected, "글 탭으로 바뀌지 않음")
        attach(app, "author-posts-tab")

        app.buttons["author.avatar"].tap()
        let close = app.buttons["author.avatar.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 4), "프로필 사진을 눌러도 크게 열리지 않음")
        attach(app, "author-avatar-viewer")
        close.tap()
        XCTAssertFalse(close.waitForExistence(timeout: 2), "닫기를 눌러도 사진 보기가 남음")
    }

    func testTappingANoteBodyOpensItsDetailWhileLinksStillOpen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        let body = app.buttons["note.body.9502"]
        XCTAssertTrue(body.waitForExistence(timeout: 10), "노트 본문이 눌리는 요소가 아님")
        body.tap()
        XCTAssertTrue(app.buttons["note.reply"].waitForExistence(timeout: 6), "본문을 눌러도 노트 상세가 안 열림")
        attach(app, "note-body-opened")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["notes.compose"].waitForExistence(timeout: 6), "상세에서 돌아오지 못함")

        let linked = app.buttons["note.body.9503"]
        var tries = 0
        while !linked.isHittable, tries < 4 { app.swipeUp(); tries += 1 }
        let link = linked.links.firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 4), "본문 안 주소가 링크로 남아 있지 않음")
        link.tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 10), "본문 안 링크를 눌러도 주소가 열리지 않음")
        app.activate()
    }

    func testALinkedNoteShowsItsCardAndTheComposerPreviewsOne() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        let card = app.descendants(matching: .any)["note.linkCard.9503"]
        var tries = 0
        while !card.exists || !card.isHittable, tries < 4 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(card.waitForExistence(timeout: 6), "주소가 든 노트에 링크 카드가 없음")
        XCTAssertTrue(card.label.contains("kurl.me"), "링크 카드에 도메인이 없음")
        attach(app, "note-link-card")

        app.buttons["notes.fab"].tap()
        let field = app.textFields["noteCompose.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("읽어 볼 글 https://example.com/essay")
        let draftCard = app.descendants(matching: .any)["noteCompose.linkCard"]
        XCTAssertTrue(draftCard.waitForExistence(timeout: 6), "작성 시트에 링크 미리보기가 안 뜸")
        attach(app, "note-compose-link-card")
        app.navigationBars.buttons["취소"].tap()
        app.alerts.firstMatch.buttons["버리기"].tap()
    }

    func testRepostMenuTogglesAndQuotePostsAboveTheFeed() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        let repost = app.buttons["note.repost.9501"]
        XCTAssertTrue(repost.waitForExistence(timeout: 10), "노트 행에 리포스트 버튼이 없음")
        XCTAssertFalse(repost.isSelected)
        repost.tap()
        let repostItem = app.buttons["리포스트"].firstMatch
        XCTAssertTrue(repostItem.waitForExistence(timeout: 3), "리포스트 메뉴에 리포스트 항목이 없음")
        XCTAssertTrue(app.buttons["인용"].firstMatch.exists, "리포스트 메뉴에 인용 항목이 없음")
        attach(app, "note-repost-menu")
        repostItem.tap()
        XCTAssertTrue(repost.waitForSelected(true, timeout: 4), "리포스트해도 버튼이 켜지지 않음")

        repost.tap()
        let undo = app.buttons["리포스트 취소"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 3), "리포스트한 노트의 메뉴에 취소가 없음")
        undo.tap()
        XCTAssertTrue(repost.waitForSelected(false, timeout: 4), "리포스트를 취소해도 버튼이 꺼지지 않음")

        repost.tap()
        app.buttons["인용"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["노트 인용"].waitForExistence(timeout: 5), "인용 작성 시트가 안 열림")
        let quoted = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '헥사고날 포트'")).firstMatch
        XCTAssertTrue(quoted.exists, "인용 작성 시트에 인용할 노트가 없음")
        let field = app.textFields["noteCompose.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("uitest quote")
        attach(app, "note-quote-sheet")
        app.buttons["noteCompose.post"].tap()
        let notice = app.alerts.firstMatch
        if notice.waitForExistence(timeout: 4) { notice.buttons["알겠어요, 올릴게요"].tap() }

        let posted = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'uitest quote'")).firstMatch
        XCTAssertTrue(posted.waitForExistence(timeout: 8), "인용 노트가 피드 맨 위에 안 꽂힘")
        XCTAssertFalse(app.navigationBars["노트 인용"].exists, "올린 뒤 인용 시트가 닫히지 않음")
        attach(app, "note-quote-posted")
    }

    func testAuthorRepostsTabShowsWhatTheyReposted() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        let name = app.buttons["yuki_dev"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        name.tap()
        let tab = app.buttons["author.tab.reposts"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "프로필에 리포스트 탭이 없음")
        tab.tap()
        XCTAssertTrue(tab.isSelected, "리포스트 탭으로 바뀌지 않음")

        let line = app.staticTexts["yuki_dev님이 리포스트함"].firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 8), "리포스트한 노트 위에 리포스트함 줄이 없음")
        let reposted = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '우리 팀은 일주일'")).firstMatch
        XCTAssertTrue(reposted.exists, "리포스트 탭에 리포스트한 노트가 없음")
        XCTAssertTrue(app.buttons["note.quoted.9501"].exists, "인용 노트 카드가 링크가 아님")
        attach(app, "author-reposts-tab")
    }

    func testCollectionNoteBlockOpensTheNote() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--screen", "collection-detail", "--collection", "101"]
        app.launch()

        let block = app.buttons
            .matching(NSPredicate(format: "label CONTAINS '더 나은 질문을 기다리는 일'")).firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: 12), "컬렉션의 노트 블록이 링크가 아님")
        XCTAssertTrue(block.label.contains("yuki_dev"), "노트 블록에 작성자가 없음")
        attach(app, "collection-note-block")
        block.tap()
        XCTAssertTrue(app.buttons["note.reply"].waitForExistence(timeout: 8), "노트 블록을 눌러도 노트가 열리지 않음")
    }

    func testFederationCanBeTurnedOffInSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "account"]
        app.launch()

        let settings = app.buttons["설정"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()

        let toggle = app.switches["settings.federation"].firstMatch
        let screenHeight = app.windows.firstMatch.frame.height
        var tries = 0
        while (!toggle.exists || toggle.frame.maxY > screenHeight * 0.7), tries < 6 {
            app.swipeUp()
            tries += 1
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "설정에 노트 연합 토글이 없음")
        XCTAssertEqual(toggle.value as? String, "1")
        attach(app, "settings-federation")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertTrue(toggle.waitForValue("0", timeout: 4), "토글이 꺼지지 않음")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testFollowingFeedRendersCards() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--feed", "following"]
        app.launch()

        // 구독함도 최신·인기와 같은 발견 카드 — 알림 같던 인박스 행을 걷어냈다. 목 팔로잉 피드의 글 제목이 선다.
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '발행된 목 글'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "구독함 카드가 렌더되지 않음")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "following-cards"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testVotingInAPollRevealsTheResults() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        let option = app.buttons["note.poll.option.9509.0"]
        XCTAssertTrue(option.waitForExistence(timeout: 10), "투표 선택지가 안 그려짐")
        XCTAssertFalse(app.descendants(matching: .any)["note.poll.result.9509.0"].exists, "투표 전에 결과가 보임")
        option.tap()

        let result = app.descendants(matching: .any)["note.poll.result.9509.0"]
        XCTAssertTrue(result.waitForExistence(timeout: 6), "투표 뒤 결과가 안 보임")
        XCTAssertTrue(result.label.contains("60%"), "내 표가 반영된 비율이 아님: \(result.label)")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS '10명 참여'")).firstMatch.exists,
            "참여 수가 늘지 않음")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "note-poll-voted"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testAPollIsWrittenInTheComposer() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        app.buttons["notes.compose"].tap()
        let field = app.textFields["noteCompose.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "작성 시트의 입력란 없음")
        field.typeText("uitest poll")
        app.buttons["noteCompose.pollToggle"].tap()

        let first = app.textFields["noteCompose.poll.option.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5), "투표 편집기가 안 열림")
        XCTAssertFalse(app.buttons["noteCompose.post"].isEnabled, "선택지가 비었는데 올리기가 켜짐")
        first.tap()
        first.typeText("cats")
        let second = app.textFields["noteCompose.poll.option.1"]
        second.tap()
        second.typeText("dogs")
        app.buttons["noteCompose.poll.add"].tap()
        XCTAssertTrue(app.textFields["noteCompose.poll.option.2"].waitForExistence(timeout: 3), "선택지가 안 늘어남")
        app.textFields["noteCompose.poll.option.2"].typeText("birds")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "note-poll-composer"
        shot.lifetime = .keepAlways
        add(shot)

        app.buttons["noteCompose.post"].tap()
        let notice = app.alerts.firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 6), "첫 노트 연합 안내가 뜨지 않음")
        notice.buttons["알겠어요, 올릴게요"].tap()

        let posted = app.descendants(matching: .any)["note.poll.result.9600.2"]
        XCTAssertTrue(posted.waitForExistence(timeout: 8), "올린 투표가 피드에 안 보임")
        XCTAssertTrue(posted.label.contains("birds"))
    }
}

private extension XCUIElement {
    func waitForSelected(_ selected: Bool, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == %@", NSNumber(value: selected)), object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    func waitForValue(_ value: String, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value), object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
