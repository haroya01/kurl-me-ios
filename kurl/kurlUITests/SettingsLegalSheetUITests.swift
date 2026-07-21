//
//  SettingsLegalSheetUITests.swift
//  kurlUITests
//

import XCTest

/// 설정의 이용약관·개인정보처리방침이 앱 밖 외부 Safari 로 내쫓지 않고 로그인 화면과 같은
/// 인앱 사파리 시트로 열리는지. 외부 Safari 로 나가면 앱이 background 로 밀리므로
/// "탭 후에도 foreground 유지 + 앱 트리에 웹뷰 존재" 두 신호로 판정한다.
final class SettingsLegalSheetUITests: XCTestCase {
    func testTermsOpenInAppSafariSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "account"]
        app.launch()

        let settings = app.buttons["설정"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 15), "계정 탭에 설정 버튼이 없음")
        settings.tap()

        let terms = app.buttons["이용약관"].firstMatch
        XCTAssertTrue(terms.waitForExistence(timeout: 8), "설정에 이용약관 행이 없음")
        // 정책 행은 폴드 아래일 수 있다 — 히트 가능해질 때까지 끌어올린다.
        var attempts = 0
        while !terms.isHittable, attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
        terms.tap()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 10), "약관 탭 후 인앱 사파리 웹뷰가 안 뜸")
        XCTAssertEqual(app.state, .runningForeground, "약관이 외부 Safari 로 열려 앱이 background 로 밀림")
    }
}
