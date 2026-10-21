//
//  HomeFeedRefreshTests.swift
//  kurlTests
//

import XCTest

@testable import kurl

@MainActor
final class HomeFeedRefreshTests: XCTestCase {
    private static var kept: [HomeFeedViewModel] = []

    private func post(_ id: Int64) -> HomeFeedItem {
        HomeFeedItem(kind: .post(FeedItem(
            id: id, author: Author(id: 1, username: "kim", bio: nil, avatarUrl: nil), slug: "p\(id)",
            title: "글 \(id)", excerpt: nil, ogImageUrl: nil, languageTag: "ko", tags: [],
            publishedAt: nil, viewCount: 0, likeCount: 0)))
    }

    private func model(
        _ tab: HomeFeedTab, first: HomeFeedBatch, newer: HomeFeedBatch?, asked: @escaping () -> Void = {}
    ) -> HomeFeedViewModel {
        let model = HomeFeedViewModel(
            tab: tab,
            newer: { _, _ in
                asked()
                return newer ?? first
            },
            load: { _, _ in first })
        Self.kept.append(model)
        return model
    }

    func testRefreshPutsOnlyTheNewOnesAboveWhatIsThere() async {
        let model = model(
            .latest,
            first: HomeFeedBatch(items: [post(2), post(1)], next: "1.1", newest: "0.2"),
            newer: HomeFeedBatch(items: [post(3)], next: nil, newest: "0.3", gap: false))
        await model.reload()
        await model.refresh()
        XCTAssertEqual(model.items.map(\.id), ["post-3", "post-2", "post-1"])
        XCTAssertEqual(model.next, "1.1")
        XCTAssertEqual(model.newest, "0.3")
    }

    func testAGapReplacesTheListWithTheFreshFirstPage() async {
        let model = model(
            .following,
            first: HomeFeedBatch(items: [post(2), post(1)], next: "1.1", newest: "0.2"),
            newer: HomeFeedBatch(items: [post(9), post(8)], next: "2.0", newest: "0.9", gap: true))
        await model.reload()
        await model.refresh()
        XCTAssertEqual(model.items.map(\.id), ["post-9", "post-8"])
        XCTAssertEqual(model.next, "2.0")
    }

    func testTrendingAlwaysStartsOver() async {
        var asked = 0
        let model = model(
            .trending,
            first: HomeFeedBatch(items: [post(1)], next: nil, newest: "0.1"),
            newer: nil, asked: { asked += 1 })
        await model.reload()
        await model.refresh()
        XCTAssertEqual(asked, 0)
        XCTAssertEqual(model.items.map(\.id), ["post-1"])
    }
}
