//
//  DiscoveryViewerTokenTests.swift
//  kurlTests
//
//  블로그 발견 경로 — 로그인했으면 공개 요청에도 토큰을 실어 서버가 차단·뮤트한 작가를 거르게 하고,
//  로그아웃이면 익명 그대로. 공개 경로는 만료 토큰을 401 없이 익명으로 받으므로 만료 직전이면 먼저 리프레시한다.
//

import XCTest

@testable import kurl

@MainActor
final class DiscoveryViewerTokenTests: XCTestCase {

    override func tearDown() async throws {
        BlogAPI.client = .shared
        CapturingProtocol.reset()
    }

    private func client(token: String?) -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CapturingProtocol.self]
        return APIClient(session: URLSession(configuration: config), viewerToken: { token })
    }

    private func callEveryDiscoveryPath() async throws {
        _ = try await BlogAPI.feed(sort: .recent)
        _ = try await BlogAPI.feed(sort: .trending)
        _ = try await BlogAPI.feed(sort: .trending, tag: "swift")
        _ = try await BlogAPI.feed(query: "kurl")
        _ = try await BlogAPI.suggestedAuthors()
        _ = try await BlogAPI.discoverSeries()
        _ = try await BlogAPI.trendingByTag()
    }

    func testDiscoveryRequestsCarryTheSignedInViewerToken() async throws {
        BlogAPI.client = client(token: "viewer-token")
        try await callEveryDiscoveryPath()

        let requests = CapturingProtocol.requests
        XCTAssertEqual(requests.count, 7)
        for request in requests {
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"), "Bearer viewer-token",
                request.url?.absoluteString ?? "")
        }
        let tagged = requests.first { $0.url?.query?.contains("tag=swift") == true }
        XCTAssertEqual(tagged?.url?.query?.contains("sort=trending"), true, "태그 인기순은 서버 sort=trending 으로 묻는다")
    }

    func testDiscoveryRequestsStayAnonymousWhenSignedOut() async throws {
        BlogAPI.client = client(token: nil)
        try await callEveryDiscoveryPath()

        let requests = CapturingProtocol.requests
        XCTAssertEqual(requests.count, 7)
        for request in requests {
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"), request.url?.absoluteString ?? "")
        }
    }

    // MARK: 만료 판정

    private func jwt(payload: String) -> String {
        func encode(_ json: String) -> String {
            Data(json.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return encode(#"{"alg":"HS256"}"#) + "." + encode(payload) + ".signature"
    }

    private func jwt(exp: TimeInterval) -> String {
        jwt(payload: #"{"sub":"1","exp":\#(Int(exp))}"#)
    }

    func testFreshAccessTokenIsSentAsIs() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        XCTAssertFalse(AuthStore.accessTokenExpires(jwt(exp: now.timeIntervalSince1970 + 600), within: 30, now: now))
    }

    func testExpiredOrNearlyExpiredAccessTokenNeedsRefreshFirst() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        XCTAssertTrue(AuthStore.accessTokenExpires(jwt(exp: now.timeIntervalSince1970 - 1), within: 30, now: now))
        XCTAssertTrue(AuthStore.accessTokenExpires(jwt(exp: now.timeIntervalSince1970 + 10), within: 30, now: now))
    }

    func testTokenThatIsNotAReadableJWTIsLeftAlone() {
        XCTAssertFalse(AuthStore.accessTokenExpires("opaque-token", within: 30))
        XCTAssertFalse(AuthStore.accessTokenExpires("a.%%%.c", within: 30))
        XCTAssertFalse(AuthStore.accessTokenExpires(jwt(payload: #"{"sub":"1","iat":0}"#), within: 30))
    }
}

/// 나가는 요청을 기록하고 경로에 맞는 빈 응답을 돌려준다(네트워크 없이).
private final class CapturingProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var captured: [URLRequest] = []
    private static let lock = NSLock()

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }

    static func reset() {
        lock.lock()
        captured = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.captured.append(request)
        Self.lock.unlock()
        let body = request.url?.path.hasSuffix("/public/posts") == true
            ? #"{"items":[],"page":0,"size":0,"hasNext":false}"#
            : "[]"
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
