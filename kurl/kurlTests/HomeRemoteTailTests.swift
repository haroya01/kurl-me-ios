import XCTest

@testable import kurl

@MainActor
final class HomeRemoteTailTests: XCTestCase {
    private static var kept: [AnyObject] = []

    private func post(_ id: Int64) -> HomeFeedItem {
        HomeFeedItem(kind: .post(FeedItem(
            id: id, author: Author(id: 1, username: "kim", bio: nil, avatarUrl: nil), slug: "p\(id)",
            title: "글 \(id)", excerpt: nil, ogImageUrl: nil, languageTag: "ko", tags: [],
            publishedAt: nil, viewCount: 0, likeCount: 0)))
    }

    private static func pool(_ n: Int) -> String {
        #"{"id":null,"uri":"https://mstdn.jp/users/a/statuses/\#(n)","body":"p\#(n)","createdAt":"2026-10-17T01:00:00Z","author":{"username":"a@mstdn.jp","displayName":null,"avatarUrl":null,"url":"https://mstdn.jp/@a"},"media":[],"contentWarning":null,"sensitive":false,"language":"ja","likeCount":1,"repostCount":0,"replyCount":0,"poll":null,"linkPreview":null,"remote":null,"servers":["mstdn.jp"]}"#
    }

    private static func page(_ ns: [Int], next: String?) throws -> RemoteStreamPage {
        let json = #"{"items":[\#(ns.map(pool).joined(separator: ","))],"next":\#(next.map { "\"\($0)\"" } ?? "null")}"#
        return try JSONDecoder.blog.decode(RemoteStreamPage.self, from: Data(json.utf8))
    }

    private final class Remote {
        var pages: [String: RemoteStreamPage]
        var asked: [String] = []

        init(_ pages: [String: RemoteStreamPage]) { self.pages = pages }

        func page(_ cursor: String?) throws -> RemoteStreamPage {
            let key = cursor ?? "first"
            asked.append(key)
            guard let page = pages[key] else { throw APIError.server(status: 503, code: nil, detail: "") }
            return page
        }
    }

    private final class Home {
        let pages: [String: HomeFeedBatch]
        let newer: HomeFeedBatch

        init(_ pages: [String: HomeFeedBatch], newer: HomeFeedBatch) {
            self.pages = pages
            self.newer = newer
        }

        func page(_ cursor: String?) throws -> HomeFeedBatch {
            guard let page = pages[cursor ?? "first"] else { throw APIError.server(status: 500, code: nil, detail: "") }
            return page
        }
    }

    private func model(_ tab: HomeFeedTab = .latest, home: Home, remote: Remote) -> HomeFeedViewModel {
        let model = HomeFeedViewModel(
            tab: tab,
            remote: { _, cursor in try remote.page(cursor) },
            newer: { _, _ in home.newer },
            load: { _, cursor in try home.page(cursor) })
        Self.kept += [model, home, remote]
        return model
    }

    private func ids(_ tail: RemoteStreamModel?) -> [String] { tail?.items.map(\.id) ?? [] }

    func testTheTailWaitsUntilKurlHasNoNextPage() async throws {
        let home = Home(
            ["first": HomeFeedBatch(items: [post(2)], next: "1.1", newest: "0.2"),
             "1.1": HomeFeedBatch(items: [post(1)], next: nil)],
            newer: HomeFeedBatch(items: [], next: nil))
        let remote = Remote(["first": try Self.page([1, 2], next: "r2")])
        let model = model(home: home, remote: remote)

        await model.reload()
        XCTAssertFalse(model.showsTail)
        XCTAssertEqual(remote.asked, [], "a reload before the tail is reached asks no other server")

        await model.loadMoreIfNeeded(current: model.items[0])
        XCTAssertNil(model.next)
        XCTAssertTrue(model.showsTail)

        await model.tail?.loadIfNeeded()
        XCTAssertEqual(remote.asked, ["first"])
        XCTAssertEqual(model.tail?.next, "r2")
    }

    func testAnEmptyFirstPageGoesStraightToTheTail() async {
        let home = Home(["first": HomeFeedBatch(items: [], next: nil)], newer: HomeFeedBatch(items: [], next: nil))
        let model = model(home: home, remote: Remote([:]))

        await model.reload()
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertTrue(model.showsTail)
    }

    func testOnlyLatestHasATail() async {
        for tab in [HomeFeedTab.trending, .following] {
            let home = Home(["first": HomeFeedBatch(items: [post(1)], next: nil)], newer: HomeFeedBatch(items: [], next: nil))
            let model = model(tab, home: home, remote: Remote([:]))
            await model.reload()
            XCTAssertNil(model.tail, "\(tab)")
            XCTAssertFalse(model.showsTail, "\(tab)")
        }
    }

    func testPullingToRefreshKeepsTheTailAndAsksForItsFirstPageAgain() async throws {
        let home = Home(
            ["first": HomeFeedBatch(items: [post(1)], next: nil, newest: "0.1")],
            newer: HomeFeedBatch(items: [post(2)], next: nil, newest: "0.2", gap: false))
        let remote = Remote(["first": try Self.page([1, 2], next: "r2"), "r2": try Self.page([3], next: nil)])
        let model = model(home: home, remote: remote)
        await model.reload()
        await model.tail?.loadIfNeeded()
        let last = try XCTUnwrap(model.tail?.items.last)
        await model.tail?.loadMoreIfNeeded(current: last)
        XCTAssertEqual(ids(model.tail).count, 3)

        remote.pages["first"] = try Self.page([4, 1], next: "r1")
        await model.refresh()

        XCTAssertEqual(model.items.map(\.id), ["post-2", "post-1"])
        XCTAssertEqual(remote.asked, ["first", "r2", "first"])
        XCTAssertEqual(
            ids(model.tail),
            ["t-https://mstdn.jp/users/a/statuses/4", "t-https://mstdn.jp/users/a/statuses/1"])
        XCTAssertEqual(model.tail?.next, "r1")
        XCTAssertTrue(model.showsTail)
    }

    func testARefreshThatFailsOnTheOtherServerKeepsWhatWasThere() async throws {
        let home = Home(
            ["first": HomeFeedBatch(items: [post(1)], next: nil, newest: "0.1")],
            newer: HomeFeedBatch(items: [], next: nil, newest: "0.1", gap: false))
        let remote = Remote(["first": try Self.page([1], next: nil)])
        let model = model(home: home, remote: remote)
        await model.reload()
        await model.tail?.loadIfNeeded()

        remote.pages = [:]
        await model.refresh()

        XCTAssertEqual(remote.asked, ["first", "first"])
        XCTAssertEqual(ids(model.tail), ["t-https://mstdn.jp/users/a/statuses/1"])
        XCTAssertTrue(model.showsTail)
    }

    func testAGapRefreshHidesTheTailUntilKurlRunsOutAgain() async throws {
        let home = Home(
            ["first": HomeFeedBatch(items: [post(1)], next: nil, newest: "0.1")],
            newer: HomeFeedBatch(items: [post(9)], next: "9.0", newest: "0.9", gap: true))
        let remote = Remote(["first": try Self.page([1], next: nil)])
        let model = model(home: home, remote: remote)
        await model.reload()
        await model.tail?.loadIfNeeded()

        await model.refresh()

        XCTAssertEqual(model.next, "9.0")
        XCTAssertFalse(model.showsTail)
        XCTAssertEqual(remote.asked, ["first", "first"])
        XCTAssertEqual(ids(model.tail), ["t-https://mstdn.jp/users/a/statuses/1"])
    }
}
