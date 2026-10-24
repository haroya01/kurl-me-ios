import XCTest

@testable import kurl

@MainActor
final class FeedTabChoiceTests: XCTestCase {
    private static var gates: [SwipePagerGate] = []

    private func defaults(_ values: [String: String]) -> UserDefaults {
        let name = "home-tab-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        values.forEach { defaults.set($1, forKey: $0) }
        return defaults
    }

    func testHomeShowsFollowingLatestTrendingInOrder() {
        XCTAssertEqual(HomeFeedTab.allCases, [.following, .latest, .trending])
        XCTAssertEqual(HomeFeedTab.allCases.last, .trending)
    }

    func testASignedInReaderKeepsTheRememberedTabFromEitherOldFeed() {
        XCTAssertEqual(HomeFeedChoice.initialTab(launched: nil, defaults: defaults(["home.tab": "trending"]), signedIn: true), .trending)
        XCTAssertEqual(HomeFeedChoice.initialTab(launched: nil, defaults: defaults(["feed.tab": "following"]), signedIn: true), .following)
        XCTAssertEqual(HomeFeedChoice.initialTab(launched: nil, defaults: defaults(["feed.tab": "recent"]), signedIn: true), .latest)
        XCTAssertEqual(HomeFeedChoice.initialTab(launched: nil, defaults: defaults(["notes.feed": "everyone"]), signedIn: true), .latest)
        XCTAssertEqual(
            HomeFeedChoice.initialTab(launched: nil, defaults: defaults(["feed.tab": "trending", "notes.feed": "following"]), signedIn: true),
            .trending, "the blog feed's choice wins over the notes feed's")
        XCTAssertEqual(
            HomeFeedChoice.initialTab(launched: nil, defaults: defaults(["home.tab": "latest", "feed.tab": "trending"]), signedIn: true),
            .latest, "once 홈 has its own choice, the old ones are ignored")
    }

    func testOldMenuOnlyFeedsOpenOnLatest() {
        XCTAssertEqual(HomeFeedChoice.initialTab(launched: nil, defaults: defaults(["feed.tab": "forYou"]), signedIn: true), .latest)
        XCTAssertEqual(HomeFeedChoice.initialTab(launched: nil, defaults: defaults(["notes.feed": "bookmarks"]), signedIn: true), .latest)
        XCTAssertEqual(HomeFeedChoice.initialTab(launched: nil, defaults: defaults(["notes.feed": "federated"]), signedIn: true), .latest)
    }

    func testASignedOutReaderOpensOnLatest() {
        XCTAssertEqual(HomeFeedChoice.initialTab(launched: nil, defaults: defaults(["home.tab": "following"]), signedIn: false), .latest)
        XCTAssertEqual(HomeFeedChoice.initialTab(launched: nil, defaults: nil, signedIn: false), .latest)
    }

    func testALaunchArgumentWins() {
        XCTAssertEqual(HomeFeedChoice.initialTab(launched: "trending", defaults: defaults(["home.tab": "following"]), signedIn: true), .trending)
        XCTAssertEqual(HomeFeedChoice.initialTab(launched: "recent", defaults: nil, signedIn: false), .latest)
    }

    func testFollowingNextToLatestWaitsUntilItIsFirstChosen() {
        let tabs = HomeFeedTab.allCases
        func warm(_ tab: HomeFeedTab, selection: HomeFeedTab, opened: Set<HomeFeedTab> = []) -> Bool {
            SwipePagerWarmth.warm(tab, tabs: tabs, selection: selection, loadOnSelect: [.following], opened: opened)
        }
        XCTAssertFalse(warm(.following, selection: .latest), "opening on 최신 must not fetch 팔로잉 too")
        XCTAssertTrue(warm(.trending, selection: .latest))
        XCTAssertTrue(warm(.following, selection: .following))
        XCTAssertTrue(warm(.following, selection: .latest, opened: [.following]))
        XCTAssertFalse(warm(.following, selection: .trending, opened: [.following]))
    }

    func testNeighborsWaitUntilTheChosenPageHasSettled() {
        let tabs = HomeFeedTab.allCases
        func warm(_ tab: HomeFeedTab, selection: HomeFeedTab, opened: Set<HomeFeedTab> = [], settled: Bool) -> Bool {
            SwipePagerWarmth.warm(
                tab, tabs: tabs, selection: selection, loadOnSelect: [.following], opened: opened, settled: settled)
        }
        XCTAssertTrue(warm(.latest, selection: .latest, settled: false), "the chosen page loads at once")
        XCTAssertFalse(warm(.trending, selection: .latest, settled: false), "인기 waits while 최신 is still loading")
        XCTAssertTrue(warm(.trending, selection: .latest, settled: true))
        XCTAssertTrue(warm(.trending, selection: .latest, opened: [.trending], settled: false), "a page once chosen stays warm")
        XCTAssertFalse(warm(.following, selection: .latest, settled: true), "settling does not wake 팔로잉")
    }

