//
//  HighlightNoteReplyUITests.swift
//  kurlUITests
//

import XCTest

/// 하이라이트 스레드의 빈칸을 메운다 — 기존 HighlightReaderUITests 는 '메모' 액션·답글의
/// 실제 반영·답글 삭제를 검증하지 않고 스크린샷으로만 지나쳤다. 시드 하이라이트 6001(내 메모+답글 2개,
/// 첫 답글은 내 것)을 앵커로 답글 왕복·내 답글 삭제를 자산으로 남기고, '메모와 함께 하이라이트'를
/// 롱프레스로 새로 만든다. 좌표 탭이 어긋나도 스샷이 남게 soft 하게 진행한다.
final class HighlightNoteReplyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func shot(_ name: String) {
        let s = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

    private func launchPost() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--post", "honggildong/hexagonal-after-3-months"]
        app.launch()
        return app
    }

    /// 시드 하이라이트 6001("다시 돌아가라면 또 갈아탄다", 첫 문단 중반) 탭 → 답글 스레드.
    /// 좌표 추정이 어긋나면 한 번 더 시도한다(기존 테스트와 동일 좌표).
    @discardableResult
    private func openThread6001(_ app: XCUIApplication) -> Bool {
        let paragraph = app.textViews.containing(
            NSPredicate(format: "value CONTAINS %@", "돌아가라면")).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 15), "하이라이트가 칠해진 첫 문단을 못 찾음")
        paragraph.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.16)).tap()

        let sendReply = app.buttons["답글 보내기"]
        if !sendReply.waitForExistence(timeout: 6) {
            paragraph.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
            _ = sendReply.waitForExistence(timeout: 6)
        }
        return sendReply.exists
    }

    /// 답글 왕복 — 시트에 한 줄 적고 보내면, 서버에 붙은 답글을 다시 읽어 스레드에 나타난다.
    func testReplyPersistsInThread() throws {
        let app = launchPost()
        XCTAssertTrue(openThread6001(app), "하이라이트 탭으로 답글 스레드가 안 열림")

        let byPlaceholder = NSPredicate(format: "placeholderValue CONTAINS '답글 남기기'")
        var field = app.textViews.matching(byPlaceholder).firstMatch
        if !field.exists { field = app.textFields.matching(byPlaceholder).firstMatch }
        XCTAssertTrue(field.waitForExistence(timeout: 4), "답글 입력란 없음")

        let unique = "왕복확인 답글 uitest"
        field.tap()
        field.typeText(unique)
        let send = app.buttons["답글 보내기"]
        XCTAssertTrue(send.isEnabled, "답글을 적었는데 보내기가 비활성")
        send.tap()

        let posted = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", unique)).firstMatch
        XCTAssertTrue(posted.waitForExistence(timeout: 8), "보낸 답글이 스레드에 나타나지 않음")
        shot("reply-persisted")
    }

    /// 내 답글 삭제 — 시드된 내 답글("저도요…")엔 휴지통(답글 삭제)이 있고, 지우면 스레드에서 사라진다.
    /// (남의 답글엔 삭제 버튼이 없다 — 소유 검사 me.id == author.id.)
    func testDeleteOwnReply() throws {
        let app = launchPost()
        XCTAssertTrue(openThread6001(app), "하이라이트 탭으로 답글 스레드가 안 열림")

        let mine = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "저도요. 작게")).firstMatch
        XCTAssertTrue(mine.waitForExistence(timeout: 6), "시드된 내 답글이 안 보임")

        let delete = app.buttons["답글 삭제"]
        XCTAssertTrue(delete.waitForExistence(timeout: 4), "내 답글에 삭제 버튼이 없음")
        if !delete.isHittable { app.swipeUp(velocity: .slow) }
        delete.tap()

        XCTAssertTrue(mine.waitForNonExistence(timeout: 8), "삭제해도 내 답글이 스레드에 남음")
        shot("own-reply-deleted")
    }

    /// 메모와 함께 하이라이트 — 칠 안 된 문단을 롱프레스(문장 스냅) → 편집 메뉴 '메모' →
    /// '메모 추가' 시트에 한 줄 적고 저장하면 시트가 닫히며 메모 달린 하이라이트가 생긴다.
    func testCreateHighlightWithNote() throws {
        let app = launchPost()

        let paragraph = app.textViews.containing(
            NSPredicate(format: "value CONTAINS %@", "레이어드 구조로 3년을")).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 15), "둘째 문단 없음")
        paragraph.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.7)
        Thread.sleep(forTimeInterval: 0.6)
        shot("1-longpress-menu")

        // 좁은 편집 메뉴에선 커스텀 액션이 '더 보기' chevron 뒤에 있을 수 있다.
        let noteItem = app.menuItems["메모"]
        if !noteItem.exists {
            let more = app.menuItems.matching(
                NSPredicate(format: "label CONTAINS '더' OR label CONTAINS 'More'")).firstMatch
            if more.exists { more.tap(); Thread.sleep(forTimeInterval: 0.4) }
        }
        XCTAssertTrue(noteItem.waitForExistence(timeout: 4), "편집 메뉴에 '메모' 액션이 없음")
        noteItem.tap()

        let composer = app.navigationBars["메모 추가"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5), "'메모 추가' 시트가 안 뜸")
        let noteField = app.textFields["이 부분에 대한 메모를 남겨보세요"]
        XCTAssertTrue(noteField.waitForExistence(timeout: 3), "메모 입력란 없음")
        noteField.tap()
        noteField.typeText("여백 메모 uitest")
        shot("2-note-typed")

        composer.buttons["저장"].tap()
        XCTAssertTrue(composer.waitForNonExistence(timeout: 6), "저장해도 '메모 추가' 시트가 안 닫힘")
        shot("3-note-saved")
    }
}
