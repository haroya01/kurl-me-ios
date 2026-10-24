import CryptoKit
import XCTest

@testable import kurl

private struct Table<Case: Decodable>: Decodable {
    let platforms: [String]
    let cases: [Case]
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

private enum HeaderVerdict: String, Decodable {
    case required
    case notNeeded
}

private struct RequestCase: Decodable {
    let id: String
    let surface: String
    let what: String
    let seenHide: Bool
    let deviceHeader: HeaderVerdict
}

private struct CacheCase: Decodable {
    let id: String
    let name: String
    let seenSecondsAgo: Double?
    let authorIsMe: Bool
    let leftOut: Bool
}

private struct PullCase: Decodable {
    let id: String
    let name: String
    let before: [String]
    let result: String
    let after: [String]?
    let notice: String
    let rowsAfter: [String]
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

    static let seenRulesSHA256 = "b16d6b691ee9a5cc204b0e30f9ca44e12bd9650b5795a8500980233a442fbd49"

    static let knownDifferences: [String: String] = [:]

    override func tearDown() async throws {
        FederationAPI.client = .shared
        HomeFeedAPI.client = .shared
        ScriptedFederation.reset()
    }

    private static func data(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: FeedVectorTests.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
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

    private static func note(_ id: Int64, uri: String? = nil) throws -> Note {
        let uriJSON = uri.map { "\"\($0)\"" } ?? "null"
        let json = #"{"id":\#(id),"uri":\#(uriJSON),"body":"n\#(id)","createdAt":"2026-10-16T01:00:00Z","editedAt":null,"likeCount":null,"likedByMe":false,"author":{"id":3,"username":"kim","bio":null,"avatarUrl":null},"media":[],"quotedPost":null,"inReplyToId":null,"replyCount":0,"repostCount":null,"repostedByMe":false,"quotedNote":null,"linkPreview":null}"#
        return try JSONDecoder.blog.decode(Note.self, from: Data(json.utf8))
    }

    private static func pool(_ uri: String) throws -> RemoteStreamItem {
        let json = #"{"uri":"\#(uri)","body":"p","createdAt":"2026-10-17T01:00:00Z","author":{"username":"a@s.example","displayName":null,"avatarUrl":null,"url":"https://s.example/@a"},"media":[],"contentWarning":null,"sensitive":false,"language":"ko","likeCount":1,"repostCount":0,"replyCount":0,"poll":null,"linkPreview":null,"remote":null,"servers":["s.example"]}"#
        return .trending(try JSONDecoder.blog.decode(TrendingNote.self, from: Data(json.utf8)))
    }

    private static func post(_ id: Int64) -> FeedItem {
        FeedItem(
            id: id, author: Author(id: 3, username: "kim", bio: nil, avatarUrl: nil), slug: "p\(id)",
            title: "글 \(id)", excerpt: nil, ogImageUrl: nil, languageTag: "ko", tags: [],
            publishedAt: nil, viewCount: 0, likeCount: 0)
    }

    @MainActor
    private final class KeyedItems {
        private var made: [String: HomeFeedItem] = [:]
        private var next: Int64 = 1_000

        func item(_ key: String) throws -> HomeFeedItem {
            if let item = made[key] { return item }
            let item: HomeFeedItem
            if let id = key.split(separator: ":").last.flatMap({ Int64($0) }), key.hasPrefix("kurl:note:") {
                item = HomeFeedItem(kind: .note(try FeedVectorTests.note(id)))
            } else if let id = key.split(separator: ":").last.flatMap({ Int64($0) }), key.hasPrefix("kurl:post:") {
                item = HomeFeedItem(kind: .post(FeedVectorTests.post(id)))
            } else if key.hasPrefix("https://") || key.hasPrefix("http://") {
                item = HomeFeedItem(kind: .remote(try FeedVectorTests.pool(key)))
            } else {
                next += 1
                item = HomeFeedItem(kind: .remote(try FeedVectorTests.pool("https://v.example/s/\(key)-\(next)")))
            }
            made[key] = item
            return item
        }

        func key(of item: HomeFeedItem) -> String? {
            made.first { $0.value.id == item.id }?.key
        }
    }

    // MARK: the file

    func testTheBundledSeenRulesAreTheSharedOnesByteForByte() throws {
        let digest = SHA256.hash(data: try Self.data("seen-rules")).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, Self.seenRulesSHA256)
        let seen = try Self.seenRules()
        XCTAssertEqual(seen.schema, "kurl.seen-rules")
        XCTAssertEqual(seen.version, 3)
    }

