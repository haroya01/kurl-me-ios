//
//  NotificationPolicyUITests.swift
//  kurlUITests
//

import XCTest

final class NotificationPolicyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func shot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testEachKindOfSenderHasItsOwnChoiceInSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "account"]
        app.launch()
        let settings = app.buttons["설정"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 15), "계정 탭에 설정 버튼이 없음")
        settings.tap()
        let row = app.buttons["settings.notificationPolicy"]
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<8 where !(row.exists && row.isHittable) {
            scroll.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "설정에 알림 거르기가 없음")
        row.tap()

        let notFollowing = app.buttons["policy.notFollowing"]
        XCTAssertTrue(notFollowing.waitForExistence(timeout: 8), "팔로우하지 않는 사람 줄이 없음")
        XCTAssertTrue(notFollowing.label.contains("거르기"), "목에서 거르기로 둔 값이 안 보임: \(notFollowing.label)")
        XCTAssertTrue(app.buttons["policy.privateMentions"].label.contains("거르기"), "개인 멘션 기본값이 거르기가 아님")

        let newAccounts = app.buttons["policy.newAccounts"]
        newAccounts.tap()
        let drop = app.buttons["버리기"].firstMatch
        XCTAssertTrue(drop.waitForExistence(timeout: 5), "받기·거르기·버리기 메뉴가 안 열림")
        drop.tap()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "identifier == 'policy.newAccounts' AND label CONTAINS '버리기'"))
                .firstMatch.waitForExistence(timeout: 5),
            "새 계정을 버리기로 바꾼 값이 남지 않음")
        shot("notification-policy")
    }

    func testKeptNoticesWaitAtopTheInboxAndAreAcceptedOrDropped() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "account"]
        app.launch()
        let bell = app.buttons["알림"].firstMatch
        XCTAssertTrue(bell.waitForExistence(timeout: 12), "계정 헤더에 알림 벨이 없음")
        bell.tap()

        let entry = app.buttons["notifications.filtered"]
        XCTAssertTrue(entry.waitForExistence(timeout: 12), "알림 맨 위에 걸러진 알림 줄이 없음")
        XCTAssertTrue(entry.label.contains("2명이 보낸 알림 4개"), "걸러진 사람·알림 수가 틀림: \(entry.label)")
        entry.tap()

        let promo = app.descendants(matching: .any)["filtered.row.promo_bot"]
        XCTAssertTrue(promo.waitForExistence(timeout: 8), "걸러진 알림에 promo_bot이 없음")
        XCTAssertTrue(promo.staticTexts["알림 3개"].exists, "보낸 알림 수가 안 보임")
        shot("filtered-notifications")
        promo.buttons["filtered.accept"].tap()
        XCTAssertTrue(promo.waitForNonExistence(timeout: 8), "받은 사람이 목록에 남음")

        let mina = app.descendants(matching: .any)["filtered.row.mina@mastodon.social"]
        mina.buttons["filtered.dismiss"].tap()
        XCTAssertTrue(
            app.staticTexts["걸러진 알림이 없어요"].waitForExistence(timeout: 8), "다 처리했는데 빈 화면이 아님")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(entry.waitForNonExistence(timeout: 8), "걸러진 알림이 없는데 맨 위 줄이 남음")
    }
}
