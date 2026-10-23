import XCTest

@testable import kurl

@MainActor
final class HomeRankedTests: XCTestCase {
    private static var kept: [AnyObject] = []
    private static let t0 = Date(timeIntervalSince1970: 1_792_000_000)

    private static func uri(_ n: Int) -> String { "https://mstdn.jp/users/a/statuses/\(n)" }

    private static func note(_ id: Int64) -> String {
        #"{"kind":"note","note":{"id":\#(id),"body":"n\#(id)","createdAt":"2026-10-22T01:00:00Z","editedAt":null,"likeCount":null,"likedByMe":null,"author":{"id":1,"username":"kim","bio":null,"avatarUrl":null},"media":[],"quotedPost":null,"inReplyToId":null,"replyCount":0,"repostCount":null,"repostedByMe":null,"quotedNote":null}}"#
    }

    private static func post(_ id: Int64) -> String {
        #"{"kind":"post","post":{"id":\#(id),"author":{"id":2,"username":"writer","bio":null,"avatarUrl":null},"slug":"p\#(id)","title":"글 \#(id)","excerpt":null,"ogImageUrl":null,"languageTag":"ko","tags":[],"publishedAt":"2026-10-22T00:00:00Z","viewCount":0,"likeCount":0}}"#
    }

    private static func pool(_ n: Int) -> String {
        #"{"kind":"remote","remote":{"id":null,"uri":"\#(uri(n))","body":"p\#(n)","createdAt":"2026-10-22T01:00:00Z","author":{"username":"a@mstdn.jp","displayName":null,"avatarUrl":null,"url":"https://mstdn.jp/@a"},"media":[],"contentWarning":null,"sensitive":false,"language":"ja","likeCount":1,"repostCount":0,"replyCount":0,"poll":null,"linkPreview":null,"remote":null,"servers":["mstdn.jp"]}}"#
    }

    private static func stored(_ id: Int64, _ n: Int) -> String {
        #"{"kind":"remote","remote":{"id":\#(id),"uri":"\#(uri(n))","body":"kept","createdAt":"2026-10-22T01:00:00Z","editedAt":null,"likeCount":null,"likedByMe":false,"author":{"id":-9800,"username":"mina@mastodon.social","bio":null,"avatarUrl":null,"displayName":"Mina","remoteId":9800,"url":"https://mastodon.social/@mina"},"media":[],"quotedPost":null,"inReplyToId":null,"replyCount":0,"repostCount":null,"repostedByMe":false,"quotedNote":null,"linkPreview":null}}"#
    }

    private static func batch(_ items: [String], next: String? = nil) throws -> HomeFeedBatch {
        let json = #"{"items":[\#(items.joined(separator: ","))],"next":\#(next.map { "\"\($0)\"" } ?? "null"),"newest":"0.9"}"#
        return try JSONDecoder.blog.decode(HomeFeedBatch.self, from: Data(json.utf8))
    }

    private final class Answers {
        var own: Result<HomeFeedBatch, Error>
        var newer = HomeFeedBatch(items: [], next: nil, newest: "0.9", gap: false)
        var now = HomeRankedTests.t0
        var said: [String] = []
        var events: [String] = []

        init(_ own: HomeFeedBatch) { self.own = .success(own) }
    }

    private static var nothingNew: String { String(localized: "새 글이 없어요") }
    private static var couldNotRefresh: String { String(localized: "새로고침하지 못했습니다") }
    private static var failed: Error { APIError.server(status: 503, code: nil, detail: "") }

    private func home(_ first: HomeFeedBatch, tab: HomeFeedTab = .forYou) async -> (HomeFeedViewModel, Answers) {
        let answers = Answers(first)
        let model = HomeFeedViewModel(
            tab: tab,
            now: { answers.now },
            notify: { answers.said.append($0) },
            flushSeen: { answers.events.append("flush") },
            seenBefore: { _ in false },
            cached: { _ in nil },
            newer: { _, _ in
                answers.events.append("newer")
                return answers.newer
            },
            load: { _, _ in
                answers.events.append("load")
                return try answers.own.get()
            })
        Self.kept += [model, answers]
        await model.reload()
        answers.events = []
        return (model, answers)
    }

    func testTheRankedShapeDecodesKurlAndRemoteItemsInPlace() throws {
        let page = try Self.batch([Self.note(1), Self.pool(3), Self.post(2), Self.stored(7, 4)])
        XCTAssertEqual(page.items.map(\.id), ["note-1", "remote-t-\(Self.uri(3))", "post-2", "remote-n-7"])
        XCTAssertEqual(page.items.map(\.seenKey), ["kurl:note:1", Self.uri(3), "kurl:post:2", Self.uri(4)])
        XCTAssertEqual(page.items[3].keptNote?.id, 7)
        XCTAssertNil(page.items[3].note, "a stored remote note is not one of my kurl notes")
    }

    func testForYouDrawsExactlyWhatTheServerSentInItsOrder() async throws {
        let (model, answers) = await home(try Self.batch([Self.pool(3), Self.note(1), Self.stored(7, 4), Self.post(2)]))
        XCTAssertEqual(model.items.map(\.id), ["remote-t-\(Self.uri(3))", "note-1", "remote-n-7", "post-2"])
        XCTAssertTrue(answers.said.isEmpty)
    }

