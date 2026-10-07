//
//  DataExportUITests.swift
//  kurlUITests
//

import XCTest

final class DataExportUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testEachMastodonFileDownloadsIntoTheShareSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "account"]
        app.launch()
        let settings = app.buttons["설정"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 15), "계정 탭에 설정 버튼이 없음")
        settings.tap()
        let row = app.buttons["settings.dataExport"]
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<8 where !(row.exists && row.isHittable) {
            scroll.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "설정에 데이터 내보내기가 없음")
        row.tap()

        for kind in ["following", "blocks", "mutes", "domain-blocks", "bookmarks", "lists"] {
            XCTAssertTrue(app.buttons["export.\(kind)"].waitForExistence(timeout: 5), "\(kind) 내보내기 줄이 없음")
        }
        XCTAssertTrue(app.staticTexts["following_accounts.csv"].exists, "마스토돈 파일 이름이 안 보임")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "data-export"
        shot.lifetime = .keepAlways
        add(shot)

        app.buttons["export.following"].tap()
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(
            sheet.waitForExistence(timeout: 10) || app.navigationBars["UIActivityContentView"].waitForExistence(timeout: 2),
            "내려받은 파일로 공유 시트가 열리지 않음")
        let shared = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shared.name = "data-export-share"
        shared.lifetime = .keepAlways
        add(shared)
    }
}
