//
//  CollectionPathUITests.swift
//  kurlUITests
//

import XCTest

/// A 척추 — 순서대로 읽는 컬렉션이 리스트가 아니라 가이드 워크(문장→왜→문장)로 읽히고,
/// 인용을 탭하면 그 글의 그 지점으로 딥링크되는지 실기기 경로로 확인한다(목 컬렉션 104, ordered).
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
            "컬렉션 헤더가 없음")
        for quote in ["경계가 없으면", "다시 돌아가라면", "재현이 안 되는 버그"] {
            XCTAssertTrue(
                app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label CONTAINS %@", quote)).firstMatch
                    .waitForExistence(timeout: 5),
                "가이드 워크에 인용이 빠짐: \(quote)")
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

    /// Stage 3 — 주인이 순서 편집 시트를 열어 저장(드래그 reorder → reorder API).
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
        // 저장 후 컬렉션 상세로 복귀.
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS '경계를 긋는다는 것'")).firstMatch
                .waitForExistence(timeout: 6),
            "저장 후 컬렉션 상세 복귀 실패")
    }

    /// 연결 시트는 길·컬렉션을 고르게 하지 않는다 — 만들기는 하나이고, 순서는 그 안의 스위치다.
    func testConnectSheetMakesAnOrderedCollection() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--screen", "connect"]
        app.launch()

        XCTAssertTrue(
            app.navigationBars["어디에 남길까요?"].waitForExistence(timeout: 15), "연결 시트가 안 뜸")
        let newCollection =
            app.buttons.matching(NSPredicate(format: "label CONTAINS '새 컬렉션 만들기'")).firstMatch
        XCTAssertTrue(newCollection.waitForExistence(timeout: 5), "'새 컬렉션 만들기'가 없음")
        XCTAssertFalse(anyElement(containing: "새 길").exists, "고르게 하는 '새 길' 줄이 남음")
        newCollection.tap()

        let name = app.textFields["컬렉션 이름"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "새 컬렉션 시트가 안 뜸")
        name.tap()
        name.typeText("경계 읽기")
        let ordered = app.switches["collection.ordered"]
        XCTAssertTrue(ordered.waitForExistence(timeout: 3), "'순서대로 읽기' 스위치가 없음")
        XCTAssertEqual(ordered.value as? String, "0", "순서대로 읽기 기본값이 켜져 있음")
        ordered.switches.firstMatch.tap()
        XCTAssertEqual(ordered.value as? String, "1", "'순서대로 읽기'가 켜지지 않음")
        shot("4-new-collection-ordered")
        app.buttons["만들기"].firstMatch.tap()

        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS '다음'")).firstMatch
                .waitForExistence(timeout: 5),
            "새 컬렉션 생성 후 선택 안 됨")
        let made = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '경계 읽기' AND label CONTAINS '순서대로 읽기'")).firstMatch
        XCTAssertTrue(made.waitForExistence(timeout: 5), "새 컬렉션 줄에 '순서대로 읽기' 표식이 없음")
        shot("5-ordered-collection-created")
    }

    /// 홈 피드의 공개 연결은 순서와 상관없이 같은 문장 하나로 읽힌다('길에 엮음' 없음).
    func testFeedConnectionsReadTheSameForOrderedCollections() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--logged-out", "--feed", "recent"]
        app.launch()

        let guest = app.buttons["로그인 없이 둘러보기"].firstMatch
        if guest.waitForExistence(timeout: 6) {
            guest.tap()
        }
        _ = app.buttons["최신"].firstMatch.waitForExistence(timeout: 12)

        let line = anyElement(containing: "경계를 긋는다는 것에 연결")
        for _ in 0..<8 where !(line.exists && line.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(line.exists, "순서 있는 컬렉션 연결이 '…에 연결'로 읽히지 않음")
        XCTAssertFalse(anyElement(containing: "길에 엮음").exists, "'길에 엮음'이 남음")
        shot("6-feed-ordered-connection")
    }

    /// 하이라이트 스레드에 '이 문장이 담긴 컬렉션' 섹션이 뜨고, 순서 있는 컬렉션을 탭하면 가이드 워크로.
    func testThreadShowsContainingCollections() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--post", "honggildong/hexagonal-after-3-months"]
        app.launch()

        let paragraph = app.textViews.containing(
            NSPredicate(format: "value CONTAINS %@", "돌아가라면")).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 15), "첫 문단 없음")
        XCTAssertTrue(app.tapHighlight(in: paragraph, at: [CGVector(dx: 0.55, dy: 0.16), CGVector(dx: 0.5, dy: 0.1)]), "하이라이트 탭으로 카드가 안 뜸")
        XCTAssertTrue(app.openConversationFromCard(), "카드에서 대화가 안 열림")

        let section = anyElement(containing: "이 문장이 담긴 컬렉션")
        XCTAssertTrue(section.waitForExistence(timeout: 6), "'이 문장이 담긴 컬렉션' 섹션이 없음")
        XCTAssertFalse(anyElement(containing: "이 문장이 속한 길").exists)
        shot("7-thread-containing-collections")
        let ordered = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '경계를 긋는다는 것'")).firstMatch
        if ordered.waitForExistence(timeout: 4) {
            ordered.tap()
            // 워크 첫 인용(상단, 렌더됨)으로 확인. 3번째는 medium 시트 밖이라 lazy 미렌더.
            XCTAssertTrue(
                anyElement(containing: "경계가 없으면").waitForExistence(timeout: 8),
                "순서 있는 컬렉션 탭 후 가이드 워크가 안 열림")
            shot("8-ordered-from-thread")
        }
    }

    /// 글 끝은 '이 글이 담긴 컬렉션' 하나 — 자리를 아는 순서 있는 컬렉션은 "N편 중 M번째",
    /// 나머지는 "@큐레이터 · N개"(목 소속: 104 ordered 2/4 · 101 sori 12개 · 107 큐레이터 없음 8개).
    func testPostEndListsTheCollectionsItIsIn() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--post", "honggildong/hexagonal-after-3-months"]
        app.launch()

        let ordered = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '다시 읽는 아키텍처'")).firstMatch
        _ = anyElement(containing: "돌아가라면").waitForExistence(timeout: 15)
        for _ in 0..<14 where !(ordered.exists && ordered.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(ordered.exists, "글 끝에 담긴 컬렉션이 없음")
        XCTAssertTrue(anyElement(containing: "이 글이 담긴 컬렉션").exists, "'이 글이 담긴 컬렉션' 제목이 없음")
        XCTAssertFalse(anyElement(containing: "이 글이 놓인 길").exists)
        XCTAssertTrue(ordered.label.contains("@minji · 4편 중 2번째"), "순서 줄: \(ordered.label)")
        let curated = app.buttons.matching(NSPredicate(format: "label CONTAINS '경계를 긋는 법'")).firstMatch
        XCTAssertTrue(curated.label.contains("@sori · 12개"), "큐레이터 줄: \(curated.label)")
        let bare = app.buttons.matching(NSPredicate(format: "label CONTAINS '회고 모음'")).firstMatch
        XCTAssertTrue(bare.label.contains("8개"), "개수 줄: \(bare.label)")
        shot("13-post-end-collections")
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
        // 새 컬렉션 만들기 = 이름 시트를 거쳐 만들어지며 선택됨 → '다음' 활성.
        let newCollection =
            app.buttons.matching(NSPredicate(format: "label CONTAINS '새 컬렉션 만들기'")).firstMatch
        XCTAssertTrue(newCollection.waitForExistence(timeout: 5), "'새 컬렉션 만들기'가 없음")
        newCollection.tap()
        let name = app.textFields["컬렉션 이름"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "컬렉션 이름 시트가 안 뜸")
        name.tap()
        name.typeText("다시 볼 것")
        let createButton = app.buttons["만들기"].firstMatch
        createButton.tap()
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
    /// 순서 없는 컬렉션에 '순서대로 읽기'를 켜고 저장하면 그 자리에서 가이드 워크(번호)로 바뀐다.
    func testEditCollectionSaveIsTappable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--screen", "collection-detail", "--collection", "101"]
        app.launch()

        let manage = app.buttons["컬렉션 관리"]
        XCTAssertTrue(manage.waitForExistence(timeout: 15), "관리 메뉴가 없음")
        XCTAssertFalse(anyElement(containing: "지금 여기").exists, "순서 없는 컬렉션에 진행 길잡이가 있음")
        manage.tap()
        let edit = app.buttons.matching(NSPredicate(format: "label CONTAINS '수정'")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "'수정' 메뉴가 없음")
        edit.tap()
        let ordered = app.switches["collection.ordered"]
        XCTAssertTrue(ordered.waitForExistence(timeout: 6), "수정 시트에 '순서대로 읽기'가 없음")
        XCTAssertEqual(ordered.value as? String, "0")
        ordered.switches.firstMatch.tap()
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
        XCTAssertTrue(
            anyElement(containing: "지금 여기").waitForExistence(timeout: 6),
            "순서대로 읽기를 켠 뒤 가이드 워크로 바뀌지 않음")
        shot("11-edit-saved-ordered")
    }

    /// 회귀 — 피드 카드의 "…에 담김" 줄을 탭하면 글이 아니라 그 컬렉션 상세로 간다
    /// (표시 전용이던 줄에 항해를 붙인 계약). 최신 피드는 목 모드에서도 공개 읽기 fall-through 로
    /// 실서버 데이터를 그리므로, 목 라우트가 잡는 팔로잉 피드에서 검증한다
    /// (목 씨앗: 글 9002 → 컬렉션 101, 요약 제목 '경계를 긋는 법'/상세 제목 '느린 사고').
    func testFeedBelongingLineOpensCollection() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks"]
        app.launch()

        let following = app.buttons["팔로잉"]
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
