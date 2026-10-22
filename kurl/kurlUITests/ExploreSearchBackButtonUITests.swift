import XCTest

final class ExploreSearchBackButtonUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOpeningAPickWhileSearchingShowsASingleBackButton() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "search"]
        app.launch()

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "검색 필드가 없음")
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "검색이 활성화되지 않음")

        let title = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'home.post.'")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 15), "추천에 글 행이 없음")
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.05)).tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 8), "글을 눌렀는데 상세가 안 열림")

        let backs = app.buttons.matching(NSPredicate(format: "label IN {'뒤로', 'Back'}"))
        XCTAssertEqual(backs.count, 1, "검색 중 연 글 상세에 뒤로 버튼이 \(backs.count)개")

        backs.firstMatch.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 8), "뒤로 가도 둘러보기로 돌아오지 않음")
    }
}
