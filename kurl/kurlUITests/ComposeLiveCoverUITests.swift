//
//  ComposeLiveCoverUITests.swift
//  kurlUITests
//
//  라이브(발행) 글 편집 중 본문에 첫 사진을 넣거나 글 정보 시트에서 커버를 정해도 '저장' 전에는 독자 앞
//  커버가 바뀌지 않고, 저장할 때 반영된다(라이브 글 명시 저장 원칙). 본문 사진은 클립보드 붙여넣기로,
//  시트 경로는 "본문 첫 이미지를 커버로" 제안으로 넣는다(사진 선택기는 프로세스 밖이라 UI 테스트 밖).
//

import XCTest

final class ComposeLiveCoverUITests: XCTestCase {

    private func coverToastAppears(_ app: XCUIApplication, within seconds: Double) -> Bool {
        let toast = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '첫 이미지를 커버로'")).firstMatch
        for _ in 0..<Int(seconds * 10) {
            if toast.exists { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchWithBodyImage() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--mocks", "--tab", "write", "--editor", "legacy", "--reset-recovery", "--published-body-image",
        ]
        app.launch()
        return app
    }

    private func applySuggestedCoverInInfoSheet(_ app: XCUIApplication) {
        openInfoSheet(app)
        let suggest = app.buttons.matching(NSPredicate(format: "label CONTAINS '본문 첫 이미지를 커버로'")).firstMatch
        XCTAssertTrue(suggest.waitForExistence(timeout: 5), "본문 사진이 있는데 커버 제안이 없음")
        suggest.tap()
        XCTAssertTrue(labeled(app, "커버 변경").waitForExistence(timeout: 5), "제안을 눌러도 카드 커버가 안 바뀜")
        app.buttons["닫기"].tap()
    }

    private func launch() -> XCUIApplication {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48)).image { ctx in
            UIColor.systemOrange.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
        }
        UIPasteboard.general.image = image
        addUIInterruptionMonitor(withDescription: "paste-consent") { alert in
            for label in ["Allow Paste", "붙여넣기 허용", "Paste", "허용", "Allow"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "write", "--editor", "legacy", "--reset-recovery"]
        app.launch()
        return app
    }

    private func openPublishedPost(_ app: XCUIApplication) {
        let manage = app.buttons["발행된 목 글 관리"]
        XCTAssertTrue(manage.waitForExistence(timeout: 15), "스튜디오에 발행된 목 글이 없음")
        manage.tap()
        app.buttons["편집"].tap()
    }

    private func pasteImage(_ app: XCUIApplication) -> XCUIElement {
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "본문 캔버스 없음")
        editor.tap()
        editor.press(forDuration: 1.2)
        let pasteEN = app.menuItems["Paste"]
        let pasteKO = app.menuItems["붙여넣기"]
        XCTAssertTrue(
            pasteEN.waitForExistence(timeout: 5) || pasteKO.waitForExistence(timeout: 2), "붙여넣기 메뉴가 안 뜸")
        (pasteEN.exists ? pasteEN : pasteKO).tap()
        app.tap()
        expectation(for: NSPredicate(format: "value CONTAINS '![]('"), evaluatedWith: editor, handler: nil)
        waitForExpectations(timeout: 15)
        return editor
    }

    private func openInfoSheet(_ app: XCUIApplication) {
        if app.buttons["키보드 내리기"].exists { app.buttons["키보드 내리기"].tap() }
        app.buttons["더 보기"].tap()
        let info = app.buttons["글 정보…"]
        XCTAssertTrue(info.waitForExistence(timeout: 4), "더 보기 메뉴에 글 정보가 없음")
        info.tap()
        XCTAssertTrue(app.navigationBars["글 정보"].waitForExistence(timeout: 5), "글 정보 시트가 안 뜸")
    }

    private func labeled(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func shot(_ name: String) {
        let s = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

    func testBodyImageDoesNotChangeLiveCoverBeforeSave() throws {
        let app = launch()
        openPublishedPost(app)
        _ = pasteImage(app)
        XCTAssertFalse(coverToastAppears(app, within: 3), "저장 전에 라이브 글 커버를 바꿨다고 알림")

        if app.buttons["키보드 내리기"].exists { app.buttons["키보드 내리기"].tap() }
        app.navigationBars.buttons.firstMatch.tap()
        openPublishedPost(app)
        let recovery = app.alerts["저장되지 못한 본문이 있어요"]
        if recovery.waitForExistence(timeout: 8) { recovery.buttons["버리기"].tap() }

        openInfoSheet(app)
        XCTAssertTrue(
            labeled(app, "커버 이미지 추가").waitForExistence(timeout: 5), "저장하지 않았는데 라이브 글 커버가 바뀜")
        shot("live-cover-unchanged-before-save")
    }

    func testSuggestedCoverInInfoSheetDoesNotChangeLiveCoverBeforeSave() throws {
        let app = launchWithBodyImage()
        openPublishedPost(app)
        applySuggestedCoverInInfoSheet(app)

        app.navigationBars.buttons.firstMatch.tap()
        openPublishedPost(app)
        let recovery = app.alerts["저장되지 못한 본문이 있어요"]
        if recovery.waitForExistence(timeout: 4) { recovery.buttons["버리기"].tap() }
        openInfoSheet(app)
        XCTAssertTrue(
            labeled(app, "커버 이미지 추가").waitForExistence(timeout: 5), "저장하지 않았는데 라이브 글 커버가 바뀜")
        shot("suggested-cover-unchanged-before-save")
    }

    func testSuggestedCoverInInfoSheetBecomesLiveCoverOnSave() throws {
        let app = launchWithBodyImage()
        openPublishedPost(app)
        applySuggestedCoverInInfoSheet(app)

        XCTAssertTrue(app.staticTexts["저장 필요"].waitForExistence(timeout: 5), "커버만 바꿔도 저장할 변경으로 안 보임")
        app.buttons["저장"].tap()
        XCTAssertTrue(app.staticTexts["저장됨"].waitForExistence(timeout: 10), "커버만 바꾼 저장이 돌지 않음")

        app.navigationBars.buttons.firstMatch.tap()
        openPublishedPost(app)
        openInfoSheet(app)
        XCTAssertTrue(labeled(app, "커버 변경").waitForExistence(timeout: 5), "저장 뒤 다시 열어도 커버가 없음")
        shot("suggested-cover-after-save")
    }

    func testBodyImageBecomesLiveCoverOnSave() throws {
        let app = launch()
        openPublishedPost(app)
        _ = pasteImage(app)
        if app.buttons["키보드 내리기"].exists { app.buttons["키보드 내리기"].tap() }
        app.buttons["저장"].tap()
        XCTAssertTrue(coverToastAppears(app, within: 10), "저장해도 커버가 반영되지 않음")

        app.navigationBars.buttons.firstMatch.tap()
        openPublishedPost(app)
        openInfoSheet(app)
        XCTAssertTrue(labeled(app, "커버 변경").waitForExistence(timeout: 5), "저장 뒤 다시 열어도 커버가 없음")
        shot("live-cover-after-save")
    }
}
