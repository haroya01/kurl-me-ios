//
//  HighlightReplySafetyUITests.swift
//  kurlUITests
//

import XCTest

final class HighlightReplySafetyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchPost(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--post", "honggildong/hexagonal-after-3-months"] + extra
        app.launch()
        return app
    }

    private func openThread6001(_ app: XCUIApplication) {
        let paragraph = app.textViews.containing(NSPredicate(format: "value CONTAINS %@", "돌아가라면")).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 15), "하이라이트가 칠해진 첫 문단을 못 찾음")
        XCTAssertTrue(
            app.tapHighlight(in: paragraph, at: [CGVector(dx: 0.55, dy: 0.16), CGVector(dx: 0.5, dy: 0.1)]),
            "하이라이트 탭으로 카드가 안 뜸")
        XCTAssertTrue(app.openConversationFromCard(), "카드에서 대화가 안 열림")
    }

    private func field(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "highlightReply.field").firstMatch
    }

    private func type(_ text: String, in app: XCUIApplication) {
        let field = field(app)
        XCTAssertTrue(field.waitForExistence(timeout: 6), "답글 입력란 없음")
        field.tap()
        field.typeText(text)
    }

    private func loginSheet(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "login.sheet").firstMatch
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let s = XCTAttachment(screenshot: app.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

    func testSignedOutSendAsksToSignInAndKeepsTheReply() {
        let app = launchPost(["--logged-out"])
        openThread6001(app)
        let draft = "로그인 전에 쓴 답글"
        type(draft, in: app)
        app.buttons["highlightReply.send"].tap()

        XCTAssertTrue(loginSheet(app).waitForExistence(timeout: 6), "비로그인 보내기에 로그인 시트가 안 뜸")
        XCTAssertTrue(app.staticTexts["답글을 남기려면 로그인하세요"].exists, "로그인 문구가 답글 맥락이 아님")
        shot(app, "reply-signed-out-login")

        let start = loginSheet(app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)),
                    withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(loginSheet(app).waitForNonExistence(timeout: 6), "로그인 시트가 닫히지 않음")

        XCTAssertTrue(app.navigationBars["대화"].exists, "로그인 시트를 닫았더니 대화 시트도 닫힘")
        XCTAssertEqual(field(app).value as? String, draft, "로그인 시트를 다녀오니 쓰던 답글이 사라짐")
    }

    func testClosingWithADraftAsksBeforeDiscarding() {
        let app = launchPost()
        openThread6001(app)
        type("아직 다 못 쓴 답글", in: app)

        app.navigationBars["대화"].buttons["닫기"].tap()
        let discard = app.buttons["답글 버리기"]
        XCTAssertTrue(discard.waitForExistence(timeout: 4), "쓰던 답글이 있는데 닫기가 묻지 않음")
        shot(app, "reply-discard-confirm")
        let keep = app.buttons["계속 쓰기"]
        if keep.exists {
            keep.tap()
        } else {
            // Popover presentations omit the cancel row; tapping outside keeps the sheet.
            field(app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(discard.waitForNonExistence(timeout: 4))
        XCTAssertTrue(app.navigationBars["대화"].exists, "계속 쓰기를 눌렀는데 시트가 닫힘")
        XCTAssertEqual(field(app).value as? String, "아직 다 못 쓴 답글")

        app.navigationBars["대화"].buttons["닫기"].tap()
        XCTAssertTrue(discard.waitForExistence(timeout: 4))
        discard.tap()
        XCTAssertTrue(app.navigationBars["대화"].waitForNonExistence(timeout: 6), "버리기를 눌렀는데 시트가 남음")
    }

    func testDeletingMyReplyAsksFirst() {
        let app = launchPost()
        openThread6001(app)
        let mine = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "저도요. 작게")).firstMatch
        XCTAssertTrue(mine.waitForExistence(timeout: 6), "시드된 내 답글이 안 보임")

        let delete = app.buttons["답글 삭제"]
        if !delete.isHittable { app.swipeUp(velocity: .slow) }
        delete.tap()
        XCTAssertTrue(app.alerts["이 답글을 삭제할까요?"].waitForExistence(timeout: 4), "답글 삭제가 묻지 않고 바로 지움")
        app.alerts.buttons["취소"].tap()
        XCTAssertTrue(mine.exists, "취소했는데 답글이 사라짐")

        delete.tap()
        app.alerts.buttons["삭제"].tap()
        XCTAssertTrue(mine.waitForNonExistence(timeout: 8), "확인했는데 답글이 남음")
    }

    func testFailedFirstLoadOffersARetryInsteadOfLookingEmpty() {
        let app = launchPost(["--mock-fail-highlight-replies", "1"])
        openThread6001(app)

        let error = app.descendants(matching: .any).matching(identifier: "highlightReply.loadError").firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 6), "첫 조회 실패에 오류 줄이 없음")
        XCTAssertFalse(app.buttons["아직 답글이 없어요"].exists, "실패를 빈 스레드로 보임")
        shot(app, "reply-load-error")

        app.buttons["highlightReply.retry"].tap()
        let seeded = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "저도요. 작게")).firstMatch
        XCTAssertTrue(seeded.waitForExistence(timeout: 6), "다시 시도해도 답글이 안 뜸")
        XCTAssertFalse(error.exists, "불러온 뒤에도 오류 줄이 남음")
    }

    func testFailedRefetchKeepsTheThread() {
        let app = launchPost(["--mock-fail-highlight-replies", "2"])
        openThread6001(app)
        let seeded = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "저도요. 작게")).firstMatch
        XCTAssertTrue(seeded.waitForExistence(timeout: 6), "시드된 답글이 안 보임")

        let draft = "다시 읽기가 실패하는 답글"
        type(draft, in: app)
        app.buttons["highlightReply.send"].tap()
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", draft), object: field(app))
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 6), .completed, "보내고 나서 입력란이 비지 않음")
        sleep(1)

        XCTAssertTrue(seeded.exists, "다시 읽기가 실패하자 기존 답글이 사라짐")
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "highlightReply.loadError").firstMatch.exists,
            "목록이 있는데 오류 줄로 바뀜")
    }
}
