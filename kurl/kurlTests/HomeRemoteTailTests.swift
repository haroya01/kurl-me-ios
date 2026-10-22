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

@MainActor
final class RemoteSeenTests: XCTestCase {
    private static var kept: [AnyObject] = []

    private static func pool(_ n: Int) -> String {
        #"{"id":null,"uri":"https://mstdn.jp/users/a/statuses/\#(n)","body":"p\#(n)","createdAt":"2026-10-17T01:00:00Z","author":{"username":"a@mstdn.jp","displayName":null,"avatarUrl":null,"url":"https://mstdn.jp/@a"},"media":[],"contentWarning":null,"sensitive":false,"language":"ja","likeCount":1,"repostCount":0,"replyCount":0,"poll":null,"linkPreview":null,"remote":null,"servers":["mstdn.jp"]}"#
    }

    private static func page(_ ns: [Int], next: String?, seenFrom: Int? = nil) throws -> RemoteStreamPage {
        let seen = seenFrom.map { #","seenFrom":\#($0)"# } ?? ""
        let json = #"{"items":[\#(ns.map(pool).joined(separator: ","))],"next":\#(next.map { "\"\($0)\"" } ?? "null")\#(seen)}"#
        return try JSONDecoder.blog.decode(RemoteStreamPage.self, from: Data(json.utf8))
    }

    private static func uri(_ n: Int) -> String { "https://mstdn.jp/users/a/statuses/\(n)" }

    private final class Pager {
        let pages: [String: RemoteStreamPage]
        var asked: [String] = []

        init(_ pages: [String: RemoteStreamPage]) { self.pages = pages }

        func page(_ cursor: String?) throws -> RemoteStreamPage {
            let key = cursor ?? "first"
            asked.append(key)
            guard let page = pages[key] else { throw APIError.server(status: 500, code: nil, detail: "") }
            return page
        }
    }

    @MainActor
    private final class Sink {
        var batches: [[String]] = []
        var failures = 0

        func send(_ uris: [String]) throws {
            batches.append(uris)
            if failures > 0 {
                failures -= 1
                throw APIError.http(status: 503)
            }
        }
    }

    @MainActor
    private final class Gate {
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            waiters.forEach { $0.resume() }
            waiters = []
        }
    }

    private func stream(_ pager: Pager) -> RemoteStreamModel {
        let model = RemoteStreamModel(feed: .latest) { _, cursor in try pager.page(cursor) }
        Self.kept += [model, pager]
        return model
    }

    private func reporter(_ sink: Sink, gate: Gate? = nil) -> RemoteSeenReporter {
        let gate = gate ?? Gate()
        let reporter = RemoteSeenReporter(send: { try sink.send($0) }, wait: { await gate.wait() })
        Self.kept += [reporter, sink, gate]
        return reporter
    }

    private func settle(_ until: () -> Bool) async {
        for _ in 0..<2000 where !until() { await Task.yield() }
    }

    func testSeenFromDecodesAndMarksWhereTheSeenPartStarts() async throws {
        let plain = try Self.page([1], next: nil)
        XCTAssertNil(plain.seenFrom)
        let pager = Pager(["first": try Self.page([1, 2, 3, 4], next: "s1", seenFrom: 2)])
        let model = stream(pager)

        await model.reload()

        XCTAssertEqual(model.firstSeenID, "t-\(Self.uri(3))")
        XCTAssertEqual(model.items.map { model.isSeen($0) }, [false, false, true, true])
    }

    func testTheSeenPartCanStartOnALaterPageAndOnlyTheFirstOneCounts() async throws {
        let pager = Pager([
            "first": try Self.page([1, 2], next: "u2"),
            "u2": try Self.page([3, 4], next: "s4", seenFrom: 1),
            "s4": try Self.page([5], next: nil, seenFrom: 0),
        ])
        let model = stream(pager)

        await model.reload()
        XCTAssertNil(model.firstSeenID)
        await model.loadMore()
        XCTAssertEqual(model.firstSeenID, "t-\(Self.uri(4))")
        await model.loadMore()
        XCTAssertEqual(model.firstSeenID, "t-\(Self.uri(4))")
        XCTAssertEqual(model.items.map { model.isSeen($0) }, [false, false, false, true, true])

        await model.reload()
        XCTAssertNil(model.firstSeenID, "a fresh first page forgets the old divider")
    }

    func testPoolItemsAndStoredNotesBothReportTheirUri() throws {
        let stored = #"{"id":7,"uri":"https://mastodon.social/users/mina/statuses/7","body":"kept","createdAt":"2026-10-16T01:00:00Z","editedAt":null,"likeCount":null,"likedByMe":false,"author":{"id":-9800,"username":"mina@mastodon.social","bio":null,"avatarUrl":null,"displayName":"Mina","remoteId":9800,"url":"https://mastodon.social/@mina"},"media":[],"quotedPost":null,"inReplyToId":null,"replyCount":0,"repostCount":null,"repostedByMe":false,"quotedNote":null,"linkPreview":null}"#
        let json = #"{"items":[\#(Self.pool(1)),\#(stored)],"next":null}"#
        let page = try JSONDecoder.blog.decode(RemoteStreamPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.items.map(\.seenURI), [Self.uri(1), "https://mastodon.social/users/mina/statuses/7"])
    }

