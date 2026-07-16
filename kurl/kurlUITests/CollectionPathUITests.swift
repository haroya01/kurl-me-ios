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

        // 연결 이벤트 흐름은 '최근' 서브탭 — 기본 탭이 '입구'로 바뀐 뒤에도 같은 자리를 본다.
        let recent = app.buttons["최근"]
        XCTAssertTrue(recent.waitForExistence(timeout: 15), "발견 서브탭이 없음")
        recent.tap()
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

    /// 회귀 — 연결 시트의 '다음'·'추가'가 실제로 눌린다(유리 캡슐이 라벨 안에 있어 히트테스트가
    /// 죽었던 사고). 고르고 → 다음 → 왜 화면 → 추가까지 탭으로 완주해야 통과.
    func testConnectSheetNextAndAddAreTappable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--screen", "connect"]
        app.launch()

        // 콜드 부팅 직후 첫 UI 테스트는 AX 서버 응답이 느리다 — 첫 대기만 넉넉히.
        XCTAssertTrue(
            app.navigationBars["어디에 남길까요?"].waitForExistence(timeout: 40), "연결 시트가 안 뜸")
        // 새 길 만들기 = 만들어지며 선택됨 → '다음' 활성.
        let newPath =
            app.buttons.matching(NSPredicate(format: "label CONTAINS '새 길 만들기'")).firstMatch
        XCTAssertTrue(newPath.waitForExistence(timeout: 5), "'새 길 만들기'가 없음")
        newPath.tap()
        let next = app.buttons.matching(NSPredicate(format: "label CONTAINS '다음'")).firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 5), "'다음'이 없음")
        next.tap()
        // ② 왜 화면으로 넘어갔는가 — 죽은 버튼이면 여기서 실패한다.
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS '왜 이었나요'")).firstMatch
                .waitForExistence(timeout: 6),
            "'다음' 탭 후 왜 화면이 안 열림(캡슐 히트테스트 회귀)")
        shot("9-connect-why-step")
        let add = app.buttons.matching(NSPredicate(format: "label CONTAINS '추가'")).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5), "'추가'가 없음")
        add.tap()
        // 연결 성공 → dismiss — 하네스가 실제 바인딩 시트라 닫힘이 관찰된다.
        XCTAssertTrue(
            waitForDisappear(app.navigationBars["추가"], timeout: 8),
            "'추가' 탭 후 시트가 안 닫힘(캡슐 히트테스트 회귀)")
        shot("10-connect-done")
    }

    /// 회귀 — 컬렉션 수정 시트의 '저장'이 실제로 눌린다(같은 유리 캡슐 사고 가족).
    func testEditCollectionSaveIsTappable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--screen", "collection-detail", "--collection", "101"]
        app.launch()

        let manage = app.buttons["컬렉션 관리"]
        XCTAssertTrue(manage.waitForExistence(timeout: 15), "관리 메뉴가 없음")
        manage.tap()
        let edit = app.buttons.matching(NSPredicate(format: "label CONTAINS '수정'")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "'수정' 메뉴가 없음")
        edit.tap()
        let save = app.buttons.matching(NSPredicate(format: "label CONTAINS '저장'")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 6), "'저장'이 없음")
        save.tap()
        // 저장되면 수정 시트가 닫힌다 — 죽은 버튼이면 시트가 남는다.
        XCTAssertTrue(
            waitForDisappear(
                app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label CONTAINS '컬렉션 수정'")).firstMatch,
                timeout: 8),
            "'저장' 탭 후 수정 시트가 안 닫힘(캡슐 히트테스트 회귀)")
        shot("11-edit-saved")
    }

    /// 회귀 — 피드 카드의 "…에 담김" 줄을 탭하면 글이 아니라 그 컬렉션 상세로 간다
    /// (표시 전용이던 줄에 항해를 붙인 계약). 최신 피드는 목 모드에서도 공개 읽기 fall-through 로
    /// 실서버 데이터를 그리므로, 목 라우트가 잡는 구독함(팔로잉) 피드에서 검증한다
    /// (목 씨앗: 글 9002 → 컬렉션 101, 요약 제목 '경계를 긋는 법'/상세 제목 '느린 사고').
    func testFeedBelongingLineOpensCollection() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks"]
        app.launch()

        let following = app.buttons["구독함"]
        XCTAssertTrue(following.waitForExistence(timeout: 40), "피드 소스 스위처가 없음")
        following.tap()

        // isLink 트레잇이라 buttons 가 아니라 any 로 잡는다. 같은 라벨이 수평 페이징의 옆
        // 페이지(음수 x)에도 있어 firstMatch 를 못 믿는다 — 화면 안(x≥0)의 것을 고른다.
        let query = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS '경계를 긋는 법' AND label CONTAINS '담김'"))
        func onScreenLine() -> XCUIElement? {
            for i in 0..<min(query.count, 6) {
                let el = query.element(boundBy: i)
                if el.exists, el.frame.minX >= 0, el.frame.minX < app.frame.width, el.isHittable {
                    return el
                }
            }
            return nil
        }
        _ = query.firstMatch.waitForExistence(timeout: 15)
        var line = onScreenLine()
        var swipes = 0
        while line == nil, swipes < 8 {
            app.swipeUp()
            swipes += 1
            line = onScreenLine()
        }
        guard let line else {
            XCTFail("'…에 담김' 줄이 없음")
            return
        }
        line.tap()
        // 컬렉션 101 상세(목 제목 '느린 사고')가 열린다 — 글 리더가 열리면 실패.
        XCTAssertTrue(
            app.navigationBars["느린 사고"].waitForExistence(timeout: 8),
            "담김 줄 탭이 컬렉션 상세로 항해하지 않음")
        shot("12-belonging-to-collection")
    }

    /// XCUIElement 소멸 대기 — waitForExistence 의 반대가 없어서 폴링으로.
    private func waitForDisappear(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return !element.exists
    }
}
