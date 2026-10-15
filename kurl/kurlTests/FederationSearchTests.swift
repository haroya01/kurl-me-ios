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

private final class ScriptedFederation: URLProtocol, @unchecked Sendable {
    enum Reply {
        case json(Int, String)
        case fail(URLError.Code)
    }

    nonisolated(unsafe) static var replies: [String: Reply] = [:]
    nonisolated(unsafe) private static var captured: [URLRequest] = []
    private static let lock = NSLock()

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }

    static var paths: [String] { requests.compactMap { $0.url?.path } }

    static func reset() {
        lock.lock()
        captured = []
        replies = [:]
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.captured.append(request)
        let path = request.url?.path ?? ""
        let reply = Self.replies.first { path.hasSuffix($0.key) }?.value
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
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
        }
    }

    override func stopLoading() {}
}
