//
//  CollectionPathUITests.swift
//  kurlUITests
//

import XCTest

/// A 척추 — reading path(PATH 컬렉션)가 리스트가 아니라 가이드 워크(문장→왜→문장)로 읽히고,
/// 인용을 탭하면 그 글의 그 지점으로 딥링크되는지 실기기 경로로 확인한다(목 PATH 컬렉션 104).
final class CollectionPathUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func shot(_ name: String) {
        let s = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

    private func anyElement(containing text: String) -> XCUIElement {
        XCUIApplication().descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func testPathRendersAsGuidedWalk() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--screen", "collection-detail", "--collection", "104"]
        app.launch()

        // 헤더 + 큐레이터의 잇는 말(why) + 세 인용이 순서대로 보인다.
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS '경계를 긋는다는 것'")).firstMatch
                .waitForExistence(timeout: 15),
            "길 헤더가 없음")
        for quote in ["경계가 없으면", "다시 돌아가라면", "재현이 안 되는 버그"] {
            XCTAssertTrue(
                app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label CONTAINS %@", quote)).firstMatch
                    .waitForExistence(timeout: 5),
                "길에 인용이 빠짐: \(quote)")
        }
        shot("1-path-guided-walk")

        // 첫 인용 탭 → 그 글로 딥링크(그 글의 다른 블록이 보이면 글이 열린 것).
        let firstQuote =
            app.buttons.matching(NSPredicate(format: "label CONTAINS '경계가 없으면'")).firstMatch
        if firstQuote.waitForExistence(timeout: 4) {
            firstQuote.tap()
            let postBlock =
                app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label CONTAINS '포트를 먼저 그었다'")).firstMatch
            XCTAssertTrue(postBlock.waitForExistence(timeout: 10), "인용 탭 후 원문이 안 열림")
            Thread.sleep(forTimeInterval: 0.8)
            shot("2-deeplinked-from-path")
        }
    }

    /// Stage 3 — 길 주인이 순서 편집 시트를 열어 저장(드래그 reorder → reorder API).
    func testPathReorderSheetOpensAndSaves() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--screen", "collection-detail", "--collection", "104"]
        app.launch()

        let manage = app.buttons["컬렉션 관리"]
        XCTAssertTrue(manage.waitForExistence(timeout: 15), "owner 관리 메뉴가 없음")
        manage.tap()
        let reorder = app.buttons["순서 편집"]
        XCTAssertTrue(reorder.waitForExistence(timeout: 5), "순서 편집 항목이 없음")
        reorder.tap()

        XCTAssertTrue(
            app.navigationBars["순서 편집"].waitForExistence(timeout: 5), "순서 편집 시트가 안 뜸")
        shot("3-reorder-sheet")
        let save = app.buttons["저장"]
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        save.tap()
        // 저장 후 길 상세로 복귀.
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS '경계를 긋는다는 것'")).firstMatch
                .waitForExistence(timeout: 6),
            "저장 후 길 상세 복귀 실패")
    }

    /// Stage 3 — 연결 시트가 '새 길 만들기'(PATH)를 제공하고, 누르면 길이 만들어져 선택된다.
    func testConnectSheetOffersNewPath() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--screen", "connect"]
        app.launch()

        XCTAssertTrue(
            app.navigationBars["어디에 남길까요?"].waitForExistence(timeout: 15), "연결 시트가 안 뜸")
        let newPath =
            app.buttons.matching(NSPredicate(format: "label CONTAINS '새 길 만들기'")).firstMatch
        XCTAssertTrue(newPath.waitForExistence(timeout: 5), "'새 길 만들기'가 없음")
        shot("4-connect-new-path")
        newPath.tap()
        // 길이 생성·선택되어 '다음'이 활성.
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS '다음'")).firstMatch
                .waitForExistence(timeout: 5),
            "새 길 생성 후 선택 안 됨")
        shot("5-new-path-created")
    }

    /// Stage 4a — 발견 피드에서 PATH 연결이 '길에 엮음'으로 구분된다.
    func testDiscoverMarksPathConnections() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "discover"]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS '길에 엮음'")).firstMatch
                .waitForExistence(timeout: 15),
            "발견 피드에 '길에 엮음' 표시가 없음")
        shot("6-discover-path-card")
    }

    /// Stage 4b — 하이라이트 스레드에 '이 문장이 속한 길' 섹션이 뜨고, 길을 탭하면 가이드 워크로.
    func testThreadShowsContainingPaths() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--post", "honggildong/hexagonal-after-3-months"]
        app.launch()

        let paragraph = app.textViews.containing(
            NSPredicate(format: "value CONTAINS %@", "돌아가라면")).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 15), "첫 문단 없음")
        paragraph.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.16)).tap()
        XCTAssertTrue(
            app.navigationBars["하이라이트"].waitForExistence(timeout: 6), "스레드가 안 열림")

        // '이 문장이 속한 길' 섹션 + 길 제목(컬렉션 104 = '경계를 긋는다는 것').
        let section = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '이 문장이 속한 길'")).firstMatch
        XCTAssertTrue(section.waitForExistence(timeout: 6), "'이 문장이 속한 길' 섹션이 없음")
        shot("7-thread-containing-paths")
        let pathTitle = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '경계를 긋는다는 것'")).firstMatch
        if pathTitle.waitForExistence(timeout: 4) {
            pathTitle.tap()
            // 길로 진입 — 워크 첫 인용(상단, 렌더됨)으로 확인. 3번째는 medium 시트 밖이라 lazy 미렌더.
            XCTAssertTrue(
                app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label CONTAINS '경계가 없으면'")).firstMatch
                    .waitForExistence(timeout: 8),
                "길 탭 후 가이드 워크가 안 열림")
            shot("8-path-from-thread")
        }
    }
}
