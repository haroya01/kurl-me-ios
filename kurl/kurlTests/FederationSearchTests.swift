//
//  FederationSearchTests.swift
//  kurlTests
//

import XCTest

@testable import kurl

@MainActor
final class FederationSearchTests: XCTestCase {

    override func tearDown() async throws {
        FederationAPI.client = .shared
        ScriptedFederation.reset()
    }

    private func serve(_ replies: [String: ScriptedFederation.Reply]) {
        ScriptedFederation.reset()
        ScriptedFederation.replies = replies
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedFederation.self]
        FederationAPI.client = APIClient(session: URLSession(configuration: config), viewerToken: { nil })
    }

    private static let alice = #"""
    {"id":42,"acct":"alice@mastodon.social","username":"alice","domain":"mastodon.social","displayName":"Alice","avatarUrl":null,"url":"https://mastodon.social/@alice","following":true,"requested":false,"domainBlocked":false}
    """#

    private static let blocked = #"""
    {"id":43,"acct":"bob@spam.example","username":"bob","domain":"spam.example","displayName":null,"avatarUrl":null,"url":"https://spam.example/@bob","following":false,"requested":false,"domainBlocked":true}
    """#

    private static let remoteNote = #"""
    {"id":9601,"body":"오늘 찍은 파도","createdAt":"2026-10-15T09:00:00Z","editedAt":null,"likeCount":null,"likedByMe":false,
     "author":{"id":-9800,"username":"mina@mastodon.social","bio":null,"avatarUrl":null,"displayName":"Mina","remoteId":9800,"url":"https://mastodon.social/@mina"},
     "media":[{"url":"https://files.mastodon.social/waves.mp4","altText":"파도","contentType":"video/mp4"}],
     "quotedPost":null,"inReplyToId":null,"replyCount":0,"repostCount":null,"repostedByMe":false,"quotedNote":null,
     "linkPreview":null,"mentions":[],"contentWarning":null,"sensitive":false,"visibility":"public"}
    """#

    private static func problem(_ status: Int, _ code: String) -> ScriptedFederation.Reply {
        .json(status, #"{"status":\#(status),"code":"\#(code)","detail":"\#(code.lowercased())"}"#)
    }

    func testSearchReadsItemsAndDropsBlockedServers() async throws {
        serve(["/federation/accounts/search": .json(200, #"{"items":[\#(Self.alice),\#(Self.blocked)]}"#)])

        let found = await FederationAPI.searchAccounts("  @al ")

        XCTAssertEqual(found?.map(\.acct), ["alice@mastodon.social"])
        XCTAssertEqual(found?.first?.following, true)
        let query = try XCTUnwrap(ScriptedFederation.requests.first?.url)
            .query(percentEncoded: false) ?? ""
        XCTAssertTrue(query.contains("q=al"), query)
        XCTAssertTrue(query.contains("limit=5"), query)
    }

    func testSearchFailureHidesTheSectionInsteadOfShowingNoMatches() async {
        serve(["/federation/accounts/search": Self.problem(400, "INVALID_ARGUMENT")])
        let rejected = await FederationAPI.searchAccounts("alice")
        XCTAssertNil(rejected)

        serve(["/federation/accounts/search": .json(401, "")])
        let signedOut = await FederationAPI.searchAccounts("alice")
        XCTAssertNil(signedOut)

        serve(["/federation/accounts/search": .json(200, #"{"results":[]}"#)])
        let reshaped = await FederationAPI.searchAccounts("alice")
        XCTAssertNil(reshaped)
    }

    func testSearchShorterThanTwoCharactersSendsNothing() async {
        serve([:])
        let found = await FederationAPI.searchAccounts(" @a ")
        XCTAssertEqual(found, [])
        XCTAssertTrue(ScriptedFederation.requests.isEmpty)
    }

    func testResolveReadsAccount() async throws {
        serve(["/federation/resolve": .json(200, #"{"account":\#(Self.alice),"note":null}"#)])

        let result = await FederationAPI.resolve("@alice@mastodon.social")

        guard case .account(let account) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(account.id, 42)
        let request = try XCTUnwrap(ScriptedFederation.requests.first)
        XCTAssertEqual(request.url?.query(percentEncoded: false), "q=@alice@mastodon.social")
        XCTAssertEqual(request.timeoutInterval, FederationAPI.resolveTimeout)
        XCTAssertEqual(FederationAPI.resolveTimeout, 20)
    }

    func testResolveReadsRemoteNote() async {
        serve(["/federation/resolve": .json(200, #"{"account":null,"note":\#(Self.remoteNote)}"#)])

        let result = await FederationAPI.resolve("https://mastodon.social/@mina/9601")

        guard case .note(let note) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(note.id, 9601)
        XCTAssertEqual(note.author.remoteId, 9800)
        XCTAssertEqual(note.media.count, 1)
    }

    func testResolveErrorCodesNameTheServer() async {
        serve(["/federation/resolve": Self.problem(404, "REMOTE_ACCOUNT_NOT_FOUND")])
        let notFound = await FederationAPI.resolve("@nobody@Mastodon.Social")
        XCTAssertEqual(notFound, .missing(domain: "mastodon.social"))
        XCTAssertEqual(ScriptedFederation.paths, ["/api/v1/federation/resolve"])

        serve(["/federation/resolve": Self.problem(400, "REMOTE_ACCOUNT_INVALID")])
        let invalid = await FederationAPI.resolve("https://mastodon.social/about")
        XCTAssertEqual(invalid, .missing(domain: "mastodon.social"))

        serve(["/federation/resolve": Self.problem(502, "REMOTE_SERVER_UNREACHABLE")])
        let down = await FederationAPI.resolve("@mina@down.example")
        XCTAssertEqual(down, .unreachable(domain: "down.example"))

        serve(["/federation/resolve": .fail(.timedOut)])
        let slow = await FederationAPI.resolve("@mina@slow.example")
        XCTAssertEqual(slow, .unreachable(domain: "slow.example"))

        serve(["/federation/resolve": .json(401, "")])
        let signedOut = await FederationAPI.resolve("@mina@mastodon.social")
        XCTAssertEqual(signedOut, .signIn)

        serve(["/federation/resolve": .json(502, "")])
        let gateway = await FederationAPI.resolve("@mina@mastodon.social")
        XCTAssertEqual(gateway, .hidden)
    }

    func testResolveRouteMissingFallsBackToLookupForHandles() async {
        for missingRoute in [
            ScriptedFederation.Reply.json(404, ""),
            Self.problem(404, "NOT_FOUND"),
        ] {
            serve([
                "/federation/resolve": missingRoute,
                "/federation/accounts/lookup": .json(200, Self.alice),
            ])

            let result = await FederationAPI.resolve("@alice@mastodon.social")

            guard case .account(let account) = result else { return XCTFail("\(result)") }
            XCTAssertEqual(account.acct, "alice@mastodon.social")
            XCTAssertEqual(
                ScriptedFederation.paths, ["/api/v1/federation/resolve", "/api/v1/federation/accounts/lookup"])
        }
    }

    func testResolveRouteMissingFallbackKeepsLookupFailureReason() async {
        serve([
            "/federation/resolve": .json(404, ""),
            "/federation/accounts/lookup": Self.problem(404, "REMOTE_ACCOUNT_NOT_FOUND"),
        ])

        let result = await FederationAPI.resolve("@nobody@mastodon.social")

        XCTAssertEqual(result, .missing(domain: "mastodon.social"))
    }

    func testResolveRouteMissingHidesAddresses() async {
        serve([
            "/federation/resolve": Self.problem(404, "NOT_FOUND"),
            "/federation/accounts/lookup": .json(200, Self.alice),
        ])

        let result = await FederationAPI.resolve("https://mastodon.social/@alice")

        XCTAssertEqual(result, .hidden)
        XCTAssertEqual(ScriptedFederation.paths, ["/api/v1/federation/resolve"])
    }

    func testQueryDomainAcceptsHandlesAndHttpsAddressesOnly() {
        XCTAssertEqual(FederationAPI.queryDomain(" @Alice@Mastodon.Social "), "mastodon.social")
        XCTAssertEqual(FederationAPI.queryDomain("alice@misskey.io"), "misskey.io")
        XCTAssertEqual(FederationAPI.queryDomain("https://Mastodon.Social/@mina/12"), "mastodon.social")
        XCTAssertNil(FederationAPI.queryDomain("http://mastodon.social/@mina"))
        XCTAssertNil(FederationAPI.queryDomain("https://localhost/@mina"))
        XCTAssertNil(FederationAPI.queryDomain("alice"))
        XCTAssertNil(FederationAPI.queryDomain("@alice"))
        XCTAssertNil(FederationAPI.queryDomain("https://mastodon.social/@mina and more"))
    }
}

@MainActor
final class FederationSafetyTests: XCTestCase {

    override func tearDown() async throws {
        FederationAPI.client = .shared
        ScriptedFederation.reset()
    }

    private func serve(_ replies: [String: ScriptedFederation.Reply]) {
        ScriptedFederation.reset()
        ScriptedFederation.replies = replies
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedFederation.self]
        FederationAPI.client = APIClient(session: URLSession(configuration: config), viewerToken: { nil })
    }

    private static func account(_ id: Int64, _ acct: String, safety: String? = nil) -> String {
        let parts = acct.split(separator: "@").map(String.init)
        let extra = safety.map { ",\($0)" } ?? ""
        return #"{"id":\#(id),"acct":"\#(acct)","username":"\#(parts[0])","domain":"\#(parts[1])","displayName":null,"avatarUrl":null,"url":"https://\#(parts[1])/@\#(parts[0])","following":false,"requested":false,"domainBlocked":false\#(extra)}"#
    }

    private func decoded(_ json: String) throws -> RemoteAccount {
        try JSONDecoder.blog.decode(RemoteAccount.self, from: Data(json.utf8))
    }

    func testAccountWithoutSafetyFieldsHidesBlockAndMute() throws {
        let old = try decoded(Self.account(1, "mina@mastodon.social"))
        XCTAssertFalse(old.offersBlockAndMute)
        XCTAssertFalse(old.isBlocking)
        XCTAssertFalse(old.isMuting)

        let current = try decoded(Self.account(1, "mina@mastodon.social", safety: #""blocking":true,"muting":false"#))
        XCTAssertTrue(current.offersBlockAndMute)
        XCTAssertTrue(current.isBlocking)
        XCTAssertFalse(current.isMuting)

        let half = try decoded(Self.account(1, "mina@mastodon.social", safety: #""blocking":false"#))
        XCTAssertFalse(half.offersBlockAndMute)
    }

    func testBlockAndUnblockUseTheAccountPath() async throws {
        serve(["/federation/accounts/7/block": .json(
            200, Self.account(7, "bob@fosstodon.org", safety: #""blocking":true,"muting":false"#))])

        let blocked = try await FederationAPI.setBlocking(true, id: 7)
        XCTAssertTrue(blocked.isBlocking)
        _ = try await FederationAPI.setBlocking(false, id: 7)

        XCTAssertEqual(ScriptedFederation.requests.map(\.httpMethod), ["PUT", "DELETE"])
        XCTAssertEqual(ScriptedFederation.paths, Array(repeating: "/api/v1/federation/accounts/7/block", count: 2))
    }

    func testMuteSendsNotificationsAndDurationAndForeverSendsNoDuration() async throws {
        serve(["/federation/accounts/7/mute": .json(
            200, Self.account(7, "bob@fosstodon.org", safety: #""blocking":false,"muting":true"#))])

        let muted = try await FederationAPI.mute(id: 7, notifications: false, duration: 3600)
        XCTAssertTrue(muted.isMuting)
        _ = try await FederationAPI.mute(id: 7, notifications: true, duration: nil)
        _ = try await FederationAPI.unmute(id: 7)

        XCTAssertEqual(ScriptedFederation.requests.map(\.httpMethod), ["PUT", "PUT", "DELETE"])
        let bodies = try ScriptedFederation.bodies.prefix(2).map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: $0) as? [String: Any])
        }
        XCTAssertEqual(bodies.count, 2)
        guard bodies.count == 2 else { return }
        XCTAssertEqual(bodies[0]["notifications"] as? Bool, false)
        XCTAssertEqual(bodies[0]["duration"] as? Int, 3600)
        XCTAssertEqual(bodies[1]["notifications"] as? Bool, true)
        XCTAssertNil(bodies[1]["duration"])
    }

    func testBlockListReadsEveryFullPage() async throws {
        let full = (0..<FederationAPI.safetyPageSize).map { Self.account(Int64(100 + $0), "u\($0)@a.example") }
        serve(["/federation/blocks": .pages([
            .json(200, #"{"items":[\#(full.joined(separator: ","))]}"#),
            .json(200, #"{"items":[\#(Self.account(9, "last@b.example"))]}"#),
        ])])

        let found = await FederationAPI.blockedAccounts()

        XCTAssertEqual(found?.count, FederationAPI.safetyPageSize + 1)
        XCTAssertEqual(found?.last?.acct, "last@b.example")
        let pages = ScriptedFederation.requests.compactMap { $0.url?.query(percentEncoded: false) }
        XCTAssertEqual(pages.count, 2)
        guard pages.count == 2 else { return }
        XCTAssertTrue(pages[0].contains("page=0"), pages[0])
        XCTAssertTrue(pages[1].contains("page=1"), pages[1])
        XCTAssertTrue(pages[1].contains("size=\(FederationAPI.safetyPageSize)"), pages[1])
    }

    func testListsHideOnAnOldBackend() async {
        serve(["/federation/blocks": .json(404, "")])
        let blocks = await FederationAPI.blockedAccounts()
        XCTAssertNil(blocks)

        serve(["/federation/mutes": .json(200, #"{"content":[]}"#)])
        let mutes = await FederationAPI.mutedAccounts()
        XCTAssertNil(mutes)
    }

    func testMuteListReadsExpiryAndNotifications() async throws {
        let mina = Self.account(5, "mina@mastodon.social")
        let carol = Self.account(6, "carol@fosstodon.org")
        let page = #"{"items":[{"account":\#(mina),"expiresAt":"2026-10-18T09:30:00Z","notifications":true},"#
            + #"{"account":\#(carol),"expiresAt":null,"notifications":false}]}"#
        serve(["/federation/mutes": .json(200, page)])

        let mutes = await FederationAPI.mutedAccounts()
        let found = try XCTUnwrap(mutes)

        XCTAssertEqual(found.map(\.id), [5, 6])
        XCTAssertEqual(found[0].expiresAt, ISO8601DateFormatter().date(from: "2026-10-18T09:30:00Z"))
        XCTAssertTrue(found[0].notifications)
        XCTAssertNil(found[1].expiresAt)
        XCTAssertFalse(found[1].notifications)
    }

    func testSearchDropsAccountsIBlocked() async {
        let blocked = Self.account(8, "bob@fosstodon.org", safety: #""blocking":true,"muting":false"#)
        let muted = Self.account(9, "bo@fosstodon.org", safety: #""blocking":false,"muting":true"#)
        serve(["/federation/accounts/search": .json(200, #"{"items":[\#(blocked),\#(muted)]}"#)])

        let found = await FederationAPI.searchAccounts("bo")

        XCTAssertEqual(found?.map(\.acct), ["bo@fosstodon.org"])
    }
}

private final class ScriptedFederation: URLProtocol, @unchecked Sendable {
    enum Reply {
        case json(Int, String)
        case fail(URLError.Code)
        indirect case pages([Reply])
    }

    nonisolated(unsafe) static var replies: [String: Reply] = [:]
    nonisolated(unsafe) private static var captured: [URLRequest] = []
    nonisolated(unsafe) private static var capturedBodies: [Data] = []
    nonisolated(unsafe) private static var served: [String: Int] = [:]
    private static let lock = NSLock()

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }

    static var bodies: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return capturedBodies
    }

    static var paths: [String] { requests.compactMap { $0.url?.path } }

    static func reset() {
        lock.lock()
        captured = []
        capturedBodies = []
        served = [:]
        replies = [:]
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.captured.append(request)
        Self.capturedBodies.append(Self.body(of: request))
        let path = request.url?.path ?? ""
        var reply: Reply?
        if let (key, found) = Self.replies.first(where: { path.hasSuffix($0.key) }) {
            reply = found
            if case .pages(let pages) = found {
                let index = Self.served[key, default: 0]
                Self.served[key] = index + 1
                reply = index < pages.count ? pages[index] : nil
            }
        }
        Self.lock.unlock()
        switch reply {
        case .fail(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .json(let status, let body):
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case .pages, nil:
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
        }
    }

    override func stopLoading() {}

    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
