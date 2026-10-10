//
//  FeedRowsUITests.swift
//  kurlUITests
//
//  블로그 피드는 카드가 아니라 한 문법의 행이다 — 행끼리 같은 컬럼·같은 폭으로 틈 없이 맞붙고
//  (카드 그리드는 16pt 틈이 있었다), 행 전체가 글로 가는 문이다.
//

import XCTest

final class FeedRowsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }

    private func launchFeed() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--feed", "recent"]
        app.launch()
        return app
    }

    private func feedBlocks(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'feed.row.' OR identifier BEGINSWITH 'feed.series.' "
                + "OR identifier BEGINSWITH 'feed.connection.' OR identifier BEGINSWITH 'feed.seriesNote.'"))
    }

    func testRowsShareOneColumnAndAbutWithoutCardGaps() throws {
        let app = launchFeed()
        let first = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'feed.row.'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15), "피드 행이 안 보임")
        Thread.sleep(forTimeInterval: 1.0)

        let window = app.windows.firstMatch.frame
        let visible = feedBlocks(app).allElementsBoundByIndex
            .map(\.frame)
            .filter { $0.minY >= window.minY && $0.maxY <= window.maxY }
            .sorted { $0.minY < $1.minY }
        XCTAssertGreaterThanOrEqual(visible.count, 2, "화면에 행이 둘 이상 보여야 맞붙음을 잴 수 있다")

        for (above, below) in zip(visible, visible.dropFirst()) {
            XCTAssertEqual(below.minX, above.minX, accuracy: 1, "행들이 같은 컬럼에 서지 않는다")
            XCTAssertEqual(below.width, above.width, accuracy: 1, "행 폭이 서로 다르다(카드 변형이 섞였다)")
            XCTAssertGreaterThanOrEqual(below.minY, above.maxY - 1, "행이 겹친다")
            XCTAssertLessThan(below.minY - above.maxY, 2, "행 사이에 카드 틈이 있다")
        }
        shot("feed-rows")
    }

    func testTappingARowOpensThePost() throws {
        let app = launchFeed()
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'feed.row.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "피드 행이 안 보임")
        row.tap()
        XCTAssertTrue(
            app.buttons["컬렉션에 연결"].firstMatch.waitForExistence(timeout: 8),
            "행 탭이 글 상세를 열지 않음")
    }

    func testAReadPostIsMarkedInItsRow() throws {
        let app = launchFeed()
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'feed.row.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "피드 행이 안 보임")
        let identifier = row.identifier
        XCTAssertFalse(row.label.contains("읽음"), "아직 읽지 않은 행에 읽음 표시가 있다: \(row.label)")
        app.terminate()

        // 읽음은 완독에 찍힌다(긴 글은 끝까지, 짧은 글은 체류) — 그 기록을 목 시드로 심어 행 표시만 본다.
        let postId = String(identifier.dropFirst("feed.row.".count))
        let seeded = XCUIApplication()
        seeded.launchArguments = ["--mocks", "--feed", "recent", "--seed-read", postId]
        seeded.launch()
        let readRow = seeded.descendants(matching: .any)[identifier]
        XCTAssertTrue(readRow.waitForExistence(timeout: 15), "같은 행을 다시 찾지 못함")
        XCTAssertTrue(readRow.label.contains("읽음"), "읽은 글 행에 읽음 표시가 없다: \(readRow.label)")
        shot("feed-row-read")
    }
}
