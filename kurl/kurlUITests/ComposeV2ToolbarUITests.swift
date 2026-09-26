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

    func testPastedLinesInTitleKeepFirstLineAndStartTheBody() throws {
        UIPasteboard.general.string = "Pasted title\nPasted body"
        let app = launchCompose()
        let title = app.textFields["제목"]
        title.tap()
        title.press(forDuration: 1.2)
        let pasteEN = app.menuItems["Paste"]
        let pasteKO = app.menuItems["붙여넣기"]
        XCTAssertTrue(pasteEN.waitForExistence(timeout: 5) || pasteKO.waitForExistence(timeout: 2))
        (pasteEN.exists ? pasteEN : pasteKO).tap()
        XCTAssertTrue(bodyContains(app, "Pasted body").waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "Pasted title")
        app.typeText(" continues")
        XCTAssertTrue(bodyContains(app, "Pasted body continues").waitForExistence(timeout: 5))
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


    func testFormatMenuTurnsAParagraphIntoAWarningBox() throws {
        let app = launchCompose()
        let body = app.textViews.firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap()
        app.typeText("Restart does not reload the config")
        XCTAssertTrue(bodyContains(app, "Restart does not reload").waitForExistence(timeout: 5))
        app.buttons["composeFormat"].tap()
        let warning = app.buttons["주의"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5), "서식 메뉴에 박스 종류가 있어야 함")
        warning.tap()
        let label = app.staticTexts["editor-callout-label"]
        XCTAssertTrue(label.waitForExistence(timeout: 5), "주의 박스 라벨이 떠야 함")
        XCTAssertEqual(label.label, "주의")
        XCTAssertTrue(bodyContains(app, "Restart does not reload the config").exists, "글은 박스 안에 그대로")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "compose-warning-box"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testLinkDialogAddsALinkCard() throws {
        let app = launchCompose()
        let body = app.textViews.firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap()
        app.typeText("Read this first")
        app.buttons["composeLink"].tap()
        let dialog = app.alerts["링크"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 5), "링크 다이얼로그가 떠야 함")
        let url = dialog.textFields["https://…"]
        url.tap()
        url.typeText("https://docs.spring.io/spring-framework/reference/web/webflux.html")
        dialog.buttons["카드로 추가"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["editor-link-card"].waitForExistence(timeout: 8), "링크 카드 블록이 들어가야 함")
        XCTAssertTrue(bodyContains(app, "Read this first").exists, "앞 문단은 그대로")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "compose-link-card"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testListMenuMakesAChecklistWithTappableBoxes() throws {
        let app = launchCompose()
        let body = app.textViews.firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap()
        app.typeText("Buy milk")
        app.buttons["composeList"].tap()
        let checklist = app.buttons["체크리스트"]
        XCTAssertTrue(checklist.waitForExistence(timeout: 5), "목록 메뉴에 체크리스트가 있어야 함")
        checklist.tap()
        let box = app.buttons["editor-task-checkbox"]
        XCTAssertTrue(box.waitForExistence(timeout: 5), "체크박스가 떠야 함")
        XCTAssertEqual(box.label, "미완료")
        app.typeText("\nCall mom")
        XCTAssertEqual(app.buttons.matching(identifier: "editor-task-checkbox").count, 2, "엔터로 다음 체크 항목")
        app.buttons.matching(identifier: "editor-task-checkbox").firstMatch.tap()
        XCTAssertEqual(app.buttons.matching(identifier: "editor-task-checkbox").firstMatch.label, "완료")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "compose-checklist"
        shot.lifetime = .keepAlways
        add(shot)
    }
}

