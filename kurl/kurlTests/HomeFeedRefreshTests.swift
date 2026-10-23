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

    func testRefreshOnFollowingAndBlogPutsOnlyTheNewOnesAboveWhatIsThere() async {
        for tab in [HomeFeedTab.following, .blog] {
            var since: [String] = []
            let model = HomeFeedViewModel(
                tab: tab,
                newer: { _, marker in
                    since.append(marker)
                    return HomeFeedBatch(items: [self.post(3)], next: nil, newest: "0.3", gap: false)
                },
                load: { _, _ in HomeFeedBatch(items: [self.post(2), self.post(1)], next: "1.1", newest: "0.2") })
            Self.kept.append(model)
            await model.reload()
            await model.refresh()
            XCTAssertEqual(since, ["0.2"], "\(tab)")
            XCTAssertEqual(model.items.map(\.id), ["post-3", "post-2", "post-1"], "\(tab)")
            XCTAssertEqual(model.next, "1.1", "\(tab)")
            XCTAssertEqual(model.newest, "0.3", "\(tab)")
        }
    }

    func testAGapReplacesTheListWithTheFreshFirstPage() async {
        for tab in [HomeFeedTab.following, .blog] {
            let model = model(
                tab,
                first: HomeFeedBatch(items: [post(2), post(1)], next: "1.1", newest: "0.2"),
                newer: HomeFeedBatch(items: [post(9), post(8)], next: "2.0", newest: "0.9", gap: true))
            await model.reload()
            await model.refresh()
            XCTAssertEqual(model.items.map(\.id), ["post-9", "post-8"], "\(tab)")
            XCTAssertEqual(model.next, "2.0", "\(tab)")
        }
    }

    func testABlogPullSaysOnlyWhenNothingCameOrItFailed() async {
        var said: [String] = []
        var answer: Result<HomeFeedBatch, Error> = .failure(URLError(.timedOut))
        let model = HomeFeedViewModel(
            tab: .blog,
            notify: { said.append($0) },
            newer: { _, _ in try answer.get() },
            load: { _, _ in HomeFeedBatch(items: [self.post(2), self.post(1)], next: nil, newest: "0.2") })
        Self.kept.append(model)
        await model.reload()

        await model.refresh()
        XCTAssertEqual(said, [String(localized: "새로고침하지 못했습니다")])
        XCTAssertEqual(model.items.map(\.id), ["post-2", "post-1"], "a failed pull keeps the rows")

        answer = .success(HomeFeedBatch(items: [], next: nil, newest: "0.2", gap: false))
        await model.refresh()
        XCTAssertEqual(said.last, String(localized: "새 글이 없어요"))

        answer = .success(HomeFeedBatch(items: [post(3)], next: nil, newest: "0.3", gap: false))
        await model.refresh()
        XCTAssertEqual(said.count, 2, "new posts land without a word")
        XCTAssertEqual(model.items.map(\.id), ["post-3", "post-2", "post-1"])
    }

    func testAPublishedPostLandsOnTopOfALoadedBlogQuietly() async {
        var said: [String] = []
        var since: [String] = []
        var answer: Result<HomeFeedBatch, Error> = .success(
            HomeFeedBatch(items: [post(5)], next: nil, newest: "0.5", gap: false))
        let model = HomeFeedViewModel(
            tab: .blog,
            notify: { said.append($0) },
            newer: { _, marker in
                since.append(marker)
                return try answer.get()
            },
            load: { _, _ in HomeFeedBatch(items: [self.post(2), self.post(1)], next: nil, newest: "0.2") })
        Self.kept.append(model)

        await model.catchUp()
        XCTAssertEqual(since, [], "a blog shelf never opened is not fetched")
        XCTAssertTrue(model.items.isEmpty)

        await model.reload()
        await model.catchUp()
        XCTAssertEqual(since, ["0.2"])
        XCTAssertEqual(model.items.map(\.id), ["post-5", "post-2", "post-1"])

        answer = .failure(URLError(.timedOut))
        await model.catchUp()
        answer = .success(HomeFeedBatch(items: [], next: nil, newest: "0.5", gap: false))
        await model.catchUp()
        XCTAssertEqual(said, [], "catching up after publishing says nothing")
    }

    func testPublishingAPostTellsHome() {
        let before = HomeFeedChoice.shared.publishedPosts
        HomeFeedChoice.shared.postPublished()
        XCTAssertEqual(HomeFeedChoice.shared.publishedPosts, before + 1)
    }

    func testForYouAlwaysStartsOverAndNeverAsksForNewer() async {
        var asked = 0
        let model = model(
            .forYou,
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
            tab: .following, settled: { settled += 1 }, load: { _, _ in HomeFeedBatch(items: [], next: nil) })
        let shown = HomeFeedViewModel(
            tab: .forYou, settled: { settled += 1 }, load: { _, _ in throw URLError(.timedOut) })
        Self.kept += [quiet, shown]

        await quiet.reload()
        XCTAssertEqual(settled, 0)
        await shown.reload(settlesLaunch: true)
        XCTAssertEqual(settled, 1, "실패해도 막은 걷힌다")
    }

    func testTheNextPageStartsFiveRowsBeforeTheEnd() async {
        var asked: [String?] = []
        let items = (1...8).map { post(Int64($0)) }
        let model = HomeFeedViewModel(tab: .forYou, load: { _, cursor in
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
        let model = HomeFeedViewModel(tab: .forYou, load: { _, cursor in
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
