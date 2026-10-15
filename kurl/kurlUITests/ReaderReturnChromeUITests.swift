import XCTest

final class ReaderReturnChromeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func back(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == '뒤로'")).firstMatch
    }

    private func tabBarButton(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let bottom = app.windows.firstMatch.frame.height * 0.8
        let candidates = app.buttons.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex
        return candidates.first { $0.frame.minY > bottom } ?? candidates[0]
    }

    private func openPostMidArticle() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--feed", "recent"]
        app.launch()
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'feed.row.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        XCTAssertTrue(back(app).waitForExistence(timeout: 8))
        for _ in 0..<3 { app.swipeUp(velocity: .slow) }
        XCTAssertFalse(back(app).waitForExistence(timeout: 1), "읽어 내려가면 상단 바가 접혀야 한다")
        app.swipeDown(velocity: .slow)
        XCTAssertTrue(back(app).waitForExistence(timeout: 3), "조금 올리면 상단 바가 돌아와야 한다")
        Thread.sleep(forTimeInterval: 0.6)
        return app
    }

    private func assertTopBarStays(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 1.5)
        shot(name)
        XCTAssertTrue(back(app).exists, "\(name): 돌아오자 상단 바가 다시 접혔다")
    }

    func testTheTopBarStaysAfterSwitchingTabsMidArticle() {
        let app = openPostMidArticle()
        tabBarButton(app, "노트").tap()
        Thread.sleep(forTimeInterval: 1.5)
        app.buttons["tab.menu"].firstMatch.tap()
        assertTopBarStays(app, "return-tabs")
    }

    func testTheTopBarStaysAfterTheShareSheetMidArticle() {
        let app = openPostMidArticle()
        app.buttons.matching(NSPredicate(format: "label == '이 글 관리' OR label == '더 보기'")).firstMatch.tap()
        let share = app.buttons["공유"].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 3))
        share.tap()
        Thread.sleep(forTimeInterval: 2)
        let close = app.buttons.matching(NSPredicate(format: "label == '닫기' OR label == 'Close'")).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        assertTopBarStays(app, "return-share")
    }

    func testTheTopBarStaysAfterBackgroundingMidArticle() {
        let app = openPostMidArticle()
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        app.activate()
        assertTopBarStays(app, "return-background")
    }
}
