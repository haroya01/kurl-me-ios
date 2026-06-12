//
//  TabBarMinimizeUITests.swift
//  kurlUITests
//

import XCTest

/// 탭바 최소화(.tabBarMinimizeBehavior(.onScrollDown)) 회귀 가드.
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

    /// 스크롤 내리면(콘텐츠 위로 스와이프) 바가 줄어드는지 — 프레임 폭으로 판정.
    /// 26.0.x·27.0 베타1 런타임은 "시뮬·실기기 모두" tabBarMinimizeBehavior 자체가 죽어
    /// 있다(2026-06-13 실기기 iPhone Air 에서 교과서 Tab+ScrollView 최소 재현으로 확정 —
    /// 27 SDK 링크 바이너리만 안 태우고, 26 SDK 스토어 앱은 같은 폰에서 동작). 그래서
    /// 깨진 런타임에선 "줄면 pass, 안 줄면 skip" — OS 가 고쳐지는 베타부터 자동 단정.
    private func assertMinimizes(_ app: XCUIApplication, surface: String) throws {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let runtimeBroken = version.minorVersion == 0
            && (version.majorVersion == 26 || version.majorVersion == 27)
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "\(surface): 탭바 자체가 없음")
        let before = tabBar.frame
        print("TABBAR[\(surface)] before: \(before)")

        // 빠른 swipe 는 플릭으로 인식돼 최소화 트리거를 건너뛸 수 있다 —
        // 손가락 팬에 가까운 느린 드래그로 화면 중앙에서 위로 끈다.
        let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22))
        center.press(forDuration: 0.05, thenDragTo: upper,
                     withVelocity: .default, thenHoldForDuration: 0.1)
        print("TABBAR[\(surface)] mid: \(tabBar.frame)")
        center.press(forDuration: 0.05, thenDragTo: upper,
                     withVelocity: .default, thenHoldForDuration: 0.1)
        print("TABBAR[\(surface)] mid2: \(tabBar.frame)")
        Thread.sleep(forTimeInterval: 1.2)

        let after = tabBar.frame
        print("TABBAR[\(surface)] after: \(after)")

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "after-scroll-\(surface)"
        attachment.lifetime = .keepAlways
        add(attachment)

        // 최소화되면 5-아이콘 바가 한 점(검색 분리 시 두 점)으로 줄어 폭이 크게 준다.
        let minimized = after.width < before.width * 0.7
        if minimized { return }
        if runtimeBroken {
            throw XCTSkip("\(surface): iOS \(version.majorVersion).\(version.minorVersion) " +
                          "런타임은 최소화 자체가 깨져 있어 판정 불가 (측정 minimized=false)")
        }
        XCTAssertTrue(minimized, "\(surface): 스크롤 후에도 탭바 폭이 줄지 않음 — 최소화 미동작")
    }

    func testFeedMinimizesTabBar() throws {
        let app = launch()
        try assertMinimizes(app, surface: "feed")
    }


    /// 피드 ZStack 이 아닌 평범한 푸시 화면(글 상세)에서도 줄어드는지.
    func testPostDetailMinimizesTabBar() throws {
        let app = launch()
        let firstCard = app.scrollViews.buttons.firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 10), "피드 카드 없음")
        // 입장 스태거(QuietAppear) 페이드 동안은 탭이 박히지 않는다 — 히터블까지 기다린다.
        var waited = 0.0
        while !firstCard.isHittable, waited < 4 {
            Thread.sleep(forTimeInterval: 0.2)
            waited += 0.2
        }
        firstCard.tap()
        Thread.sleep(forTimeInterval: 2)
        try assertMinimizes(app, surface: "post-detail")
    }
}
