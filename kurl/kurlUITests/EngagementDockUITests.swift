import XCTest

/// 인게이지 독(연결·좋아요·북마크)과 본문 끝 줄.
/// `--mocks --post honggildong/hexagonal-after-3-months` 는 읽는 동안 독이 뜨는 긴 글,
/// `honggildong/p-mock-2` 는 첫 화면에서 본문이 끝나는 글이다.
final class EngagementDockUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 좋아요만 눌렀을 때 북마크·연결이 함께 반응하지 않아야 한다(독립성).
    func testLikeDoesNotToggleNeighbors() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--post", "honggildong/hexagonal-after-3-months"]
        app.launch()

        let like = app.buttons["dock.like"]
        let bookmark = app.buttons["dock.bookmark"]
        let connect = app.buttons["dock.connect"]
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

    /// 읽어 내려가는 동안엔 독이 본문을 가리지 않고, 멈춰도 숨은 채이며, 위로 올리면 돌아온다.
    func testDockHidesWhileReadingDownAndReturnsOnlyWhenScrolledBackUp() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--post", "honggildong/hexagonal-after-3-months"]
        app.launch()

        let like = app.buttons["dock.like"]
        let bookmark = app.buttons["dock.bookmark"]
        XCTAssertTrue(like.waitForExistence(timeout: 15), "독에 좋아요 버튼이 없음")

        let window = app.windows.firstMatch.frame
        XCTAssertEqual(like.frame.midX, bookmark.frame.midX, accuracy: 2, "독이 세로로 쌓이지 않음")
        XCTAssertGreaterThan(bookmark.frame.minY, like.frame.maxY, "북마크가 좋아요 아래에 있지 않음")
        XCTAssertGreaterThan(like.frame.minX, window.midX, "독이 오른쪽에 붙지 않음")

        app.swipeUp()
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertFalse(like.isHittable, "읽어 내려가는데 독이 본문 위에 떠 있음")
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertFalse(like.isHittable, "스크롤을 멈췄더니 독이 돌아와 읽던 문장을 덮음")
        attach("dock-hidden-while-reading")

        nudgeContentDown(app)
        XCTAssertTrue(like.isHittable, "위로 올렸는데 독이 돌아오지 않음")
        XCTAssertTrue(bookmark.isHittable, "위로 올렸는데 북마크가 돌아오지 않음")
        attach("dock-back-after-scrolling-up")
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testDockRetreatsAtTheEndAndReturnsInTheBody() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--post", "honggildong/hexagonal-after-3-months"]
        app.launch()

        let like = app.buttons["dock.like"]
        XCTAssertTrue(like.waitForExistence(timeout: 15), "독에 좋아요 버튼이 없음")
        XCTAssertTrue(like.isHittable, "처음 연 글에서 독이 보여야 함")

        for _ in 0..<12 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.3)
        }
        nudgeContentDown(app)
        XCTAssertFalse(like.isHittable, "글 끝맺음에서 살짝 올렸는데 독이 끝맺음 위로 돌아옴")

        for _ in 0..<12 where !like.isHittable {
            app.swipeDown()
            Thread.sleep(forTimeInterval: 0.4)
        }
        XCTAssertTrue(like.isHittable, "본문으로 되돌아오면 독이 다시 떠야 함")
    }

    /// 본문 끝 줄이 독을 이어받는다 — 줄이 보이는 동안 독은 물러나 있고, 줄에서 누른 좋아요는 독에도 그대로다.
    func testTheBodyEndRowTakesOverFromTheDockAndSharesItsState() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--post", "honggildong/hexagonal-after-3-months"]
        app.launch()

        let dockLike = app.buttons["dock.like"]
        let endLike = app.buttons["end.like"]
        XCTAssertTrue(dockLike.waitForExistence(timeout: 15), "독에 좋아요 버튼이 없음")
        XCTAssertFalse(dockLike.isSelected, "처음부터 좋아요가 눌려 있음")

        for _ in 0..<60 where !endLike.isHittable {
            dragContent(app, by: -300)
        }
        XCTAssertTrue(endLike.isHittable, "본문이 끝난 자리에 좋아요가 없음")
        XCTAssertTrue(app.buttons["end.bookmark"].isHittable, "본문이 끝난 자리에 북마크가 없음")
        XCTAssertFalse(dockLike.isHittable, "본문 끝 줄이 보이는데 독이 함께 떠 있음")
        attach("body-end-row")

        endLike.tap()
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertTrue(endLike.isSelected, "본문 끝 줄의 좋아요가 선택 상태가 아님")

        for _ in 0..<12 where !dockLike.isHittable {
            app.swipeDown()
            Thread.sleep(forTimeInterval: 0.4)
        }
        XCTAssertTrue(dockLike.isHittable, "본문으로 되돌아오면 독이 다시 떠야 함")
        XCTAssertTrue(dockLike.isSelected, "본문 끝 줄에서 누른 좋아요가 독에 반영되지 않음")
    }

    /// 첫 화면에서 본문이 끝나는 글 — 좋아요·북마크는 처음부터 본문 끝 줄에 있고, 독은 그 줄과 함께 뜨지 않는다.
    func testAPostWhoseBodyEndsOnTheFirstScreenShowsTheEndRowInsteadOfTheDock() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--post", "honggildong/p-mock-2"]
        app.launch()

        let endLike = app.buttons["end.like"]
        let endBookmark = app.buttons["end.bookmark"]
        XCTAssertTrue(endLike.waitForExistence(timeout: 15), "본문이 끝난 자리에 좋아요가 없음")
        XCTAssertTrue(endLike.isHittable, "처음 연 짧은 글에서 좋아요를 누를 수 없음")
        XCTAssertFalse(app.buttons["dock.like"].isHittable, "본문 끝 줄이 보이는데 독이 함께 떠 있음")

        let bookmarkSelectedBefore = endBookmark.isSelected
        endLike.tap()
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertTrue(endLike.isSelected, "좋아요 탭 후 좋아요가 선택 상태가 아님")
        XCTAssertEqual(endBookmark.isSelected, bookmarkSelectedBefore, "좋아요를 눌렀는데 북마크 선택 상태가 바뀜")

        for _ in 0..<10 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.3)
        }
        Thread.sleep(forTimeInterval: 0.5)
        let prompt = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "댓글 쓰기")).firstMatch
        XCTAssertTrue(prompt.isHittable, "댓글 입구가 가려짐")
        nudgeContentDown(app)
        XCTAssertFalse(app.buttons["dock.like"].isHittable, "댓글에서 살짝 올렸는데 독이 댓글 위에 떠 있음")
    }

    /// 관성 없이 끌어 내용을 옮긴다 — 한 번에 화면 하나를 넘기지 않아 본문 끝 줄을 건너뛰지 않는다.
    private func dragContent(_ app: XCUIApplication, by dy: CGFloat) {
        let start = app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: dy < 0 ? 0.7 : 0.35))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: dy)))
        Thread.sleep(forTimeInterval: 0.35)
    }

    /// 관성 없이 150pt 만 끌어 내용을 아래로 — 스크롤 방향 판정 임계(44pt)는 넘고, 글 끝 영역은 화면에 남긴다.
    private func nudgeContentDown(_ app: XCUIApplication) {
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 150)))
        Thread.sleep(forTimeInterval: 0.8)
    }
}
