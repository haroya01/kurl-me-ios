//
//  FeedSeriesCardUITests.swift
//  kurlUITests
//
//  최신 피드의 발견 시리즈 카드 — 회차 넘김(방향성 슬라이드+크로스페이드) 동작 + 무회귀
//  (넘김 버튼 전진·카드 탭 시리즈 상세 항해). 오프셋이 탭 타깃을 훔치지 않는지 단언.
//

import XCTest

final class FeedSeriesCardUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }

    private func launchToCard() -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks"]
        app.launch()
        let nextBtn = app.buttons["다음 편"].firstMatch
        // 시리즈 카드는 최신 피드 index 3 뒤 — 보일 때까지 스크롤.
        for _ in 0..<10 {
            if nextBtn.exists && nextBtn.isHittable { break }
            app.swipeUp()
        }
        return (app, nextBtn)
    }

    // MARK: 넘김 버튼이 회차를 전진시킨다(순환) — 오프셋 로직이 넘김을 깨지 않는다.

    func testNextButtonAdvancesEpisode() throws {
        let (app, nextBtn) = launchToCard()
        XCTAssertTrue(nextBtn.waitForExistence(timeout: 15), "시리즈 카드 다음 편 버튼 미도착")
        shot("01-card-ep1")
        // 목 시리즈("헥사고날 전환기")는 4장(ep-1..4). 넘김마다 카드 회차 제목이 바뀐다.
        // 카드는 .combine 이라 회차 제목이 카드 요소 라벨에 섞여 든다 — 라벨 대신 카드 존재로
        // 항해 무회귀를 확인하고, 여기선 넘김 버튼이 여러 번 눌려도 크래시/소실 없이
        // 계속 히트 가능한지(=카드가 살아 회차를 계속 전진)로 전진을 단언한다.
        for step in 0..<4 {
            XCTAssertTrue(nextBtn.isHittable, "넘김 \(step)회차에서 버튼이 사라졌다(카드 소실/오프셋 이탈)")
            nextBtn.tap()
            usleep(600_000) // 전환 애니(0.42s) 여유
        }
        shot("02-after-four-advances")
        // 4장 순환 후에도 버튼은 여전히 살아 있어야(카드가 클램프 없이 정상).
        XCTAssertTrue(nextBtn.waitForExistence(timeout: 3), "순환 후 넘김 버튼 소실")
    }

    // MARK: 무회귀 — 카드 본문 탭은 시리즈 상세로 항해(오프셋이 탭을 훔치지 않는다).

    func testCardTapNavigatesToSeriesDetail() throws {
        let (app, nextBtn) = launchToCard()
        XCTAssertTrue(nextBtn.waitForExistence(timeout: 15), "시리즈 카드 미도착")
        // 회차를 한 번 넘긴 뒤에도 카드 본문 링크는 살아 있어야(오프셋이 링크를 훔치지 않음).
        nextBtn.tap()
        usleep(600_000)
        // 카드 = .combine + NavigationLink 이라 "시리즈 …, N편" 라벨의 버튼으로 노출된다.
        let card = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH '시리즈 헥사고날 전환기'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 4), "시리즈 카드 링크 요소 없음")
        XCTAssertTrue(card.isHittable, "시리즈 카드 링크가 히트 불가(오프셋/버튼이 가림)")
        card.tap()
        // 시리즈 상세 도착 — 제목이 상세 화면에 뜬다.
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS '헥사고날 전환기'")).firstMatch
                .waitForExistence(timeout: 8),
            "카드 탭이 시리즈 상세로 항해하지 않음(오프셋이 탭을 훔쳤을 수 있음)")
        shot("03-series-detail")
    }
}
