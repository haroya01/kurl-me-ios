//
//  FeedBellDeepLinkUITests.swift
//  kurlUITests
//

import XCTest

/// 피드 벨 경로의 인박스 딥링크 — 벨이 isPresented 목적지였을 때 인박스 안의 값 푸시(행·아바타)가
/// 목적지 대신 인박스를 한 번 더 열던 회귀를 막는다(계정 벨은 GraphNotificationsUITests 가 커버).
final class FeedBellDeepLinkUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// 피드 첫 화면의 벨로 인박스 진입.
    private func launchInboxViaFeedBell() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks"]
        app.launch()
        let bell = app.buttons["알림"].firstMatch
        XCTAssertTrue(bell.waitForExistence(timeout: 12), "피드 헤더에 알림 벨이 없음")
        bell.tap()
        return app
    }

    /// CONNECTED 행 탭 = 컬렉션 상세로 딥링크(인박스 재등장이 아니라).
    func testRowDeepLinksToCollection() throws {
        let app = launchInboxViaFeedBell()

        let connected = app.buttons
            .matching(NSPredicate(format: "label CONTAINS '엮었어요'")).firstMatch
        XCTAssertTrue(connected.waitForExistence(timeout: 12), "인박스에 CONNECTED 알림이 없음")
        connected.tap()

        // 컬렉션 101 "느린 사고"의 설명 문장 — 인박스 행엔 없어 오탐 없이 항해를 증명한다.
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS '빨리 답하지 않고'"))
                .firstMatch.waitForExistence(timeout: 8),
            "행 탭이 컬렉션 상세로 딥링크되지 않음")
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label CONTAINS '엮었어요'")).firstMatch.exists,
            "행 탭 후에도 인박스가 보임 — isPresented 재발화 회귀")
        shoot("feed-bell-row-collection")
    }

    /// 아바타 탭 = 행위자 프로필로 딥링크. '팔로우했어요' 행이 CONTAINS '팔로우' 에 걸리는
    /// 오탐이 있어, 정확 라벨(팔로우/팔로잉 캡슐)과 인박스 부재를 함께 단언한다.
    func testAvatarDeepLinksToProfile() throws {
        let app = launchInboxViaFeedBell()

        let avatar = app.buttons
            .matching(NSPredicate(format: "label ENDSWITH '프로필'")).firstMatch
        XCTAssertTrue(avatar.waitForExistence(timeout: 12), "인박스에 아바타(프로필) 링크가 없음")
        avatar.tap()

        let followCapsule = app.buttons
            .matching(NSPredicate(format: "label IN {'팔로우', '팔로잉'}")).firstMatch
        XCTAssertTrue(
            followCapsule.waitForExistence(timeout: 8),
            "아바타 탭이 작가 프로필로 딥링크되지 않음(팔로우 캡슐이 안 보임)")
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label CONTAINS '엮었어요'")).firstMatch.exists,
            "아바타 탭 후에도 인박스가 보임 — isPresented 재발화 회귀")
        shoot("feed-bell-avatar-profile")
    }
}
