//
//  SeriesNotesUITests.swift
//  kurlUITests
//
//  시리즈에 든 노트 — 목차에 글과 한 순서로 서고, 글 배너에서 노트로·노트 배너에서 글로 이어지며,
//  구독함엔 구독한 시리즈의 새 노트가 글 사이에 낀다. 목 시리즈 "헥사고날 전환기"는 4편과 5편
//  사이에 노트(9540)를 둔 7편짜리다.
//

import XCTest

final class SeriesNotesUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks"] + arguments
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, labelBeginsWith prefix: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    func testTheSeriesTableOfContentsListsTheNoteInItsPlaceAndOpensIt() {
        let app = launch(["--series", "honggildong/hexagonal"])

        let noteRow = element(app, labelBeginsWith: "5편 — 노트")
        XCTAssertTrue(noteRow.waitForExistence(timeout: 10), "목차 5편 자리에 노트가 없음")
        app.swipeUp()
        XCTAssertTrue(
            element(app, labelBeginsWith: "6편 — 테스트 전략").waitForExistence(timeout: 4),
            "노트 뒤 글 번호가 밀리지 않음")
        noteRow.tap()

        XCTAssertTrue(
            element(app, labelBeginsWith: "시리즈 헥사고날 전환기 — 5/7").waitForExistence(timeout: 8),
            "노트 상세에 시리즈 배너가 없음")
        XCTAssertTrue(element(app, labelBeginsWith: "다음 편 — 테스트 전략").exists, "노트 다음 편 링크가 없음")
    }

    func testAPostStepsIntoTheNoteAndTheNoteStepsOnToTheNextPost() {
        let app = launch(["--post", "honggildong/ep-4"])

        let toNote = element(app, labelBeginsWith: "다음 편 — 노트")
        XCTAssertTrue(toNote.waitForExistence(timeout: 12), "4편 배너의 다음 편이 노트가 아님")
        toNote.tap()
        XCTAssertTrue(
            element(app, labelBeginsWith: "시리즈 헥사고날 전환기 — 5/7").waitForExistence(timeout: 8),
            "노트 상세로 가지 않음")

        let toPost = element(app, labelBeginsWith: "다음 편 — 테스트 전략")
        XCTAssertTrue(toPost.waitForExistence(timeout: 4))
        toPost.tap()
        XCTAssertTrue(
            element(app, labelBeginsWith: "시리즈 헥사고날 전환기 — 6/7").waitForExistence(timeout: 12),
            "노트에서 다음 글(5편)로 가지 않음")
    }

    func testTheSubscriptionFeedPlacesASubscribedSeriesNoteByTime() {
        let app = launch(["--feed", "following"])

        let card = app.descendants(matching: .any)["feed.seriesNote.9540"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "구독함에 시리즈 노트 카드가 없음")
        let post = element(app, labelBeginsWith: "발행된 목 글")
        XCTAssertTrue(post.waitForExistence(timeout: 4))
        XCTAssertLessThan(card.frame.minY, post.frame.minY, "더 늦게 나온 노트가 글 앞에 서지 않음")

        card.tap()
        XCTAssertTrue(
            element(app, labelBeginsWith: "시리즈 헥사고날 전환기 — 5/7").waitForExistence(timeout: 8),
            "카드가 노트 상세로 가지 않음")
    }

    func testAnOwnNoteGoesIntoASeriesFromItsMenu() {
        let app = launch(["--tab", "notes"])

        let menu = app.buttons["note.menu.9505"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "내 노트(9505)가 피드에 없음")
        menu.tap()
        let add = app.buttons["note.addToSeries.9505"]
        XCTAssertTrue(add.waitForExistence(timeout: 4), "내 노트 메뉴에 시리즈에 넣기가 없음")
        add.tap()

        let series = app.buttons["series.pick.1"]
        XCTAssertTrue(series.waitForExistence(timeout: 8), "내 시리즈 목록이 안 뜸")
        series.tap()
        XCTAssertTrue(
            element(app, labelBeginsWith: "‘헥사고날 전환기’에 넣었어요").waitForExistence(timeout: 6),
            "넣었다는 안내가 없음")
    }

    func testSomeoneElsesNoteOffersNoSeries() {
        let app = launch(["--tab", "notes"])

        let menu = app.buttons["note.menu.9501"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        XCTAssertFalse(app.buttons["note.addToSeries.9501"].waitForExistence(timeout: 2), "남의 노트에 시리즈에 넣기가 뜸")
    }

    func testTheEpisodeEditorAddsANoteAndKeepsItsPlace() {
        let app = launch(["--series", "honggildong/hexagonal"])

        let manage = app.buttons["시리즈 관리"]
        XCTAssertTrue(manage.waitForExistence(timeout: 10))
        manage.tap()
        app.buttons["회차 편집"].tap()
        XCTAssertTrue(app.navigationBars["회차 편집"].waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS '4편을 쓰고 남은 메모'")).firstMatch
                .waitForExistence(timeout: 6),
            "회차 편집에 시리즈 속 노트가 없음")

        let addNote = app.buttons["series.addNote"]
        if !addNote.waitForExistence(timeout: 2) { app.swipeUp() }
        XCTAssertTrue(addNote.waitForExistence(timeout: 4), "노트 더하기가 없음")
        addNote.tap()
        let pick = app.buttons["series.pickNote.9505"]
        XCTAssertTrue(pick.waitForExistence(timeout: 8), "고를 내 노트가 없음")
        XCTAssertFalse(app.buttons["series.pickNote.9540"].exists, "이미 든 노트가 다시 후보에 뜸")
        pick.tap()

        let save = app.navigationBars["회차 편집"].buttons["저장"]
        XCTAssertTrue(save.waitForExistence(timeout: 4))
        XCTAssertTrue(save.isEnabled, "노트를 더해도 저장이 켜지지 않음")
        save.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.navigationBars["회차 편집"])
        waitForExpectations(timeout: 8)
    }
}
