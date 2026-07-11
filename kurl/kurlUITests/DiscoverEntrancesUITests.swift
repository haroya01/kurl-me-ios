//
//  DiscoverEntrancesUITests.swift
//  kurlUITests
//
//  발견 = 입구 모음(P3) — 기본 탭이 입구(지금 열려 있는 길 · 취향이 겹치는 큐레이터)로 서고,
//  칭찬받은 시간순 큐레이터 연결 흐름은 "최근" 탭에 그대로 보존되는지(회귀 0).
//

import XCTest

final class DiscoverEntrancesUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testEntrancesDefaultThenRecentPreservesTimeline() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "discover"]
        app.launch()

        // 기본 = 입구. 입구 섹션 두 머릿글이 서야 한다.
        let openPaths = app.staticTexts["지금 열려 있는 길"].firstMatch
        XCTAssertTrue(openPaths.waitForExistence(timeout: 15), "기본 입구 탭에 '지금 열려 있는 길'이 없음")
        let kindred = app.staticTexts["취향이 겹치는 큐레이터"].firstMatch
        XCTAssertTrue(kindred.waitForExistence(timeout: 5), "입구 탭에 '취향이 겹치는 큐레이터'가 없음")

        let entrances = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        entrances.name = "discover-entrances"
        entrances.lifetime = .keepAlways
        add(entrances)

        // "최근" 탭 = 보존된 시간순 큐레이터 연결 흐름. 세그먼트 버튼을 탭한다.
        let recent = app.buttons["최근"].firstMatch
        XCTAssertTrue(recent.waitForExistence(timeout: 5), "'최근' 세그먼트가 없음")
        recent.tap()

        // 최근 흐름의 컬렉션 eyebrow("…에 연결")이 서면 시간순 카드가 보존된 것.
        let connectedVerb = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '에 연결' OR label CONTAINS '길에 엮음'")).firstMatch
        XCTAssertTrue(
            connectedVerb.waitForExistence(timeout: 10),
            "최근 탭에 시간순 연결 카드가 없음 — 타임라인 회귀")

        let recentShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        recentShot.name = "discover-recent-preserved"
        recentShot.lifetime = .keepAlways
        add(recentShot)
    }
}
