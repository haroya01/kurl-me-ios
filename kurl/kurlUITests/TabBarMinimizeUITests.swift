//
//  TabBarMinimizeUITests.swift
//  kurlUITests
//

import XCTest

/// 스크롤 내리면 하단 탭바가 통째로 사라지고(스레드식), 올리면 되돌아오는 커스텀 동작의
/// 회귀 가드. iOS 26/27.0 런타임은 네이티브 `.tabBarMinimizeBehavior` 를 안 태우고
/// (2026-06-13 실기기 확정) `.toolbar(.hidden, for: .tabBar)` 도 탭 루트에선 시스템 바를
/// 못 숨긴다(27 실측). 그래서 커스텀 FloatingTabBar 를 스크롤 방향으로 직접 숨겼다 되살린다.
/// simctl 은 터치를 못 넣으니 — 스크롤 제스처 검증은 이 UI 테스트가 유일한 자동화 경로다.
final class TabBarMinimizeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks"]
        app.launch()
        return app
    }

    /// 화면 중앙에서 위로 끄는 느린 팬(콘텐츠가 위로 = 아래로 읽는 중) — 플릭으로 인식돼
    /// 방향 판정을 건너뛰지 않게 손가락 팬에 가깝게 여러 번.
    private func scrollDown(_ app: XCUIApplication) {
        let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18))
        for _ in 0..<3 {
            center.press(forDuration: 0.06, thenDragTo: upper,
                         withVelocity: .default, thenHoldForDuration: 0.1)
        }
    }

    /// 위에서 아래로 끄는 팬(콘텐츠가 아래로 = 위로 되돌리는 중).
    private func scrollUp(_ app: XCUIApplication) {
        let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        for _ in 0..<3 {
            upper.press(forDuration: 0.06, thenDragTo: lower,
                        withVelocity: .default, thenHoldForDuration: 0.1)
        }
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// 스크롤다운 후 탭바가 사라지고, 스크롤업 후 되돌아오는지 — 탭바 아이콘의 존재/명중
    /// 가능 여부로 판정(숨김 = offset 으로 밀려나 hittable 아님 + accessibilityHidden).
    func testFeedScrollHidesAndRestoresTabBar() throws {
        let app = launch()

        // 카드가 실제로 뜬 뒤에 스크롤한다 — 콜드 스켈레톤에선 스크롤이 안 먹는다.
        let firstCard = app.scrollViews.buttons.firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 15), "피드 카드가 뜨지 않음")

        // 커스텀 바의 탭 = VoiceOver 라벨 달린 버튼. "발견" 은 스크롤 대상 카드와 안 겹치는
        // 안전한 탭바 프로브(피드 카드에 "피드" 라벨이 없어 유일하게 잡힌다).
        let discoverTab = app.buttons["발견"]
        XCTAssertTrue(discoverTab.waitForExistence(timeout: 8), "탭바(발견 버튼)가 없음")

        // before — 스크롤 전엔 탭바가 명중 가능.
        XCTAssertTrue(discoverTab.isHittable, "before: 탭바가 처음부터 보이지 않음")
        attach("before-scroll-tabbar-visible")

        // 스크롤다운 → 탭바가 사라진다(offset 132pt 로 밀려 hittable 아님).
        scrollDown(app)
        let hidden = NSPredicate(format: "isHittable == false")
        expectation(for: hidden, evaluatedWith: discoverTab)
        waitForExpectations(timeout: 5)
        attach("after-scrolldown-tabbar-hidden")
        XCTAssertFalse(discoverTab.isHittable, "after: 스크롤다운 후에도 탭바가 사라지지 않음")

        // 스크롤업 → 탭바가 되돌아온다.
        scrollUp(app)
        let shown = NSPredicate(format: "isHittable == true")
        expectation(for: shown, evaluatedWith: discoverTab)
        waitForExpectations(timeout: 5)
        attach("after-scrollup-tabbar-restored")
        XCTAssertTrue(discoverTab.isHittable, "restore: 스크롤업 후에도 탭바가 돌아오지 않음")
    }
}
