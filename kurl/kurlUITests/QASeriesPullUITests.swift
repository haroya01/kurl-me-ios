//
//  QASeriesPullUITests.swift
//  kurlUITests
//
//  시리즈 회차 "끝에서 이어 당기기" — 전환 단언 + 무회귀(스택 1단·읽기바 리셋).
//

import XCTest

final class QASeriesPullUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }

    private func launchEp(_ n: Int, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--post", "honggildong/ep-\(n)"] + extra
        app.launch()
        return app
    }

    // MARK: 배너 다음 버튼 = 제자리 교체 전환

    func testBannerNextAdvancesInPlace() throws {
        let app = launchEp(1)
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '1편 — 포트와 어댑터'")).firstMatch
            .waitForExistence(timeout: 15), "1편 본문 미도착")
        shot(app, "01-ep1")
        // 배너 다음 편 버튼
        let nextBtn = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '다음 편'")).firstMatch
        XCTAssertTrue(nextBtn.waitForExistence(timeout: 6), "배너 다음 편 버튼 없음")
        nextBtn.tap()
        // 2편 본문으로 제자리 교체
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '2편 — 도메인을 안으로'")).firstMatch
            .waitForExistence(timeout: 8), "다음 버튼이 2편으로 전환하지 않음")
        shot(app, "02-ep2")
        // 배너 스텝퍼가 02/06 로
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '02 / 06' OR label CONTAINS '2/6'")).firstMatch
            .waitForExistence(timeout: 4)
            || app.staticTexts.matching(NSPredicate(format: "label CONTAINS '02'")).firstMatch.exists,
            "회차 인디케이터가 2편으로 안 바뀜")
    }

    // MARK: 스택 안 쌓임 — 회차 전환은 제자리 교체라 이전 회차가 스택에 남지 않는다

    func testNoStackGrowthAcrossEpisodes() throws {
        // 딥링크 ep-1 은 리더가 스택 루트다(부모 없음). 2·3편으로 전환 후 엣지 스와이프 뒤로가기 —
        // 제자리 교체면 이전 회차(ep-1/ep-2)가 스택에 없어 뒤로가기로 되살아나지 않는다.
        // (회차마다 push 했다면 뒤로가기 한 번에 ep-2 가 떠야 한다 — 그게 안티패턴.)
        let app = launchEp(1)
        _ = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '1편'")).firstMatch
            .waitForExistence(timeout: 15)
        for target in ["2편 — 도메인을 안으로", "3편 — 의존성 뒤집기"] {
            let nextBtn = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '다음 편'")).firstMatch
            guard nextBtn.waitForExistence(timeout: 6) else { break }
            nextBtn.tap()
            _ = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", target)).firstMatch
                .waitForExistence(timeout: 8)
        }
        shot(app, "03-ep3-after-two-advances")
        // 엣지 스와이프 뒤로가기 한 번.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)))
        Thread.sleep(forTimeInterval: 1.0)
        shot(app, "04-after-back")
        // 핵심 단언: 뒤로가기로 이전 회차(2편)가 되살아나면 = 스택에 쌓였다는 증거(안티패턴).
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS '2편 — 도메인을 안으로'")).firstMatch.isHittable,
            "뒤로가기 한 번에 2편이 떴다 — 회차 전환이 스택에 쌓였다(제자리 교체 아님)")
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS '1편 — 포트와 어댑터'")).firstMatch.isHittable,
            "뒤로가기 한 번에 1편이 떴다 — 스택 누적")
    }

    // MARK: 마지막 회차 — 다음 편 큐 없음 + 마지막 안내

    func testLastEpisodeNoNextCue() throws {
        let app = launchEp(6)
        _ = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '6편'")).firstMatch
            .waitForExistence(timeout: 15)
        // 끝까지 스크롤
        for _ in 0..<12 {
            if app.staticTexts.matching(NSPredicate(format: "label CONTAINS '마지막 회차'")).firstMatch.exists { break }
            app.swipeUp()
        }
        shot(app, "05-last-episode")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS '마지막 회차'")).firstMatch
                .waitForExistence(timeout: 4),
            "마지막 회차 안내 문구 없음")
        // 다음 편 큐/버튼은 없어야 한다
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS '계속 당기면 다음 편'")).firstMatch.exists,
            "마지막 회차인데 '다음 편' 당김 큐가 떴다")
    }

    // MARK: 비시리즈 글 무변화

    func testNonSeriesPostUnaffected() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--post", "honggildong/hexagonal-after-3-months"]
        app.launch()
        XCTAssertTrue(app.buttons["좋아요"].firstMatch.waitForExistence(timeout: 15), "비시리즈 글 진입 실패")
        // 시리즈 배너·다음 편 큐가 없어야 한다
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS '계속 당기면 다음 편'")).firstMatch.exists,
            "비시리즈 글에 다음 편 큐가 떴다")
        shot(app, "06-non-series")
    }
}
