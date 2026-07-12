//
//  GraphNotificationsUITests.swift
//  kurlUITests
//

import XCTest

/// 연결 그래프 알림(CONNECTED·PATH_GREW) 검증 — 인박스 렌더, 컬렉션 딥링크, 선호 토글.
/// `simctl` 로는 탭이 안 되는 경로(인박스 도달·행 탭·설정 진입)를 XCUITest 로 밟아 스크린샷 첨부.
///
/// 실행:
///   xcodebuild test -scheme kurl -only-testing:kurlUITests/GraphNotificationsUITests \
///     -destination 'platform=iOS Simulator,id=<udid>'
///
/// `--mocks` 면 MockBackend 가 CONNECTED(컬렉션 101)·PATH_GREW(PATH 104) 픽스처를 내주므로
/// 실서버 없이 결정론적으로 렌더된다.
final class GraphNotificationsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func rowButton(_ app: XCUIApplication, contains label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }

    /// 계정 탭에서 알림 인박스로 — 헤더의 벨(값 기반 링크)을 눌러 연다. 값 링크로 밀어야 인박스
    /// 안의 딥링크(글·컬렉션)가 같은 스택에서 이어 밀린다(디버그 `--open` 은 isPresented 라 딥링크 불가).
    private func launchInbox() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "account"]
        app.launch()
        let bell = app.buttons["알림"].firstMatch
        XCTAssertTrue(bell.waitForExistence(timeout: 12), "계정 헤더에 알림 벨이 없음")
        bell.tap()
        return app
    }

    /// 인박스에 두 그래프 알림이 선다 — CONNECTED(회원 글이 컬렉션에 엮임)·PATH_GREW(엮인 길에 새 글).
    func testGraphNotificationsRender() throws {
        let app = launchInbox()

        let connected = app.buttons
            .matching(NSPredicate(format: "label CONTAINS '엮었어요'")).firstMatch
        XCTAssertTrue(connected.waitForExistence(timeout: 12), "인박스에 CONNECTED 알림이 없음")
        if !connected.isHittable { app.swipeUp() }

        let pathGrew = app.buttons
            .matching(NSPredicate(format: "label CONTAINS '이어졌어요'")).firstMatch
        XCTAssertTrue(pathGrew.waitForExistence(timeout: 8), "인박스에 PATH_GREW 알림이 없음")

        // 컬렉션 이름이 문장에 박혀 온다 — 카피가 collectionName 을 실제로 끼웠는지 확인.
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS '느린 사고'")).firstMatch.exists,
            "CONNECTED 카피에 컬렉션 이름이 없음")
        shoot("graph-notifications-inbox")
    }

    /// CONNECTED 행 탭 = 컬렉션 상세로 딥링크(글·작가가 아니라 엮인 맥락으로).
    func testConnectedDeepLinksToCollection() throws {
        let app = launchInbox()

        let connected = app.buttons
            .matching(NSPredicate(format: "label CONTAINS '엮었어요'")).firstMatch
        XCTAssertTrue(connected.waitForExistence(timeout: 12), "인박스에 CONNECTED 알림이 없음")
        connected.tap()

        // CollectionDetailView 도달 — 컬렉션 설명·연결 이유는 상세에만 있다(인박스 행엔 없어
        // 오탐 없이 항해를 증명한다). 컬렉션 101 "느린 사고"의 설명 문장으로 단언.
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS '빨리 답하지 않고'"))
                .firstMatch.waitForExistence(timeout: 8),
            "CONNECTED 탭이 컬렉션 상세로 딥링크되지 않음(설명이 안 보임)")
        shoot("graph-notification-collection-deeplink")
    }

    /// 선호 화면에 그래프 토글 2종이 선다(기본 켜짐) — 계정 톱니 → 알림 종류.
    func testGraphPreferenceToggles() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "account"]
        app.launch()

        let gear = app.buttons["설정"].firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 12), "계정 탭에 설정 버튼이 없음")
        gear.tap()

        let row = rowButton(app, contains: "알림 종류")
        XCTAssertTrue(row.waitForExistence(timeout: 8), "설정에 '알림 종류' 행이 없음")
        if !row.isHittable { app.swipeUp() }
        row.tap()

        let connectedToggle = app.switches
            .matching(NSPredicate(format: "label CONTAINS '컬렉션에 엮'")).firstMatch
        XCTAssertTrue(connectedToggle.waitForExistence(timeout: 8), "CONNECTED 토글이 없음")
        if !connectedToggle.isHittable { app.swipeUp() }
        let pathToggle = app.switches
            .matching(NSPredicate(format: "label CONTAINS '새 글이 이어질'")).firstMatch
        XCTAssertTrue(pathToggle.waitForExistence(timeout: 4), "PATH_GREW 토글이 없음")

        // 두 그래프 토글은 목 기본값 = 켜짐(on).
        XCTAssertEqual(connectedToggle.value as? String, "1", "CONNECTED 토글 기본값이 on 이 아님")
        XCTAssertEqual(pathToggle.value as? String, "1", "PATH_GREW 토글 기본값이 on 이 아님")
        shoot("graph-notification-preferences")
    }
}
