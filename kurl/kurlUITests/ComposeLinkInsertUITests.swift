import XCTest

final class ComposeLinkInsertUITests: XCTestCase {
    private let guide = "https://example.com/guide"

    override func setUpWithError() throws { continueAfterFailure = false }

    private func launchCompose() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write", "--open", "compose", "--editor", "v2", "--reset-recovery"]
        app.launch()
        XCTAssertTrue(app.textFields["제목"].waitForExistence(timeout: 15))
        return app
    }

    private func body(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.textViews.containing(NSPredicate(format: "value CONTAINS %@", text)).firstMatch
    }

    private func type(_ app: XCUIApplication, _ text: String) {
        let canvas = app.textViews.firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        canvas.tap()
        app.typeText(text)
        XCTAssertTrue(body(app, containing: text).waitForExistence(timeout: 5))
    }

    private func menuItem(_ app: XCUIApplication, _ labels: String...) -> XCUIElement {
        for label in labels where app.menuItems[label].waitForExistence(timeout: 2) {
            return app.menuItems[label]
        }
        return app.menuItems[labels[0]]
    }

    private func allowPaste() {
        addUIInterruptionMonitor(withDescription: "paste-consent") { alert in
            for label in ["Allow Paste", "붙여넣기 허용", "허용", "Allow"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
    }

    private func selectAll(in element: XCUIElement, _ app: XCUIApplication) {
        element.press(forDuration: 1.2)
        let selectAll = menuItem(app, "Select All", "전체 선택", "모두 선택")
        XCTAssertTrue(selectAll.exists, "전체 선택 메뉴가 떠야 함")
        selectAll.tap()
    }

    private func paste(on element: XCUIElement, _ app: XCUIApplication, pressing: Bool = true) {
        if pressing { element.press(forDuration: 1.2) }
        let item = menuItem(app, "Paste", "붙여넣기")
        XCTAssertTrue(item.exists, "붙여넣기 메뉴가 떠야 함")
        item.tap()
    }

    private func tapLabel(of element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 16, dy: 0)).tap()
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPastingOverSelectedTextLinksItWithoutASheet() throws {
        UIPasteboard.general.string = guide
        allowPaste()
        let app = launchCompose()
        type(app, "guide")
        let block = body(app, containing: "guide")
        selectAll(in: block, app)
        paste(on: block, app, pressing: false)
        XCTAssertTrue(body(app, containing: "[guide](\(guide))").waitForExistence(timeout: 5), "고른 글자에 링크가 걸려야 함")
        XCTAssertFalse(app.navigationBars["링크 넣기"].exists, "창이 뜨지 않아야 함")
        app.buttons["composeMoreTools"].tap()
        let undo = app.buttons.matching(identifier: "실행취소")
        XCTAssertTrue(undo.firstMatch.waitForExistence(timeout: 3))
        let hittable = (0..<undo.count).map { undo.element(boundBy: $0) }.first { $0.isHittable }
        XCTAssertNotNil(hittable, "실행취소 메뉴 항목")
        hittable?.tap()
        XCTAssertTrue(app.textViews.containing(NSPredicate(format: "value == %@", "guide")).firstMatch.waitForExistence(timeout: 5), "되돌리기 한 번에 돌아와야 함")
    }

    func testPastingAnAddressIntoAnEmptyParagraphOffersLinkOrCard() throws {
        UIPasteboard.general.string = guide
        allowPaste()
        let app = launchCompose()
        let canvas = app.textViews.firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        canvas.tap()
        paste(on: canvas, app)
        XCTAssertTrue(body(app, containing: "<\(guide)>").waitForExistence(timeout: 5), "주소가 링크로 들어가야 함")
        let card = app.menuItems["카드"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "링크·카드 칩이 떠야 함")
        XCTAssertTrue(app.menuItems["링크"].exists)
        shot(app, "link-paste-chip")
        card.tap()
        XCTAssertTrue(app.descendants(matching: .any)["editor-link-card"].waitForExistence(timeout: 5), "카드 블록으로 바뀌어야 함")
        XCTAssertFalse(body(app, containing: "kurl.me").exists, "붙여넣은 주소를 단축하지 않아야 함")
    }

    func testTypingAfterThePasteDismissesTheChip() throws {
        UIPasteboard.general.string = guide
        allowPaste()
        let app = launchCompose()
        let canvas = app.textViews.firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        canvas.tap()
        paste(on: canvas, app)
        XCTAssertTrue(app.menuItems["카드"].waitForExistence(timeout: 5))
        app.typeText(" 참고")
        XCTAssertTrue(body(app, containing: "<\(guide)> 참고").waitForExistence(timeout: 5))
        XCTAssertFalse(app.menuItems["카드"].waitForExistence(timeout: 1), "계속 입력하면 칩이 사라져야 함")
    }

    func testLinkButtonOpensASheetFilledWithTheSelection() throws {
        let app = launchCompose()
        type(app, "guide")
        let block = body(app, containing: "guide")
        selectAll(in: block, app)
        app.buttons["composeLink"].tap()
        XCTAssertTrue(app.navigationBars["링크 넣기"].waitForExistence(timeout: 5), "링크 시트가 떠야 함")
        XCTAssertEqual(app.textFields["editor-link-text"].value as? String, "guide", "표시 텍스트는 고른 글자")
        XCTAssertFalse(app.segmentedControls["editor-link-kind"].exists, "글자를 골랐으면 카드 전환이 없다")
        let shorten = app.switches["editor-link-shorten"]
        XCTAssertTrue(shorten.exists)
        XCTAssertEqual(shorten.value as? String, "0", "단축은 기본 꺼짐")
        app.textFields["editor-link-address"].typeText("example.com/guide")
        shot(app, "link-sheet-selection")
        app.buttons["editor-link-submit"].tap()
        XCTAssertTrue(body(app, containing: "[guide](\(guide))").waitForExistence(timeout: 5), "넣기 하나로 링크가 걸려야 함")
    }

    func testCardModeShowsThePreviewAndTheShortenSwitchMakesAKurlLink() throws {
        let app = launchCompose()
        type(app, "Read this first")
        app.buttons["composeLink"].tap()
        XCTAssertTrue(app.navigationBars["링크 넣기"].waitForExistence(timeout: 5))
        app.textFields["editor-link-address"].typeText("https://docs.spring.io/spring-framework/reference/web/webflux.html")
        app.segmentedControls["editor-link-kind"].buttons["카드"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["editor-link-preview"].waitForExistence(timeout: 5), "카드 미리보기가 떠야 함")
        XCTAssertFalse(app.switches["editor-link-shorten"].exists, "카드엔 단축 스위치가 없다")
        shot(app, "link-sheet-card")
        app.segmentedControls["editor-link-kind"].buttons["링크"].tap()
        let shorten = app.switches["editor-link-shorten"]
        XCTAssertTrue(shorten.waitForExistence(timeout: 3))
        shorten.switches.firstMatch.exists ? shorten.switches.firstMatch.tap() : shorten.tap()
        XCTAssertEqual(shorten.value as? String, "1")
        app.buttons["editor-link-submit"].tap()
        XCTAssertTrue(body(app, containing: "<https://kurl.me/").waitForExistence(timeout: 8), "스위치를 켜면 kurl 단축 주소로 넣는다")
    }

    func testTappingALinkOffersOpenEditAndRemove() throws {
        let app = launchCompose()
        type(app, "[guide](https://example.com/old) ")
        app.buttons["키보드 내리기"].tap()
        let block = body(app, containing: "[guide](")
        tapLabel(of: block)
        let edit = app.menuItems["고치기"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "링크를 누르면 메뉴가 떠야 함")
        XCTAssertTrue(app.menuItems["열기"].exists)
        XCTAssertTrue(app.menuItems["링크 빼기"].exists)
        shot(app, "link-tap-menu")
        edit.tap()
        XCTAssertTrue(app.navigationBars["링크 고치기"].waitForExistence(timeout: 5), "고치기 시트")
        XCTAssertEqual(app.textFields["editor-link-address"].value as? String, "https://example.com/old")
        XCTAssertTrue(app.buttons["저장"].exists)
        app.buttons["editor-link-clear"].tap()
        app.textFields["editor-link-address"].typeText(guide)
        app.buttons["editor-link-submit"].tap()
        XCTAssertTrue(body(app, containing: "[guide](\(guide))").waitForExistence(timeout: 5), "주소가 바뀌어야 함")

        app.buttons["키보드 내리기"].tap()
        tapLabel(of: body(app, containing: "[guide]("))
        let remove = app.menuItems["링크 빼기"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertTrue(app.textViews.containing(NSPredicate(format: "value BEGINSWITH %@", "guide")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(body(app, containing: "](").exists, "링크만 빠지고 글자는 남아야 함")
    }

    func testPasteButtonFillsTheAddressFromTheClipboard() throws {
        UIPasteboard.general.string = guide
        let app = launchCompose()
        type(app, "Read")
        app.buttons["composeLink"].tap()
        XCTAssertTrue(app.navigationBars["링크 넣기"].waitForExistence(timeout: 5))
        let pasteButton = app.buttons["Paste"].exists ? app.buttons["Paste"] : app.buttons["붙여넣기"]
        XCTAssertTrue(pasteButton.waitForExistence(timeout: 3), "주소 칸의 붙여넣기 버튼")
        pasteButton.tap()
        XCTAssertTrue(app.staticTexts["editor-link-pasted"].waitForExistence(timeout: 5), "붙여넣음 표시")
        XCTAssertEqual(app.textFields["editor-link-address"].value as? String, guide)
        XCTAssertTrue(app.buttons["editor-link-clear"].exists, "지우기 버튼")
        shot(app, "link-sheet-pasted")
        app.buttons["취소"].tap()
        XCTAssertFalse(app.navigationBars["링크 넣기"].waitForExistence(timeout: 2))
    }
}
