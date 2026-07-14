//
//  LikeStoreTests.swift
//  kurlTests
//
//  퀵액션 좋아요의 낙관 카운트 회귀 — 기준값이 살아 있는 동안만 +1 하고, 서버가 새 숫자를
//  들고 오면 그 값을 믿는다(중복 가산 금지). 0→1 등장(하트가 없던 카드)도 고정한다.
//

import XCTest

@testable import kurl

@MainActor
final class LikeStoreTests: XCTestCase {

    override func setUp() async throws {
        LikeStore.shared.reset()
    }

    func testDisplayCountWithoutBumpReturnsServerValue() {
        XCTAssertEqual(LikeStore.shared.displayCount(username: "a", slug: "s", server: 5), 5)
    }

    func testBumpAddsOneWhileServerIsStale() {
        LikeStore.shared.bumpCount(username: "a", slug: "s", baseline: 5)
        XCTAssertEqual(LikeStore.shared.displayCount(username: "a", slug: "s", server: 5), 6)
    }

    func testZeroLikeCardShowsOneAfterBump() {
        LikeStore.shared.bumpCount(username: "a", slug: "s", baseline: 0)
        XCTAssertEqual(LikeStore.shared.displayCount(username: "a", slug: "s", server: 0), 1)
    }

    func testFreshServerCountRetiresBump() {
        LikeStore.shared.bumpCount(username: "a", slug: "s", baseline: 5)
        // 내 좋아요가 반영된 새 응답(6) — 그대로 믿고 +1 하지 않는다.
        XCTAssertEqual(LikeStore.shared.displayCount(username: "a", slug: "s", server: 6), 6)
        // 그 사이 다른 사람 좋아요까지 실려 와도(9) 서버 값 그대로.
        XCTAssertEqual(LikeStore.shared.displayCount(username: "a", slug: "s", server: 9), 9)
    }

    func testBumpIsKeyedPerPost() {
        LikeStore.shared.bumpCount(username: "a", slug: "s", baseline: 5)
        XCTAssertEqual(LikeStore.shared.displayCount(username: "a", slug: "other", server: 5), 5)
        XCTAssertEqual(LikeStore.shared.displayCount(username: "b", slug: "s", server: 5), 5)
    }

    func testResetClearsBumps() {
        LikeStore.shared.bumpCount(username: "a", slug: "s", baseline: 5)
        LikeStore.shared.reset()
        XCTAssertEqual(LikeStore.shared.displayCount(username: "a", slug: "s", server: 5), 5)
    }
}

/// 위젯 딥링크(kurlwidget://…) 라우팅 계약 — 위젯 탭이 분석 분면·서재 탭·저장 글 시트로
/// 정확히 떨어지는지. TabRouter 는 프로세스 공유 싱글턴이라 각 테스트가 상태를 되돌린다.
@MainActor
final class WidgetDeepLinkTests: XCTestCase {

    override func tearDown() {
        TabRouter.shared.pendingStudioSection = nil
        TabRouter.shared.pendingPost = nil
    }

    func testAnalyticsLinkSwitchesToWriteTabAndQueuesSection() {
        WidgetDeepLink.open(URL(string: "kurlwidget://analytics")!)
        XCTAssertEqual(TabRouter.shared.selection, 2, "분석은 글쓰기 탭의 분면")
        XCTAssertEqual(TabRouter.shared.pendingStudioSection, StudioSection.analytics.rawValue)
    }

    func testLibraryLinkSwitchesToAccountTab() {
        WidgetDeepLink.open(URL(string: "kurlwidget://library")!)
        XCTAssertEqual(TabRouter.shared.selection, 4, "서재는 계정 탭에 산다")
    }

    func testPostLinkQueuesSheetRef() {
        WidgetDeepLink.open(URL(string: "kurlwidget://post/hana/slow-reading")!)
        XCTAssertEqual(
            TabRouter.shared.pendingPost,
            WidgetPostRef(username: "hana", slug: "slow-reading"))
    }

    func testMalformedPostLinkIsIgnored() {
        WidgetDeepLink.open(URL(string: "kurlwidget://post/only-one-part")!)
        XCTAssertNil(TabRouter.shared.pendingPost, "재료가 모자라면 조용히 무시 — 404 시트를 띄우지 않는다")
    }

    func testForeignSchemeIsIgnored() {
        let before = TabRouter.shared.selection
        WidgetDeepLink.open(URL(string: "https://blog.kurl.me/@hana/slow-reading")!)
        XCTAssertEqual(TabRouter.shared.selection, before)
        XCTAssertNil(TabRouter.shared.pendingPost)
    }
}
