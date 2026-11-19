import XCTest

/// 인용은 방의 벽을 넘지 않는다 — 방의 것은 그 방 안에서만, 누구나 보는 것은 어디서나.
/// 목 백엔드의 방 1(동아리 사람들)에는 노트 9901·9903 과 글 8801(9903 을 실음)이, 방 2(대학 동기)가 따로 있다.
/// 방 밖 글 picking-mt-photos 는 같은 9903 주소를 실었다. 목에서 새로 올린 방 노트의 번호는 9960 부터다.
final class RoomQuoteUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks"] + arguments
        app.launch()
        return app
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func text(_ app: XCUIApplication, containing fragment: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    private func element(_ app: XCUIApplication, _ identifier: String, labelContaining fragment: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", identifier, fragment)).firstMatch
    }

    private func write(_ app: XCUIApplication, _ body: String) {
        let field = app.textFields["noteCompose.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 4), "작성 칸이 없음")
        field.typeText(body)
    }

    private func post(_ app: XCUIApplication) {
        let button = app.buttons["noteCompose.post"]
        button.tap()
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 2), "방 노트에 다른 서버로 전해진다는 안내가 뜸")
        XCTAssertTrue(button.waitForNonExistence(timeout: 8), "올린 뒤 작성기가 닫히지 않음")
    }

    func testARoomNoteIsQuotedInsideItsRoom() {
        let app = launch(["--tab", "rooms", "--room", "1"])
        let quote = app.buttons["note.quote.9901"]
        XCTAssertTrue(quote.waitForExistence(timeout: 15), "방 노트에 인용 버튼이 없음")
        quote.tap()
        let asNote = app.buttons["노트로 인용"]
        XCTAssertTrue(asNote.waitForExistence(timeout: 4), "인용 메뉴에 노트로 인용이 없음")
        asNote.tap()

        let room = app.staticTexts["noteCompose.room"]
        XCTAssertTrue(room.waitForExistence(timeout: 6), "방 노트 인용이 그 방에 고정되지 않음")
        XCTAssertEqual(room.label, "동아리 사람들")
        XCTAssertFalse(app.buttons["noteCompose.destination"].exists, "방 노트 인용이 올릴 곳을 고르게 함")
        XCTAssertEqual(app.staticTexts["noteCompose.roomAudience"].label, "동아리 사람들 멤버만 볼 수 있어요")
        write(app, "uitest room quote")
        attach("room-note-quote-sheet")
        post(app)

        XCTAssertTrue(
            text(app, containing: "uitest room quote").waitForExistence(timeout: 8), "인용 노트가 방 타임라인에 안 꽂힘")
        XCTAssertTrue(app.buttons["note.quoted.9901"].exists, "인용한 방 노트가 카드로 안 보임")
        attach("room-timeline-quoting-a-room-note")
    }

    func testARoomNoteIsQuotedIntoABlogPostOfItsRoom() {
        let app = launch(["--tab", "rooms", "--room", "1"])
        let quote = app.buttons["note.quote.9901"]
        XCTAssertTrue(quote.waitForExistence(timeout: 15), "방 노트에 인용 버튼이 없음")
        quote.tap()
        let asPost = app.buttons["블로그 글로 인용"]
        XCTAssertTrue(asPost.waitForExistence(timeout: 4), "인용 메뉴에 블로그 글로 인용이 없음")
        asPost.tap()

        XCTAssertTrue(
            element(app, "compose.room", labelContaining: "동아리 사람들").waitForExistence(timeout: 10),
            "글 에디터가 그 방의 글로 열리지 않음")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "editor-link-card").firstMatch
                .waitForExistence(timeout: 8),
            "노트 주소가 첫 줄에 실리지 않음")
        XCTAssertTrue(
            element(app, "editor-link-card", labelContaining: "퇴근하다 한강").waitForExistence(timeout: 8),
            "같은 방 글에 실은 방 노트가 카드가 아님")
        attach("room-note-quote-in-post-editor")

        app.navigationBars["새 글"].buttons.element(boundBy: 0).tap()
        let back = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: quote)
        XCTAssertEqual(XCTWaiter().wait(for: [back], timeout: 8), .completed, "에디터를 닫아도 방으로 돌아오지 않음")
    }

    func testAPublicNoteQuoteOffersWhereToPostAndGoesIntoThePickedRoom() {
        let app = launch([])
        let repost = app.buttons["note.repost.9501"]
        XCTAssertTrue(repost.waitForExistence(timeout: 15), "홈에 공개 노트가 없음")
        repost.tap()
        let quoteItem = app.buttons["인용"].firstMatch
        XCTAssertTrue(quoteItem.waitForExistence(timeout: 4), "리포스트 메뉴에 인용이 없음")
        quoteItem.tap()

        let destination = app.buttons["noteCompose.destination"]
        XCTAssertTrue(destination.waitForExistence(timeout: 6), "공개 노트 인용이 올릴 곳을 고르게 하지 않음")
        XCTAssertTrue(destination.label.contains("내 노트"), "올릴 곳 기본값이 내 노트가 아님: \(destination.label)")
        XCTAssertGreaterThanOrEqual(
            destination.frame.height, app.buttons["취소"].firstMatch.frame.height, "올릴 곳 고르기의 터치 영역이 옆 버튼보다 낮음")
        XCTAssertTrue(app.buttons["noteCompose.visibility"].exists, "내 노트로 올리는데 공개 범위가 없음")
        attach("public-note-quote-sheet")

        destination.tap()
        let room = app.buttons["대학 동기"]
        XCTAssertTrue(room.waitForExistence(timeout: 4), "올릴 곳에 내 방이 없음")
        attach("public-note-quote-destinations")
        room.tap()

        let audience = app.staticTexts["noteCompose.roomAudience"]
        XCTAssertTrue(audience.waitForExistence(timeout: 4), "방을 골랐는데 멤버만 본다는 줄이 없음")
        XCTAssertEqual(audience.label, "대학 동기 멤버만 볼 수 있어요")
        XCTAssertFalse(app.buttons["noteCompose.visibility"].exists, "방 노트에 공개 범위가 남음")
        XCTAssertFalse(app.buttons["noteCompose.schedule"].exists, "방 노트에 예약이 남음")
        write(app, "uitest into room")
        attach("public-note-quote-into-a-room")
        post(app)

        XCTAssertFalse(text(app, containing: "uitest into room").exists, "방에 올린 인용이 홈 목록에 끼어듦")

        app.buttons["방"].firstMatch.tap()
        let all = app.buttons["segment.all"]
        XCTAssertTrue(all.waitForExistence(timeout: 10), "방 탭에 전체 보기가 없음")
        all.tap()
        XCTAssertTrue(
            text(app, containing: "uitest into room").waitForExistence(timeout: 8), "방 글 모음에 인용 노트가 없음")
        XCTAssertEqual(app.buttons["note.room.9960"].label, "대학 동기 방에서", "인용 노트가 고른 방에 올라가지 않음")
        XCTAssertTrue(app.buttons["note.quoted.9501"].exists, "인용한 공개 노트가 카드로 안 보임")
        attach("rooms-quoting-a-public-note")
    }

    func testARoomNotesMenuQuotesInsteadOfReposting() {
        let app = launch(["--tab", "rooms", "--room", "1"])
        let quote = app.buttons["note.quote.9901"]
        XCTAssertTrue(quote.waitForExistence(timeout: 15), "방 노트에 인용 버튼이 없음")
        XCTAssertFalse(app.buttons["note.repost.9901"].exists, "방 노트에 리포스트가 있음")
        XCTAssertFalse(app.buttons["note.share.9901"].exists, "방 노트에 공유가 있음")
        XCTAssertGreaterThanOrEqual(quote.frame.width, 44, "인용 버튼 터치 영역이 좁음")
        XCTAssertGreaterThanOrEqual(quote.frame.height, 44, "인용 버튼 터치 영역이 낮음")
        attach("room-note-row")

        quote.tap()
        let asNote = app.buttons["노트로 인용"]
        XCTAssertTrue(asNote.waitForExistence(timeout: 4), "인용 메뉴에 노트로 인용이 없음")
        XCTAssertTrue(app.buttons["블로그 글로 인용"].exists, "인용 메뉴에 블로그 글로 인용이 없음")
        XCTAssertFalse(app.buttons["리포스트"].exists, "방 노트 메뉴에 리포스트가 있음")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "인용 메뉴를 열었는데 키보드가 올라옴")
        attach("room-note-quote-menu")

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertTrue(asNote.waitForNonExistence(timeout: 4), "바깥을 눌러도 인용 메뉴가 닫히지 않음")
    }

    func testARoomPostDrawsItsRoomsNoteAsACardAndIsQuotedInsideItsRoom() {
        let app = launch(["--post", "yuki_dev/rainy-mt-night"])
        XCTAssertTrue(
            app.buttons["post.noteEmbed.9903"].waitForExistence(timeout: 15), "방 글에 실린 같은 방 노트가 카드가 아님")
        attach("room-post-note-card")

        let more = app.buttons["더 보기"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 6), "글 메뉴가 없음")
        more.tap()
        let asNote = app.buttons["노트로 인용"].firstMatch
        XCTAssertTrue(asNote.waitForExistence(timeout: 4), "방 글 메뉴에 노트로 인용이 없음")
        attach("room-post-menu")
        asNote.tap()

        let room = app.staticTexts["noteCompose.room"]
        XCTAssertTrue(room.waitForExistence(timeout: 6), "방 글 인용이 그 방에 고정되지 않음")
        XCTAssertEqual(room.label, "동아리 사람들")
        XCTAssertFalse(app.buttons["noteCompose.destination"].exists, "방 글 인용이 올릴 곳을 고르게 함")
        write(app, "uitest room post quote")
        attach("room-post-quote-sheet")
        post(app)

        let notes = app.buttons["discussion.notes"]
        let window = app.windows.firstMatch.frame
        for _ in 0..<6 where !notes.waitForExistence(timeout: 2) || notes.frame.midY > window.height * 0.7 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
        }
        XCTAssertTrue(notes.waitForExistence(timeout: 4), "방 안에서 한 인용이 글의 노트 탭에 들지 않음")
        XCTAssertTrue(notes.label.contains("노트 1"), "노트 탭에 인용 수가 없음: \(notes.label)")
        notes.tap()
        XCTAssertTrue(app.buttons["note.quotedPost.8801"].waitForExistence(timeout: 4), "노트 탭에 방금 올린 인용이 없음")
        attach("room-post-notes-tab")
    }

    func testARoomNotesAddressInAPostOutsideTheRoomStaysALink() {
        let app = launch(["--post", "yuki_dev/picking-mt-photos"])
        XCTAssertTrue(
            text(app, containing: "링크 열기").waitForExistence(timeout: 15), "방 밖 글에 실린 방 노트 주소가 링크로 안 보임")
        XCTAssertFalse(app.buttons["post.noteEmbed.9903"].exists, "방 밖 글이 방 노트를 카드로 그림")
        attach("outside-post-link-card")
    }
}
