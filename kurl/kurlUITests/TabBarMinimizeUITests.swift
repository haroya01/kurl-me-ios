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

    /// 설정 루트로 들어가면 커스텀 하단바가 접히고, 탭 루트로 pop 하면 되돌아온다 — iOS 관습이자,
    /// 바에 가려 하단 행(회원 탈퇴)이 도달 불가하던 자리. 탭바 프로브 = "발견" 버튼(설정 콘텐츠와
    /// 라벨이 안 겹친다).
    func testSettingsFoldsTabBarAndRestoresOnBack() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "account"]
        app.launch()

        let discoverTab = app.buttons["발견"]
        XCTAssertTrue(discoverTab.waitForExistence(timeout: 15), "계정 탭에 탭바가 없음")
        XCTAssertTrue(discoverTab.isHittable, "계정 루트에서 탭바가 처음부터 안 보임")

        // 설정 진입 → 바가 접힌다.
        let settings = app.buttons["설정"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 8), "계정 탭에 설정 버튼이 없음")
        settings.tap()
        expectation(for: NSPredicate(format: "isHittable == false"), evaluatedWith: discoverTab)
        waitForExpectations(timeout: 5)
        attach("settings-root-tabbar-folded")
        XCTAssertFalse(discoverTab.isHittable, "설정 루트에서 하단바가 접히지 않음")

        // 설정 → 탭 루트로 pop → 바가 돌아온다. isHittable 은 계정 루트에서 밑으로 흐르는 글
        // 카드가 바 영역과 겹쳐 프론트모스트 판정이 흔들리므로(바는 그려져 있어도 카드가 히트
        // 포인트를 가로챈다), 되살아난 바를 실제로 눌러 항해가 되는지로 판정한다 — 발견 탭을
        // 눌러 설정 진입점(gearshape)이 사라지는 발견 표면으로 넘어가면 바가 살아난 것.
        app.navigationBars.buttons.firstMatch.tap()
        expectation(for: NSPredicate(format: "exists == true"), evaluatedWith: discoverTab)
        waitForExpectations(timeout: 5)
        attach("settings-dismissed-tabbar-restored")
        assertTabBarNavigates(app, discoverTab: discoverTab)
    }

    /// 되살아난 하단바가 실제로 동작하는지 — 발견 탭을 눌러(좌표 탭으로 겹침 무관) 발견 표면으로
    /// 넘어갔음을 계정 전용 진입점(gearshape 설정 버튼)의 소멸로 확인한다.
    private func assertTabBarNavigates(_ app: XCUIApplication, discoverTab: XCUIElement) {
        XCTAssertTrue(discoverTab.exists, "복귀 후 하단바(발견 버튼)가 트리에 없음")
        discoverTab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let gear = app.buttons["설정"].firstMatch
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: gear)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(gear.exists, "발견 탭을 눌렀는데 계정 표면(설정 버튼)이 그대로 — 하단바가 안 살아남")
    }

    /// 설정 안 하위 푸시(차단한 사용자)로 더 들어가도 하단바 접힘이 유지되고, 하위→설정→탭 루트로
    /// 되돌아 나오면 바가 돌아온다 — iOS 27 은 자식 푸시에 부모 onDisappear 를 태워 부모만의
    /// 접힘이 풀리므로 하위 화면에도 접힘을 건다(집합 토큰이라 순서가 뒤엉켜도 안정적으로 복귀).
    func testSettingsChildKeepsTabBarFoldedAndRestores() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "account"]
        app.launch()

        let discoverTab = app.buttons["발견"]
        XCTAssertTrue(discoverTab.waitForExistence(timeout: 15), "계정 탭에 탭바가 없음")

        let settings = app.buttons["설정"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 8), "계정 탭에 설정 버튼이 없음")
        settings.tap()
        expectation(for: NSPredicate(format: "isHittable == false"), evaluatedWith: discoverTab)
        waitForExpectations(timeout: 5)

        let blocked = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '차단한 사용자'")).firstMatch
        XCTAssertTrue(blocked.waitForExistence(timeout: 5), "설정에 차단한 사용자 행이 없음")
        blocked.tap()
        Thread.sleep(forTimeInterval: 0.8)
        attach("settings-child-tabbar-folded")
        XCTAssertFalse(discoverTab.isHittable, "설정 하위 푸시(차단 목록)에서 하단바가 다시 나타남")

        // 하위 → 설정 → 탭 루트로 끝까지 되돌아 나온다 — 각 pop 사이를 넉넉히 두어
        // onAppear·onDisappear 가 뒤엉키지 않게(사람 손 속도).
        app.navigationBars.buttons.firstMatch.tap()
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertFalse(discoverTab.isHittable, "차단 목록에서 설정으로 돌아오니 하단바가 나타남")
        app.navigationBars.buttons.firstMatch.tap()
        expectation(for: NSPredicate(format: "exists == true"), evaluatedWith: discoverTab)
        waitForExpectations(timeout: 5)
        attach("settings-child-dismissed-tabbar-restored")
        assertTabBarNavigates(app, discoverTab: discoverTab)
    }
}
