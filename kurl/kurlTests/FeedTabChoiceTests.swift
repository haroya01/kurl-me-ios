//
//  FeedTabChoiceTests.swift
//  kurlTests
//
//  블로그·노트 피드 머리의 첫 탭 — 같은 이름·같은 순서, 로그인했으면 기억한 탭, 비로그인이면 최신,
//  옛 저장값(구독함·추천)은 새 구조로 옮겨 읽는다. 더 보기는 피드만 담고, 고른 피드는 짧은 이름으로 끝 칸에 선다.
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

    func testTheMoreMenusHoldFeedsOnly() {
        XCTAssertEqual(BlogFeedMoreMenu.feeds, [.forYou])
        XCTAssertEqual(NoteFeedKind.more, [.federated, .bookmarks, .direct])
    }

    func testTheMoreSlotShowsTheChosenFeedWithAShortName() {
        XCTAssertEqual(FeedSource.forYou.moreChoice, SegmentMoreChoice(title: String(localized: "추천"), symbol: "sparkles"))
        let lists = [NoteListSummary(id: 7, title: "동료", memberCount: 2)]
        XCTAssertEqual(NoteMoreFeed.kind(.federated).choice(lists: lists), SegmentMoreChoice(title: String(localized: "다른 서버"), symbol: "globe"))
        XCTAssertEqual(NoteMoreFeed.kind(.bookmarks).choice(lists: lists), SegmentMoreChoice(title: String(localized: "북마크"), symbol: "bookmark"))
        XCTAssertEqual(NoteMoreFeed.kind(.direct).choice(lists: lists), SegmentMoreChoice(title: String(localized: "멘션"), symbol: "at"))
        XCTAssertEqual(NoteMoreFeed.list(7).choice(lists: lists), SegmentMoreChoice(title: "동료", symbol: "list.bullet"))
        XCTAssertEqual(NoteMoreFeed.list(8).choice(lists: lists).title, String(localized: "리스트"), "목록에 없는 리스트는 이름 대신 '리스트'")
    }

    func testAListFeedLeavesWhenItsListIsGone() {
        let lists = [NoteListSummary(id: 7, title: "동료", memberCount: 2)]
        XCTAssertTrue(NoteMoreFeed.list(7).isListed(in: lists))
        XCTAssertFalse(NoteMoreFeed.list(8).isListed(in: lists))
        XCTAssertTrue(NoteMoreFeed.kind(.bookmarks).isListed(in: []), "리스트가 아닌 피드는 목록과 상관없다")
    }
}