    func testTheMoreMenuHoldsForYouOnly() {
        XCTAssertEqual(HomeMoreMenu.feeds, [.forYou])
        XCTAssertEqual(FeedSource.forYou.moreChoice, SegmentMoreChoice(title: String(localized: "추천"), symbol: "binoculars"))
    }

    func testHomeKeepsEveryPageMountedAndExploreMountsNeighborsOnlyWhileMoving() {
        for tab in HomeFeedTab.allCases {
            for moving in [false, true] {
                XCTAssertTrue(SwipePagerMount.mounted(tab, selection: .latest, onlySelectionAtRest: false, moving: moving))
            }
        }
        XCTAssertEqual(ExploreLane.allCases, [.picks, .remote, .people])
        XCTAssertEqual(ExploreLane.picks.label, String(localized: "발견"))
        XCTAssertEqual(ExploreLane.picks.rawValue, "picks")
        XCTAssertTrue(SwipePagerMount.mounted(ExploreLane.picks, selection: .picks, onlySelectionAtRest: true, moving: false))
        XCTAssertFalse(SwipePagerMount.mounted(ExploreLane.remote, selection: .picks, onlySelectionAtRest: true, moving: false))
        XCTAssertFalse(SwipePagerMount.mounted(ExploreLane.people, selection: .picks, onlySelectionAtRest: true, moving: false))
        XCTAssertTrue(SwipePagerMount.mounted(ExploreLane.remote, selection: .picks, onlySelectionAtRest: true, moving: true))
    }

    func testASwipeThatStartsOnAHeldStripDoesNotTurnThePage() {
        let gate = SwipePagerGate()
        Self.gates.append(gate)
        XCTAssertFalse(gate.holds(CGPoint(x: 100, y: 500)))
        gate.frames[UUID()] = CGRect(x: 0, y: 400, width: 402, height: 190)
        XCTAssertTrue(gate.holds(CGPoint(x: 100, y: 500)), "a swipe that starts on the strip stays with the strip")
        XCTAssertFalse(gate.holds(CGPoint(x: 100, y: 300)), "a swipe above the strip turns the page")
        XCTAssertFalse(gate.holds(CGPoint(x: 100, y: 600)), "a swipe below the strip turns the page")
        gate.held = true
        XCTAssertTrue(gate.holds(CGPoint(x: 100, y: 300)), "a strip still gliding holds every swipe")
    }

    func testARightSwipeOnAMoreFeedStepsBackToTheLastTab() {
        let right = CGSize(width: 120, height: 6), left = CGSize(width: -120, height: 6)
        let fast = CGSize(width: 700, height: 0), still = CGSize.zero
        XCTAssertEqual(SwipeSelects<Int>.step(from: 1, count: 2, translation: right, velocity: fast), 0)
        XCTAssertEqual(SwipeSelects<Int>.step(from: 1, count: 2, translation: right, velocity: still), 0)
        XCTAssertNil(SwipeSelects<Int>.step(from: 1, count: 2, translation: left, velocity: fast))
        XCTAssertNil(SwipeSelects<Int>.step(from: 1, count: 2, translation: CGSize(width: 40, height: 200), velocity: fast))
    }

    func testAPublishedNoteOpensHomeAtTheTop() {
        let choice = HomeFeedChoice.shared
        let saved = (choice.tab, TabRouter.shared.selection)
        defer {
            choice.select(saved.0)
            TabRouter.shared.selection = saved.1
        }
        let note = Note(
            id: 77, body: "방금", createdAt: nil, editedAt: nil, likeCount: nil, likedByMe: nil,
            author: Author(id: 1, username: "author", bio: nil, avatarUrl: nil), media: [], quotedPost: nil,
            inReplyToId: nil, replyCount: 0, repostCount: nil, repostedByMe: nil, quotedNote: nil)
        choice.select(.trending)
        choice.path.append(Route.note(id: 1))
        TabRouter.shared.selection = TabRouter.accountTab

        TabRouter.shared.revealPosted(note)

        XCTAssertEqual(TabRouter.shared.selection, TabRouter.homeTab)
        XCTAssertEqual(choice.tab, .latest, "인기 doesn't have the note you just wrote")
        XCTAssertTrue(choice.path.isEmpty)
        XCTAssertEqual(choice.posted?.id, 77)
        XCTAssertEqual(choice.arrivingID, 77)

        choice.select(.following)
        TabRouter.shared.revealPosted(note)
        XCTAssertEqual(choice.tab, .following, "팔로잉 and 최신 stay")
    }
}

@MainActor
final class HomeFeedTests: XCTestCase {
    private static var kept: [AnyObject] = []

