//
//  NotesFeedUITests.swift
//  kurlUITests
//

import XCTest

/// 노트 — 발견의 노트 흐름, 목 피드 렌더, 작성 시트 → 첫 노트 연합 안내 → 맨 위 꽂힘, 답글 화면까지.
final class NotesFeedUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func openNotes(_ app: XCUIApplication) {
        let segment = app.buttons["노트"].firstMatch
        XCTAssertTrue(segment.waitForExistence(timeout: 12), "발견 탭에 노트 흐름이 없음")
        segment.tap()
    }

    func testNotesFlowInDiscoverPublishes() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "discover"]
        app.launch()
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
        shot.name = "notes-in-discover"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testANotesRepliesOpenFromItsRow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "discover"]
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
    }

    func testADraftIsKeptUntilDiscardedAndPhotosOpenLarge() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "discover"]
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
    func waitForValue(_ value: String, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value), object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
