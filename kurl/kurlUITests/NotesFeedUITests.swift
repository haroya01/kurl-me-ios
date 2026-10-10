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
        XCTAssertTrue(app.buttons["notes.more"].waitForExistence(timeout: 12), "노트 탭이 열리지 않음")
    }

    private func composeTab(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["글쓰기"]
    }

    private func pickFeed(_ app: XCUIApplication, _ label: String) {
        let segment = app.buttons[label].firstMatch
        XCTAssertTrue(segment.waitForExistence(timeout: 8), "노트 머리 스위처에 \(label)이 없음")
        segment.tap()
        XCTAssertTrue(segment.isSelected, "\(label)로 바뀌지 않음")
    }

    private func openMore(_ app: XCUIApplication, _ label: String) {
        let more = app.buttons["notes.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 8), "노트 머리에 더 보기 메뉴가 없음")
        more.tap()
        let item = app.buttons[label].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 4), "더 보기 메뉴에 \(label)이 없음")
        item.tap()
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

        let compose = composeTab(app)
        XCTAssertTrue(compose.waitForExistence(timeout: 5), "탭바 가운데 글쓰기가 없음")
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

    /// 스레드처럼 여러 노트를 이어 써 한 번에 올린다 — 첫 노트가 피드에, 이어 쓴 노트는 그 답글로 상세에.
    func testATwoNoteThreadPostsAtOnceAndReadsAsAReplyChain() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)
        composeTab(app).tap()

        let field = app.textFields["noteCompose.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "작성 시트의 입력란 없음")
        field.typeText("이어 쓰기 첫 노트")
        let add = app.buttons["noteCompose.addPart"]
        XCTAssertTrue(add.exists, "스레드에 추가 줄이 없음")
        add.tap()
        let part = app.textFields["noteCompose.part"].firstMatch
        XCTAssertTrue(part.waitForExistence(timeout: 3), "이어 쓰는 칸이 안 생김")
        part.typeText("이어 쓰기 둘째 노트")
        XCTAssertFalse(app.buttons["noteCompose.schedule"].exists, "이어 쓰는 중에 예약이 보임")
        app.buttons["noteCompose.post"].tap()
        let notice = app.alerts.firstMatch
        if notice.waitForExistence(timeout: 4) { notice.buttons["알겠어요, 올릴게요"].tap() }

        let first = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '이어 쓰기 첫 노트'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 8), "첫 노트가 피드 맨 위에 안 꽂힘")
        XCTAssertFalse(field.exists, "올린 뒤 시트가 닫히지 않음")
        first.tap()
        let second = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '이어 쓰기 둘째 노트'")).firstMatch
        XCTAssertTrue(second.waitForExistence(timeout: 8), "이어 쓴 노트가 첫 노트의 답글로 안 보임")
        attach(app, "thread-posted")
    }

    func testTheNotesFeedSwitchesLikeTheBlogFeedByTapOrSwipe() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)
        XCTAssertTrue(app.buttons["note.menu.9503"].waitForExistence(timeout: 10), "최신에 reader_kim 노트가 없음")
        XCTAssertTrue(app.buttons["최신"].isSelected, "노트 탭이 최신으로 열리지 않음")
        XCTAssertTrue(app.buttons["알림"].exists, "노트 머리에 알림 벨이 없음")
        attach(app, "notes-header")

        pickFeed(app, "인기")
        let top = app.buttons["note.menu.9502"]
        let newest = app.buttons["note.menu.9501"]
        XCTAssertTrue(top.waitForExistence(timeout: 8) && newest.waitForExistence(timeout: 2), "인기 피드가 안 그려짐")
        XCTAssertLessThan(top.frame.minY, newest.frame.minY, "좋아요 11개 노트가 최신 노트보다 위에 있지 않음")

        app.swipeLeft()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label == '팔로잉' AND selected == true")).firstMatch
                .waitForExistence(timeout: 5),
            "왼쪽으로 밀어도 팔로잉으로 안 넘어감")
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

    private func menuOption(_ app: XCUIApplication, _ label: String) -> XCUIElement? {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex
            .first { $0.frame.minY > 200 }
    }

    func testSlowlyScrollingPastAPhotoNoteKeepsTheAppResponsive() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)
        XCTAssertTrue(app.buttons["note.menu.9501"].waitForExistence(timeout: 10), "노트가 안 뜸")
        let start = Date()
        for _ in 0..<3 { app.swipeUp(velocity: .slow) }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 40, "사진 노트를 지나는 느린 스크롤에서 앱이 \(Int(elapsed))초 동안 응답하지 않음")
    }

    func testSwipingAPhotoCarouselLeavesTheFeedPageWhereItIs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)
        XCTAssertTrue(app.buttons["note.menu.9501"].waitForExistence(timeout: 10), "노트가 안 뜸")

        let photo = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == '비 오는 창밖'")).firstMatch
        var tries = 0
        while !(photo.exists && photo.isHittable), tries < 6 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(photo.isHittable, "사진 여러 장 노트가 안 보임")
        photo.swipeLeft()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label == '최신' AND selected == true")).firstMatch
                .waitForExistence(timeout: 3),
            "사진 넘기기가 피드 페이지까지 넘김")
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label == '인기' AND selected == true")).firstMatch.exists,
            "사진 넘기기가 인기로 넘어감")
    }

    /// 서버가 사진 크기를 주면 타일이 처음부터 원래 비율로 그려진다 — 세로 사진은 가로 사진보다 좁다.
    func testPhotosKeepTheirOwnShapeWhenTheServerKnowsTheirSize() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)
        XCTAssertTrue(app.buttons["note.menu.9501"].waitForExistence(timeout: 10), "노트가 안 뜸")

        let wide = app.descendants(matching: .any).matching(NSPredicate(format: "label == '비 오는 창밖'")).firstMatch
        let tall = app.descendants(matching: .any).matching(NSPredicate(format: "label == '젖은 골목'")).firstMatch
        var tries = 0
        while !(wide.exists && wide.isHittable), tries < 6 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(tall.waitForExistence(timeout: 3), "두 번째 사진이 없음")
        XCTAssertEqual(wide.frame.height, tall.frame.height, accuracy: 1, "넘기기 사진들의 높이가 다름")
        XCTAssertEqual(wide.frame.width / wide.frame.height, 900.0 / 700.0, accuracy: 0.03, "가로 사진이 원래 비율이 아님")
        XCTAssertEqual(tall.frame.width / tall.frame.height, 600.0 / 800.0, accuracy: 0.03, "세로 사진이 원래 비율이 아님")
    }

    func testTappingTheNotesTabAgainPopsToTheFeedAndHoldingItOpensTheFeedMenu() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)
        openMore(app, "다른 서버")
        XCTAssertTrue(app.navigationBars["다른 서버"].waitForExistence(timeout: 6), "다른 서버 화면이 안 열림")

        app.buttons["노트"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["다른 서버"].waitForNonExistence(timeout: 5), "탭을 다시 눌러도 피드로 안 돌아감")

        let menu = app.buttons["tab.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "피드에서 노트 탭이 메뉴가 아님")
        menu.press(forDuration: 1.0)
        Thread.sleep(forTimeInterval: 0.6)
        let trending = menuOption(app, "인기")
        XCTAssertNotNil(trending, "탭 위로 피드 메뉴가 열리지 않음")
        attach(app, "notes-tab-menu")
        trending?.tap()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label == '인기' AND selected == true")).firstMatch
                .waitForExistence(timeout: 5),
            "탭 메뉴로 고른 인기가 머리 스위처에 반영되지 않음")
    }

    func testHoldingTheBlogTabOpensItsFeedMenuToo() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks"]
        app.launch()
        let menu = app.buttons["tab.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 12), "피드 탭이 메뉴가 아님")
        XCTAssertTrue(app.buttons["알림"].exists, "블로그 머리에 알림 벨이 없음")
        menu.press(forDuration: 1.0)
        Thread.sleep(forTimeInterval: 0.6)
        let following = menuOption(app, "구독함")
        XCTAssertNotNil(following, "피드 탭 위로 피드 메뉴가 열리지 않음")
        attach(app, "blog-tab-menu")
        following?.tap()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label == '구독함' AND selected == true")).firstMatch
                .waitForExistence(timeout: 5),
            "탭 메뉴로 고른 구독함이 머리 스위처에 반영되지 않음")
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
        XCTAssertTrue(app.navigationBars["인용"].waitForExistence(timeout: 6), "인용 목록이 안 열림")
        XCTAssertTrue(app.buttons["note.menu.9505"].waitForExistence(timeout: 6), "인용한 노트가 목록에 없음")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        openMore(app, "북마크한 노트")
        XCTAssertTrue(app.navigationBars["북마크한 노트"].waitForExistence(timeout: 6), "북마크 화면이 안 열림")
        XCTAssertTrue(app.buttons["note.menu.9501"].waitForExistence(timeout: 8), "북마크한 노트가 북마크 피드에 없음")
    }

    func testANoteCarriedInABlogPostListsThatPostAndThePostShowsTheNoteAsACard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        let replies = app.buttons["note.replies.9501"]
        XCTAssertTrue(replies.waitForExistence(timeout: 10), "답글 버튼 없음")
        replies.tap()
        let quotes = app.buttons["note.quotes.9501"]
        XCTAssertTrue(quotes.waitForExistence(timeout: 6), "인용 줄이 없음")
        quotes.tap()

        let post = app.buttons["quotingPost.9201"]
        XCTAssertTrue(post.waitForExistence(timeout: 6), "노트를 실은 글이 인용 목록에 없음")
        XCTAssertTrue(app.buttons["note.menu.9505"].waitForExistence(timeout: 4), "인용한 노트가 글 아래에 없음")
        attach(app, "note-quotes-carrying-post")
        post.tap()

        let card = app.buttons["post.noteEmbed.9501"]
        var tries = 0
        while !card.exists, tries < 4 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(card.waitForExistence(timeout: 10), "글 본문에 노트 카드가 없음")
        attach(app, "post-carries-note")
        card.tap()
        XCTAssertTrue(app.buttons["note.replies.9501"].waitForExistence(timeout: 8), "노트 카드가 그 노트를 열지 않음")
    }

    func testTheShareMenuStartsABlogPostThatCarriesTheNote() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        let share = app.buttons["note.share.9501"]
        XCTAssertTrue(share.waitForExistence(timeout: 10), "공유 버튼 없음")
        share.tap()
        XCTAssertTrue(app.buttons["링크 복사"].waitForExistence(timeout: 4), "공유 메뉴에 링크 복사가 없음")
        let quote = app.buttons["블로그 글로 인용"]
        XCTAssertTrue(quote.exists, "공유 메뉴에 블로그 글로 인용이 없음")
        attach(app, "note-share-menu")
        quote.tap()

        XCTAssertTrue(app.navigationBars["새 글"].waitForExistence(timeout: 8), "블로그 글 작성기가 안 열림")
        let carried = app.descendants(matching: .any)["editor-link-card"]
        XCTAssertTrue(carried.waitForExistence(timeout: 8), "새 글 첫 줄에 카드가 없음")
        let card = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS '헥사고날 포트'"), object: carried)
        XCTAssertEqual(XCTWaiter().wait(for: [card], timeout: 8), .completed, "새 글 첫 줄의 카드가 노트 카드가 아님")
        attach(app, "quote-post-composer")
        app.navigationBars["새 글"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(share.waitForExistence(timeout: 6), "작성기를 닫아도 노트로 돌아오지 않음")
        attach(app, "quote-post-closed")
    }

    func testTheFeedOfOtherServersShowsNotesThisServerReceived() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        openMore(app, "다른 서버")
        XCTAssertTrue(app.navigationBars["다른 서버"].waitForExistence(timeout: 6), "다른 서버 화면이 안 열림")
        XCTAssertTrue(app.buttons["note.menu.9600"].waitForExistence(timeout: 8), "다른 서버 피드에 받은 노트가 없음")
        XCTAssertFalse(app.buttons["note.menu.9501"].exists, "다른 서버 피드에 이 서버 노트가 섞임")
        attach(app, "notes-federated")
    }

    func testRepostsHideForTheWholeFollowingFeedAndForOnePerson() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        pickFeed(app, "팔로잉")
        let header = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'yuki_dev님이 리포스트함'")).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 8), "팔로잉에 리포스트가 없음")

        let menu = app.buttons["notes.more"]
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

        let tag = app.links.matching(NSPredicate(format: "label CONTAINS %@", "아키텍처")).firstMatch
        XCTAssertTrue(tag.waitForExistence(timeout: 10), "노트 본문의 해시태그가 링크가 아님")
        tag.tap()

        let notesTab = app.buttons["tag.tab.notes"]
        XCTAssertTrue(notesTab.waitForExistence(timeout: 8), "태그 화면이 안 열림")
        XCTAssertTrue(notesTab.isSelected, "노트에서 연 태그가 노트 탭으로 열리지 않음")
        XCTAssertTrue(app.buttons["note.menu.9501"].waitForExistence(timeout: 8), "태그의 노트가 안 보임")
        attach(app, "tag-notes")

        let postsTab = app.buttons["tag.tab.posts"]
        postsTab.tap()
        XCTAssertTrue(postsTab.isSelected, "글 탭으로 바뀌지 않음")
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

        let compose = composeTab(app)
        XCTAssertTrue(compose.waitForExistence(timeout: 8))
        compose.tap()
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

        openMore(app, "개인 멘션")
        XCTAssertTrue(app.navigationBars["개인 멘션"].waitForExistence(timeout: 6), "개인 멘션 피드로 안 바뀜")
        let dm = app.descendants(matching: .any)["note.visibility.9508"].firstMatch
        XCTAssertTrue(dm.waitForExistence(timeout: 8), "개인 멘션 노트에 범위 표시가 없음")
        XCTAssertEqual(app.descendants(matching: .any)["note.repost.9508"].firstMatch.label, "리포스트할 수 없는 노트",
                       "멘션한 사람만 보는 노트를 리포스트할 수 있음")
        attach(app, "notes-direct-feed")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        composeTab(app).tap()
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
        openMore(app, "동료")
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

    func testAKeywordFilterFoldsMatchingNotesUntilOpened() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "account"]
        app.launch()

        let settings = app.buttons["설정"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        let entry = app.buttons["settings.filters"].firstMatch
        var tries = 0
        while !entry.isHittable, tries < 8 {
            app.swipeUp()
            tries += 1
        }
        entry.tap()
        app.buttons["noteFilter.add"].firstMatch.tap()
        let phrase = app.textFields["noteFilter.phrase"]
        XCTAssertTrue(phrase.waitForExistence(timeout: 6), "필터 편집기가 안 열림")
        phrase.tap()
        phrase.typeText("hexagonal")
        attach(app, "note-filter-editor")
        app.buttons["noteFilter.save"].tap()
        XCTAssertTrue(app.buttons["noteFilter.row.800"].waitForExistence(timeout: 6), "필터가 목록에 안 생김")

        let notesTab = app.buttons["노트"].firstMatch
        var backs = 0
        while !notesTab.isHittable, backs < 4 {
            app.navigationBars.buttons.element(boundBy: 0).tap()
            backs += 1
        }
        notesTab.tap()
        let folded = app.descendants(matching: .any)["note.filtered.9510"]
        XCTAssertTrue(folded.waitForExistence(timeout: 10), "걸린 노트가 접히지 않음")
        XCTAssertFalse(app.buttons["note.menu.9510"].exists, "접힌 노트의 본문이 보임")
        attach(app, "note-filter-folded")
        app.buttons["note.filtered.reveal.9510"].tap()
        XCTAssertTrue(app.buttons["note.menu.9510"].waitForExistence(timeout: 4), "보기를 눌러도 안 펼쳐짐")
    }

    func testSearchShowsTrendingHashtagsThatOpenTheirNotes() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "search"]
        app.launch()

        let trend = app.buttons["search.trendingTag.산책"]
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<4 where !(trend.exists && trend.isHittable) {
            scroll.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(trend.waitForExistence(timeout: 12), "검색 대기 화면에 뜨는 해시태그가 없음")
        XCTAssertTrue(trend.label.contains("3명이 이번 주에 썼어요"), "쓴 사람 수가 안 보임: \(trend.label)")
        attach(app, "search-trending-tags")
        trend.tap()
        let notesTab = app.buttons["tag.tab.notes"]
        XCTAssertTrue(notesTab.waitForExistence(timeout: 8), "태그 화면이 안 열림")
        XCTAssertTrue(notesTab.isSelected, "뜨는 해시태그가 노트 탭으로 열리지 않음")
    }

    func testSearchShowsTrendingLinksThatOpenTheNotesCarryingThem() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "search"]
        app.launch()

        let link = app.buttons["search.trendingLink.example.com"]
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<5 where !(link.exists && link.isHittable) {
            scroll.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(link.waitForExistence(timeout: 12), "검색 대기 화면에 뜨는 링크가 없음")
        XCTAssertTrue(link.label.contains("3명이 이번 주에 공유했어요"), "공유한 사람 수가 안 보임: \(link.label)")
        attach(app, "search-trending-links")
        link.tap()

        let header = app.buttons["linkNotes.open"]
        XCTAssertTrue(header.waitForExistence(timeout: 8), "링크 노트 화면이 안 열림")
        XCTAssertTrue(header.label.contains("느린 웹을 위한 변론"), "링크 제목이 머리에 없음: \(header.label)")
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'note.menu.'")).firstMatch
                .waitForExistence(timeout: 8),
            "링크를 실은 노트가 없음")
        attach(app, "link-notes")
    }

    func testSearchFindsNotesInTheNotesScope() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "search"]
        app.launch()

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 12))
        field.tap()
        field.typeText("Hexagonal")
        let notesScope = app.segmentedControls.buttons["노트"].firstMatch
        XCTAssertTrue(notesScope.waitForExistence(timeout: 6), "검색 범위에 노트가 없음")
        notesScope.tap()
        XCTAssertTrue(app.buttons["note.menu.9510"].waitForExistence(timeout: 8), "노트 검색 결과가 안 보임")
        XCTAssertFalse(app.buttons["note.menu.9501"].exists, "검색어가 없는 노트가 결과에 있음")
        attach(app, "search-notes")
    }

    func testAHandleInSearchFindsAnAccountOnAnotherServerToFollow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "search"]
        app.launch()

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 12))
        field.tap()
        field.typeText("@alice@mastodon.social")
        let follow = app.buttons["remote.follow.alice@mastodon.social"]
        XCTAssertTrue(follow.waitForExistence(timeout: 8), "원격 계정 행이 안 뜸")
        follow.tap()
        let requested = NSPredicate(format: "label CONTAINS '요청됨'")
        expectation(for: requested, evaluatedWith: follow)
        waitForExpectations(timeout: 6)
        attach(app, "remote-search-requested")

        app.buttons["remote.row.alice@mastodon.social"].tap()
        let accepted = app.staticTexts["mastodon.social에 있는 계정이에요. 이 계정의 새 노트가 팔로잉 피드에 와요."]
        XCTAssertTrue(accepted.waitForExistence(timeout: 8), "계정 화면이 안 열리거나 수락이 반영되지 않음")
        XCTAssertTrue(app.navigationBars["@alice@mastodon.social"].exists, "계정 화면 제목이 핸들이 아님")
        attach(app, "remote-account")
    }

    func testANoteFromAnotherServerOpensItsAccountWithItsNotes() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)
        pickFeed(app, "팔로잉")

        let remote = app.buttons["note.menu.9600"]
        for _ in 0..<6 where !remote.exists {
            app.swipeUp()
        }
        XCTAssertTrue(remote.waitForExistence(timeout: 6), "팔로잉에 다른 서버 노트가 없음")
        let author = app.buttons.matching(NSPredicate(format: "label CONTAINS '@mina@mastodon.social'")).firstMatch
        XCTAssertTrue(author.exists, "다른 서버 노트 머리에 @아이디@서버가 없음")
        attach(app, "remote-note-row")
        author.tap()

        XCTAssertTrue(app.navigationBars["@mina@mastodon.social"].waitForExistence(timeout: 8), "원격 계정 화면이 안 열림")
        XCTAssertTrue(app.buttons["note.menu.9600"].waitForExistence(timeout: 8), "계정 화면에 받은 노트가 없음")
        let video = app.buttons["note.video"].firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 6), "동영상 첨부가 재생 타일로 안 그려짐")
        XCTAssertEqual(video.value as? String, "소리 없이 재생 중", "화면에 보이는 동영상이 소리 없이 자동 재생되지 않음")
        XCTAssertTrue(app.buttons["note.audio"].firstMatch.exists, "오디오 첨부가 재생 행으로 안 그려짐")
        attach(app, "remote-account-notes")
        video.tap()
        XCTAssertTrue(app.buttons["닫기"].waitForExistence(timeout: 6), "동영상 전체 화면이 안 열림")
        app.buttons["닫기"].tap()
    }

    func testBlockingAServerHidesItsAccountUntilUnblocked() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)
        pickFeed(app, "팔로잉")
        let remote = app.buttons["note.menu.9600"]
        for _ in 0..<6 where !remote.exists {
            app.swipeUp()
        }
        let author = app.buttons.matching(NSPredicate(format: "label CONTAINS '@mina@mastodon.social'")).firstMatch
        XCTAssertTrue(author.waitForExistence(timeout: 6), "팔로잉에 다른 서버 노트가 없음")
        author.tap()

        let more = app.buttons["remote.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 8), "원격 계정 화면에 ⋯ 메뉴가 없음")
        more.tap()
        app.buttons["mastodon.social 차단"].tap()
        let confirm = app.alerts.buttons["서버 차단"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "서버 차단을 되묻지 않음")
        confirm.tap()
        XCTAssertTrue(app.staticTexts["차단한 서버예요"].waitForExistence(timeout: 6), "차단한 서버 안내가 없음")
        XCTAssertFalse(app.buttons["note.menu.9600"].exists, "차단한 서버의 노트가 계정 화면에 남음")
        XCTAssertFalse(app.buttons["remote.follow.mina@mastodon.social"].exists, "차단한 서버 계정에 팔로우 버튼이 남음")
        attach(app, "remote-domain-blocked")

        app.buttons["remote.domain.unblock"].tap()
        XCTAssertTrue(app.buttons["note.menu.9600"].waitForExistence(timeout: 8), "차단 해제 뒤 노트가 돌아오지 않음")
    }

    func testANoteScheduledFromTheComposerWaitsInScheduledNotesUntilCanceled() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)
        let compose = composeTab(app)
        XCTAssertTrue(compose.waitForExistence(timeout: 10), "탭바 가운데 글쓰기가 없음")
        compose.tap()
        let field = app.textFields["noteCompose.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("uitest scheduled note")

        let language = app.buttons["noteCompose.language"]
        XCTAssertTrue(language.exists, "작성기에 언어 고르기가 없음")
        language.tap()
        app.buttons["English"].tap()
        XCTAssertEqual(language.value as? String, "English", "고른 언어가 작성기에 반영되지 않음")

        app.buttons["noteCompose.schedule"].tap()
        let done = app.buttons["noteSchedule.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "예약 시각 시트가 안 열림")
        done.tap()
        let post = app.buttons["noteCompose.post"]
        XCTAssertTrue(post.label.contains("예약"), "예약을 고른 뒤 올리기 버튼이 예약으로 바뀌지 않음")
        attach(app, "compose-scheduled")
        post.tap()
        let notice = app.alerts.firstMatch
        if notice.waitForExistence(timeout: 3) {
            notice.buttons["알겠어요, 올릴게요"].tap()
        }
        XCTAssertTrue(field.waitForNonExistence(timeout: 8), "예약한 뒤 작성 시트가 닫히지 않음")

        openMore(app, "예약한 노트")
        let mine = app.buttons.matching(NSPredicate(format: "label CONTAINS 'uitest scheduled note'")).firstMatch
        XCTAssertTrue(mine.waitForExistence(timeout: 8), "예약한 노트 목록에 방금 예약한 노트가 없음")
        XCTAssertTrue(
            app.staticTexts["답글을 달 노트가 지워졌어요"].exists, "올리지 못한 예약에 이유가 보이지 않음")
        attach(app, "scheduled-notes")
        mine.swipeLeft()
        let cancel = app.buttons["취소"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 4), "밀어서 나오는 취소가 없음")
        cancel.tap()
        XCTAssertTrue(mine.waitForNonExistence(timeout: 6), "취소한 예약이 목록에 남음")
    }

    func testMutingAConversationFromTheNoteMenuFlipsItsLabel() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        let menu = app.buttons["note.menu.9501"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        let mute = app.buttons["대화 알림 끄기"]
        XCTAssertTrue(mute.waitForExistence(timeout: 5), "노트 메뉴에 대화 알림 끄기가 없음")
        attach(app, "note-menu-conversation-mute")
        mute.tap()
        let toast = app.staticTexts["이 대화의 알림을 껐어요"]
        var appeared = false
        for _ in 0..<30 where !appeared {
            appeared = toast.exists
            if !appeared { Thread.sleep(forTimeInterval: 0.1) }
        }
        XCTAssertTrue(appeared, "끈 뒤 알림이 없음")

        menu.tap()
        XCTAssertTrue(app.buttons["대화 알림 켜기"].waitForExistence(timeout: 5), "끈 뒤 메뉴가 켜기로 바뀌지 않음")
    }

    func testSomeoneElsesNoteCanBeReportedFromItsMenu() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        let menu = app.buttons["note.menu.9501"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        let report = app.buttons["신고"]
        XCTAssertTrue(report.waitForExistence(timeout: 5), "남의 노트 메뉴에 신고가 없음")
        report.tap()
        XCTAssertTrue(app.staticTexts["신고 사유를 선택하세요"].waitForExistence(timeout: 5), "신고 사유 시트가 안 열림")
        XCTAssertFalse(app.switches["report.forward"].exists, "우리 회원 노트 신고에 다른 서버 전달이 보임")
        attach(app, "note-report-sheet")
    }

    func testANoteFromAnotherServerCanBeReportedThereToo() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)
        pickFeed(app, "팔로잉")
        let remote = app.buttons["note.menu.9600"]
        for _ in 0..<6 where !remote.exists {
            app.swipeUp()
        }
        XCTAssertTrue(remote.waitForExistence(timeout: 6), "팔로잉에 다른 서버 노트가 없음")
        remote.tap()
        app.buttons["신고"].tap()
        let forward = app.switches["report.forward"]
        XCTAssertTrue(forward.waitForExistence(timeout: 5), "다른 서버 노트 신고에 그 서버로 전달하기가 없음")
        XCTAssertEqual(forward.value as? String, "0", "그 서버 전달이 기본으로 켜져 있음")
        XCTAssertTrue(app.staticTexts["mastodon.social에도 전달"].exists)
        forward.switches.firstMatch.tap()
        XCTAssertEqual(forward.value as? String, "1")
        attach(app, "remote-note-report-sheet")
        app.buttons["스팸·광고"].tap()
        XCTAssertTrue(
            app.staticTexts["신고가 접수되었습니다"].waitForExistence(timeout: 5), "전달을 켠 신고가 접수되지 않음")
    }

    func testADisplayNameLeadsTheRowWithTheHandleBesideIt() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        XCTAssertTrue(app.buttons["note.menu.9503"].waitForExistence(timeout: 10))
        let name = app.buttons.matching(NSPredicate(format: "label CONTAINS '김독자'")).firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 6), "표시 이름이 행에 없음")
        XCTAssertTrue(name.label.contains("@reader_kim"), "표시 이름 옆에 @아이디가 없음: \(name.label)")
        attach(app, "display-name-row")
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

        composeTab(app).tap()
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
        XCTAssertTrue(app.buttons["note.menu.9501"].waitForExistence(timeout: 10), "노트가 안 뜸")

        let share = app.buttons["note.share.9504"]
        var tries = 0
        while !share.isHittable, tries < 6 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(share.isHittable, "노트 행에 공유 버튼이 없음")

        XCTAssertTrue(
            app.buttons["사진 설명 보기"].firstMatch.waitForExistence(timeout: 5), "대체 텍스트가 있는 사진에 ALT 배지가 없음")
        let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        func onScreenAlt() -> XCUIElement? {
            app.buttons.matching(NSPredicate(format: "label == '사진 설명 보기'")).allElementsBoundByIndex.first {
                $0.frame.minX >= 0 && $0.frame.maxX <= app.frame.width
                    && $0.frame.minY > 160 && $0.frame.maxY < app.frame.height - 160
            }
        }
        for _ in 0..<6 where onScreenAlt() == nil {
            center.press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62)))
        }
        let alt = try XCTUnwrap(onScreenAlt(), "화면 안에 ALT 배지가 없음")
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

    func testTheCenterTabOpensTheComposerOverTheNotesFeed() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        let compose = composeTab(app)
        XCTAssertTrue(compose.waitForExistence(timeout: 5), "탭바 가운데 글쓰기가 없음")
        attach(app, "notes-tab")
        compose.tap()
        let field = app.textFields["noteCompose.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "가운데 탭이 작성 시트를 열지 않음")
        field.typeText("스레드처럼 가볍게 쓰는 창")
        XCTAssertTrue(app.staticTexts["누구나 볼 수 있어요"].exists, "작성 시트 아래 공개 범위 줄이 없음")
        attach(app, "note-compose-sheet")
        app.navigationBars.buttons["취소"].tap()
        app.alerts.firstMatch.buttons["버리기"].tap()
        XCTAssertTrue(app.buttons["notes.more"].waitForExistence(timeout: 4), "시트를 닫은 뒤 노트 탭으로 돌아오지 않음")
    }

    func testProfileAndTagTabsSwitchBySwipeToo() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        let name = app.buttons["yuki_dev"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        name.tap()
        let notesTab = app.buttons["author.tab.notes"]
        XCTAssertTrue(notesTab.waitForExistence(timeout: 10), "프로필에 노트 탭이 없음")
        XCTAssertTrue(notesTab.isSelected)
        app.swipeRight()
        let postsTab = app.buttons["author.tab.posts"]
        expectation(for: NSPredicate(format: "selected == true"), evaluatedWith: postsTab)
        waitForExpectations(timeout: 5)
        attach(app, "author-swiped-to-posts")
        app.swipeLeft()
        expectation(for: NSPredicate(format: "selected == true"), evaluatedWith: notesTab)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(notesTab.exists, "가로로 밀었는데 글 행이 눌려 글이 열림")

        let followers = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '팔로워'")).firstMatch
        XCTAssertTrue(followers.waitForExistence(timeout: 5), "프로필에 팔로워 링크가 없음")
        followers.tap()
        let followersTab = app.buttons["follow.tab.followers"]
        XCTAssertTrue(followersTab.waitForExistence(timeout: 8), "팔로워 목록이 밑줄 탭으로 안 열림")
        XCTAssertTrue(followersTab.isSelected)
        app.swipeLeft()
        expectation(for: NSPredicate(format: "selected == true"), evaluatedWith: app.buttons["follow.tab.following"])
        waitForExpectations(timeout: 5)
        attach(app, "follow-lists-swiped")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let tag = app.links.matching(NSPredicate(format: "label CONTAINS %@", "아키텍처")).firstMatch
        XCTAssertTrue(tag.waitForExistence(timeout: 10))
        tag.tap()
        let tagNotes = app.buttons["tag.tab.notes"]
        XCTAssertTrue(tagNotes.waitForExistence(timeout: 8), "태그 화면이 안 열림")
        app.swipeRight()
        expectation(for: NSPredicate(format: "selected == true"), evaluatedWith: app.buttons["tag.tab.posts"])
        waitForExpectations(timeout: 5)
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
        XCTAssertTrue(app.buttons["notes.more"].waitForExistence(timeout: 6), "상세에서 돌아오지 못함")

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

        composeTab(app).tap()
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

    func testANoteWrittenInPartsShowsTwoPartsInTheFeedAndTheRestInItsDetail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "notes"]
        app.launch()
        openNotes(app)

        let first = app.staticTexts["note.position.9530"]
        var tries = 0
        while !first.isHittable, tries < 20 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(first.waitForExistence(timeout: 4), "이어 쓴 노트의 첫 편에 편 표시가 없음")
        XCTAssertEqual(first.label, "이어 쓴 노트 1/4")
        XCTAssertTrue(app.buttons["note.body.9531"].exists, "피드에 둘째 편이 이어 붙지 않음")
        XCTAssertEqual(app.staticTexts["note.position.9531"].label, "이어 쓴 노트 2/4")
        XCTAssertFalse(app.buttons["note.body.9532"].exists, "피드에 셋째 편까지 펼쳐짐")
        let more = app.buttons["note.threadMore.9530"]
        XCTAssertTrue(more.exists, "남은 편으로 가는 \"이어지는 글 N개 더\"가 없음")
        XCTAssertTrue(more.label.contains("2개"), "남은 편 수가 틀림: \(more.label)")
        attach(app, "note-thread-feed")

        more.tap()
        let last = app.staticTexts["note.position.9533"]
        XCTAssertTrue(last.waitForExistence(timeout: 6), "상세에 마지막 편이 이어지지 않음")
        XCTAssertEqual(last.label, "이어 쓴 노트 4/4")
        XCTAssertTrue(app.buttons["note.body.9532"].exists, "상세에 셋째 편이 없음")
        XCTAssertTrue(app.buttons["note.body.9534"].exists, "남의 답글이 사라짐")
        XCTAssertLessThan(last.frame.minY, app.buttons["note.body.9534"].frame.minY, "남의 답글이 이어 쓴 편보다 위에 있음")
        attach(app, "note-thread-detail")
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

        composeTab(app).tap()
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
