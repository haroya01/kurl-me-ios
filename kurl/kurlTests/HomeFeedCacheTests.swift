import XCTest

@testable import kurl

@MainActor
final class HomeFeedCacheTests: XCTestCase {
    private static var kept: [AnyObject] = []

    private static func note(_ id: Int64, author: String = "author", room: String = "null") -> String {
        #"{"kind":"note","note":{"id":\#(id),"body":"n\#(id)","createdAt":"2026-10-22T01:00:00Z","editedAt":null,"likeCount":null,"likedByMe":null,"author":{"id":1,"username":"\#(author)","bio":null,"avatarUrl":null},"media":[],"quotedPost":null,"inReplyToId":null,"replyCount":0,"repostCount":null,"repostedByMe":null,"quotedNote":null,"room":\#(room)}}"#
    }

    private static func post(_ id: Int64) -> String {
        #"{"kind":"post","post":{"id":\#(id),"author":{"id":2,"username":"writer","bio":null,"avatarUrl":null},"slug":"p\#(id)","title":"글 \#(id)","excerpt":"요약","ogImageUrl":null,"languageTag":"ko","tags":[],"publishedAt":"2026-10-22T00:00:00Z","viewCount":3,"likeCount":5}}"#
    }

    private static func remote(_ id: Int64, author: String = "far") -> String {
        note(id, author: author).replacingOccurrences(
            of: #"{"kind":"note","note":{"#,
            with: #"{"kind":"remote","remote":{"uri":"https://far.example/n/\#(id)","#)
    }

    private static func page(_ items: [String], next: String? = "1.1") -> Data {
        Data(#"{"items":[\#(items.joined(separator: ","))],"next":\#(next.map { "\"\($0)\"" } ?? "null"),"newest":"0.9"}"#.utf8)
    }

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func cache(now: @escaping () -> Date = Date.init) -> HomeFeedCache {
        let cache = HomeFeedCache(directory: directory, now: now)
        Self.kept.append(cache)
        return cache
    }

    private func store(
        _ cache: HomeFeedCache, _ data: Data, tab: HomeFeedTab = .forYou,
        ticket: HomeFeedCache.Ticket? = nil, withheld: @escaping (HomeFeedItem) -> Bool = { _ in false }
    ) async throws {
        let batch = try JSONDecoder.blog.decode(HomeFeedBatch.self, from: data)
        cache.store(data, batch: batch, tab: tab, ticket: ticket ?? cache.ticket(), withheld: withheld)
        await cache.settle()
    }

    func testTheLastFirstPageComesBackPerTab() async throws {
        let cache = cache()
        try await store(cache, Self.page([Self.note(2), Self.post(7)]))

        let forYou = await cache.read(.forYou)
        XCTAssertEqual(forYou?.items.map(\.id), ["note-2", "post-7"])
        XCTAssertEqual(forYou?.next, "1.1")
        XCTAssertEqual(forYou?.newest, "0.9")
        let following = await cache.read(.following)
        XCTAssertNil(following)
        let blog = await cache.read(.blog)
        XCTAssertNil(blog)
    }

    func testOtherServerRowsComeBackUnlessWithheld() async throws {
        let cache = cache()
        try await store(cache, Self.page([Self.remote(9700), Self.note(1), Self.remote(9701, author: "blocked")])) {
            $0.keptNote?.author.username == "blocked"
        }
        let saved = await cache.read(.forYou)
        XCTAssertEqual(saved?.items.map(\.id), ["remote-n-9700", "note-1"])
    }

    func testRoomNotesNeverReachTheDisk() async throws {
        let cache = cache()
        let data = Self.page([Self.note(1), Self.note(2, room: #"{"id":5,"name":"우리 가족"}"#), Self.note(3)])
        try await store(cache, data, withheld: HomeFeedCache.withheld)

        let saved = await cache.read(.forYou)
        XCTAssertEqual(saved?.items.map(\.id), ["note-1", "note-3"])
        let raw = try String(contentsOf: directory.appendingPathComponent("guest-for-you.json"), encoding: .utf8)
        XCTAssertFalse(raw.contains("우리 가족"))
    }

    func testWithheldItemsAreLeftOut() async throws {
        let cache = cache()
        try await store(cache, Self.page([Self.note(1, author: "kim"), Self.note(2, author: "blocked")])) {
            $0.note?.author.username == "blocked"
        }
        let saved = await cache.read(.forYou)
        XCTAssertEqual(saved?.items.map(\.id), ["note-1"])
    }

    func testAWipeDropsEverythingAndAnAnswerAskedBeforeItIsNotSaved() async throws {
        let cache = cache()
        try await store(cache, Self.page([Self.note(1)]))
        let before = cache.ticket()

        cache.wipe()
        try await store(cache, Self.page([Self.note(2)]), ticket: before)

        let saved = await cache.read(.forYou)
        XCTAssertNil(saved, "a page asked for by the account before the wipe never lands for the next one")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testADayOldPageIsNotShown() async throws {
        var clock = Date()
        let cache = cache(now: { clock })
        try await store(cache, Self.page([Self.note(1)]))

        clock += HomeFeedCache.maxAge - 60
        let fresh = await cache.read(.forYou)
        XCTAssertNotNil(fresh)
        clock += 120
        let stale = await cache.read(.forYou)
        XCTAssertNil(stale)
    }

    func testSigningOutWipesTheHomeCache() {
        let before = HomeFeedCache.shared.generation
        AuthStore.shared.signOut()
        XCTAssertGreaterThan(HomeFeedCache.shared.generation, before)
    }

    func testBlockingAndUnblockingWipeTheHomeCache() async throws {
        let store = BlockStore(api: BlockStore.API(list: { [] }, block: { _ in }, unblock: { _ in }))
        Self.kept.append(store)
        let before = HomeFeedCache.shared.generation
        try await store.block(id: 9, username: "spam")
        XCTAssertEqual(HomeFeedCache.shared.generation, before + 1)
        try await store.unblock(id: 9, username: "spam")
        XCTAssertEqual(HomeFeedCache.shared.generation, before + 2)
    }

    func testDeletingANoteWipesTheHomeCache() {
        let model = HomeFeedViewModel(tab: .forYou, cached: { _ in nil })
        Self.kept.append(model)
        let before = HomeFeedCache.shared.generation
        model.removed(7)
        XCTAssertGreaterThan(HomeFeedCache.shared.generation, before)
    }

    func testMutingWipesTheHomeCache() {
        let before = HomeFeedCache.shared.generation
        NoteFeedPreferences.shared.mutesChanged()
        XCTAssertGreaterThan(HomeFeedCache.shared.generation, before)
    }

    func testTheSavedPageShowsAtOnceAndTheNetworkReplacesIt() async throws {
        let saved = try JSONDecoder.blog.decode(HomeFeedBatch.self, from: Self.page([Self.note(1), Self.note(2)]))
        let fresh = try JSONDecoder.blog.decode(HomeFeedBatch.self, from: Self.page([Self.note(3), Self.note(1)], next: nil))
        var shownBeforeNetwork: [String] = []
        var settledCount = 0
        var settledBeforeNetwork = 0
        var model: HomeFeedViewModel!
        model = HomeFeedViewModel(
            tab: .forYou,
            settled: { settledCount += 1 },
            cached: { _ in saved },
            load: { _, _ in
                shownBeforeNetwork = model.items.map(\.id)
                settledBeforeNetwork = settledCount
                return fresh
            })
        Self.kept.append(model)

        await model.reload(settlesLaunch: true)

        XCTAssertEqual(shownBeforeNetwork, ["note-1", "note-2"])
        XCTAssertEqual(model.items.map(\.id), ["note-3", "note-1"])
        XCTAssertNil(model.next)
        XCTAssertEqual(settledBeforeNetwork, 1, "the splash lifts on the saved page, not on the network")
    }

    func testOfflineKeepsTheSavedPage() async throws {
        let saved = try JSONDecoder.blog.decode(HomeFeedBatch.self, from: Self.page([Self.note(1)]))
        let model = HomeFeedViewModel(
            tab: .forYou, cached: { _ in saved },
            load: { _, _ in throw APIError.transport(URLError(.notConnectedToInternet)) })
        Self.kept.append(model)

        await model.reload()

        XCTAssertEqual(model.items.map(\.id), ["note-1"])
        guard case .loaded = model.phase else { return XCTFail("offline with a saved page still shows it") }
    }
}