    func testEmptyPagesAreFollowedUpToThreeTimesThenWaitForTheNextScroll() async throws {
        let pager = Pager([
            "first": try Self.page([], next: "a"),
            "a": try Self.page([], next: "b"),
            "b": try Self.page([], next: "c"),
            "c": try Self.page([], next: "d"),
            "d": try Self.page([7], next: nil, seenFrom: 0),
        ])
        let model = stream(pager)

        await model.reload()
        XCTAssertEqual(pager.asked, ["first", "a", "b", "c"])
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertEqual(model.next, "d")

        await model.loadMore()
        XCTAssertEqual(pager.asked, ["first", "a", "b", "c", "d"])
        XCTAssertEqual(model.items.map(\.id), ["t-\(Self.uri(7))"])
        XCTAssertEqual(model.firstSeenID, "t-\(Self.uri(7))")
    }

    func testAnEmptyPageInTheMiddleIsFollowedRightAway() async throws {
        let pager = Pager([
            "first": try Self.page([1], next: "a"),
            "a": try Self.page([], next: "b"),
            "b": try Self.page([2], next: nil),
        ])
        let model = stream(pager)

        await model.reload()
        await model.loadMoreIfNeeded(current: model.items[0])

        XCTAssertEqual(pager.asked, ["first", "a", "b"])
        XCTAssertEqual(model.items.count, 2)
    }

    func testTwentyMarksSendOneBatch() async {
        let sink = Sink()
        let reporter = reporter(sink)

        for n in 1...19 { reporter.mark(Self.uri(n)) }
        await Task.yield()
        XCTAssertEqual(sink.batches.count, 0)

        reporter.mark(Self.uri(20))
        await settle { !sink.batches.isEmpty }
        XCTAssertEqual(sink.batches, [(1...20).map(Self.uri)])
        XCTAssertEqual(reporter.queued, 0)
    }

    func testTheTimerSendsWhatHasGatheredSoFar() async {
        let sink = Sink()
        let gate = Gate()
        let reporter = reporter(sink, gate: gate)

        reporter.mark(Self.uri(1))
        reporter.mark(Self.uri(2))
        await Task.yield()
        XCTAssertEqual(sink.batches.count, 0)

        gate.open()
        await settle { !sink.batches.isEmpty }
        XCTAssertEqual(sink.batches, [[Self.uri(1), Self.uri(2)]])
    }

    func testAFlushSendsEarlyAndAUriIsSentOncePerSession() async {
        let sink = Sink()
        let reporter = reporter(sink)

        reporter.mark(Self.uri(1))
        reporter.mark(Self.uri(1))
        await reporter.flush().value
        reporter.mark(Self.uri(1))
        reporter.mark(Self.uri(2))
        await reporter.flush().value
        await reporter.flush().value

        XCTAssertEqual(sink.batches, [[Self.uri(1)], [Self.uri(2)]])
    }

    func testAFailedBatchRidesWithTheNextOneOnceThenIsDropped() async {
        let sink = Sink()
        sink.failures = 2
        let reporter = reporter(sink)

        reporter.mark(Self.uri(1))
        await reporter.flush().value
        XCTAssertEqual(reporter.queued, 1)

        reporter.mark(Self.uri(2))
        await reporter.flush().value
        XCTAssertEqual(sink.batches, [[Self.uri(1)], [Self.uri(1), Self.uri(2)]])
        XCTAssertEqual(reporter.queued, 1, "uri 1 failed twice and is dropped, uri 2 waits for one more try")

        reporter.mark(Self.uri(1))
        await reporter.flush().value
        XCTAssertEqual(sink.batches.last, [Self.uri(2), Self.uri(1)])
        XCTAssertEqual(reporter.queued, 0)
    }

    func testFailuresPilingUpKeepAtMostTwoHundredQueued() async {
        let down = Gate()
        var calls = 0
        let reporter = RemoteSeenReporter(
            send: { _ in
                calls += 1
                await down.wait()
                throw APIError.http(status: 503)
            },
            wait: { await Gate().wait() })
        Self.kept += [reporter, down]

        for n in 1...220 { reporter.mark(Self.uri(n)) }
        await settle { calls == 11 }
        XCTAssertEqual(calls, 11)
        XCTAssertEqual(reporter.queued, 0)

        down.open()
        await settle { reporter.queued == RemoteSeenReporter.queueLimit }
        XCTAssertEqual(reporter.queued, 200)
        reporter.mark(Self.uri(999))
        XCTAssertEqual(reporter.queued, 200)
    }
}
