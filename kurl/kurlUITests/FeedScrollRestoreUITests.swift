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

        // 목 레인의 최신 피드는 실서버 글을 그대로 받아 제목이 날마다 바뀐다 — 제목 대신 카드 모양으로 잡는다.
        let cards = app.scrollViews.buttons
        let firstCard = cards.firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 15), "피드 첫 카드가 안 보임")
        let firstLabel = firstCard.label
        func card(_ label: String) -> XCUIElement {
            cards.matching(NSPredicate(format: "label == %@", label)).firstMatch
        }

        var target: XCUIElement?
        for _ in 0..<5 {
            app.swipeUp()
            if card(firstLabel).isHittable { continue }
            target = cards.allElementsBoundByIndex.first {
                $0.label != firstLabel && $0.frame.height > 80 && $0.frame.minY > 150 && $0.isHittable
            }
            if target != nil { break }
        }
        guard let target else {
            throw XCTSkip("목 피드에서 화면 밖 카드를 확보하지 못함 — 좌표 독립 검증 불가")
        }
        let targetLabel = target.label
        target.tap()

        // 글 상세 진입 확인(독의 연결 버튼이 뜨면 진입 성공) 후 엣지 스와이프로 복귀
        // (글 상세는 스크롤 전까지 내비바가 숨김이라 시스템 back 버튼이 없다).
        let dock = app.buttons["컬렉션에 연결"].firstMatch
        XCTAssertTrue(dock.waitForExistence(timeout: 8), "글 상세 진입 실패")
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)))
        Thread.sleep(forTimeInterval: 1.0)

        // 복원 단언 — 보던 카드가 다시 화면 안에 있어야 한다(복원 없으면 맨 위로 튕겨 화면 밖).
        let restored = card(targetLabel)
        XCTAssertTrue(
            restored.waitForExistence(timeout: 6) && restored.isHittable,
            "복귀 후 보던 카드가 화면에 없다 — 스크롤 복원 실패")
        // 그리고 맨 위 첫 카드는 화면 밖이어야 한다(맨 위로 튕기지 않았다는 반대 증거).
        XCTAssertFalse(card(firstLabel).isHittable, "복귀 후 리스트가 맨 위로 튕겼다")
    }
}
