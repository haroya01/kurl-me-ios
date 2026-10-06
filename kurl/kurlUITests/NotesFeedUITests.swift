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

        let seeded = app.staticTexts
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

        let published = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS 'uitest note round trip'")).firstMatch
        XCTAssertTrue(published.waitForExistence(timeout: 8), "발행한 노트가 맨 위에 안 꽂힘")
        XCTAssertFalse(app.textFields["noteCompose.text"].exists, "올린 뒤 시트가 닫히지 않음")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "notes-tab"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testANotesRepliesOpenFromItsRow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        let replies = app.buttons["note.replies.9501"]
        XCTAssertTrue(replies.waitForExistence(timeout: 10), "답글 버튼 없음")
        replies.tap()

        let reply = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS '이름이 경계라는 말'")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 8), "노트 상세에 답글이 안 보임")
        XCTAssertTrue(app.buttons["note.reply"].waitForExistence(timeout: 3), "답글 달기 버튼 없음")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "note-thread"
        shot.lifetime = .keepAlways
        add(shot)

        let replyThread = app.buttons["note.replies.9551"]
        XCTAssertTrue(replyThread.waitForExistence(timeout: 5), "답글 행에 답글 버튼이 없음")
        replyThread.tap()
        let parent = app.staticTexts
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

        app.buttons["note.menu.9504"].tap()
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
        let note = app.staticTexts
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
        let quoted = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS '헥사고날 포트'")).firstMatch
        XCTAssertTrue(quoted.exists, "인용 작성 시트에 인용할 노트가 없음")
        let field = app.textFields["noteCompose.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("uitest quote")
        attach(app, "note-quote-sheet")
        app.buttons["noteCompose.post"].tap()
        let notice = app.alerts.firstMatch
        if notice.waitForExistence(timeout: 4) { notice.buttons["알겠어요, 올릴게요"].tap() }

        let posted = app.staticTexts
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
        let reposted = app.staticTexts
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
        let row = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS '발행된 목 글'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "구독함 카드가 렌더되지 않음")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "following-cards"
        shot.lifetime = .keepAlways
        add(shot)
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