    func testAPullSendsWhatWasSeenFirstThenAsksForTheFirstPageAgain() async throws {
        let (model, answers) = await home(try Self.batch([Self.note(1), Self.pool(3)]))

        await model.refresh()

        XCTAssertEqual(answers.events, ["flush", "load"])
    }

    func testAPullWithTheSameRowsSaysNothingNew() async throws {
        let (model, answers) = await home(try Self.batch([Self.note(1), Self.pool(3)]))

        await model.refresh()

        XCTAssertEqual(answers.said, [Self.nothingNew])
    }

    func testAPullWithANewRowReplacesTheListQuietly() async throws {
        let (model, answers) = await home(try Self.batch([Self.note(1), Self.pool(3)]))
        answers.own = .success(try Self.batch([Self.pool(5), Self.note(1)]))

        await model.refresh()

        XCTAssertEqual(model.items.map(\.id), ["remote-t-\(Self.uri(5))", "note-1"])
        XCTAssertTrue(answers.said.isEmpty)
    }

    func testAPullThatOnlyDropsSeenRowsSaysNothingNew() async throws {
        let (model, answers) = await home(try Self.batch([Self.note(1), Self.pool(3), Self.post(2)]))
        answers.own = .success(try Self.batch([Self.post(2)]))

        await model.refresh()

        XCTAssertEqual(model.items.map(\.id), ["post-2"])
        XCTAssertEqual(answers.said, [Self.nothingNew])
    }

    func testAPullThatComesBackEmptyLeavesItToTheEndLine() async throws {
        let (model, answers) = await home(try Self.batch([Self.note(1)]))
        answers.own = .success(try Self.batch([]))

        await model.refresh()

        XCTAssertTrue(model.items.isEmpty)
        XCTAssertTrue(answers.said.isEmpty)
    }

    func testAPullThatFailsKeepsTheRowsAndSaysSo() async throws {
        let (model, answers) = await home(try Self.batch([Self.note(1), Self.pool(3)]))
        answers.own = .failure(Self.failed)

        await model.refresh()

        XCTAssertEqual(model.items.map(\.id), ["note-1", "remote-t-\(Self.uri(3))"])
        XCTAssertEqual(answers.said, [Self.couldNotRefresh])
    }

    func testFollowingStillAsksOnlyForNewerPostsWithoutWaitingForTheSeenBatch() async throws {
        let (model, answers) = await home(try Self.batch([Self.note(1)]), tab: .following)

        await model.refresh()

        XCTAssertEqual(answers.events, ["newer"])
        XCTAssertEqual(answers.said, [Self.nothingNew])
    }

    func testComingBackAfterThirtyMinutesSendsWhatWasSeenAndReloadsQuietly() async throws {
        let (model, answers) = await home(try Self.batch([Self.note(1)]))
        model.left()
        answers.now = Self.t0.addingTimeInterval(1_799)
        await model.returned()
        XCTAssertEqual(answers.events, [])

        model.left()
        answers.now = answers.now.addingTimeInterval(1_800)
        await model.returned()
        XCTAssertEqual(answers.events, ["flush", "load"])
        XCTAssertTrue(answers.said.isEmpty)
    }

    func testHomeIsStaleOnlyAfterThirtyMinutesAway() {
        XCTAssertFalse(HomeFeedViewModel.needsReload(leftAt: nil, now: Self.t0))
        XCTAssertFalse(HomeFeedViewModel.needsReload(leftAt: Self.t0, now: Self.t0.addingTimeInterval(1_799)))
        XCTAssertTrue(HomeFeedViewModel.needsReload(leftAt: Self.t0, now: Self.t0.addingTimeInterval(1_800)))
    }

    func testAStoredRemoteNoteInTheListChangesAndGoesAwayInPlace() async throws {
        let (model, _) = await home(try Self.batch([Self.note(1), Self.stored(7, 4)]))
        guard var kept = model.items[1].keptNote else { return XCTFail("stored note") }
        kept.language = "fr"

        model.replaced(kept)
        XCTAssertEqual(model.items[1].keptNote?.language, "fr")
        XCTAssertEqual(model.items.map(\.id), ["note-1", "remote-n-7"])

        model.removed(7)
        XCTAssertEqual(model.items.map(\.id), ["note-1"])
    }

    func testTheCachedFirstPageLeavesOutWhatWasSeenOnForYouOnly() async throws {
        let saved = try Self.batch([Self.note(1), Self.pool(3), Self.post(2)], next: "p2")
        for tab in [HomeFeedTab.forYou, .following] {
            let model = HomeFeedViewModel(
                tab: tab,
                seenBefore: { $0.seenKey == Self.uri(3) || $0.seenKey == "kurl:note:1" },
                cached: { _ in saved },
                load: { _, _ in throw Self.failed })
            Self.kept.append(model)

            await model.reload()

            XCTAssertEqual(
                model.items.map(\.id), tab == .forYou ? ["post-2"] : ["note-1", "remote-t-\(Self.uri(3))", "post-2"], "\(tab)")
        }
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
