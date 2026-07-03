//
//  EngagementDockUITests.swift
//  kurlUITests
//

import XCTest

/// 인게이지 독(연결·좋아요·북마크) 버튼 독립성 회귀.
/// `--mocks --post honggildong/p-mock-2` 로 글 상세를 열어 독을 띄운다.
final class EngagementDockUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 좋아요만 눌렀을 때 북마크·연결이 함께 반응하지 않아야 한다(독립성).
    func testLikeDoesNotToggleNeighbors() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--post", "honggildong/p-mock-2"]
        app.launch()

        let like = app.buttons["좋아요"]
        let bookmark = app.buttons["북마크"]
        let connect = app.buttons["컬렉션에 연결"]
        XCTAssertTrue(like.waitForExistence(timeout: 15), "독에 좋아요 버튼이 없음")
        XCTAssertTrue(bookmark.exists, "독에 북마크 버튼이 없음")
        XCTAssertTrue(connect.exists, "독에 연결 버튼이 없음")

        let bookmarkSelectedBefore = bookmark.isSelected
        like.tap()
        Thread.sleep(forTimeInterval: 0.8)

        XCTAssertTrue(like.isSelected, "좋아요 탭 후 좋아요가 선택 상태가 아님")
        XCTAssertEqual(bookmark.isSelected, bookmarkSelectedBefore,
                       "좋아요를 눌렀는데 북마크 선택 상태가 바뀜 — 독립성 깨짐")
        XCTAssertFalse(app.sheets.firstMatch.exists, "좋아요를 눌렀는데 연결 시트가 뜸 — 독립성 깨짐")
    }
}
