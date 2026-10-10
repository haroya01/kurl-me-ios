//
//  ComposeEditConflictUITests.swift
//  kurlUITests
//
//  글 동시 편집 충돌 — 목 백엔드가 `--mock-remote-edit <id>` 로 "다른 기기"의 편집을 흉내 내면, 이 기기의 저장은
//  버전이 어긋나 409 를 받고 자동저장을 멈춘 채 두 갈래를 묻는다. 최신으로 불러오면 내 내용은 기기에 남아 다시 열 때
//  되살릴 수 있고, 내 내용으로 덮으면 저장된다. 앱이 앞으로 돌아왔을 때 고친 게 없으면 조용히 최신본으로 바뀐다.
//

import XCTest

final class ComposeEditConflictUITests: XCTestCase {

    private let remoteParagraph = "다른 기기에서 고친 문단."

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(remoteEdit postId: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--mocks", "--tab", "write", "--editor", "v2", "--reset-recovery", "--mock-remote-edit", postId,
        ]
        app.launch()
        return app
    }

    private func openDraft(_ app: XCUIApplication) {
        let row = app.staticTexts["목 초안 — 헥사고날 정리"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "스튜디오에 목 초안이 안 보임")
        row.tap()
    }

    private func block(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.textViews.containing(NSPredicate(format: "value CONTAINS %@", text)).firstMatch
    }

    private func shot(_ name: String) {
        let s = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

    private func typeIntoDraftAndWaitForConflict(_ app: XCUIApplication) -> XCUIElement {
        openDraft(app)
        let paragraph = block(app, containing: "포트와 어댑터.")
        XCTAssertTrue(paragraph.waitForExistence(timeout: 12), "초안 본문 로드 실패")
        paragraph.tap()
        app.typeText(" 내가 고친 줄.")
        let alert = app.alerts["다른 기기에서 이 글을 고쳤어요"]
        XCTAssertTrue(alert.waitForExistence(timeout: 15), "버전이 어긋난 저장인데 충돌 안내가 안 뜸")
        return alert
    }

    func testLoadingLatestKeepsMyTextRecoverableOnTheDevice() throws {
        let app = launch(remoteEdit: "9001")
        let alert = typeIntoDraftAndWaitForConflict(app)
        shot("conflict-alert")
        alert.buttons["최신으로 불러오기"].tap()

        XCTAssertTrue(block(app, containing: remoteParagraph).waitForExistence(timeout: 10), "최신본으로 안 바뀜")
        XCTAssertFalse(block(app, containing: "내가 고친 줄").exists, "최신으로 불러왔는데 내 편집이 남음")
        shot("conflict-loaded-latest")

        app.navigationBars.buttons.firstMatch.tap()
        openDraft(app)
        let recovery = app.alerts["저장되지 못한 본문이 있어요"]
        XCTAssertTrue(recovery.waitForExistence(timeout: 10), "밀려난 내 내용을 다시 열 때 되살리자고 하지 않음")
        recovery.buttons["이어서 쓰기"].tap()
        XCTAssertTrue(block(app, containing: "내가 고친 줄").waitForExistence(timeout: 10), "보관한 내 내용이 안 돌아옴")
        shot("conflict-recovered-mine")
    }

    func testKeepingMineOverwritesAndSaves() throws {
        let app = launch(remoteEdit: "9001")
        let alert = typeIntoDraftAndWaitForConflict(app)
        alert.buttons["내 내용으로 덮기"].tap()

        XCTAssertTrue(app.staticTexts["저장됨"].waitForExistence(timeout: 15), "덮어 저장이 안 됨")
        shot("conflict-overwritten")

        app.navigationBars.buttons.firstMatch.tap()
        openDraft(app)
        XCTAssertTrue(block(app, containing: "내가 고친 줄").waitForExistence(timeout: 12), "덮은 내 내용이 서버에 없음")
        XCTAssertFalse(block(app, containing: remoteParagraph).exists, "덮었는데 다른 기기 문단이 남음")
        XCTAssertFalse(app.alerts["다른 기기에서 이 글을 고쳤어요"].exists)
    }

    func testLivePostSaveAsksTheSameWay() throws {
        let app = launch(remoteEdit: "9002")
        let manage = app.buttons["발행된 목 글 관리"]
        XCTAssertTrue(manage.waitForExistence(timeout: 15), "스튜디오에 발행된 목 글이 없음")
        manage.tap()
        app.buttons["편집"].tap()
        let paragraph = app.textViews.containing(NSPredicate(format: "value == %@", "본문.")).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 12), "발행 글 본문 로드 실패")
        paragraph.tap()
        app.typeText(" 고침.")
        if app.buttons["키보드 내리기"].exists { app.buttons["키보드 내리기"].tap() }
        app.buttons["저장"].tap()

        let alert = app.alerts["다른 기기에서 이 글을 고쳤어요"]
        XCTAssertTrue(alert.waitForExistence(timeout: 15), "라이브 글 저장 충돌인데 안내가 안 뜸")
        alert.buttons["내 내용으로 덮기"].tap()
        XCTAssertTrue(app.staticTexts["저장됨"].waitForExistence(timeout: 15), "라이브 글 덮어 저장이 안 됨")
    }

    func testReturningToTheAppReloadsAnUntouchedPostEditedElsewhere() throws {
        let app = launch(remoteEdit: "9001")
        openDraft(app)
        XCTAssertTrue(block(app, containing: "포트와 어댑터.").waitForExistence(timeout: 12), "초안 본문 로드 실패")
        XCTAssertFalse(block(app, containing: remoteParagraph).exists)

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1)
        app.activate()

        XCTAssertTrue(
            block(app, containing: remoteParagraph).waitForExistence(timeout: 10),
            "앞으로 돌아왔는데 다른 기기 편집을 안 읽어 옴")
        XCTAssertFalse(app.alerts["다른 기기에서 이 글을 고쳤어요"].exists, "고친 게 없는데 충돌을 물음")
        shot("foreground-refreshed")
    }
}
