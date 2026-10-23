import CryptoKit
import XCTest

@testable import kurl

private struct VectorItem: Decodable {
    let key: String
    let kind: String?
    let id: Int64?
    let uri: String?
    let keptNoteId: Int64?
}

private struct MixInput: Decodable {
    let own: [VectorItem]
    let remote: [VectorItem]
    let ownDone: Bool
}

private struct MixStep: Decodable {
    let input: MixInput
    let expected: [String]
    let expectedIsPrefixOfNext: Bool?
}

private struct Differs: Decodable {
    let ios: Bool

    private enum CodingKeys: String, CodingKey { case ios }

    init(from decoder: Decoder) throws {
        ios = try decoder.container(keyedBy: CodingKeys.self).contains(.ios)
    }
}

private struct MixCase: Decodable {
    let id: String
    let name: String
    let input: MixInput?
    let expected: [String]?
    let steps: [MixStep]?
    let currentlyDiffers: Differs?
}

private struct Table<Case: Decodable>: Decodable {
    let platforms: [String]
    let cases: [Case]
}

private struct HomeMixVectors: Decodable {
    let schema: String
    let version: Int
    let tables: Tables

    struct Tables: Decodable {
        let base: Table<MixCase>
    }
}

private struct KeyCase: Decodable {
    struct Row: Decodable {
        let kind: String
        let id: String?
        let uri: String?
    }

    let id: String
    let row: Row
    let key: String?
}

private struct ExposureCase: Decodable {
    let id: String
    let surface: String
    let visibleRatio: Double
    let visibleMs: Int
    let appActive: Bool
    let counted: Bool
}

private struct DwellCase: Decodable {
    let id: String
    let key: String
    let totalMs: Int
    let sentMs: Int?
}

private struct RequestCase: Decodable {
    let id: String
    let surface: String
    let what: String
    let seenHide: Bool
    let deviceHeader: Bool
}

private struct CacheCase: Decodable {
    let id: String
    let name: String
    let seenSecondsAgo: Double?
    let authorIsMe: Bool
    let leftOut: Bool
}

private struct PullCase: Decodable {
    struct Result: Decodable {
        let result: String
        let items: [VectorItem]?
        let done: Bool?
    }

    let id: String
    let name: String
    let before: MixInput
    let own: Result
    let remote: Result
    let notice: String
    let currentlyDiffers: Differs?
}

private struct SeenRulesVectors: Decodable {
    let schema: String
    let version: Int
    let tables: Tables

    struct Tables: Decodable {
        let keyFormat: Table<KeyCase>
        let exposure: Table<ExposureCase>
        let dwell: Table<DwellCase>
        let requests: Table<RequestCase>
        let cache: Table<CacheCase>
        let pull: Table<PullCase>
    }
}

@MainActor
final class FeedVectorTests: XCTestCase {
    private static var kept: [AnyObject] = []

    static let homeMixSHA256 = "a8b48c25c93821da8fcca802e70665227b12d6b6700102eb7ceecd106a9687a2"
    static let seenRulesSHA256 = "49f34eb20e4c0cad594db594276fe73c93d49e6c0800a87167680dcceb550e9a"

    static let knownDifferences: [String: String] = [
        "request-006": "following sends no X-Kurl-Device",
        "request-007": "trending sends no X-Kurl-Device",
        "pull-011": "my feed failing with new for-you rows ends silently as new rows (v2 pull rule agrees with iOS)",
    ]

    override func tearDown() async throws {
        FederationAPI.client = .shared
        HomeFeedAPI.client = .shared
        ScriptedFederation.reset()
    }

