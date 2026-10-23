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
        var pages: [String: HomeFeedBatch]
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

    private func ids(_ remote: RemoteStreamModel?) -> [String] { remote?.items.map(\.id) ?? [] }

    private func shape(_ rows: [HomeMix.Row]) -> [String] {
        rows.map { row in
            switch row {
            case .own(let item): item.id
            case .remote(let item, let mixed): "\(mixed ? "mix" : "end"):\(item.key.split(separator: "/").last ?? "")"
            }
        }
    }

    private static func pool(_ ns: [Int]) throws -> [RemoteStreamItem] {
        try page(ns, next: nil).items
    }

    func testTwoForYouPostsFollowEveryFiveOfMine() throws {
        let own = (1...12).map(post)
        let rows = HomeMix.rows(own: own, remote: try Self.pool(Array(1...9)), ownDone: false)
        XCTAssertEqual(shape(rows), [
            "post-1", "post-2", "post-3", "post-4", "post-5", "mix:1", "mix:2",
            "post-6", "post-7", "post-8", "post-9", "post-10", "mix:3", "mix:4",
            "post-11", "post-12",
        ])
        XCTAssertEqual(HomeMix.unused(own: own, remote: try Self.pool(Array(1...9))), 5)
    }

    func testOnceMineRunsOutTheRestOfForYouCarriesOn() throws {
        let rows = HomeMix.rows(own: (1...6).map(post), remote: try Self.pool([1, 2, 3, 4]), ownDone: true)
        XCTAssertEqual(shape(rows), [
            "post-1", "post-2", "post-3", "post-4", "post-5", "mix:1", "mix:2", "post-6", "end:3", "end:4",
        ])
        XCTAssertEqual(
            shape(HomeMix.rows(own: [], remote: try Self.pool([1, 2]), ownDone: true)), ["end:1", "end:2"])
    }

    func testAnEmptyForYouLeavesMyFeedAsItIs() {
        let own = (1...7).map(post)
        XCTAssertEqual(shape(HomeMix.rows(own: own, remote: [], ownDone: true)), own.map(\.id))
        XCTAssertEqual(shape(HomeMix.rows(own: own, remote: [], ownDone: false)), own.map(\.id))
    }

    func testAStoredNoteAlreadyInMyFeedIsNotMixedInAgain() throws {
        let stored = #"{"id":7,"uri":"https://mastodon.social/users/mina/statuses/7","body":"kept","createdAt":"2026-10-16T01:00:00Z","editedAt":null,"likeCount":null,"likedByMe":false,"author":{"id":-9800,"username":"mina@mastodon.social","bio":null,"avatarUrl":null,"displayName":"Mina","remoteId":9800,"url":"https://mastodon.social/@mina"},"media":[],"quotedPost":null,"inReplyToId":null,"replyCount":0,"repostCount":null,"repostedByMe":false,"quotedNote":null,"linkPreview":null}"#
        let json = #"{"items":[\#(stored),\#(Self.pool(1)),\#(Self.pool(2))],"next":null}"#
        let remote = try JSONDecoder.blog.decode(RemoteStreamPage.self, from: Data(json.utf8)).items
        guard case .kept(let note) = remote[0] else { return XCTFail("stored note did not decode") }
        var own = (1...4).map(post)
        own.insert(HomeFeedItem(kind: .note(note)), at: 2)

        XCTAssertEqual(
            shape(HomeMix.rows(own: own, remote: remote, ownDone: false)),
            ["post-1", "post-2", "note-7", "post-3", "post-4", "mix:1", "mix:2"])
    }

    func testAnotherPageOfMineKeepsWhatWasAlreadyPlaced() throws {
        let remote = try Self.pool(Array(1...6))
        let first = HomeMix.rows(own: (1...7).map(post), remote: remote, ownDone: false)
        let more = HomeMix.rows(own: (1...14).map(post), remote: remote, ownDone: false)
        XCTAssertEqual(Array(shape(more).prefix(first.count)), shape(first))
        XCTAssertEqual(shape(more).filter { $0.hasPrefix("mix") }, ["mix:1", "mix:2", "mix:3", "mix:4"])
        XCTAssertEqual(
            shape(HomeMix.rows(own: (1...14).map(post), remote: remote, ownDone: false)), shape(more),
            "the same answers place the same way")
    }

    func testForYouLoadsWithMyFeedAndCarriesOnOnlyAfterMineRunsOut() async throws {
        let home = Home(
            ["first": HomeFeedBatch(items: [post(2)], next: "1.1", newest: "0.2"),
             "1.1": HomeFeedBatch(items: [post(1)], next: nil)],
            newer: HomeFeedBatch(items: [], next: nil))
        let remote = Remote(["first": try Self.page([1, 2], next: "r2")])
        let model = model(home: home, remote: remote)

        await model.reload()
        XCTAssertEqual(remote.asked, ["first"], "for-you comes in with the first page of mine")
        XCTAssertEqual(shape(model.rows), ["post-2"])

        await model.loadMoreIfNeeded(current: model.rows[0])
        XCTAssertNil(model.next)
        XCTAssertEqual(shape(model.rows), ["post-2", "post-1", "end:1", "end:2"])
    }

    func testRunningLowOnForYouAsksForTheNextPage() async throws {
        let home = Home(
            ["first": HomeFeedBatch(items: (1...10).map(post), next: "p2", newest: "0.10"),
             "p2": HomeFeedBatch(items: (11...20).map(post), next: "p3")],
            newer: HomeFeedBatch(items: [], next: nil))
        let remote = Remote([
            "first": try Self.page([1, 2, 3, 4, 5], next: "r2"),
            "r2": try Self.page([6, 7, 8, 9], next: nil),
        ])
        let model = model(home: home, remote: remote)
        await model.reload()
        XCTAssertEqual(remote.asked, ["first"])

        await model.loadMoreIfNeeded(current: model.rows[0])
        XCTAssertEqual(remote.asked, ["first", "r2"], "one left after two slots is below the low water")
        XCTAssertEqual(model.remote?.items.count, 9)
    }

    func testAnEmptyFirstPageIsAllForYou() async throws {
        let home = Home(["first": HomeFeedBatch(items: [], next: nil)], newer: HomeFeedBatch(items: [], next: nil))
        let model = model(home: home, remote: Remote(["first": try Self.page([1], next: nil)]))

        await model.reload()
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertEqual(shape(model.rows), ["end:1"])
    }

    func testTheMixIsTheForYouFeed() async throws {
        let home = Home(["first": HomeFeedBatch(items: [], next: nil)], newer: HomeFeedBatch(items: [], next: nil))
        var feeds: [RemoteStreamFeed] = []
        let model = HomeFeedViewModel(
            tab: .latest,
            remote: { feed, _ in
                feeds.append(feed)
                return try Self.page([1], next: nil)
            },
            newer: { _, _ in home.newer },
            load: { _, cursor in try home.page(cursor) })
        Self.kept += [model, home]

        await model.reload()

        XCTAssertEqual(model.remote?.feed, .forYou)
        XCTAssertEqual(feeds, [.forYou])
    }

    func testOnlyLatestMixes() async throws {
        for tab in [HomeFeedTab.trending, .following] {
            let home = Home(["first": HomeFeedBatch(items: (1...6).map(post), next: nil)], newer: HomeFeedBatch(items: [], next: nil))
            let remote = Remote(["first": try Self.page([1, 2], next: nil)])
            let model = model(tab, home: home, remote: remote)
            await model.reload()
            XCTAssertNil(model.remote, "\(tab)")
            XCTAssertEqual(shape(model.rows), (1...6).map { "post-\($0)" }, "\(tab)")
            XCTAssertEqual(remote.asked, [], "\(tab)")
        }
    }

    private static let t0 = Date(timeIntervalSince1970: 1_792_000_000)

    private static func uri(_ n: Int) -> String { "https://mstdn.jp/users/a/statuses/\(n)" }

    private static func dated(_ n: Int, _ at: Date) -> String {
        pool(n).replacingOccurrences(
            of: "2026-10-17T01:00:00Z", with: ISO8601DateFormatter().string(from: at))
    }

    private static func datedPage(_ items: [String], next: String?) throws -> RemoteStreamPage {
        let json = #"{"items":[\#(items.joined(separator: ","))],"next":\#(next.map { "\"\($0)\"" } ?? "null")}"#
        return try JSONDecoder.blog.decode(RemoteStreamPage.self, from: Data(json.utf8))
    }

    private final class Clock {
        var now = HomeRemoteTailTests.t0
        var said: [String] = []
        var events: [String] = []
    }

    private final class Newer {
        var batch = HomeFeedBatch(items: [], next: nil, newest: "0.6", gap: false)
        var fails = false

        func answer() throws -> HomeFeedBatch {
            if fails { throw APIError.server(status: 503, code: nil, detail: "") }
            return batch
        }
    }

    private func pulling(
        _ tab: HomeFeedTab = .latest, own: [HomeFeedItem], remote: Remote, newer: Newer, clock: Clock,
        home: Home? = nil
    ) -> HomeFeedViewModel {
        let home = home ?? Home(["first": HomeFeedBatch(items: own, next: nil, newest: "0.6")], newer: newer.batch)
        let model = HomeFeedViewModel(
            tab: tab,
            now: { clock.now },
            notify: { clock.said.append($0) },
            flushSeen: { clock.events.append("flush") },
            seenBefore: { _ in false },
            cached: { _ in nil },
            remote: { _, cursor in try remote.page(cursor) },
            newer: { _, _ in
                clock.events.append("newer")
                return try newer.answer()
            },
            load: { _, cursor in
                clock.events.append("load")
                return try home.page(cursor)
            })
        Self.kept += [model, home, remote, newer, clock]
        return model
    }

    func testHomeIsStaleOnlyAfterThirtyMinutesAway() {
        let left = Self.t0
        XCTAssertFalse(HomeMix.needsReload(leftAt: nil, now: left.addingTimeInterval(9_999)))
        XCTAssertFalse(HomeMix.needsReload(leftAt: left, now: left.addingTimeInterval(1_799)))
        XCTAssertTrue(HomeMix.needsReload(leftAt: left, now: left.addingTimeInterval(1_800)))
    }

    private static var nothingNew: String { String(localized: "새 글이 없어요") }
    private static var couldNotRefresh: String { String(localized: "새로고침하지 못했습니다") }

    private struct Pulled {
        let model: HomeFeedViewModel
        let home: Home
        let remote: Remote
        let clock: Clock
    }

    private func pulled(_ tab: HomeFeedTab = .latest) async throws -> Pulled {
        let home = Home(["first": HomeFeedBatch(items: (1...6).map(post), next: nil, newest: "0.6")], newer: Newer().batch)
        let remote = Remote(["first": try Self.page([1, 2], next: nil)])
        let clock = Clock()
        let model = pulling(tab, own: [], remote: remote, newer: Newer(), clock: clock, home: home)
        await model.reload()
        clock.events = []
        return Pulled(model: model, home: home, remote: remote, clock: clock)
    }

    func testAPullSendsWhatWasSeenThenAsksForBothFirstPagesAgain() async throws {
        let it = try await pulled()

        await it.model.refresh()

        XCTAssertEqual(it.clock.events, ["flush", "load"])
        XCTAssertEqual(it.remote.asked, ["first", "first"])
    }

    func testAPullThatBringsBackTheSameRowsSaysNothingNew() async throws {
        let it = try await pulled()
        let before = shape(it.model.rows)

        await it.model.refresh()

        XCTAssertEqual(shape(it.model.rows), before)
        XCTAssertEqual(it.clock.said, [Self.nothingNew])
    }

    func testAPullWithoutWhatWasSeenLaysOutTheUnseenAfreshWithoutAToast() async throws {
        let it = try await pulled()
        it.home.pages["first"] = HomeFeedBatch(items: [post(9)] + (4...6).map(post), next: nil, newest: "0.9")
        it.remote.pages["first"] = try Self.page([3, 4], next: nil)

        await it.model.refresh()

        XCTAssertEqual(shape(it.model.rows), ["post-9", "post-4", "post-5", "post-6", "end:3", "end:4"])
        XCTAssertTrue(it.clock.said.isEmpty)
    }

    func testAPullThatHidesSomethingButAddsNothingSaysNothingNew() async throws {
        let it = try await pulled()
        it.home.pages["first"] = HomeFeedBatch(items: (4...6).map(post), next: nil, newest: "0.6")
        it.remote.pages["first"] = try Self.page([2], next: nil)

        await it.model.refresh()

        XCTAssertEqual(shape(it.model.rows), ["post-4", "post-5", "post-6", "end:2"])
        XCTAssertEqual(it.clock.said, [Self.nothingNew])
    }

    func testAPullThatComesBackEmptyLeavesItToTheEndLine() async throws {
        let it = try await pulled()
        it.home.pages["first"] = HomeFeedBatch(items: [], next: nil, newest: "0.6")
        it.remote.pages["first"] = try Self.page([], next: nil)

        await it.model.refresh()

        XCTAssertTrue(it.model.rows.isEmpty)
        XCTAssertTrue(it.clock.said.isEmpty, "the end line says all seen, no toast on top of it")
    }

    func testAPullWhoseOwnFeedFailsKeepsTheListAndSaysSo() async throws {
        let it = try await pulled()
        let before = shape(it.model.rows)
        it.home.pages = [:]

        await it.model.refresh()

        XCTAssertEqual(shape(it.model.rows), before)
        XCTAssertEqual(it.clock.said, [Self.couldNotRefresh])
    }

    func testAPullWithOnlyForYouFailingAndNothingNewSaysTheRefreshFailed() async throws {
        let it = try await pulled()
        it.remote.pages = [:]

        await it.model.refresh()

        XCTAssertEqual(it.clock.said, [Self.couldNotRefresh])
    }

    func testFollowingStillAsksOnlyForNewerPostsAndDoesNotWaitForTheSeenBatch() async throws {
        let it = try await pulled(.following)

        await it.model.refresh()

        XCTAssertEqual(it.clock.events, ["newer"])
        XCTAssertEqual(it.clock.said, [Self.nothingNew])
    }

    func testComingBackAfterThirtyMinutesSendsWhatWasSeenAndReloadsQuietly() async throws {
        let it = try await pulled()
        it.model.left()
        it.clock.now = it.clock.now.addingTimeInterval(1_800)

        await it.model.returned()

        XCTAssertEqual(it.clock.events, ["flush", "load"])
        XCTAssertEqual(it.remote.asked, ["first", "first"])
        XCTAssertTrue(it.clock.said.isEmpty)
    }

    func testTheCachedFirstPageLeavesOutWhatWasSeenOnLatestOnly() async {
        let saved = (1...3).map(post)
        for tab in [HomeFeedTab.latest, .following] {
            let model = HomeFeedViewModel(
                tab: tab,
                seenBefore: { $0.id == "post-2" },
                cached: { _ in HomeFeedBatch(items: saved, next: "p2", newest: "0.3") },
                remote: { _, _ in throw APIError.server(status: 503, code: nil, detail: "") },
                newer: { _, _ in HomeFeedBatch(items: [], next: nil) },
                load: { _, _ in throw APIError.server(status: 503, code: nil, detail: "") })
            Self.kept.append(model)

            await model.reload()

            XCTAssertEqual(
                model.items.map(\.id), tab == .latest ? ["post-1", "post-3"] : ["post-1", "post-2", "post-3"], "\(tab)")
        }
    }

    func testEveryHomeRowHasTheKeyItIsReportedBy() throws {
        let stored = #"{"id":7,"uri":"https://mastodon.social/users/mina/statuses/7","body":"kept","createdAt":"2026-10-16T01:00:00Z","editedAt":null,"likeCount":null,"likedByMe":false,"author":{"id":-9800,"username":"mina@mastodon.social","bio":null,"avatarUrl":null,"displayName":"Mina","remoteId":9800,"url":"https://mastodon.social/@mina"},"media":[],"quotedPost":null,"inReplyToId":null,"replyCount":0,"repostCount":null,"repostedByMe":false,"quotedNote":null,"linkPreview":null}"#
        let note = try JSONDecoder.blog.decode(Note.self, from: Data(stored.utf8))
        let remote = try Self.pool([3])
        let rows = HomeMix.rows(
            own: [post(5), HomeFeedItem(kind: .note(note))], remote: remote, ownDone: true)

        XCTAssertEqual(rows.map(\.seenKey), ["kurl:post:5", "kurl:note:7", Self.uri(3)])
    }

    func testComingBackAfterThirtyMinutesReloadsBothAndShorterDoesNot() async throws {
        let old = Self.t0.addingTimeInterval(-3_600)
        let remote = Remote(["first": try Self.datedPage([1, 2].map { Self.dated($0, old) }, next: nil)])
        let clock = Clock()
        let model = pulling(own: (1...6).map(post), remote: remote, newer: Newer(), clock: clock)
        await model.reload()

        model.left()
        clock.now = Self.t0.addingTimeInterval(1_799)
        await model.returned()
        XCTAssertEqual(remote.asked, ["first"])

        model.left()
        clock.now = clock.now.addingTimeInterval(1_800)
        await model.returned()
        XCTAssertEqual(remote.asked, ["first", "first"])
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
        var sent: [RemoteSeenBatch] = []
        var failures = 0

        var batches: [[String]] { sent.map(\.uris) }

        func send(_ batch: RemoteSeenBatch) throws {
            sent.append(batch)
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
        XCTAssertEqual(model.seenDividerID, "t-\(Self.uri(3))")
        XCTAssertEqual(model.items.map { model.isSeen($0) }, [false, false, true, true])
    }

    func testTheSameNoteInTwoFeedsGetsADifferentRowKey() async throws {
        let page = try Self.page([1, 2], next: nil)
        let trending = RemoteStreamModel(feed: .trending) { _, _ in page }
        let latest = RemoteStreamModel(feed: .latest) { _, _ in page }
        Self.kept += [trending, latest]

        await trending.reload()
        await latest.reload()

        XCTAssertEqual(trending.items.map(\.id), latest.items.map(\.id))
        XCTAssertTrue(Set(trending.rows.map(\.key)).isDisjoint(with: latest.rows.map(\.key)))
        XCTAssertEqual(latest.rows.map(\.index), [0, 1])
    }

    func testWhenEverythingIsSeenThereIsNoDividerUnderTheHeading() async throws {
        let pager = Pager(["first": try Self.page([1, 2], next: nil, seenFrom: 0)])
        let model = stream(pager)

        await model.reload()

        XCTAssertEqual(model.firstSeenID, "t-\(Self.uri(1))")
        XCTAssertNil(model.seenDividerID)
        XCTAssertEqual(model.items.map { model.isSeen($0) }, [true, true])
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

        for n in 1...19 { reporter.mark(Self.uri(n), feed: .latest) }
        await Task.yield()
        XCTAssertEqual(sink.batches.count, 0)

        reporter.mark(Self.uri(20), feed: .latest)
        await settle { !sink.batches.isEmpty }
        XCTAssertEqual(sink.batches, [(1...20).map(Self.uri)])
        XCTAssertEqual(reporter.queued, 0)
    }

    func testTheTimerSendsWhatHasGatheredSoFar() async {
        let sink = Sink()
        let gate = Gate()
        let reporter = reporter(sink, gate: gate)

        reporter.mark(Self.uri(1), feed: .latest)
        reporter.mark(Self.uri(2), feed: .latest)
        await Task.yield()
        XCTAssertEqual(sink.batches.count, 0)

        gate.open()
        await settle { !sink.batches.isEmpty }
        XCTAssertEqual(sink.batches, [[Self.uri(1), Self.uri(2)]])
    }

    func testAFlushSendsEarlyAndAUriIsSentOncePerSession() async {
        let sink = Sink()
        let reporter = reporter(sink)

        reporter.mark(Self.uri(1), feed: .latest)
        reporter.mark(Self.uri(1), feed: .latest)
        await reporter.flush().value
        reporter.mark(Self.uri(1), feed: .latest)
        reporter.mark(Self.uri(2), feed: .latest)
        await reporter.flush().value
        await reporter.flush().value

        XCTAssertEqual(sink.batches, [[Self.uri(1)], [Self.uri(2)]])
    }

    func testAFailedBatchRidesWithTheNextOneOnceThenIsDropped() async {
        let sink = Sink()
        sink.failures = 2
        let reporter = reporter(sink)

        reporter.mark(Self.uri(1), feed: .latest)
        await reporter.flush().value
        XCTAssertEqual(reporter.queued, 1)

        reporter.mark(Self.uri(2), feed: .latest)
        await reporter.flush().value
        XCTAssertEqual(sink.batches, [[Self.uri(1)], [Self.uri(1), Self.uri(2)]])
        XCTAssertEqual(reporter.queued, 1, "uri 1 failed twice and is dropped, uri 2 waits for one more try")

        reporter.mark(Self.uri(1), feed: .latest)
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

        for n in 1...220 { reporter.mark(Self.uri(n), feed: .latest) }
        await settle { calls == 11 }
        XCTAssertEqual(calls, 11)
        XCTAssertEqual(reporter.queued, 0)

        down.open()
        await settle { reporter.queued == RemoteSeenReporter.queueLimit }
        XCTAssertEqual(reporter.queued, 200)
        reporter.mark(Self.uri(999), feed: .latest)
        XCTAssertEqual(reporter.queued, 200)
    }

    private static func kept(_ id: Int64, _ n: Int) -> String {
        #"{"id":\#(id),"uri":"\#(uri(n))","body":"kept","createdAt":"2026-10-16T01:00:00Z","editedAt":null,"likeCount":null,"likedByMe":false,"author":{"id":-9800,"username":"mina@mastodon.social","bio":null,"avatarUrl":null,"displayName":"Mina","remoteId":9800,"url":"https://mastodon.social/@mina"},"media":[],"quotedPost":null,"inReplyToId":null,"replyCount":0,"repostCount":null,"repostedByMe":false,"quotedNote":null,"linkPreview":null}"#
    }

    private static func mixed(_ items: [String], next: String?, seenFrom: Int? = nil) throws -> RemoteStreamPage {
        let seen = seenFrom.map { #","seenFrom":\#($0)"# } ?? ""
        let json = #"{"items":[\#(items.joined(separator: ","))],"next":\#(next.map { "\"\($0)\"" } ?? "null")\#(seen)}"#
        return try JSONDecoder.blog.decode(RemoteStreamPage.self, from: Data(json.utf8))
    }

    func testForYouHandsTheCursorBackAsItCameAndDropsAUriItAlreadyShows() async throws {
        var asked: [String?] = []
        let pages = [
            "first": try Self.mixed([Self.kept(7, 1), Self.pool(2), Self.pool(2)], next: "f1792656810855.3"),
            "f1792656810855.3": try Self.mixed([Self.pool(1), Self.pool(3), Self.kept(9, 4)], next: nil, seenFrom: 1),
        ]
        let model = RemoteStreamModel(feed: .forYou) { feed, cursor in
            XCTAssertEqual(feed, .forYou)
            asked.append(cursor)
            return try XCTUnwrap(pages[cursor ?? "first"])
        }
        Self.kept.append(model)

        await model.reload()
        XCTAssertEqual(model.items.map(\.key), [Self.uri(1), Self.uri(2)], "a uri twice on one page shows once")
        await model.loadMore()

        XCTAssertEqual(asked, [nil, "f1792656810855.3"])
        XCTAssertEqual(
            model.items.map(\.id), ["n-7", "t-\(Self.uri(2))", "t-\(Self.uri(3))", "n-9"],
            "the pool copy of a stored note already on screen is dropped by its uri")
        XCTAssertEqual(model.firstSeenID, "t-\(Self.uri(3))")
        XCTAssertNil(model.next)
    }

    func testAStoredNoteShowsOnceEvenUnderAnotherUriOnTheSameOrALaterPage() async throws {
        let pages = [
            "first": try Self.mixed([Self.kept(7, 1), Self.kept(7, 2), Self.pool(3)], next: "f2"),
            "f2": try Self.mixed([Self.kept(7, 4), Self.pool(5)], next: nil),
        ]
        let model = RemoteStreamModel(feed: .forYou) { _, cursor in try XCTUnwrap(pages[cursor ?? "first"]) }
        Self.kept.append(model)

        await model.reload()
        XCTAssertEqual(model.items.map(\.id), ["n-7", "t-\(Self.uri(3))"])
        await model.loadMore()

        XCTAssertEqual(model.items.map(\.id), ["n-7", "t-\(Self.uri(3))", "t-\(Self.uri(5))"])
    }

    func testEachFeedSendsItsOwnBatchNamingTheFeed() async {
        let sink = Sink()
        let reporter = reporter(sink)

        reporter.mark(Self.uri(1), feed: .forYou)
        reporter.mark(Self.uri(2), feed: .latest)
        reporter.mark(Self.uri(3), feed: .forYou)
        await reporter.flush().value

        XCTAssertEqual(sink.sent, [
            RemoteSeenBatch(uris: [Self.uri(1), Self.uri(3)], dwell: nil, feed: "for-you"),
            RemoteSeenBatch(uris: [Self.uri(2)], dwell: nil, feed: "latest"),
        ])
    }

    func testDwellAddsUpPerUriAndRidesWithTheMarksOfItsFeed() async {
        let sink = Sink()
        let reporter = reporter(sink)

        reporter.mark(Self.uri(1), feed: .forYou)
        reporter.dwell(Self.uri(1), ms: 600, feed: .forYou)
        reporter.dwell(Self.uri(2), ms: 999, feed: .forYou)
        reporter.dwell(Self.uri(1), ms: 700, feed: .forYou)
        reporter.dwell(Self.uri(3), ms: 900_000, feed: .forYou)
        await reporter.flush().value

        XCTAssertEqual(sink.sent, [RemoteSeenBatch(
            uris: [Self.uri(1)],
            dwell: [RemoteDwell(uri: Self.uri(1), ms: 1_300), RemoteDwell(uri: Self.uri(3), ms: 600_000)],
            feed: "for-you")],
            "under a second waits for more, over ten minutes is cut")

        reporter.dwell(Self.uri(2), ms: 1, feed: .latest)
        reporter.dwell(Self.uri(1), ms: 2_000, feed: .latest)
        await reporter.flush().value
        XCTAssertEqual(sink.sent.last, RemoteSeenBatch(
            uris: [],
            dwell: [RemoteDwell(uri: Self.uri(1), ms: 3_300), RemoteDwell(uri: Self.uri(2), ms: 1_000)],
            feed: "latest"),
            "a uri already reported sends its running total, and dwell goes out on its own")
    }

    func testDwellAloneStartsTheTimer() async {
        let sink = Sink()
        let gate = Gate()
        let reporter = reporter(sink, gate: gate)

        reporter.dwell(Self.uri(1), ms: 4_000, feed: .forYou)
        await Task.yield()
        XCTAssertTrue(sink.sent.isEmpty)

        gate.open()
        await settle { !sink.sent.isEmpty }
        XCTAssertEqual(sink.sent, [RemoteSeenBatch(uris: [], dwell: [RemoteDwell(uri: Self.uri(1), ms: 4_000)], feed: "for-you")])
    }

    func testAFailedDwellIsTriedOnceMore() async {
        let sink = Sink()
        sink.failures = 2
        let reporter = reporter(sink)

        reporter.dwell(Self.uri(1), ms: 2_000, feed: .forYou)
        await reporter.flush().value
        await reporter.flush().value
        await reporter.flush().value

        XCTAssertEqual(sink.sent.map(\.dwell), [
            [RemoteDwell(uri: Self.uri(1), ms: 2_000)], [RemoteDwell(uri: Self.uri(1), ms: 2_000)],
        ])
    }

    func testTimeOnANoteOpenedFromAMeasuredRowCountsForItsUri() async {
        let sink = Sink()
        let reporter = reporter(sink)

        reporter.dwell(note: 7, ms: 9_000)
        reporter.remember(7, uri: Self.uri(1), feed: .forYou)
        reporter.dwell(Self.uri(1), ms: 1_500, feed: .forYou)
        reporter.dwell(note: 7, ms: 9_000)
        await reporter.flush().value

        XCTAssertEqual(sink.sent, [RemoteSeenBatch(uris: [], dwell: [RemoteDwell(uri: Self.uri(1), ms: 10_500)], feed: "for-you")])
    }

    private func log(_ clock: @escaping () -> Date) -> HomeSeenLog {
        let suite = "home-seen-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let log = HomeSeenLog(defaults: defaults, now: clock, viewer: { nil })
        Self.kept.append(log)
        return log
    }

    func testTheLocalSeenLogKeepsEachAccountAndTheDeviceApart() {
        let suite = "home-seen-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        var viewer: Int64? = 7
        let log = HomeSeenLog(defaults: defaults, viewer: { viewer })
        Self.kept.append(log)

        log.record("kurl:note:1")
        viewer = nil
        XCTAssertFalse(log.contains("kurl:note:1"), "the device does not see what account 7 saw")
        log.record("kurl:note:2")
        viewer = 8
        XCTAssertFalse(log.contains("kurl:note:1"))
        XCTAssertFalse(log.contains("kurl:note:2"))
        viewer = 7
        XCTAssertTrue(log.contains("kurl:note:1"))
        XCTAssertFalse(log.contains("kurl:note:2"))
        log.save()
        XCTAssertNotNil(defaults.dictionary(forKey: HomeSeenLog.storageKey(for: 7)))
        XCTAssertNotNil(defaults.dictionary(forKey: HomeSeenLog.storageKey(for: nil)))
        defaults.removePersistentDomain(forName: suite)
    }

    func testTheLocalSeenLogKeepsKeysForFourteenDaysAndSurvivesARestart() {
        var now = Date(timeIntervalSince1970: 1_792_000_000)
        let suite = "home-seen-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let log = HomeSeenLog(defaults: defaults, now: { now }, viewer: { nil })
        log.record("kurl:note:1")
        XCTAssertTrue(log.contains("kurl:note:1"))
        XCTAssertFalse(log.contains("kurl:note:2"))
        log.save()

        let again = HomeSeenLog(defaults: defaults, now: { now }, viewer: { nil })
        Self.kept += [log, again]
        XCTAssertTrue(again.contains("kurl:note:1"), "the log is read back after a restart")

        now = now.addingTimeInterval(HomeSeenLog.keep - 1)
        XCTAssertTrue(log.contains("kurl:note:1"))
        now = now.addingTimeInterval(1)
        XCTAssertFalse(log.contains("kurl:note:1"))
        defaults.removePersistentDomain(forName: suite)
    }

    func testTheLocalSeenLogDropsTheOldestPastItsLimit() {
        var now = Date(timeIntervalSince1970: 1_792_000_000)
        let log = log { now }
        for n in 0...HomeSeenLog.limit {
            now = now.addingTimeInterval(1)
            log.record("kurl:post:\(n)")
        }
        XCTAssertFalse(log.contains("kurl:post:0"))
        XCTAssertTrue(log.contains("kurl:post:1"))
        XCTAssertTrue(log.contains("kurl:post:\(HomeSeenLog.limit)"))
    }
}
