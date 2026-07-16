//
//  SearchNoResultsUITests.swift
//  kurlUITests
//
//  검색 무결과 폴백 도달 — 실결과(글·작가·실태그)가 전무한 검색어면 입력어를 태그 칩으로
//  조작하지 않고 무결과 안내("결과가 없어요" + 추천 레일/발견 CTA)가 뜬다. 존재하지 않는
//  태그 피드로 데려가던 막다른 길 회귀 가드.
//

import XCTest

final class SearchNoResultsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testGibberishQueryReachesNoResultsWithoutFabricatedTag() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "search"]
        app.launch()

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "검색 필드가 없음")
        field.tap()
        // 어떤 글·작가·실태그와도 안 겹치는 문자열 — 실결과 0.
        field.typeText("zzxqwkjhqwe999")

        // 무결과 안내가 실제로 뜬다("결과가 없어요"). 예전엔 에코 태그 칩 때문에 영영 안 떴다.
        let emptyTitle = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '결과가 없어요'")).firstMatch
        XCTAssertTrue(
            emptyTitle.waitForExistence(timeout: 12),
            "무결과 안내가 안 뜸 — 에코 태그 칩이 폴백을 가로챈 회귀")

        // 그리고 입력어를 그대로 박은 태그 칩(#zzxqwkjhqwe999)은 없어야 한다(존재하지 않는 태그 조작 금지).
        let fabricatedChip = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'zzxqwkjhqwe999' AND label BEGINSWITH '#'")).firstMatch
        XCTAssertFalse(
            fabricatedChip.exists,
            "존재하지 않는 태그 칩(#zzxqwkjhqwe999)이 조작돼 표시됨")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "search-no-results-recovery"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
