//
//  WebIntroUITests.swift
//  kurlUITests
//

import XCTest

/// 로그인 직후 1회 웹 안내 시트 — 개인화 주소가 뜨고, 탭하면 인앱 사파리, 확인으로 닫힌다.
final class WebIntroUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSheetShowsAddressOpensWebAndDismisses() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--screen", "webintro"]
        app.launch()

        // 개인화 주소(목 계정 honggildong)가 칩에 떠 있다.
        let address = app.buttons["내 블로그 웹 주소 열기"].firstMatch
        XCTAssertTrue(address.waitForExistence(timeout: 10), "주소 칩이 없음")
        XCTAssertTrue(address.label.contains("honggildong") || app.staticTexts["blog.kurl.me/@honggildong"].exists,
                      "개인화 주소가 아님")

        // 칩 탭 → 인앱 사파리(웹뷰)가 앱 안에서 뜬다(외부 이탈 없음).
        address.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10), "인앱 사파리가 안 뜸")
        XCTAssertEqual(app.state, .runningForeground, "외부 Safari 로 새어 나감")
        app.swipeDown(velocity: .fast)

        // 확인 → 시트 닫힘.
        let ok = app.buttons["확인"].firstMatch
        XCTAssertTrue(ok.waitForExistence(timeout: 6), "확인 버튼이 없음")
        ok.tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: ok)
        waitForExpectations(timeout: 5)
    }
}