    private static func note(_ id: Int64, at time: String) -> String {
        #"{"kind":"note","note":{"id":\#(id),"body":"n\#(id)","createdAt":"\#(time)","editedAt":null,"likeCount":null,"likedByMe":null,"author":{"id":1,"username":"author","bio":null,"avatarUrl":null},"media":[],"quotedPost":null,"inReplyToId":null,"replyCount":0,"repostCount":null,"repostedByMe":null,"quotedNote":null}}"#
    }

    private static func post(_ id: Int64, at time: String, extra: String = "") -> String {
        #"{"kind":"post","post":{"id":\#(id),"author":{"id":2,"username":"writer","bio":null,"avatarUrl":null},"slug":"p\#(id)","title":"글 \#(id)","excerpt":"요약","ogImageUrl":null,"languageTag":"ko","tags":[],"publishedAt":"\#(time)","viewCount":3,"likeCount":5\#(extra)}}"#
    }

    private static func batch(_ items: [String], next: String?) throws -> HomeFeedBatch {
        let json = #"{"items":[\#(items.joined(separator: ","))],"next":\#(next.map { "\"\($0)\"" } ?? "null")}"#
        return try JSONDecoder.blog.decode(HomeFeedBatch.self, from: Data(json.utf8))
    }

    private final class Pager {
        let pages: [String: HomeFeedBatch]
        var asked: [String] = []

        init(_ pages: [String: HomeFeedBatch]) { self.pages = pages }

        func page(_ cursor: String?) throws -> HomeFeedBatch {
            let key = cursor ?? "first"
            asked.append(key)
            guard let page = pages[key] else { throw APIError.server(status: 500, code: nil, detail: "") }
            return page
        }
    }

    func testTheHomeShapeDecodesNotesAndPostCardsWithTheirReactionFields() throws {
        let page = try Self.batch([
            Self.note(9, at: "2026-10-20T01:00:00Z"),
            Self.post(4, at: "2026-10-20T00:30:00Z", extra: #","readMinutes":3,"commentCount":2,"likedByMe":true"#),
        ], next: "12.4")
        XCTAssertEqual(page.items.map(\.id), ["note-9", "post-4"])
        XCTAssertEqual(page.next, "12.4")
        guard case .post(let post) = page.items[1].kind else { return XCTFail("post card") }
        XCTAssertEqual(post.readMinutes, 3)
        XCTAssertEqual(post.commentCount, 2)
        XCTAssertEqual(post.likedByMe, true)
    }

    func testAPostWithoutTheNewFieldsStillDecodes() throws {
        let page = try Self.batch([Self.post(4, at: "2026-10-20T00:30:00Z")], next: nil)
        guard case .post(let post) = page.items[0].kind else { return XCTFail("post card") }
        XCTAssertNil(post.readMinutes)
        XCTAssertNil(post.commentCount)
        XCTAssertNil(post.likedByMe)
    }

    func testTheFallbackMergeKeepsOneTimeOrderOrTwoNotesPerPost() throws {
        let items = try Self.batch([
            Self.note(1, at: "2026-10-20T03:00:00Z"), Self.note(2, at: "2026-10-20T01:00:00Z"),
            Self.note(3, at: "2026-10-19T23:00:00Z"),
            Self.post(7, at: "2026-10-20T02:00:00Z"), Self.post(8, at: "2026-10-19T22:00:00Z"),
        ], next: nil).items
        let notes = Array(items.prefix(3)), posts = Array(items.suffix(2))
        XCTAssertEqual(
            HomeFeedAPI.merge(notes: notes, posts: posts, byTime: true).map(\.id),
            ["note-1", "post-7", "note-2", "note-3", "post-8"])
        XCTAssertEqual(
            HomeFeedAPI.merge(notes: notes, posts: posts, byTime: false).map(\.id),
            ["note-1", "note-2", "post-7", "note-3", "post-8"])
    }

    func testScrollingSendsNextBackAsTheCursorUntilItIsNull() async throws {
        let pager = Pager([
            "first": try Self.batch([Self.note(1, at: "2026-10-20T03:00:00Z"), Self.post(7, at: "2026-10-20T02:00:00Z")], next: "1.1"),
            "1.1": try Self.batch([Self.post(7, at: "2026-10-20T02:00:00Z"), Self.note(2, at: "2026-10-20T01:00:00Z")], next: nil),
        ])
        Self.kept.append(pager)
        let model = HomeFeedViewModel(tab: .latest) { _, cursor in try pager.page(cursor) }
        Self.kept.append(model)

        await model.reload()
        await model.loadMoreIfNeeded(current: model.items[0])
        XCTAssertEqual(pager.asked, ["first", "1.1"], "a row within the last five asks for more")
        await model.loadMoreIfNeeded(current: model.items[1])
        XCTAssertEqual(pager.asked, ["first", "1.1"])
        XCTAssertEqual(model.items.map(\.id), ["note-1", "post-7", "note-2"], "a repeat across pages shows once")
        XCTAssertNil(model.next)
        await model.loadMoreIfNeeded(current: model.items[2])
        XCTAssertEqual(pager.asked.count, 2)
    }
}
