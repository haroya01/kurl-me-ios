//
//  SignedInScreensUITests.swift
//  kurlUITests
//

import XCTest

/// 로그인(mock) 딥 화면 캡처 — `simctl` 로는 탭·스크롤이 안 되는 게이트 화면(For You·내 하이라이트·
/// 읽기 기록)을 XCUITest 로 도달해 스크린샷 첨부한다. 절제 패스의 시각 검증을 자동화하는 정공법.
///
/// 실행:
///   xcodebuild test -scheme kurl -only-testing:kurlUITests/SignedInScreensUITests \
///     -destination 'platform=iOS Simulator,id=<udid>'
/// 추출:
///   xcrun xcresulttool export attachments --path <result>.xcresult --output-path <dir>
///   (manifest.json 의 suggestedHumanReadableName 이 아래 name 과 매핑)
///
/// `--mocks` 면 AuthStore 가 로그인 상태이고 MockBackend 가 authed 엔드포인트를 데이터까지
/// 내주므로 실서버 없이 결정론적으로 렌더된다.
final class SignedInScreensUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// 라벨을 포함하는 첫 버튼(행 NavigationLink) — 행 자식은 라벨 뒤로 합쳐진다.
    private func rowButton(_ app: XCUIApplication, contains label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }

    func testForYouFeed() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks"]
        app.launch()

        let forYou = app.buttons["추천"].firstMatch
        XCTAssertTrue(forYou.waitForExistence(timeout: 12), "피드 세그먼트에 '추천' 탭이 없음")
        forYou.tap()
        _ = app.staticTexts["발행된 목 글"].firstMatch.waitForExistence(timeout: 8)
        shoot("for-you-feed")
    }

    func testMyHighlights() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "account"]
        app.launch()

        let row = rowButton(app, contains: "내 하이라이트")
        XCTAssertTrue(row.waitForExistence(timeout: 12), "서재에 '내 하이라이트' 행이 없음")
        if !row.isHittable { app.swipeUp() }
        row.tap()
        _ = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '경계를 먼저'"))
            .firstMatch.waitForExistence(timeout: 8)
        shoot("my-highlights")
    }

    func testReadingHistory() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "account"]
        app.launch()

        let row = rowButton(app, contains: "읽기 기록")
        XCTAssertTrue(row.waitForExistence(timeout: 12), "서재에 '읽기 기록' 행이 없음")
        if !row.isHittable { app.swipeUp() }
        row.tap()
        _ = app.staticTexts["발행된 목 글"].firstMatch.waitForExistence(timeout: 8)
        shoot("reading-history")
    }
}
