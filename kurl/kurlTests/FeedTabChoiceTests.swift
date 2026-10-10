//
//  FeedTabChoiceTests.swift
//  kurlTests
//
//  블로그·노트 피드 머리의 첫 탭 — 같은 이름·같은 순서, 로그인했으면 기억한 탭, 비로그인이면 최신,
//  옛 저장값(구독함·추천)은 새 구조로 옮겨 읽는다.
//

import XCTest

@testable import kurl

@MainActor
final class FeedTabChoiceTests: XCTestCase {

    func testBothFeedsShowFollowingLatestTrendingInOrder() {
        XCTAssertEqual(FeedTab.allCases, [.following, .recent, .trending])
        XCTAssertEqual(NoteFeedKind.tabs, [.following, .everyone, .trending])
        XCTAssertEqual(FeedTab.allCases.map(\.label), NoteFeedKind.tabs.map(\.label))
    }

    func testASignedInReaderKeepsTheRememberedTab() {
        XCTAssertEqual(FeedTab.initialTab(launched: nil, saved: "following", signedIn: true), .following)
        XCTAssertEqual(FeedTab.initialTab(launched: nil, saved: "trending", signedIn: true), .trending)
        XCTAssertEqual(NoteFeedKind.initialTab(launched: nil, saved: "following", signedIn: true), .following)
    }

    func testASignedOutReaderOpensOnLatest() {
        XCTAssertEqual(FeedTab.initialTab(launched: nil, saved: "following", signedIn: false), .recent)
        XCTAssertEqual(FeedTab.initialTab(launched: nil, saved: nil, signedIn: false), .recent)
        XCTAssertEqual(NoteFeedKind.initialTab(launched: nil, saved: "following", signedIn: false), .everyone)
        XCTAssertEqual(NoteFeedKind.initialTab(launched: nil, saved: nil, signedIn: false), .everyone)
    }

    func testOldStoredValuesMapToTheNewTabs() {
        XCTAssertEqual(FeedTab(stored: "following"), .following, "구독함은 같은 저장값으로 팔로잉이 된다")
        XCTAssertEqual(FeedTab(stored: "forYou"), .recent, "추천은 더 보기로 옮겨 최신으로 연다")
        XCTAssertEqual(FeedTab.initialTab(launched: nil, saved: "forYou", signedIn: true), .recent)
        XCTAssertNil(FeedTab(stored: "inbox"))
        XCTAssertEqual(FeedTab.initialTab(launched: nil, saved: "inbox", signedIn: true), .recent)
    }

    func testALaunchArgumentWinsAndMenuOnlyNoteFeedsAreNotTabs() {
        XCTAssertEqual(FeedTab.initialTab(launched: "trending", saved: "following", signedIn: true), .trending)
        XCTAssertEqual(FeedTab.initialTab(launched: "following", saved: nil, signedIn: false), .following)
        XCTAssertEqual(NoteFeedKind.initialTab(launched: "bookmarks", saved: "trending", signedIn: true), .trending)
    }

    func testFollowingNextToLatestWaitsUntilItIsFirstChosen() {
        let tabs = FeedTab.allCases
        func warm(_ tab: FeedTab, selection: FeedTab, opened: Set<FeedTab> = []) -> Bool {
            SwipePagerWarmth.warm(tab, tabs: tabs, selection: selection, loadOnSelect: [.following], opened: opened)
        }
        XCTAssertFalse(warm(.following, selection: .recent), "최신으로 열자마자 팔로잉까지 받으면 안 된다")
        XCTAssertTrue(warm(.trending, selection: .recent))
        XCTAssertTrue(warm(.following, selection: .following))
        XCTAssertTrue(warm(.following, selection: .recent, opened: [.following]), "한 번 연 팔로잉은 옆에 있으면 계속 산다")
        XCTAssertFalse(warm(.following, selection: .trending, opened: [.following]), "두 칸 떨어진 페이지는 그리지 않는다")
        XCTAssertTrue(warm(.recent, selection: .following))
    }
}
