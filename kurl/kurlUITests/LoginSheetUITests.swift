//
//  LoginSheetUITests.swift
//  kurlUITests
//

import XCTest

/// 비로그인 로그인 표면은 시트 하나 — 글쓰기 탭은 탭을 바꾸지 않고 시트를 띄우고,
/// 계정 탭은 빈 상태의 "로그인"으로 같은 시트를 연다.
final class LoginSheetUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func loginSheet(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "login.sheet").firstMatch
    }

    private func dismissSheet(_ app: XCUIApplication) {
        let start = loginSheet(app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
    }

    func testGuestWriteTabOpensTheLoginSheetWithoutSwitchingTabs() throws {
        let app = launch(["--mocks", "--logged-out", "--screen", "none"])
        let writeTab = app.buttons["글쓰기"]
        XCTAssertTrue(writeTab.waitForExistence(timeout: 15), "탭바(글쓰기 버튼)가 없음")
        XCTAssertTrue(app.buttons["tab.menu"].isSelected, "시작 탭이 피드가 아님")

        writeTab.tap()

        XCTAssertTrue(loginSheet(app).waitForExistence(timeout: 5), "글쓰기 탭에서 로그인 시트가 뜨지 않음")
        XCTAssertTrue(app.staticTexts["글을 쓰려면 로그인하세요"].exists, "시트 문구가 글쓰기 맥락이 아님")
        XCTAssertTrue(app.buttons["Google로 계속하기"].exists, "시트에 Google 버튼이 없음")
        attach("guest-write-sheet")

        dismissSheet(app)
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: loginSheet(app))
        waitForExpectations(timeout: 5)

        XCTAssertTrue(app.buttons["tab.menu"].isSelected, "시트를 닫았는데 보던 탭(피드)이 아님")
        XCTAssertFalse(app.buttons["글쓰기"].isSelected, "비로그인인데 글쓰기 탭으로 넘어감")
        XCTAssertFalse(app.staticTexts["로그인하지 않았어요"].exists, "글쓰기 탭 화면이 열림")
        attach("guest-write-after-dismiss")
    }

    func testSigningInFromTheWriteSheetOpensTheStudio() throws {
        let app = launch(["--mocks", "--logged-out", "--screen", "none"])
        let writeTab = app.buttons["글쓰기"]
        XCTAssertTrue(writeTab.waitForExistence(timeout: 15), "탭바(글쓰기 버튼)가 없음")
        writeTab.tap()

        let google = app.buttons["Google로 계속하기"]
        XCTAssertTrue(google.waitForExistence(timeout: 5), "로그인 시트가 뜨지 않음")
        google.tap()

        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: loginSheet(app))
        waitForExpectations(timeout: 8)

        if app.buttons["내 블로그 웹 주소 열기"].waitForExistence(timeout: 3) {
            app.buttons["확인"].firstMatch.tap()
        }

        XCTAssertTrue(app.buttons["새 글 쓰기"].waitForExistence(timeout: 8), "로그인했는데 스튜디오가 열리지 않음")
        XCTAssertTrue(app.buttons["글쓰기"].isSelected, "로그인했는데 글쓰기 탭이 아님")
        attach("guest-write-signed-in-studio")
    }

    func testGuestAccountTabShowsTheEmptyStateAndOpensTheSameSheet() throws {
        let app = launch(["--mocks", "--logged-out", "--screen", "none", "--tab", "account"])
        XCTAssertTrue(app.staticTexts["로그인하지 않았어요"].waitForExistence(timeout: 15), "계정 탭 빈 상태 제목이 없음")
        XCTAssertTrue(app.staticTexts["내 글과 노트, 라이브러리가 여기 모여요."].exists, "계정 탭 빈 상태 설명이 없음")
        XCTAssertTrue(app.buttons["설정"].exists, "설정 톱니가 없음")
        XCTAssertFalse(app.buttons["Google로 계속하기"].exists, "계정 탭 화면에 로그인 버튼 묶음이 그대로 있음")
        attach("guest-account-empty")

        app.buttons["로그인"].firstMatch.tap()

        XCTAssertTrue(loginSheet(app).waitForExistence(timeout: 5), "계정 탭 로그인 버튼이 로그인 시트를 열지 않음")
        XCTAssertTrue(app.staticTexts["kurl에 로그인하세요"].exists, "시트 문구가 계정 맥락이 아님")
        XCTAssertTrue(app.buttons["Google로 계속하기"].exists, "시트에 Google 버튼이 없음")
        attach("guest-account-sheet")
    }

    func testSignedInWriteTabOpensTheStudioDirectly() throws {
        let app = launch(["--mocks", "--screen", "none"])
        let writeTab = app.buttons["글쓰기"]
        XCTAssertTrue(writeTab.waitForExistence(timeout: 15), "탭바(글쓰기 버튼)가 없음")
        writeTab.tap()

        XCTAssertTrue(app.buttons["새 글 쓰기"].waitForExistence(timeout: 8), "로그인 상태인데 스튜디오가 열리지 않음")
        XCTAssertTrue(app.buttons["글쓰기"].isSelected, "로그인 상태인데 글쓰기 탭이 아님")
        XCTAssertFalse(loginSheet(app).exists, "로그인 상태인데 로그인 시트가 뜸")
    }
}
