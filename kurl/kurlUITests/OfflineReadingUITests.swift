//
//  OfflineReadingUITests.swift
//  kurlUITests
//

import XCTest

/// 오프라인 폴백 — `--offline`(전 네트워크 즉사) + `--seed-offline`(기기 사본 픽스처)으로
/// 비행기 모드를 결정적으로 재현한다. 사본이 본문으로 서고 오프라인 배지가 보이면 합격.
final class OfflineReadingUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCachedPostRendersWithoutNetwork() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--offline", "--seed-offline", "--post", "offline-fixture/offline-post",
        ]
        app.launch()

        let title = app.staticTexts["오프라인 사본 검증 글"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10), "기기 사본이 본문으로 서지 않음")

        let body = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS '비행기 모드에서도'")).firstMatch
        XCTAssertTrue(body.exists, "사본 본문 블록이 렌더되지 않음")

        let badge = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS '연결되면 최신으로'")).firstMatch
        XCTAssertTrue(badge.exists, "오프라인 배지가 없음")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "offline-post"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// 사본이 없는 글은 오프라인에서 정직하게 실패 화면 — 빈 본문으로 위장하지 않는다.
    func testUncachedPostFailsHonestlyOffline() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--offline", "--post", "offline-fixture/never-cached"]
        app.launch()

        let failed = app.staticTexts["불러오지 못했습니다"].firstMatch
        XCTAssertTrue(failed.waitForExistence(timeout: 10), "오프라인 실패 상태가 안 보임")
    }
}
