//
//  ComposeRecoveryUITests.swift
//  kurlUITests
//
//  유실 보호 실동작 — 오프라인(저장 실패) 상태로 본문을 치고 앱을 강제 종료한 뒤 다시 열면,
//  기기 금고의 "저장되지 못한 본문"이 복구 제안으로 돌아오는지. 세션이 죽어도 강제 종료돼도
//  쓰던 글을 잃지 않는다는 출시 게이트의 실증.
//

import XCTest

final class ComposeRecoveryUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testOfflineTypingSurvivesForceQuitAndOffersRecovery() throws {
        // 1) 오프라인 시뮬레이션(--offline) — 자동저장·플러시가 전부 실패하는 세계.
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--offline", "--tab", "write", "--open", "compose", "--editor", "v2"]
        app.launch()

        let title = app.textFields["제목"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        title.tap()
        title.typeText("Recovery draft")

        let runway = app.buttons["본문 이어 쓰기"].firstMatch
        if runway.waitForExistence(timeout: 4), runway.isHittable { runway.tap() }
        Thread.sleep(forTimeInterval: 0.5)
        app.typeText("offline body that must survive")
        // 금고 스태시 디바운스(0.8s)가 눕힐 시간.
        Thread.sleep(forTimeInterval: 2.0)

        // 2) 강제 종료 — 이탈 플러시도 오프라인이라 실패한다(기기 금고만 남는다).
        app.terminate()

        // 3) 정상(온라인 목) 재실행 → 새 글 컴포즈 → 복구 제안이 떠야 한다.
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["--mocks", "--tab", "write", "--open", "compose", "--editor", "v2"]
        relaunched.launch()

        let alert = relaunched.alerts["저장되지 못한 본문이 있어요"]
        XCTAssertTrue(alert.waitForExistence(timeout: 15), "복구 제안 알럿이 안 뜸")
        alert.buttons["이어서 쓰기"].tap()

        // 4) 본문·제목이 되살아나고, 온라인이므로 자동저장 배지까지 선다.
        let restored = relaunched.textViews.containing(
            NSPredicate(format: "value CONTAINS %@", "offline body that must survive")).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 10), "복구된 본문이 캔버스에 없음")
        XCTAssertEqual(relaunched.textFields["제목"].value as? String, "Recovery draft")
        XCTAssertTrue(
            relaunched.buttons["저장 상태 보기"].waitForExistence(timeout: 15),
            "복구 후 자동저장이 안 돎")
    }
}
