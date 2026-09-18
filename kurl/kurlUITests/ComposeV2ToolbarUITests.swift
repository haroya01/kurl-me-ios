import XCTest

/// Primary writing actions stay visible; structure and text share one reversible history.
final class ComposeV2ToolbarUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launchCompose() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write", "--open", "compose", "--editor", "v2", "--reset-recovery"]
        app.launch()
        XCTAssertTrue(app.textFields["제목"].waitForExistence(timeout: 15))
        return app
    }

    private func bodyContains(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.textViews.containing(NSPredicate(format: "value CONTAINS %@", text)).firstMatch
    }

    private func recordTabBarState(_ app: XCUIApplication, phase: String) {
        let feed = app.buttons["피드"]
        print("TAB_BAR_CHECK \(phase): exists=\(feed.exists) hittable=\(feed.isHittable)")
        let snapshot = XCTAttachment(string: app.debugDescription)
        snapshot.name = "tab-bar-\(phase)"
        snapshot.lifetime = .keepAlways
        add(snapshot)
    }

    func testTitleNextEntersBodyAndPrimaryToolsNeedNoScroll() throws {
        let app = launchCompose()
        app.textFields["제목"].tap()
        app.textFields["제목"].typeText("Next target\n")
        app.typeText("Body begins here")
        XCTAssertTrue(bodyContains(app, "Body begins here").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["피드"].isHittable)
        XCTAssertEqual(app.textFields["제목"].value as? String, "Next target")
        for id in ["composeFormat", "composeList", "composeLink", "composePhoto", "composeMoreTools"] {
            let tool = app.buttons[id]
            XCTAssertTrue(tool.isHittable, "Primary tool needs no horizontal scroll: \(id)")
            XCTAssertGreaterThanOrEqual(tool.frame.width, 44)
            XCTAssertGreaterThanOrEqual(tool.frame.height, 44)
        }
        app.buttons["composeMoreTools"].tap()
        app.buttons["표"].tap()
        XCTAssertTrue(app.buttons["표 삭제"].waitForExistence(timeout: 5))
        app.typeText("After table")
        XCTAssertTrue(bodyContains(app, "After table").waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "compose-fixed-primary-tools"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testUndoRedoCrossesParagraphBoundary() throws {
        let app = launchCompose()
        app.textFields["제목"].tap()
        app.textFields["제목"].typeText("History\n")
        app.typeText("First\nSecond")
        XCTAssertTrue(bodyContains(app, "Second").waitForExistence(timeout: 5))
        app.buttons["composeUndo"].tap() // Second paragraph's typing group.
        XCTAssertTrue(bodyContains(app, "Second").waitForNonExistence(timeout: 4))
        app.buttons["composeUndo"].tap() // Structural Enter.
        XCTAssertEqual(app.textViews.count, 1)
        XCTAssertTrue(bodyContains(app, "First").exists)
        app.buttons["composeMoreTools"].tap()
        app.buttons["다시실행"].tap()
        XCTAssertEqual(app.textViews.count, 2)
        app.buttons["composeMoreTools"].tap()
        app.buttons["다시실행"].tap()
        XCTAssertTrue(bodyContains(app, "Second").waitForExistence(timeout: 5))
    }

    func testFastTypingAcrossQuoteAndListExitKeepsInput() throws {
        let app = launchCompose()
        app.textFields["제목"].tap()
        app.textFields["제목"].typeText("Transitions\n")
        app.typeText("> quote\nAfter quote\n- item\n\nAfter list")
        for value in ["quote", "After quote", "item", "After list"] {
            let paragraph = app.textViews.containing(NSPredicate(format: "value == %@", value)).firstMatch
            XCTAssertTrue(paragraph.waitForExistence(timeout: 5), "Continuous input survives quote/list exit: \(value)")
        }
        XCTAssertEqual(app.textViews.count, 4)
    }

    func testPublishedBodyWaitsForSaveAndDepartureKeepsRecovery() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write", "--editor", "v2", "--reset-recovery"]
        app.launch()
        let published = app.staticTexts["발행된 목 글"]
        XCTAssertTrue(published.waitForExistence(timeout: 15))
        recordTabBarState(app, phase: "initial-studio")
        XCTAssertTrue(app.buttons["피드"].isHittable, app.debugDescription)
        app.buttons["발행된 목 글 관리"].tap()
        app.buttons["편집"].tap()
        let paragraph = app.textViews.containing(NSPredicate(format: "value == %@", "본문.")).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 10))
        paragraph.tap()
        app.typeText(" pending local edit")
        XCTAssertTrue(app.staticTexts["저장 필요"].waitForExistence(timeout: 4))
        Thread.sleep(forTimeInterval: 3) // Beyond the draft autosave debounce.
        XCTAssertTrue(app.staticTexts["저장 필요"].exists)
        app.buttons["키보드 내리기"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(published.waitForExistence(timeout: 8))
        recordTabBarState(app, phase: "returned-studio")
        XCTAssertTrue(app.buttons["피드"].isHittable, app.debugDescription)
        app.buttons["발행된 목 글 관리"].tap()
        app.buttons["편집"].tap()
        let recovery = app.alerts["저장되지 못한 본문이 있어요"]
        XCTAssertTrue(recovery.waitForExistence(timeout: 8), "Departure must not publish the local body silently")
        recovery.buttons["이어서 쓰기"].tap()
        XCTAssertTrue(bodyContains(app, "pending local edit").waitForExistence(timeout: 5))
        app.buttons["저장"].tap()
        XCTAssertTrue(app.staticTexts["저장됨"].waitForExistence(timeout: 10))
    }

    func testBodyUndoCannotHijackTitleEditing() throws {
        let app = launchCompose()
        let title = app.textFields["제목"]
        title.tap()
        title.typeText("Title\n")
        app.typeText("Keep this body")
        XCTAssertTrue(bodyContains(app, "Keep this body").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["composeUndo"].isEnabled)
        title.tap()
        title.typeText(" edit")
        XCTAssertFalse(app.buttons["composeUndo"].isEnabled)
        XCTAssertTrue(bodyContains(app, "Keep this body").exists)
        XCTAssertTrue((title.value as? String)?.contains("edit") == true)
    }

}
