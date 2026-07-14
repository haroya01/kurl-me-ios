//
//  FeedScrollRestoreUITests.swift
//  kurlUITests
//
//  피드→글→복귀 스크롤 복원(#122) — 보던 카드가 복귀 후에도 화면에 남아 있어야 한다.
//  (복원이 없으면 pop 시 리스트 맨 위로 튕겨 아래쪽 카드는 화면 밖이다.)
//

import XCTest

final class FeedScrollRestoreUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFeedKeepsScrollAfterReadingPost() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks"]
        app.launch()

        // 피드가 서길 기다렸다가 아래로 내려간다 — 첫 화면 밖의 카드를 보는 상태를 만든다.
        let firstCard = app.staticTexts["편집 제목"].firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 10), "피드 첫 카드가 안 보임")

        // 화면 아래쪽의 목 카드 하나가 잡힐 때까지 내려간다(레이아웃 변화에 적응).
        let candidates = [
            "K-means clustering accelerator 설계 (1)", "fd",
            "조용한 웹로그라는 결정", "헥사고날로 갈아탄 지 석 달, 무엇이 남았나",
        ]
        var target: XCUIElement?
        for _ in 0..<5 {
            app.swipeUp()
            if firstCard.isHittable { continue }
            if let hit = candidates
                .map({ app.staticTexts[$0].firstMatch })
                .first(where: { $0.exists && $0.isHittable })
            {
                target = hit
                break
            }
        }
        guard let target else {
            throw XCTSkip("목 피드에서 화면 밖 카드를 확보하지 못함 — 좌표 독립 검증 불가")
        }
        target.tap()

        // 글 상세 진입 확인(독의 연결 버튼이 뜨면 진입 성공) 후 엣지 스와이프로 복귀
        // (글 상세는 스크롤 전까지 내비바가 숨김이라 시스템 back 버튼이 없다).
        let dock = app.buttons["컬렉션에 연결"].firstMatch
        XCTAssertTrue(dock.waitForExistence(timeout: 8), "글 상세 진입 실패")
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)))
        Thread.sleep(forTimeInterval: 1.0)

        // 복원 단언 — 보던 카드가 다시 화면 안에 있어야 한다(복원 없으면 맨 위로 튕겨 화면 밖).
        XCTAssertTrue(
            target.waitForExistence(timeout: 6) && target.isHittable,
            "복귀 후 보던 카드가 화면에 없다 — 스크롤 복원 실패")
        // 그리고 맨 위 첫 카드는 화면 밖이어야 한다(맨 위로 튕기지 않았다는 반대 증거).
        XCTAssertFalse(firstCard.isHittable, "복귀 후 리스트가 맨 위로 튕겼다")
    }
}
