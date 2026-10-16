//
//  PostAudienceTests.swift
//  kurlTests
//

import XCTest

@testable import kurl

@MainActor
final class PostAudienceTests: XCTestCase {

    private static var retained: [AnyObject] = []

    override func setUp() async throws {
        PostAccess.shared.reset()
        AudienceStub.reset()
    }

    override func tearDown() async throws {
        BlogAPI.client = .shared
        HighlightsAPI.client = .shared
        NoteAPI.client = .shared
        PostAccess.shared.reset()
        AudienceStub.reset()
    }

    private func stubbedClient() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AudienceStub.self]
        return APIClient(session: URLSession(configuration: config), viewerToken: { nil })
    }

    private func useStub() {
        let client = stubbedClient()
        BlogAPI.client = client
        HighlightsAPI.client = client
        NoteAPI.client = client
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.blog.decode(T.self, from: Data(json.utf8))
    }

    private static func post(_ extra: String = "") -> String {
        """
        {"id":42,"slug":"memo","title":"모임 메모","excerpt":null,"ogImageUrl":null,"languageTag":"ko",\
        "tags":[],"likeCount":0,"publishedAt":"2026-10-16T01:00:00Z","lastEditedAt":null,"pinned":false\(extra)}
        """
    }

    private static func detail(_ extra: String = "") -> String {
        """
        {"author":{"id":3,"username":"writer","bio":null,"avatarUrl":null},"post":\(post(extra)),\
        "blocks":[{"type":"PARAGRAPH","content":"본문","blockOrder":0}],"series":null}
        """
    }

    // MARK: 디코딩

    func testPostObjectCarriesAudienceLockAndOwnerFields() throws {
        let item = try decode(PostListItem.self, Self.post(
            #","audience":"UNLISTED","regionRestricted":true,"hasPassword":true,"#
                + #""unlistedUrl":"https://blog.kurl.me/@me/memo?k=abc","blockedCountries":["JP","US"]"#))
        XCTAssertEqual(item.audience, .unlisted)
        XCTAssertEqual(item.regionRestricted, true)
        XCTAssertEqual(item.hasPassword, true)
        XCTAssertEqual(item.unlistedUrl, "https://blog.kurl.me/@me/memo?k=abc")
        XCTAssertEqual(item.blockedCountries, ["JP", "US"])
        XCTAssertNil(item.locked)

        let locked = try decode(PostListItem.self, Self.post(#","audience":"FOLLOWERS","locked":{"reason":"FOLLOWERS"}"#))
        XCTAssertEqual(locked.locked?.reason, .followers)
    }

    func testAnOldServerOrPublicPostDecodesWithoutTheNewFields() throws {
        let item = try decode(PostListItem.self, Self.post())
        XCTAssertNil(item.audience)
        XCTAssertNil(item.locked)
        XCTAssertFalse(item.access.isProtected)
        XCTAssertFalse(item.access.isMarked)
    }

    func testUnknownAudienceReadsAsPublicAndDoesNotBreakTheList() throws {
        let item = try decode(PostListItem.self, Self.post(#","audience":"SECRET""#))
        XCTAssertEqual(item.audience, .everyone)
    }

    func testRegionCheckReadsAsARegionLock() throws {
        let item = try decode(PostListItem.self, Self.post(#","audience":"PUBLIC","locked":{"reason":"REGION_CHECK"}"#))
        XCTAssertEqual(item.locked?.reason, .region)
        let unknown = try decode(PostListItem.self, Self.post(#","locked":{"reason":"SOMETHING_NEW"}"#))
        XCTAssertEqual(unknown.locked?.reason, .region)
    }

    func testFeedCardsNoteCardsAndMyPostsDecodeAccess() throws {
        let feed = try decode(FeedItem.self, """
            {"id":1,"author":{"id":3,"username":"w","bio":null,"avatarUrl":null},"slug":"s","title":"t",\
            "excerpt":null,"ogImageUrl":null,"languageTag":"ko","tags":[],"publishedAt":null,"viewCount":0,\
            "likeCount":0,"audience":"PUBLIC","regionRestricted":true}
            """)
        XCTAssertEqual(feed.access.showsRegionMark, true)

        let quoted = try decode(QuotedPost.self, #"{"id":1,"title":"t","slug":"s","authorUsername":"w","audience":"PASSWORD","locked":{"reason":"PASSWORD"}}"#)
        XCTAssertEqual(quoted.access.audienceMark, .password)

        let mine = try decode(MyPost.self, """
            {"id":7,"slug":"s","title":"t","status":"PUBLISHED","audience":"PASSWORD","hasPassword":true,\
            "blockedCountries":["KR"]}
            """)
        XCTAssertEqual(mine.audience, .password)
        XCTAssertEqual(mine.hasPassword, true)
        XCTAssertEqual(mine.access.showsRegionMark, true)
    }

    // MARK: 목록 표시

    func testListMarksStandInForTheAudienceAndCountryBlock() {
        func marks(_ audience: PostAudience?, _ reason: PostLock.Reason? = nil, region: Bool = false) -> PostAccessMarks {
            PostAccessMarks(audience: audience, locked: reason.map(PostLock.init(reason:)), regionRestricted: region)
        }
        XCTAssertFalse(marks(.everyone).isMarked)
        XCTAssertFalse(marks(nil).isMarked)
        XCTAssertEqual(marks(.unlisted).audienceMark, .unlisted)
        XCTAssertEqual(marks(.followers).audienceMark, .followers)
        XCTAssertEqual(marks(.followers, .followers).audienceMark, .followers)
        XCTAssertEqual(marks(.password, .password).audienceMark, .password)
        XCTAssertEqual(marks(nil, .password).audienceMark, .password)
        XCTAssertNil(marks(.everyone, .region).audienceMark)
        XCTAssertTrue(marks(.everyone, .region).showsRegionMark)
        XCTAssertTrue(marks(.everyone, region: true).showsRegionMark)
        XCTAssertEqual(marks(.followers, .region, region: true).audienceMark, .followers)
        XCTAssertEqual(PostAudience.unlisted.symbol, "link")
        XCTAssertEqual(PostAudience.followers.symbol, "lock")
        XCTAssertEqual(PostAudience.password.symbol, "key")
    }

    func testOwnerListRowShowsTheCountryMarkFromBlockedCountries() throws {
        let owner = try decode(PostListItem.self, Self.post(#","audience":"PUBLIC","blockedCountries":["JP"]"#))
        XCTAssertTrue(owner.access.showsRegionMark)
        XCTAssertNil(owner.access.audienceMark)
    }

    // MARK: 열람 키·열람권 헤더

    func testCredentialsRideOnEveryRequestScopedToThePost() {
        let access = PostAccess.shared
        access.setKey("k-1", username: "writer", slug: "memo")
        access.setGrant("g-1", username: "writer", slug: "memo")
        access.bind(postId: 42, username: "writer", slug: "memo")
        access.link(highlights: [7], to: 42)
        access.link(comments: [9], to: 42)

        let scoped = [
            "/public/profiles/writer/posts/memo",
            "/public/profiles/writer/posts/memo/view",
            "/public/posts/42/comments",
            "/public/posts/42/highlights",
            "/public/posts/42/quotes",
            "/posts/42/like",
            "/posts/42/bookmark",
            "/posts/42/comments",
            "/posts/42/comments/liked",
            "/posts/42/highlights",
            "/posts/42/read",
            "/public/highlights/7/replies",
            "/highlights/7/replies",
            "/comments/9/like",
        ]
        for path in scoped {
            XCTAssertEqual(access.headers(forPath: path), ["X-Post-Key": "k-1", "X-Post-Grant": "g-1"], path)
        }
        let unrelated = [
            "/public/profiles/writer/posts",
            "/public/profiles/writer/posts/other",
            "/public/posts/43/comments",
            "/posts/pins",
            "/posts/analytics/overview",
            "/public/highlights/8/replies",
            "/comments/10/like",
            "/public/posts",
        ]
        for path in unrelated {
            XCTAssertEqual(access.headers(forPath: path), [:], path)
        }
    }

    func testTheAPIClientSendsTheHeadersIncludingOnTheViewBeacon() async throws {
        useStub()
        PostAccess.shared.setGrant("g-1", username: "writer", slug: "memo")
        PostAccess.shared.bind(postId: 42, username: "writer", slug: "memo")
        AudienceStub.route("GET", "/public/profiles/writer/posts/memo", body: Self.detail())
        AudienceStub.route("GET", "/public/posts/42/comments", body: "[]")
        AudienceStub.route("GET", "/public/posts/42/highlights", body: "[]")

        _ = try await BlogAPI.postDetail(username: "writer", slug: "memo")
        await BlogAPI.recordView(username: "writer", slug: "memo")
        _ = try await BlogAPI.comments(postId: 42)
        _ = try await HighlightsAPI.list(postId: 42)
        _ = try? await BlogAPI.authorPosts(username: "writer")

        let requests = AudienceStub.requests
        XCTAssertEqual(requests.count, 5)
        for request in requests.prefix(4) {
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Post-Grant"), "g-1", request.url?.path ?? "")
        }
        XCTAssertNil(requests[4].value(forHTTPHeaderField: "X-Post-Grant"), "작가 글 목록은 열람권을 받지 않는다")
    }

    func testALockedAnswerWhileHoldingAGrantDropsTheGrant() async throws {
        useStub()
        PostAccess.shared.setGrant("g-1", username: "writer", slug: "memo")
        PostAccess.shared.bind(postId: 42, username: "writer", slug: "memo")
        AudienceStub.route(
            "GET", "/public/posts/42/comments", status: 403,
            body: #"{"title":"Forbidden","detail":"post is locked","code":"POST_LOCKED","reason":"PASSWORD"}"#)

        _ = try? await BlogAPI.comments(postId: 42)

        XCTAssertFalse(PostAccess.shared.hasGrant(username: "writer", slug: "memo"))
        XCTAssertEqual(PostAccess.shared.lockouts["writer/memo"], 1)
    }

    func testALockedAnswerWithoutAGrantChangesNothing() {
        PostAccess.shared.setKey("k-1", username: "writer", slug: "memo")
        PostAccess.shared.lockedOut(path: "/public/profiles/writer/posts/memo")
        XCTAssertNil(PostAccess.shared.lockouts["writer/memo"])
        XCTAssertEqual(PostAccess.shared.credential(username: "writer", slug: "memo")?.key, "k-1")
    }

    func testSignOutForgetsEveryCredential() {
        PostAccess.shared.setKey("k-1", username: "writer", slug: "memo")
        PostAccess.shared.setGrant("g-1", username: "writer", slug: "memo")
        PostAccess.shared.reset()
        XCTAssertNil(PostAccess.shared.credential(username: "writer", slug: "memo"))
        XCTAssertEqual(PostAccess.shared.headers(forPath: "/public/profiles/writer/posts/memo"), [:])
    }

    // MARK: 위젯 스킴·--post 진입로의 키

    func testTheDebugPostPathCarriesTheKey() {
        let link = PostLink(target: "writer/memo?k=abc123")
        XCTAssertEqual(link?.username, "writer")
        XCTAssertEqual(link?.slug, "memo")
        XCTAssertEqual(link?.key, "abc123")
        XCTAssertNil(PostLink(target: "writer/memo")?.key)
        XCTAssertNil(PostLink(target: "writer/memo?k=")?.key)
        XCTAssertNil(PostLink(target: "writer"))
        XCTAssertNil(PostLink(target: "a/b/c"))
    }

    func testTheWidgetSchemeCarriesTheKeyIntoTheRequestHeader() throws {
        let url = try XCTUnwrap(URL(string: "kurlwidget://post/writer/memo?k=abc123"))
        let link = try XCTUnwrap(PostLink(widgetURL: url))
        XCTAssertEqual(link.username, "writer")
        XCTAssertEqual(link.slug, "memo")
        XCTAssertEqual(link.key, "abc123")
        link.register()
        XCTAssertEqual(
            PostAccess.shared.headers(forPath: "/public/profiles/writer/posts/memo"), ["X-Post-Key": "abc123"])

        XCTAssertNil(PostLink(widgetURL: try XCTUnwrap(URL(string: "kurlwidget://analytics"))))
        XCTAssertNil(PostLink(widgetURL: try XCTUnwrap(URL(string: "https://blog.kurl.me/@writer/memo?k=abc"))))
    }

    // MARK: 비밀번호로 열기

    private func model() -> PostDetailViewModel {
        let model = PostDetailViewModel(username: "writer", slug: "memo")
        Self.retained.append(model)
        return model
    }

    private let lockedPassword = #","audience":"PASSWORD","locked":{"reason":"PASSWORD"}"#

    func testUnlockStoresTheGrantAndReadsThePostWithIt() async throws {
        useStub()
        AudienceStub.route("GET", "/public/profiles/writer/posts/memo", body: Self.detail(lockedPassword))
        let vm = model()
        await vm.load()
        XCTAssertEqual(vm.lock, .password)

        AudienceStub.route(
            "POST", "/public/profiles/writer/posts/memo/unlock",
            body: #"{"grant":"g-ok","expiresAt":"2026-10-17T01:00:00Z"}"#)
        AudienceStub.route("GET", "/public/profiles/writer/posts/memo", body: Self.detail(#","audience":"PASSWORD""#))
        AudienceStub.route("GET", "/public/posts/42/comments", body: "[]")
        AudienceStub.route("GET", "/public/posts/42/quotes", body: #"{"items":[],"page":0,"hasNext":false,"total":0}"#)
        AudienceStub.clearRequests()

        await vm.unlock(password: "kurl1234")

        XCTAssertNil(vm.lock)
        XCTAssertEqual(vm.unlockState, .idle)
        XCTAssertEqual(vm.unlockedCount, 1)
        XCTAssertTrue(PostAccess.shared.hasGrant(username: "writer", slug: "memo"))
        let unlock = AudienceStub.requests.first { $0.url?.path.hasSuffix("/unlock") == true }
        XCTAssertEqual(unlock?.httpMethod, "POST")
        let reread = AudienceStub.requests.first {
            $0.httpMethod == "GET" && $0.url?.path.hasSuffix("/posts/memo") == true
        }
        XCTAssertEqual(reread?.value(forHTTPHeaderField: "X-Post-Grant"), "g-ok")
        try await Task.sleep(for: .milliseconds(200))
    }

    func testAWrongPasswordAndTooManyTriesStayOnTheGate() async throws {
        useStub()
        AudienceStub.route("GET", "/public/profiles/writer/posts/memo", body: Self.detail(lockedPassword))
        let vm = model()
        await vm.load()

        AudienceStub.route("POST", "/public/profiles/writer/posts/memo/unlock", status: 401,
                           body: #"{"title":"Unauthorized","code":"POST_PASSWORD_INVALID"}"#)
        await vm.unlock(password: "nope")
        XCTAssertEqual(vm.unlockState, .wrongPassword)
        XCTAssertEqual(vm.lock, .password)
        XCTAssertFalse(PostAccess.shared.hasGrant(username: "writer", slug: "memo"))

        vm.clearUnlockError()
        XCTAssertEqual(vm.unlockState, .idle)

        AudienceStub.route("POST", "/public/profiles/writer/posts/memo/unlock", status: 429,
                           body: #"{"title":"Too Many Requests","detail":"slow down","code":"POST_PASSWORD_ATTEMPTS_EXCEEDED"}"#)
        await vm.unlock(password: "nope")
        XCTAssertEqual(vm.unlockState, .tooManyAttempts)
        XCTAssertEqual(vm.unlockedCount, 0)
    }

    func testARevokedGrantIsDroppedWhenTheDetailComesBackLocked() async throws {
        useStub()
        PostAccess.shared.setGrant("g-old", username: "writer", slug: "memo")
        AudienceStub.route("GET", "/public/profiles/writer/posts/memo", body: Self.detail(lockedPassword))
        let vm = model()
        await vm.load()
        XCTAssertEqual(vm.lock, .password)
        XCTAssertFalse(PostAccess.shared.hasGrant(username: "writer", slug: "memo"))
    }

    // MARK: 나라 문

    func testARegionLockedPostShowsTheGateAndAsksForNothingElse() async throws {
        useStub()
        AudienceStub.route(
            "GET", "/public/profiles/writer/posts/memo",
            body: Self.detail(#","audience":"PUBLIC","regionRestricted":true,"locked":{"reason":"REGION"}"#))
        let vm = model()
        await vm.load()
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(vm.lock, .region)
        XCTAssertTrue(vm.comments.isEmpty)
        let paths = AudienceStub.requests.compactMap { $0.url?.path }
        XCTAssertEqual(paths, ["/api/v1/public/profiles/writer/posts/memo"], "잠긴 글은 댓글·인용·조회 비콘을 부르지 않는다")
    }

    // MARK: 오프라인 사본

    func testProtectedBodiesAreNeverPersisted() {
        XCTAssertFalse(OfflineStore.isProtected(Data(Self.detail().utf8)))
        XCTAssertFalse(OfflineStore.isProtected(Data(Self.detail(#","audience":"PUBLIC""#).utf8)))
        XCTAssertTrue(OfflineStore.isProtected(Data(Self.detail(#","audience":"FOLLOWERS""#).utf8)))
        XCTAssertTrue(OfflineStore.isProtected(Data(Self.detail(#","audience":"UNLISTED""#).utf8)))
        XCTAssertTrue(OfflineStore.isProtected(Data(Self.detail(#","audience":"PASSWORD""#).utf8)))
        XCTAssertTrue(OfflineStore.isProtected(Data(Self.detail(#","regionRestricted":true"#).utf8)))
        XCTAssertTrue(OfflineStore.isProtected(Data(Self.detail(#","blockedCountries":["JP"]"#).utf8)))
        XCTAssertTrue(OfflineStore.isProtected(Data(Self.detail(#","locked":{"reason":"REGION"}"#).utf8)))
    }

    func testSavingAProtectedBodyKeepsNoCopyAndDropsTheOldOne() {
        let store = OfflineStore.shared
        store.save(raw: Data(Self.detail().utf8), username: "audience-test", slug: "memo")
        XCTAssertTrue(store.contains(username: "audience-test", slug: "memo"))
        store.save(raw: Data(Self.detail(#","audience":"FOLLOWERS""#).utf8), username: "audience-test", slug: "memo")
        XCTAssertFalse(store.contains(username: "audience-test", slug: "memo"))
        store.save(raw: Data(Self.detail(#","locked":{"reason":"PASSWORD"}"#).utf8), username: "audience-test", slug: "other")
        XCTAssertFalse(store.contains(username: "audience-test", slug: "other"))
        store.remove(username: "audience-test", slug: "memo")
    }

    // MARK: 글 머리 조건 표시

    private func condition(_ extra: String, owner: Bool) throws -> String? {
        let names = ["JP": "일본", "CN": "중국", "US": "미국"]
        return PostConditionLabel.text(
            for: try decode(PostListItem.self, Self.post(extra)), isOwner: owner, countryName: { names[$0] ?? $0 })
    }

    func testEachAudienceNamesItsConditionForReadersAndTheOwner() throws {
        for owner in [false, true] {
            XCTAssertEqual(try condition(#","audience":"FOLLOWERS""#, owner: owner), "팔로워 공개")
            XCTAssertEqual(try condition(#","audience":"UNLISTED""#, owner: owner), "링크로만 공개")
            XCTAssertEqual(try condition(#","audience":"PASSWORD""#, owner: owner), "비밀번호 글")
        }
    }

    func testAPlainPublicPostShowsNoCondition() throws {
        for owner in [false, true] {
            XCTAssertNil(try condition(#","audience":"PUBLIC""#, owner: owner))
            XCTAssertNil(try condition("", owner: owner))
            XCTAssertNil(try condition(#","audience":"PUBLIC","blockedCountries":[]"#, owner: owner))
        }
    }

    func testReadersSeeTheCountryRuleWithoutNamesAndTheOwnerSeesTheNames() throws {
        XCTAssertEqual(
            try condition(#","audience":"FOLLOWERS","regionRestricted":true"#, owner: false), "팔로워 공개 · 일부 나라 제한")
        XCTAssertEqual(try condition(#","audience":"PUBLIC","regionRestricted":true"#, owner: false), "일부 나라 제한")
        XCTAssertEqual(
            try condition(#","audience":"PUBLIC","regionRestricted":true,"blockedCountries":["JP"]"#, owner: false),
            "일부 나라 제한")
        XCTAssertEqual(
            try condition(#","audience":"FOLLOWERS","regionRestricted":true,"blockedCountries":["CN","JP"]"#, owner: true),
            "팔로워 공개 · 일본·중국 제한")
        XCTAssertEqual(
            try condition(#","audience":"PUBLIC","regionRestricted":true,"blockedCountries":["US"]"#, owner: true),
            "미국 제한")
    }

    func testALockedPostShowsNoConditionInItsByline() throws {
        XCTAssertNil(try condition(#","audience":"FOLLOWERS","locked":{"reason":"FOLLOWERS"}"#, owner: false))
        XCTAssertNil(try condition(#","audience":"PASSWORD","locked":{"reason":"PASSWORD"}"#, owner: false))
        XCTAssertNil(
            try condition(#","audience":"PUBLIC","regionRestricted":true,"locked":{"reason":"REGION"}"#, owner: false))
    }

    func testRemovingAReplyLikeCarriesTheGrantOfItsPost() {
        let access = PostAccess.shared
        access.setGrant("g-1", username: "writer", slug: "memo")
        access.bind(postId: 42, username: "writer", slug: "memo")
        access.link(highlights: [7], to: 42)
        access.link(replies: [70, 71], ofHighlight: 7)
        XCTAssertEqual(access.headers(forPath: "/highlight-replies/70/like"), ["X-Post-Grant": "g-1"])
        XCTAssertEqual(access.headers(forPath: "/highlight-replies/71"), ["X-Post-Grant": "g-1"])
        XCTAssertEqual(access.headers(forPath: "/highlight-replies/72/like"), [:])
        access.link(replies: [80], ofHighlight: 8)
        XCTAssertEqual(access.headers(forPath: "/highlight-replies/80/like"), [:])
    }

    // MARK: 발행 시트가 보내는 것

    func testAutosaveNeverSendsThePasswordOrAPasswordAudienceWithoutOne() {
        var draft = PostAccessDraft()
        draft.audience = .password
        XCTAssertNil(draft.patch(silent: true))
        XCTAssertEqual(draft.blockReason, "비밀번호를 정하면 발행할 수 있어요.")

        draft.newPassword = "abc"
        XCTAssertEqual(draft.blockReason, "비밀번호는 4자 이상으로 정해 주세요.")
        XCTAssertNil(draft.patch(silent: false))

        draft.newPassword = "abcd"
        XCTAssertNil(draft.blockReason)
        XCTAssertNil(draft.patch(silent: true))
        XCTAssertEqual(draft.patch(silent: false), .init(audience: .password, password: "abcd", countries: nil))
    }

    func testAStoredPasswordLetsTheAudienceAutosaveAndCountriesAlwaysDo() {
        var draft = PostAccessDraft()
        draft.hasPassword = true
        draft.audience = .password
        XCTAssertNil(draft.blockReason)
        XCTAssertEqual(draft.patch(silent: true), .init(audience: .password, password: nil, countries: nil))

        var countries = PostAccessDraft()
        countries.countries = ["US", "JP"]
        XCTAssertEqual(countries.patch(silent: true), .init(audience: nil, password: nil, countries: ["JP", "US"]))
        countries.savedCountries = ["JP", "US"]
        XCTAssertNil(countries.patch(silent: true))
        countries.countries = []
        XCTAssertEqual(countries.patch(silent: true), .init(audience: nil, password: nil, countries: []))
    }

    func testATypedPasswordIsIgnoredOnceTheAudienceMovesAway() {
        var draft = PostAccessDraft()
        draft.newPassword = "abcd"
        draft.audience = .followers
        XCTAssertNil(draft.blockReason)
        XCTAssertEqual(draft.patch(silent: false), .init(audience: .followers, password: nil, countries: nil))
    }

    func testSavingAdoptsTheServerState() throws {
        var draft = PostAccessDraft()
        draft.audience = .unlisted
        let sent = try XCTUnwrap(draft.patch(silent: false))
        let saved = try decode(MyPost.self, """
            {"id":7,"slug":"s","title":"t","status":"PUBLISHED","audience":"UNLISTED",\
            "unlistedUrl":"https://blog.kurl.me/@me/s?k=new"}
            """)
        draft.adopt(saved: saved, sent: sent)
        XCTAssertEqual(draft.savedAudience, .unlisted)
        XCTAssertEqual(draft.unlistedUrl, "https://blog.kurl.me/@me/s?k=new")
        XCTAssertNil(draft.patch(silent: false))
    }
}

private final class AudienceStub: URLProtocol, @unchecked Sendable {
    private struct Response {
        let status: Int
        let body: String
    }

    nonisolated(unsafe) private static var routes: [String: Response] = [:]
    nonisolated(unsafe) private static var captured: [URLRequest] = []
    private static let lock = NSLock()

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }

    static func route(_ method: String, _ path: String, status: Int = 200, body: String) {
        lock.lock()
        routes["\(method) /api/v1\(path)"] = Response(status: status, body: body)
        lock.unlock()
    }

    static func clearRequests() {
        lock.lock()
        captured = []
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        routes = [:]
        captured = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.captured.append(request)
        let key = "\(request.httpMethod ?? "GET") \(request.url?.path ?? "")"
        let response = Self.routes[key] ?? Response(status: 200, body: "[]")
        Self.lock.unlock()
        let http = HTTPURLResponse(
            url: request.url!, statusCode: response.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(response.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
