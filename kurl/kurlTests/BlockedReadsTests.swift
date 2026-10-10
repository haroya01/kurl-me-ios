//
//  BlockedReadsTests.swift
//  kurlTests
//
//  차단 관계에서 서버가 비우거나 404 로 답한 글을 앱이 어떻게 보이는지 — 작가 페이지 자리, 글 상세와 기기 사본.
//

import XCTest

@testable import kurl

@MainActor
final class BlockedReadsTests: XCTestCase {

    private let username = "blocked-reads-writer"
    private let slug = "a-saved-post"

    override func tearDown() async throws {
        BlogAPI.client = .shared
        OfflineStore.shared.remove(username: username, slug: slug)
        StubbedServer.reply = .status(200)
    }

    // MARK: 작가 페이지

    private func authorPosts(_ flags: String) throws -> PublicPostListView {
        try JSONDecoder.blog.decode(
            PublicPostListView.self,
            from: Data(#"{"author":{"id":2,"username":"writer","bio":null,"avatarUrl":null},"posts":[]\#(flags)}"#.utf8))
    }

    func testABlockEitherWayTakesTheTabContentsPlace() throws {
        XCTAssertEqual(
            AuthorBlockGate.of(try authorPosts(#","blockedByViewer":true,"blocksViewer":false"#), blockedHere: false),
            .blockedByViewer)
        XCTAssertEqual(
            AuthorBlockGate.of(try authorPosts(#","blockedByViewer":false,"blocksViewer":true"#), blockedHere: false),
            .blocksViewer)
        XCTAssertEqual(
            AuthorBlockGate.of(try authorPosts(#","blockedByViewer":false,"blocksViewer":false"#), blockedHere: false),
            .open)
        XCTAssertEqual(AuthorBlockGate.of(try authorPosts(""), blockedHere: false), .open)
    }

    func testABlockMadeOnThisDeviceShowsBeforeTheServerSaysSo() throws {
        XCTAssertEqual(AuthorBlockGate.of(try authorPosts(""), blockedHere: true), .blockedByViewer)
        XCTAssertEqual(
            AuthorBlockGate.of(try authorPosts(#","blockedByViewer":false,"blocksViewer":true"#), blockedHere: true),
            .blockedByViewer)
    }

    // MARK: 글 상세와 기기 사본

    private func useServer(_ reply: StubbedServer.Reply) {
        StubbedServer.reply = reply
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubbedServer.self]
        BlogAPI.client = APIClient(session: URLSession(configuration: config), viewerToken: { nil })
    }

    private func saveOfflineCopy() async throws {
        let detail = #"""
        {"author":{"id":2,"username":"blocked-reads-writer","bio":null,"avatarUrl":null},
         "post":{"id":10,"slug":"a-saved-post","title":"Saved","excerpt":null,"ogImageUrl":null,
                 "languageTag":"ko","tags":[],"likeCount":0,"publishedAt":null,"lastEditedAt":null,"pinned":false},
         "blocks":[]}
        """#
        OfflineStore.shared.save(raw: Data(detail.utf8), username: username, slug: slug)
        for _ in 0..<100 where OfflineStore.shared.data(username: username, slug: slug) == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNotNil(OfflineStore.shared.data(username: username, slug: slug))
    }

    private func assertUnavailableAndCopyGone(_ model: PostDetailViewModel) {
        guard case .failed(let message) = model.phase else {
            return XCTFail("기대한 실패 상태가 아니다: \(model.phase)")
        }
        XCTAssertEqual(message, String(localized: "볼 수 없는 글이에요"))
        XCTAssertFalse(model.isOfflineCopy)
        XCTAssertFalse(OfflineStore.shared.contains(username: username, slug: slug))
    }

    func testAPostTheServerNoLongerShowsIsUnavailableAndItsSavedCopyIsDeleted() async throws {
        try await saveOfflineCopy()
        useServer(.status(404))

        let model = PostDetailViewModel(username: username, slug: slug, recordsView: false)
        await model.load()

        assertUnavailableAndCopyGone(model)
    }

    func testAGonePostIsUnavailableAndItsSavedCopyIsDeletedToo() async throws {
        try await saveOfflineCopy()
        useServer(.status(410))

        let model = PostDetailViewModel(username: username, slug: slug, recordsView: false)
        await model.load()

        assertUnavailableAndCopyGone(model)
    }

    func testWithoutAConnectionTheSavedCopyStillOpens() async throws {
        try await saveOfflineCopy()
        useServer(.offline)

        let model = PostDetailViewModel(username: username, slug: slug, recordsView: false)
        await model.load()

        guard case .loaded(let detail) = model.phase else {
            return XCTFail("기기 사본을 띄우지 않았다: \(model.phase)")
        }
        XCTAssertEqual(detail.post.slug, slug)
        XCTAssertTrue(model.isOfflineCopy)
        XCTAssertTrue(OfflineStore.shared.contains(username: username, slug: slug))
    }
}

/// 정해 둔 상태 코드로 답하거나, 연결이 없는 것처럼 실패한다(네트워크 없이).
private final class StubbedServer: URLProtocol, @unchecked Sendable {
    enum Reply {
        case status(Int)
        case offline
    }

    nonisolated(unsafe) static var reply: Reply = .status(200)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        switch Self.reply {
        case .offline:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        case .status(let code):
            let response = HTTPURLResponse(
                url: request.url!, statusCode: code, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/problem+json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(
                self, didLoad: Data(#"{"status":\#(code),"code":"POST_NOT_FOUND","detail":"post not found"}"#.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
