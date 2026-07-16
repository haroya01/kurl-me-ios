//
//  DiscoverGlobalFallbackUITests.swift
//  kurlUITests
//
//  발견 콜드스타트 전역 폴백 — 로그인했지만 팔로우 0/활동 0이면 서버가 page 0 을 전역 공개
//  흐름으로 내려주고(source="global"), 클라이언트는 조용한 맥락 한 줄을 세그먼트 콘텐츠 위에
//  올린다. 개인화 모드에선 그 캡션이 없어야 한다(무회귀).
//

import XCTest

final class DiscoverGlobalFallbackUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// 캡션의 앞부분(고정 리터럴) — 정확한 카피가 바뀌어도 흔들리지 않게 접두만 본다.
    private let captionPrefix = "아직 팔로우한 큐레이터의 소식이 없어"

    func testGlobalFallbackShowsCaptionAndRows() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--discover-global", "--tab", "discover"]
        app.launch()

        // 전역 폴백이어도 입구 흐름은 그대로 렌더된다(전역 rows).
        let openPaths = app.staticTexts["지금 열려 있는 길"].firstMatch
        XCTAssertTrue(openPaths.waitForExistence(timeout: 20), "전역 폴백에서 입구 rows 가 안 뜸")

        // 맥락 캡션이 세그먼트 콘텐츠 위에 뜬다.
        let caption = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", captionPrefix)).firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 5), "전역 폴백 맥락 캡션이 없음")
        // 큐레이터 찾기 인라인 링크도 함께.
        XCTAssertTrue(
            app.buttons["큐레이터 찾기"].firstMatch.waitForExistence(timeout: 3),
            "'큐레이터 찾기' 진입 링크가 없음")
        shoot(app, "global-fallback-entrances")

        // "최근" 흐름도 같은 연결 소스라 캡션이 유지된다.
        app.buttons["최근"].firstMatch.tap()
        let connectedVerb = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '에 연결' OR label CONTAINS '길에 엮음'")).firstMatch
        XCTAssertTrue(connectedVerb.waitForExistence(timeout: 8), "전역 폴백 최근 흐름 rows 가 안 뜸")
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", captionPrefix)).firstMatch.exists,
            "최근 흐름에서 캡션이 사라짐")

        // "하이라이트" 흐름 — 목 하이라이트 피드가 전역으로 렌더되고 캡션 유지.
        app.buttons["하이라이트"].firstMatch.tap()
        let quote = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '타이밍 버그' OR label CONTAINS '전역 변경'")).firstMatch
        XCTAssertTrue(quote.waitForExistence(timeout: 8), "전역 폴백 하이라이트 rows 가 안 뜸")
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", captionPrefix)).firstMatch.exists,
            "하이라이트 흐름에서 캡션이 사라짐")
        shoot(app, "global-fallback-highlights")
    }

    func testPersonalizedModeHasNoCaption() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "discover"]
        app.launch()

        let openPaths = app.staticTexts["지금 열려 있는 길"].firstMatch
        XCTAssertTrue(openPaths.waitForExistence(timeout: 20), "개인화 모드 입구 rows 가 안 뜸")

        // 개인화(following) 모드에선 전역 폴백 캡션이 없어야 한다(무회귀).
        let caption = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", captionPrefix)).firstMatch
        XCTAssertFalse(caption.exists, "개인화 모드인데 전역 폴백 캡션이 떴다")
        shoot(app, "personalized-no-caption")
    }
}
