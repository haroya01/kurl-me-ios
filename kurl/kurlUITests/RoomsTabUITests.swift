//
//  RoomsTabUITests.swift
//  kurlUITests
//

import XCTest

final class RoomsTabUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "rooms"]
        app.launch()
        return app
    }

    func testMoreOpensThatRoom() {
        let app = launch()
        let more = app.buttons["rooms.more.1"]
        XCTAssertTrue(more.waitForExistence(timeout: 12), "동아리 사람들 덩어리에 더 보기가 없음")
        more.tap()
        XCTAssertTrue(app.buttons["room.compose"].waitForExistence(timeout: 6), "더 보기를 눌러도 방이 열리지 않음")
        XCTAssertTrue(app.navigationBars["동아리 사람들"].exists, "다른 방이 열림")
    }

    func testRoomNameOpensThatRoom() {
        let app = launch()
        let header = app.buttons["rooms.row.5"]
        XCTAssertTrue(header.waitForExistence(timeout: 12), "고정한 방 머리가 없음")
        header.tap()
        XCTAssertTrue(app.navigationBars["우리 가족"].waitForExistence(timeout: 6), "방 이름을 눌러도 그 방이 열리지 않음")
    }

    func testAcceptingAnInvitationOpensTheRoom() {
        let app = launch()
        let accept = app.buttons["rooms.invitation.accept.4"]
        XCTAssertTrue(accept.waitForExistence(timeout: 12), "받은 초대가 없음")
        accept.tap()
        XCTAssertTrue(app.navigationBars["주말 등산 모임"].waitForExistence(timeout: 6), "들어가기를 눌러도 방이 열리지 않음")
    }

    func testAllShowsEveryRoomInOneStream() {
        let app = launch()
        let all = app.buttons["segment.all"]
        XCTAssertTrue(all.waitForExistence(timeout: 12), "전체 보기 스위치가 없음")
        all.tap()
        let line = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "대학 동기 방에서")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 6), "전체 보기에 다른 방 글이 이어지지 않음")
        XCTAssertFalse(app.buttons["rooms.more.1"].exists, "전체 보기에 방별 덩어리가 남아 있음")
    }

    func testOwnerRenamesTheRoomFromSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "rooms", "--room", "1", "--room-sheet", "settings"]
        app.launch()
        let field = app.textFields["roomSettings.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 12), "방장 설정에 이름 칸이 없음")
        field.tap()
        field.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        field.typeText("새 동아리")
        app.buttons["roomSettings.saveName"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["새 동아리"].waitForExistence(timeout: 6), "이름을 바꿔도 방 제목이 그대로")
    }
}
