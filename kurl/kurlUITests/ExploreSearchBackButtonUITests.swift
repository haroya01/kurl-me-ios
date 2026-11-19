import XCTest

final class ExploreSearchBackButtonUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOpeningATopicWhileSearchingShowsASingleBackButton() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "search"]
        app.launch()

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "검색 필드가 없음")
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "검색이 활성화되지 않음")

        let row = app.buttons["topic.link:https://news.example/library-night"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "트렌드에 화제 행이 없음")
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.05)).tap()
        XCTAssertTrue(app.buttons["linkNotes.open"].waitForExistence(timeout: 8), "화제를 눌렀는데 링크 화면이 안 열림")
        XCTAssertTrue(field.waitForNonExistence(timeout: 8), "연 화면에 검색칸이 남음")

        let backs = app.buttons.matching(NSPredicate(format: "label IN {'뒤로', 'Back'}"))
        XCTAssertEqual(backs.count, 1, "검색 중 연 화면에 뒤로 버튼이 \(backs.count)개")

        backs.firstMatch.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 8), "뒤로 가도 둘러보기로 돌아오지 않음")
    }
}
