//
//  FeedPageChaseTests.swift
//  kurlTests
//
//  피드 페이지 이어받기(collectKept) — 차단 작가가 연속 페이지를 통째로 차지해도
//  피드가 글 한둘에서 조용히 끝나지 않는다는 계약을 못박는다.
//

import XCTest
@testable import kurl

@MainActor
final class FeedPageChaseTests: XCTestCase {

    private func item(_ id: Int64, author: String = "author") -> FeedItem {
        FeedItem(
            id: id,
            author: Author(id: 1, username: author, bio: nil, avatarUrl: nil),
            slug: "post-\(id)",
            title: "글 \(id)",
            excerpt: nil,
            ogImageUrl: nil,
            languageTag: "ko",
            tags: [],
            publishedAt: nil,
            viewCount: 0,
            likeCount: 0)
    }

    private func page(_ items: [FeedItem], hasNext: Bool) -> PublicFeedView {
        PublicFeedView(items: items, page: 0, size: items.count, hasNext: hasNext)
    }

    /// 걸러서 빈 페이지는 응답이 아니라 통과 — 남는 카드가 나올 때까지 다음 페이지를 이어 받는다.
    func testChasesPastFullyFilteredPages() async throws {
        let pages: [PublicFeedView] = [
            page((0..<20).map { item($0, author: "blocked") }, hasNext: true),
            page((20..<40).map { item($0, author: "blocked") }, hasNext: true),
            page([item(40, author: "blocked"), item(41)], hasNext: true),
        ]
        var fetched: [Int] = []
        let result = try await FeedViewModel.collectKept(
            from: 0, seen: [], isKept: { $0.author.username != "blocked" }
        ) { p in
            fetched.append(p)
            return pages[p]
        }
        XCTAssertEqual(fetched, [0, 1, 2])
        XCTAssertEqual(result.kept.map(\.id), [41])
        XCTAssertEqual(result.page, 2)
        XCTAssertTrue(result.hasNext)
    }

    /// 첫 페이지에서 카드가 남으면 더 긁지 않는다 — 이어받기는 소멸 시에만.
    func testStopsAtFirstPageWithKeptCards() async throws {
        var fetched = 0
        let result = try await FeedViewModel.collectKept(
            from: 3, seen: [], isKept: { _ in true }
        ) { _ in
            fetched += 1
            return self.page([self.item(1), self.item(2)], hasNext: true)
        }
        XCTAssertEqual(fetched, 1)
        XCTAssertEqual(result.kept.count, 2)
        XCTAssertEqual(result.page, 3)
    }

    /// 피드 끝(hasNext=false)이면 전량 걸러졌어도 멈춘다 — 빈 상태는 빈 상태로.
    func testStopsAtFeedEndWhenAllFiltered() async throws {
        let result = try await FeedViewModel.collectKept(
            from: 0, seen: [], isKept: { _ in false }
        ) { _ in
            self.page([self.item(1)], hasNext: false)
        }
        XCTAssertTrue(result.kept.isEmpty)
        XCTAssertFalse(result.hasNext)
    }

    /// 상한 — 전량 소멸이 끝없이 이어져도 한 호출은 cap 페이지까지만 긁는다.
    func testCapBoundsChase() async throws {
        var fetched = 0
        let result = try await FeedViewModel.collectKept(
            from: 0, seen: [], cap: 5, isKept: { _ in false }
        ) { p in
            fetched += 1
            return self.page([self.item(Int64(p))], hasNext: true)
        }
        XCTAssertEqual(fetched, 5)
        XCTAssertTrue(result.kept.isEmpty)
        XCTAssertEqual(result.page, 4)
        XCTAssertTrue(result.hasNext)
    }

    /// 서버 페이지가 겹쳐 와도, 이미 화면에 있는 id 도 두 번 박히지 않는다.
    func testDedupesAgainstSeenAndAcrossPages() async throws {
        let pages: [PublicFeedView] = [
            page([item(1), item(2), item(3)], hasNext: true),
        ]
        let result = try await FeedViewModel.collectKept(
            from: 0, seen: [1], isKept: { _ in true }
        ) { p in pages[p] }
        XCTAssertEqual(result.kept.map(\.id), [2, 3])
    }
}
