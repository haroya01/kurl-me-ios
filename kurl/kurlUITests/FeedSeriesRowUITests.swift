//
//  FeedSeriesRowUITests.swift
//  kurlUITests
//
//  최신 피드에 끼는 발견 시리즈는 글과 같은 한 행이다 — 넘김 버튼 없이, 행 탭이 시리즈 상세로 간다.
//

import XCTest

final class FeedSeriesRowUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testSeriesRowOpensSeriesDetail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks"]
        app.launch()

        let row = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH '시리즈 헥사고날 전환기'")).firstMatch
        for _ in 0..<10 {
            if row.exists && row.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 15), "시리즈 행이 피드에 없음")
        XCTAssertFalse(app.buttons["다음 편"].exists, "시리즈가 아직 넘김 카드로 그려진다")
        shot("01-series-row")

        row.tap()
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS '헥사고날 전환기'")).firstMatch
                .waitForExistence(timeout: 8),
            "시리즈 행 탭이 시리즈 상세로 항해하지 않음")
        shot("02-series-detail")
    }
}
