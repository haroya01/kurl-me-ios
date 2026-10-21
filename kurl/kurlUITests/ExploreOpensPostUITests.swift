import XCTest

final class ExploreOpensPostUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchExplore() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "search"]
        app.launch()
        XCTAssertTrue(app.buttons["segment.picks"].waitForExistence(timeout: 20), "둘러보기 머리 세그먼트가 없음")
        return app
    }

    private func first(_ app: XCUIApplication, prefix: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
    }

    private func assertOpenedPost(_ app: XCUIApplication, _ what: String) {
        XCTAssertTrue(app.buttons["dock.like"].waitForExistence(timeout: 15), "\(what) 글을 눌렀는데 상세가 안 열림")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = what
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testAPickedPostOpens() throws {
        let app = launchExplore()
        let row = first(app, prefix: "search.trending.")
        XCTAssertTrue(row.waitForExistence(timeout: 20), "추천 글 행이 없음")
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        assertOpenedPost(app, "explore-pick")
    }

    func testASearchResultOpens() throws {
        let app = launchExplore()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "검색 필드가 없음")
        field.tap()
        field.typeText("kurl\n")
        let row = first(app, prefix: "search.row.")
        XCTAssertTrue(row.waitForExistence(timeout: 20), "검색 결과 글 행이 없음")
        row.tap()
        assertOpenedPost(app, "search-result")
    }

    func testARemoteNoteOpens() throws {
        let app = launchExplore()
        app.buttons["segment.remote"].tap()
        let note = first(app, prefix: "note.body.")
        XCTAssertTrue(note.waitForExistence(timeout: 20), "다른 서버 노트가 없음")
        note.tap()
        let left = NSPredicate(format: "hittable == false")
        expectation(for: left, evaluatedWith: app.buttons["segment.picks"])
        waitForExpectations(timeout: 10)
    }
}
