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

    func testRefreshOnFollowingPutsOnlyTheNewOnesAboveWhatIsThere() async {
        let model = model(
            .following,
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

    func testOnlyTheReloadThatSettlesLaunchLiftsTheSplash() async {
        var settled = 0
        let quiet = HomeFeedViewModel(
            tab: .trending, settled: { settled += 1 }, load: { _, _ in HomeFeedBatch(items: [], next: nil) })
        let shown = HomeFeedViewModel(
            tab: .latest, settled: { settled += 1 }, load: { _, _ in throw URLError(.timedOut) })
        Self.kept += [quiet, shown]

        await quiet.reload()
        XCTAssertEqual(settled, 0)
        await shown.reload(settlesLaunch: true)
        XCTAssertEqual(settled, 1, "실패해도 막은 걷힌다")
    }

    func testTheNextPageStartsFiveRowsBeforeTheEnd() async {
        var asked: [String?] = []
        let items = (1...8).map { post(Int64($0)) }
        let model = HomeFeedViewModel(tab: .latest, load: { _, cursor in
            asked.append(cursor)
            return cursor == nil
                ? HomeFeedBatch(items: items, next: "c1")
                : HomeFeedBatch(items: [self.post(9)], next: nil)
        })
        Self.kept.append(model)
        await model.reload()

        await model.loadMoreIfNeeded(current: items[2])
        XCTAssertEqual(asked, [nil])
        await model.loadMoreIfNeeded(current: items[3])
        XCTAssertEqual(asked, [nil, "c1"])
        XCTAssertEqual(model.items.last?.id, "post-9")
    }

    func testARowScrollingAwayDoesNotCancelTheNextPage() async {
        let first = HomeFeedBatch(items: [post(1)], next: "c1")
        let model = HomeFeedViewModel(tab: .latest, load: { _, cursor in
            guard cursor != nil else { return first }
            try await Task.sleep(for: .milliseconds(150))
            return HomeFeedBatch(items: [self.post(2)], next: nil)
        })
        Self.kept.append(model)
        await model.reload()

        let row = Task { await model.loadMoreIfNeeded(current: self.post(1)) }
        row.cancel()
        await row.value

        XCTAssertEqual(model.items.map(\.id), ["post-1", "post-2"])
        XCTAssertNil(model.next)
        XCTAssertFalse(model.isLoadingMore)
    }
}