    // MARK: tables

    func testSeenKeyFormatTable() throws {
        for vector in try Self.seenRules().tables.keyFormat.cases {
            let item: HomeFeedItem
            switch vector.row.kind {
            case "note":
                item = HomeFeedItem(kind: .note(try Self.note(try XCTUnwrap(Int64(try XCTUnwrap(vector.row.id))))))
            case "post":
                item = HomeFeedItem(kind: .post(Self.post(try XCTUnwrap(Int64(try XCTUnwrap(vector.row.id))))))
            default:
                item = HomeFeedItem(kind: .remote(try vector.row.uri.map(Self.pool) ?? .kept(try Self.note(9, uri: nil))))
            }
            check(vector.id) { XCTAssertEqual(item.seenKey, vector.key, vector.id) }
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
            case ("home-for-you", "next page"): _ = try await HomeFeedAPI.page(.forYou, cursor: "r1792656810855.20")
            case ("home-for-you", _): _ = try await HomeFeedAPI.page(.forYou, cursor: nil)
            case ("home-following", _): _ = try await HomeFeedAPI.page(.following, cursor: nil)
            case ("explore-remote", _): _ = try await FederationAPI.stream(.forYou, cursor: nil)
            default: XCTFail("\(vector.id) has no request mapped: \(vector.surface) \(vector.what)")
            }
            let request = try XCTUnwrap(ScriptedFederation.requests.last, vector.id)
            let items = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
            let hides = items.contains { $0.name == "seen" && $0.value == "hide" }
            let device = request.value(forHTTPHeaderField: RemoteSeenDevice.header) != nil
            check(vector.id) {
                XCTAssertEqual(hides, vector.seenHide, "\(vector.id) seen=hide")
                if vector.deviceHeader == .required {
                    XCTAssertTrue(device, "\(vector.id) device header")
                }
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
            let item = HomeFeedItem(kind: .note(try Self.note(1)))
            if let ago = vector.seenSecondsAgo {
                log.record(try XCTUnwrap(item.seenKey))
                now = now.addingTimeInterval(ago)
            }
            let leftOut = HomeFeedViewModel.leftOutOfCache(item, log: log)
            check(vector.id) { XCTAssertEqual(leftOut, vector.leftOut, "\(vector.id) \(vector.name)") }
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private final class PullAnswers {
        var own: Result<HomeFeedBatch, Error>
        var said: [String] = []

        init(_ own: HomeFeedBatch) { self.own = .success(own) }
    }

    func testPullTable() async throws {
        let failed = APIError.server(status: 503, code: nil, detail: "")
        for vector in try Self.seenRules().tables.pull.cases {
            let keyed = KeyedItems()
            let answers = PullAnswers(HomeFeedBatch(items: try vector.before.map(keyed.item), next: nil))
            let model = HomeFeedViewModel(
                tab: .forYou,
                notify: { answers.said.append($0) },
                flushSeen: {},
                seenBefore: { _ in false },
                cached: { _ in nil },
                newer: { _, _ in throw failed },
                load: { _, _ in try answers.own.get() })
            Self.kept += [model, answers, keyed]
            await model.reload()

            answers.own = vector.result == "ok"
                ? .success(HomeFeedBatch(items: try (vector.after ?? []).map(keyed.item), next: nil)) : .failure(failed)
            await model.refresh()

            let notice: String
            if answers.said == [String(localized: "새로고침하지 못했습니다")] {
                notice = "failed"
            } else if answers.said == [String(localized: "새 글이 없어요")] {
                notice = "nothingNew"
            } else if answers.said.isEmpty, case .failed = model.phase {
                notice = "failed"
            } else if answers.said.isEmpty {
                notice = model.items.isEmpty ? "caughtUp" : "newRows"
            } else {
                notice = "said \(answers.said)"
            }
            let rows = model.items.map { keyed.key(of: $0) ?? $0.id }
            check(vector.id) {
                XCTAssertEqual(notice, vector.notice, "\(vector.id) \(vector.name)")
                XCTAssertEqual(rows, vector.rowsAfter, "\(vector.id) rows after")
            }
        }
    }
}
