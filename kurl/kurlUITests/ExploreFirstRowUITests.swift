import XCTest

final class ExploreFirstRowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTheFirstPicksRowOpensItsAuthorFromTheAvatar() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "search"]
        app.launch()

        let title = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'home.post.'")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 15), "발견에 글 행이 없음")
        title.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: -30, dy: -10)).tap()
        XCTAssertTrue(app.buttons["author.card"].waitForExistence(timeout: 8), "첫 행 아바타를 눌렀는데 작가 화면이 안 열림")
    }

    func testTheFirstPicksRowOpensThePostFromTheTopOfItsTitle() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "search"]
        app.launch()

        let title = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'home.post.'")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 15), "발견에 글 행이 없음")
        let chips = app.buttons["segment.picks"]
        XCTAssertTrue(chips.exists, "둘러보기 칩이 없음")
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.05)).tap()
        XCTAssertTrue(chips.waitForNonExistence(timeout: 8), "첫 행 제목 윗부분을 눌렀는데 상세가 안 열림")
    }
}