    private static func data(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: FeedVectorTests.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private static func homeMix() throws -> HomeMixVectors {
        try JSONDecoder().decode(HomeMixVectors.self, from: data("home-mix"))
    }

    private static func seenRules() throws -> SeenRulesVectors {
        try JSONDecoder().decode(SeenRulesVectors.self, from: data("seen-rules"))
    }

    private func check(_ id: String, _ body: () throws -> Void) rethrows {
        if let reason = Self.knownDifferences[id] {
            let options = XCTExpectedFailure.Options()
            options.isStrict = true
            try XCTExpectFailure("\(id): \(reason)", options: options) { try body() }
        } else {
            try body()
        }
    }

    // MARK: items

    private static func noteJSON(_ id: Int64, uri: String?) -> String {
        let uriJSON = uri.map { "\"\($0)\"" } ?? "null"
        return #"{"id":\#(id),"uri":\#(uriJSON),"body":"n\#(id)","createdAt":"2026-10-16T01:00:00Z","editedAt":null,"likeCount":null,"likedByMe":false,"author":{"id":3,"username":"kim","bio":null,"avatarUrl":null},"media":[],"quotedPost":null,"inReplyToId":null,"replyCount":0,"repostCount":null,"repostedByMe":false,"quotedNote":null,"linkPreview":null}"#
    }

    private static func poolJSON(_ uri: String) -> String {
        #"{"uri":"\#(uri)","body":"p","createdAt":"2026-10-17T01:00:00Z","author":{"username":"a@s.example","displayName":null,"avatarUrl":null,"url":"https://s.example/@a"},"media":[],"contentWarning":null,"sensitive":false,"language":"ko","likeCount":1,"repostCount":0,"replyCount":0,"poll":null,"linkPreview":null,"remote":null,"servers":["s.example"]}"#
    }

    private static func note(_ id: Int64, uri: String? = nil, author: Int64 = 3) throws -> Note {
        let json = noteJSON(id, uri: uri).replacingOccurrences(of: #""author":{"id":3"#, with: #""author":{"id":\#(author)"#)
        return try JSONDecoder.blog.decode(Note.self, from: Data(json.utf8))
    }

    private static func own(_ item: VectorItem, author: Int64 = 3) throws -> HomeFeedItem {
        let id = try XCTUnwrap(item.id)
        if item.kind == "post" {
            return HomeFeedItem(kind: .post(FeedItem(
                id: id, author: Author(id: author, username: "kim", bio: nil, avatarUrl: nil), slug: "p\(id)",
                title: "글 \(id)", excerpt: nil, ogImageUrl: nil, languageTag: "ko", tags: [],
                publishedAt: nil, viewCount: 0, likeCount: 0)))
        }
        return HomeFeedItem(kind: .note(try note(id, author: author)))
    }

    private static func remote(_ item: VectorItem) throws -> RemoteStreamItem {
        if let kept = item.keptNoteId { return .kept(try note(kept, uri: item.uri)) }
        let uri = try XCTUnwrap(item.uri)
        return .trending(try JSONDecoder.blog.decode(TrendingNote.self, from: Data(poolJSON(uri).utf8)))
    }

    private static func layout(_ input: MixInput) throws -> [String] {
        let ownItems = try input.own.map { try own($0) }
        let remoteItems = try input.remote.map { try remote($0) }
        var ownKeys: [String: String] = [:]
        for (item, vector) in zip(ownItems, input.own) where ownKeys[item.id] == nil { ownKeys[item.id] = vector.key }
        var remoteKeys: [String: String] = [:]
        for (item, vector) in zip(remoteItems, input.remote) where remoteKeys[item.id] == nil {
            remoteKeys[item.id] = vector.key
        }
        let rows = HomeMix.rows(
            own: HomeFeedViewModel.unique(ownItems), remote: RemoteStreamModel.unique(remoteItems),
            ownDone: input.ownDone)
        return rows.map { row in
            switch row {
            case .own(let item): "own:\(ownKeys[item.id] ?? item.id)"
            case .remote(let item, let mixed): "\(mixed ? "mixed" : "tail"):\(remoteKeys[item.id] ?? item.id)"
            }
        }
    }

    // MARK: the files

    func testTheBundledVectorsAreTheSharedOnesByteForByte() throws {
        func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        XCTAssertEqual(sha(try Self.data("home-mix")), Self.homeMixSHA256)
        XCTAssertEqual(sha(try Self.data("seen-rules")), Self.seenRulesSHA256)
        let mix = try Self.homeMix()
        XCTAssertEqual(mix.schema, "kurl.home-mix")
        XCTAssertEqual(mix.version, 1)
        XCTAssertTrue(mix.tables.base.platforms.contains("ios"))
        let seen = try Self.seenRules()
        XCTAssertEqual(seen.schema, "kurl.seen-rules")
        XCTAssertEqual(seen.version, 1)
    }

    // MARK: home-mix

    func testHomeMixBaseTable() throws {
        let cases = try Self.homeMix().tables.base.cases
        XCTAssertEqual(cases.count, 134)
        for vector in cases {
            if let input = vector.input, let expected = vector.expected {
                let got = try Self.layout(input)
                check(vector.id) {
                    XCTAssertEqual(got, expected, "\(vector.id) \(vector.name)")
                }
            }
            for (index, step) in (vector.steps ?? []).enumerated() {
                let got = try Self.layout(step.input)
                check(vector.id) {
                    XCTAssertEqual(got, step.expected, "\(vector.id) step \(index + 1) \(vector.name)")
                }
                guard let prefix = step.expectedIsPrefixOfNext, let next = vector.steps?[index + 1] else { continue }
                let following = try Self.layout(next.input)
                check(vector.id) {
                    XCTAssertEqual(
                        Array(following.prefix(got.count)) == got, prefix,
                        "\(vector.id) step \(index + 1) prefix of the next \(vector.name)")
                }
            }
        }
    }

    // MARK: seen-rules

    func testSeenKeyFormatTable() throws {
        for vector in try Self.seenRules().tables.keyFormat.cases {
            let row: HomeMix.Row
            switch vector.row.kind {
            case "note", "post":
                let id = try XCTUnwrap(Int64(try XCTUnwrap(vector.row.id)))
                row = .own(try Self.own(VectorItem(key: vector.id, kind: vector.row.kind, id: id, uri: nil, keptNoteId: nil)))
            default:
                let item: RemoteStreamItem = try vector.row.uri.map {
                    .trending(try JSONDecoder.blog.decode(TrendingNote.self, from: Data(Self.poolJSON($0).utf8)))
                } ?? .kept(try Self.note(9, uri: nil))
                row = .remote(item, mixed: true)
            }
            check(vector.id) { XCTAssertEqual(row.seenKey, vector.key, vector.id) }
        }
    }

    func testExposureTable() throws {
        for vector in try Self.seenRules().tables.exposure.cases {
            let surface = try XCTUnwrap(SeenSurface(rawValue: vector.surface), vector.surface)
            let counted = SeenExposure.counts(
                surface, visibleRatio: vector.visibleRatio, visibleFor: .milliseconds(vector.visibleMs),
                appActive: vector.appActive)
            check(vector.id) { XCTAssertEqual(counted, vector.counted, vector.id) }
        }
    }

    func testDwellTable() async throws {
        for vector in try Self.seenRules().tables.dwell.cases {
            var sent: [RemoteSeenBatch] = []
            let reporter = RemoteSeenReporter(send: { sent.append($0) }, wait: { try await Task.sleep(for: .seconds(3_600)) })
            Self.kept.append(reporter)
            reporter.dwell(vector.key, ms: vector.totalMs, feed: .forYou)
            await reporter.flush().value
            let got = sent.flatMap { $0.dwell ?? [] }.first { $0.uri == vector.key }?.ms
            check(vector.id) { XCTAssertEqual(got, vector.sentMs, vector.id) }
        }
    }

    func testRequestTable() async throws {
        ScriptedFederation.reset()
        ScriptedFederation.replies = [
            "/public/home": .json(200, #"{"items":[],"next":null,"newest":"1.1"}"#),
            "/federation/for-you": .json(200, #"{"items":[],"next":null}"#),
        ]
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedFederation.self]
        let client = APIClient(session: URLSession(configuration: config), viewerToken: { nil }, bearerToken: { "token" })
        FederationAPI.client = client
        HomeFeedAPI.client = client

        for vector in try Self.seenRules().tables.requests.cases {
            ScriptedFederation.reset()
            ScriptedFederation.replies = [
                "/public/home": .json(200, #"{"items":[],"next":null,"newest":"1.1"}"#),
                "/federation/for-you": .json(200, #"{"items":[],"next":null}"#),
            ]
            switch (vector.surface, vector.what) {
            case ("home-latest", "next page"): _ = try await HomeFeedAPI.page(.latest, cursor: "h1792656810855.20.3")
            case ("home-latest", "맞춤 mixed into it"): _ = try await FederationAPI.homeStream(.forYou, cursor: nil)
            case ("home-latest", "맞춤 next page"): _ = try await FederationAPI.homeStream(.forYou, cursor: "f1792656810855.20")
            case ("home-latest", _): _ = try await HomeFeedAPI.page(.latest, cursor: nil)
            case ("home-following", _): _ = try await HomeFeedAPI.page(.following, cursor: nil)
            case ("home-trending", _): _ = try await HomeFeedAPI.page(.trending, cursor: nil)
            case ("explore-remote", _): _ = try await FederationAPI.stream(.forYou, cursor: nil)
            default: XCTFail("\(vector.id) has no request mapped: \(vector.surface) \(vector.what)")
            }
            let request = try XCTUnwrap(ScriptedFederation.requests.last, vector.id)
            let items = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
            let hides = items.contains { $0.name == "seen" && $0.value == "hide" }
            let device = request.value(forHTTPHeaderField: RemoteSeenDevice.header) != nil
            check(vector.id) {
                XCTAssertEqual(hides, vector.seenHide, "\(vector.id) seen=hide")
                XCTAssertEqual(device, vector.deviceHeader, "\(vector.id) device header")
            }
        }
    }

    func testCachedFirstPageTable() throws {
        for vector in try Self.seenRules().tables.cache.cases {
            var now = Date(timeIntervalSince1970: 1_792_000_000)
            let suite = "feed-vectors-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            let log = HomeSeenLog(defaults: defaults, now: { now }, viewer: { nil })
            Self.kept.append(log)
            let me: Int64 = 7
            let item = try Self.own(
                VectorItem(key: vector.id, kind: "note", id: 1, uri: nil, keptNoteId: nil),
                author: vector.authorIsMe ? me : 3)
            if let ago = vector.seenSecondsAgo {
                log.record(item.seenKey)
                now = now.addingTimeInterval(ago)
            }
            let leftOut = HomeFeedViewModel.leftOutOfCache(item, log: log, me: me)
            check(vector.id) { XCTAssertEqual(leftOut, vector.leftOut, "\(vector.id) \(vector.name)") }
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private final class PullAnswers {
        var own: Result<HomeFeedBatch, Error>
        var remote: Result<RemoteStreamPage, Error>
        var said: [String] = []

        init(own: Result<HomeFeedBatch, Error>, remote: Result<RemoteStreamPage, Error>) {
            self.own = own
            self.remote = remote
        }
    }

    private static func ownAnswer(_ items: [VectorItem]?, done: Bool) throws -> HomeFeedBatch {
        HomeFeedBatch(items: try (items ?? []).map { try own($0) }, next: done ? nil : "p2", newest: "1.1")
    }

    private static func remoteAnswer(_ items: [VectorItem]?) throws -> RemoteStreamPage {
        RemoteStreamPage(items: try (items ?? []).map { try remote($0) }, next: nil, seenFrom: nil)
    }

    func testPullTable() async throws {
        let failed = APIError.server(status: 503, code: nil, detail: "")
        for vector in try Self.seenRules().tables.pull.cases {
            let answers = PullAnswers(
                own: .success(try Self.ownAnswer(vector.before.own, done: vector.before.ownDone)),
                remote: .success(try Self.remoteAnswer(vector.before.remote)))
            let model = HomeFeedViewModel(
                tab: .latest,
                notify: { answers.said.append($0) },
                flushSeen: {},
                seenBefore: { _ in false },
                cached: { _ in nil },
                remote: { _, _ in try answers.remote.get() },
                newer: { _, _ in throw failed },
                load: { _, _ in try answers.own.get() })
            Self.kept += [model, answers]
            await model.reload()

            answers.own = vector.own.result == "ok"
                ? .success(try Self.ownAnswer(vector.own.items, done: vector.own.done ?? true)) : .failure(failed)
            answers.remote = vector.remote.result == "ok"
                ? .success(try Self.remoteAnswer(vector.remote.items)) : .failure(failed)
            await model.refresh()

            let notice: String
            if answers.said == [String(localized: "새로고침하지 못했습니다")] {
                notice = "failed"
            } else if answers.said == [String(localized: "새 글이 없어요")] {
                notice = "nothingNew"
            } else if answers.said.isEmpty, case .failed = model.phase {
                notice = "failed"
            } else if answers.said.isEmpty {
                notice = model.rows.isEmpty ? "caughtUp" : "newRows"
            } else {
                notice = "said \(answers.said)"
            }
            check(vector.id) { XCTAssertEqual(notice, vector.notice, "\(vector.id) \(vector.name)") }
        }
    }

    // MARK: properties

    private struct Seeded: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    private static func world(_ rng: inout Seeded, keptCanCollide: Bool) throws -> ([HomeFeedItem], [RemoteStreamItem]) {
        let ownCount = Int.random(in: 0...37, using: &rng)
        let own = try (0..<ownCount).map { _ -> HomeFeedItem in
            let id = Int64.random(in: 1...30, using: &rng)
            return try Self.own(
                VectorItem(key: "", kind: Bool.random(using: &rng) ? "note" : "post", id: id, uri: nil, keptNoteId: nil))
        }
        let remoteCount = Int.random(in: 0...25, using: &rng)
        let remote = try (0..<remoteCount).map { _ -> RemoteStreamItem in
            let n = Int64.random(in: 1...40, using: &rng)
            let uri = "https://s.example/s/\(n)"
            guard Int.random(in: 0..<3, using: &rng) == 0 else {
                return try Self.remote(VectorItem(key: "", kind: nil, id: nil, uri: uri, keptNoteId: nil))
            }
            let kept = keptCanCollide ? Int64.random(in: 1...30, using: &rng) : 1_000 + n
            return try Self.remote(VectorItem(key: "", kind: nil, id: nil, uri: uri, keptNoteId: kept))
        }
        return (own, remote)
    }

    func testTheMixKeepsMyOrderAndTheForYouOrderForAnyFeed() throws {
        var rng = Seeded(state: 20_261_023)
        for _ in 0..<300 {
            let (own, remote) = try Self.world(&rng, keptCanCollide: true)
            let ownDone = Bool.random(using: &rng)
            let mine = HomeFeedViewModel.unique(own)
            let theirs = RemoteStreamModel.unique(remote)
            let rows = HomeMix.rows(own: mine, remote: theirs, ownDone: ownDone)

            let ownRows = rows.compactMap { row -> String? in if case .own(let item) = row { item.id } else { nil } }
            XCTAssertEqual(ownRows, mine.map(\.id), "every one of mine, once, in order")

            let shown = Set(mine.compactMap { $0.note?.id })
            let candidates = theirs.filter { $0.keptID.map { !shown.contains($0) } ?? true }.map(\.id)
            let remoteRows = rows.compactMap { row -> String? in if case .remote(let item, _) = row { item.id } else { nil } }
            XCTAssertEqual(remoteRows, Array(candidates.prefix(remoteRows.count)), "for-you keeps its order from the top")
            let slots = mine.count / HomeMix.run * HomeMix.pair
            XCTAssertEqual(remoteRows.count, ownDone ? candidates.count : min(slots, candidates.count))
        }
    }

    func testMorePagesOfMineKeepTheEarlierLayoutAsTheStart() throws {
        var rng = Seeded(state: 7_777)
        for _ in 0..<300 {
            let (own, remote) = try Self.world(&rng, keptCanCollide: false)
            let mine = HomeFeedViewModel.unique(own)
            let theirs = RemoteStreamModel.unique(remote)
            let cut = Int.random(in: 0...mine.count, using: &rng)
            let earlier = HomeMix.rows(own: Array(mine.prefix(cut)), remote: theirs, ownDone: false).map(\.id)
            let later = HomeMix.rows(own: mine, remote: theirs, ownDone: Bool.random(using: &rng)).map(\.id)
            XCTAssertEqual(Array(later.prefix(earlier.count)), earlier, "cut at \(cut) of \(mine.count)")
        }
    }
}
