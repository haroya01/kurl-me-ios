//
//  PublicConnectionFeedUITests.swift
//  kurlUITests
//
//  비로그인 첫 피드(최신)에 인터리브되는 공개 연결은 섹션 머리 없이 글과 같은 행으로 흐른다 —
//  행 맨 위 한 줄("큐레이터가 컬렉션에 연결")이 맥락을 맡는다. simctl 로는 웰컴 게이트 통과·스크롤이
//  안 되어 XCUITest 로 도달한다. 연결 이벤트는 목이 내주고, 최신 글 행은 공개 피드라 실서버로 흐른다.
//

import XCTest

final class PublicConnectionFeedUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testPublicConnectionInterleavesAsARow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--logged-out", "--feed", "recent"]
        app.launch()

        let guest = app.buttons["로그인 없이 둘러보기"].firstMatch
        if guest.waitForExistence(timeout: 6) {
            guest.tap()
        }
        _ = app.buttons["최신"].firstMatch.waitForExistence(timeout: 12)

        let connection = app.descendants(matching: .any)["feed.connection.11"]
        for _ in 0..<8 {
            if connection.exists && connection.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(connection.exists, "인터리브된 공개 연결 행을 못 찾음")
        XCTAssertFalse(app.staticTexts["지금 이어지는 것들"].exists, "섹션 머리가 아직 피드에 남아 있다")

        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'feed.row.'")).firstMatch
        XCTAssertTrue(row.exists, "연결 행 곁에 글 행이 없다")
        XCTAssertEqual(connection.frame.minX, row.frame.minX, accuracy: 1, "연결 행이 글 행과 다른 컬럼에 선다")
        XCTAssertEqual(connection.frame.width, row.frame.width, accuracy: 1, "연결 행이 글 행과 폭이 다르다")
        shoot("public-connection-row")
    }
}
