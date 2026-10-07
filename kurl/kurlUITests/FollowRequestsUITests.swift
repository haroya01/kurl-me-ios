//
//  FollowRequestsUITests.swift
//  kurlUITests
//

import XCTest

final class FollowRequestsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func shot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testRequestsWaitInTheInboxAndAreAnsweredThereOrInTheirList() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "account"]
        app.launch()
        let bell = app.buttons["알림"].firstMatch
        XCTAssertTrue(bell.waitForExistence(timeout: 12), "계정 헤더에 알림 벨이 없음")
        bell.tap()

        let entry = app.buttons["notifications.followRequests"]
        XCTAssertTrue(entry.waitForExistence(timeout: 12), "알림 맨 위에 팔로우 요청 줄이 없음")
        XCTAssertTrue(entry.label.contains("2"), "기다리는 요청 수가 2가 아님: \(entry.label)")
        let memberRow = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "sori님이 팔로우를 요청했어요")).firstMatch
        XCTAssertTrue(memberRow.exists, "이 서버 회원의 요청 알림이 없음")
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "carol@fosstodon.org님이 팔로우를 요청했어요"))
                .firstMatch.exists,
            "다른 서버 계정의 요청 알림이 없음")
        shot("follow-requests-inbox")

        app.buttons.matching(identifier: "followRequests.authorize").firstMatch.tap()
        XCTAssertTrue(
            memberRow.waitForNonExistence(timeout: 8), "승인한 요청 알림이 남아 있음")
        XCTAssertTrue(entry.label.contains("1"), "승인 뒤 요청 수가 줄지 않음: \(entry.label)")

        entry.tap()
        let remoteRow = app.descendants(matching: .any)["followRequests.row.carol@fosstodon.org"]
        XCTAssertTrue(remoteRow.waitForExistence(timeout: 8), "요청 화면에 다른 서버 계정이 없음")
        XCTAssertFalse(
            app.descendants(matching: .any)["followRequests.row.sori"].exists, "승인한 회원이 요청 화면에 남음")
        shot("follow-requests-list")

        remoteRow.buttons["followRequests.reject"].tap()
        XCTAssertTrue(
            app.staticTexts["기다리는 팔로우 요청이 없어요"].waitForExistence(timeout: 8), "다 답한 뒤 빈 화면이 아님")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(entry.waitForNonExistence(timeout: 8), "요청이 없는데 알림 맨 위 줄이 남음")
    }

    func testFollowingALockedAuthorLeavesARequestToWithdraw() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--author", "haneul"]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["author.locked"].waitForExistence(timeout: 12),
            "잠긴 작가 이름 옆에 자물쇠가 없음")
        let follow = app.buttons["follow.button"]
        XCTAssertTrue(follow.waitForExistence(timeout: 8), "팔로우 버튼이 없음")
        XCTAssertTrue(follow.label.contains("팔로우"), "처음 버튼이 팔로우가 아님: \(follow.label)")
        follow.tap()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "identifier == 'follow.button' AND label CONTAINS '요청함'"))
                .firstMatch.waitForExistence(timeout: 8),
            "잠긴 작가를 팔로우했는데 요청함이 아님")
        XCTAssertFalse(app.buttons["follow.bell"].exists, "요청만 했는데 새 노트 알림 종이 보임")
        shot("follow-requested")

        follow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let withdraw = app.buttons["요청 취소"]
        XCTAssertTrue(withdraw.waitForExistence(timeout: 8), "요청 취소 확인이 없음")
        withdraw.tap()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "identifier == 'follow.button' AND label CONTAINS '팔로우'"))
                .firstMatch.waitForExistence(timeout: 8),
            "요청을 취소했는데 팔로우로 돌아오지 않음")
    }

    func testTheLockLivesInProfileEditAndWarnsThatUnlockingLetsEveryoneIn() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--screen", "profile-edit"]
        app.launch()

        let lock = app.switches["profile.locked"]
        XCTAssertTrue(app.navigationBars["프로필 편집"].waitForExistence(timeout: 12), "프로필 편집이 열리지 않음")
        for _ in 0..<4 where !lock.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(lock.waitForExistence(timeout: 5), "프로필 편집에 팔로우 직접 승인 토글이 없음")
        XCTAssertTrue(
            (lock.value as? String) == "1" || lock.isSelected, "잠긴 목 계정인데 토글이 꺼져 있음")
        lock.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(
            app.staticTexts["끄면 기다리던 팔로우 요청이 모두 승인돼요."].waitForExistence(timeout: 5),
            "잠금을 풀 때 기다리던 요청이 승인된다는 안내가 없음")
        shot("profile-lock-off")
    }
}
