import XCTest

final class ExploreSwipeUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "search"]
        app.launch()
        XCTAssertTrue(app.buttons["segment.picks"].waitForExistence(timeout: 15), "둘러보기 갈래 스위처가 없음")
        return app
    }

    private func flick(_ app: XCUIApplication, from: CGFloat, to: CGFloat, y: CGFloat = 0.32) {
        app.coordinate(withNormalizedOffset: CGVector(dx: from, dy: y))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: to, dy: y)))
    }

    private func selected(_ app: XCUIApplication, _ lane: String) -> Bool {
        let segment = app.buttons["segment.\(lane)"]
        let picked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: segment)
        return XCTWaiter().wait(for: [picked], timeout: 4) == .completed
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testSwipingMovesBetweenLanesAndTheSwitcherFollows() throws {
        let app = launch()
        XCTAssertTrue(selected(app, "picks"))

        flick(app, from: 0.85, to: 0.1)
        XCTAssertTrue(selected(app, "remote"), "왼쪽으로 밀었는데 다른 서버로 안 넘어감")
        flick(app, from: 0.85, to: 0.1)
        XCTAssertTrue(selected(app, "people"), "왼쪽으로 밀었는데 사람으로 안 넘어감")
        flick(app, from: 0.85, to: 0.1)
        XCTAssertTrue(selected(app, "people"), "끝 갈래에서 더 넘어감")
        flick(app, from: 0.15, to: 0.9)
        XCTAssertTrue(selected(app, "remote"), "오른쪽으로 밀었는데 다른 서버로 안 돌아옴")

        app.buttons["segment.picks"].tap()
        XCTAssertTrue(selected(app, "picks"), "스위처를 눌렀는데 추천으로 안 바뀜")
        shot("explore-picks-after-swipes")
    }

    func testTheSearchFieldFoldsWhenReadingDownAndALaneArrivesWithItOpen() throws {
        let app = launch()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 6) && field.isHittable, "맨 위에서 검색칸이 안 보임")

        app.swipeUp()
        app.swipeUp()
        expectation(for: NSPredicate(format: "exists == false OR isHittable == false"), evaluatedWith: field)
        waitForExpectations(timeout: 5)
        shot("explore-read-down")

        flick(app, from: 0.85, to: 0.1)
        XCTAssertTrue(selected(app, "remote"))
        expectation(for: NSPredicate(format: "exists == true AND isHittable == true"), evaluatedWith: field)
        waitForExpectations(timeout: 5)
        shot("explore-lane-arrived")
    }

    func testAFocusedSearchFieldHoldsTheLane() throws {
        let app = launch()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        field.tap()

        flick(app, from: 0.85, to: 0.1, y: 0.45)
        XCTAssertTrue(selected(app, "picks"), "검색칸에 포커스가 있는데 갈래가 넘어감")
        shot("explore-focused-held")
    }
}
