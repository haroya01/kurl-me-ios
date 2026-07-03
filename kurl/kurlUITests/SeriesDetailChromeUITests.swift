//
//  SeriesDetailChromeUITests.swift
//  kurlUITests
//

import XCTest

/// 시리즈 상세의 크롬 제목 규칙 — 마스트헤드 H1 이 제목의 주인이라, 로드된 뒤 상단 바에는
/// 같은 제목을 다시 띄우지 않는다(제목 중복 회귀 가드). simctl 로는 못 세우는 판정이라 여기서.
final class SeriesDetailChromeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMastheadOwnsTitleWithoutNavBarDuplicate() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--series", "honggildong/hexagonal", "--seed-read", "8001,8002"]
        app.launch()

        // 로드 완료 신호 — 주행동(이어 읽기) 버튼.
        let resume = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH '이어 읽기'")).firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 12), "시리즈 상세가 로드되지 않음")

        // 본문의 마스트헤드 제목은 있어야 하고(H1), 상단 바에는 같은 제목이 없어야 한다.
        XCTAssertTrue(
            app.staticTexts["헥사고날 전환기"].exists,
            "마스트헤드 제목(H1)이 본문에 없음")
        XCTAssertFalse(
            app.navigationBars.staticTexts["헥사고날 전환기"].exists,
            "상단 바에도 제목이 떠 마스트헤드와 제목이 두 번 겹침")
    }
}
