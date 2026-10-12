import XCTest

final class HighlightThreadAnchorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchReader() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--post", "honggildong/hexagonal-after-3-months"]
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func closeSheet(_ app: XCUIApplication) {
        app.buttons["닫기"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["대화"].waitForNonExistence(timeout: 6), "대화 시트가 닫히지 않음")
    }

    func testThreadLeadsWithThePaintedSentenceItsSourceAndTheHighlightersMemo() throws {
        let app = launchReader()
        let paragraph = app.textViews.containing(NSPredicate(format: "value CONTAINS %@", "돌아가라면")).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 15), "첫 문단 없음")
        XCTAssertTrue(
            app.tapHighlight(in: paragraph, at: [CGVector(dx: 0.55, dy: 0.16), CGVector(dx: 0.5, dy: 0.1)]),
            "하이라이트 탭으로 카드가 안 뜸")
        XCTAssertFalse(
            app.otherElements["highlightCard"].descendants(matching: .any)["모두에게 공개된 하이라이트"].exists,
            "카드에 지구본(공개) 표시가 남아 있음")
        XCTAssertTrue(app.openConversationFromCard(), "카드에서 대화가 안 열림")

        let quote = element(app, "highlight.quote")
        XCTAssertTrue(quote.waitForExistence(timeout: 6), "대화 시트 맨 위에 문장이 없음")
        XCTAssertEqual(quote.label, "다시 돌아가라면 또 갈아탄다")
        XCTAssertTrue(
            element(app, "highlight.source").label.contains("헥사고날로 갈아탄 지 석 달"),
            "문장 아래에 글 제목이 없음")
        XCTAssertTrue(
            element(app, "highlight.highlighters").label.contains("haruka님이 그은 문장"),
            "그은 사람이 한 명일 때 이름으로 말하지 않음")
        let opener = element(app, "highlight.opener")
        XCTAssertTrue(opener.exists, "메모가 없음")
        XCTAssertTrue(
            opener.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@", "haruka의 메모")).firstMatch.exists,
            "메모가 '○○의 메모' 머리로 답글과 구분되지 않음")
        XCTAssertFalse(app.staticTexts["공개 메모"].exists, "옛 '공개 메모' 머리가 남아 있음")
        XCTAssertFalse(app.staticTexts["이것과 이어진 것"].exists, "'이것과 이어진 것' 레일이 남아 있음")
        closeSheet(app)
    }

    func testASentenceManyReadersMarkedCountsThem() throws {
        let app = launchReader()
        XCTAssertTrue(
            app.textViews.containing(NSPredicate(format: "value CONTAINS %@", "돌아가라면")).firstMatch
                .waitForExistence(timeout: 15),
            "본문이 안 열림")
        let paragraph = app.textViews.containing(NSPredicate(format: "value CONTAINS %@", "가장 아픈 슬라이스부터")).firstMatch
        for _ in 0..<12 where !(paragraph.exists && paragraph.isHittable && paragraph.frame.minY > 120) {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(paragraph.isHittable, "마지막 문단까지 내려가지 못함")
        XCTAssertTrue(
            app.tapHighlight(in: paragraph, at: [CGVector(dx: 0.5, dy: 0.5), CGVector(dx: 0.5, dy: 0.62)]),
            "다섯 명이 그은 문장을 탭해도 카드가 안 뜸")
        XCTAssertTrue(app.openConversationFromCard(), "카드에서 대화가 안 열림")

        let highlighters = element(app, "highlight.highlighters")
        XCTAssertTrue(highlighters.waitForExistence(timeout: 6), "그은 사람 줄이 없음")
        XCTAssertTrue(highlighters.label.contains("5명이 그은 문장"), "겹쳐 그은 사람 수를 세지 않음: \(highlighters.label)")
        XCTAssertFalse(element(app, "highlight.opener").exists, "메모 없는 하이라이트에 메모 머리가 있음")
        closeSheet(app)
    }
}
