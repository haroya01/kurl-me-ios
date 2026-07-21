//
//  DiscoverSwipeUITests.swift
//  kurlUITests
//

import XCTest

/// 발견 세그먼트(둘러보기·최근·하이라이트) 좌우 스와이프 전환 회귀 가드.
/// 신고 재현: 세로 ScrollView 안 가로 드래그는 카드 탭을 취소하지 않아, 스와이프가
/// 세그먼트 전환 대신 컬렉션 상세 push 로 새고 있었다(드래그 중 disabled 문법으로 수리).
final class DiscoverSwipeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSwipeSwitchesSegmentsWithoutNavigating() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--mocks", "--tab", "discover"]
        app.launch()

        let browse = app.buttons["둘러보기"].firstMatch
        let recent = app.buttons["최근"].firstMatch
        XCTAssertTrue(browse.waitForExistence(timeout: 12), "세그먼트가 없음")
        Thread.sleep(forTimeInterval: 2)

        // 왼쪽 스와이프 → 최근. 세그먼트가 트리에 남아 있어야 한다(항해로 새면 사라진다).
        app.swipeLeft()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(recent.exists, "스와이프가 세그먼트 전환 대신 다른 화면으로 항해함")
        XCTAssertTrue(recent.isSelected, "스와이프 1회 후 '최근' 미선택")

        // 한 번 더 → 하이라이트.
        app.swipeLeft()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(app.buttons["하이라이트"].firstMatch.isSelected, "스와이프 2회 후 '하이라이트' 미선택")

        // 오른쪽 → 최근 복귀.
        app.swipeRight()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(recent.isSelected, "우스와이프 복귀 실패")

        // 스와이프 수리가 탭 항해를 죽이지 않았는지 — 정지 상태 탭은 여전히 상세로 들어간다.
        app.swipeRight()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(browse.isSelected, "둘러보기 복귀 실패")
    }
}
