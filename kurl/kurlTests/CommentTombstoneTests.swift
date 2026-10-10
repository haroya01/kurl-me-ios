//
//  CommentTombstoneTests.swift
//  kurlTests
//
//  답글이 남은 지운 댓글은 자리(`deleted: true`, 작성자·본문 null)로 온다 — 앱은 그 모양을 받겠다고(`tombstones=1`) 말하고
//  디코드에서 넘어지지 않아야 한다.
//

import XCTest

@testable import kurl

@MainActor
final class CommentTombstoneTests: XCTestCase {

    override func tearDown() async throws {
        BlogAPI.client = .shared
        RecordingServer.lastURL = nil
    }

    func testATombstoneDecodesWithoutAuthorOrBody() throws {
        let comments = try JSONDecoder.blog.decode([Comment].self, from: Data(#"""
            [{"id":1,"parentId":null,"author":null,"body":null,"createdAt":"2026-10-01T00:00:00Z",
              "likeCount":0,"mentions":[],"deleted":true},
             {"id":2,"parentId":1,"author":{"id":3,"username":"sori","bio":null,"avatarUrl":null},
              "body":"hi","createdAt":"2026-10-01T00:00:00Z","likeCount":2}]
            """#.utf8))
        XCTAssertTrue(comments[0].isDeleted)
        XCTAssertNil(comments[0].author)
        XCTAssertNil(comments[0].body)
        XCTAssertFalse(comments[1].isDeleted)
        XCTAssertEqual(comments[1].author?.username, "sori")
        XCTAssertEqual(comments[1].likeCount, 2)
    }

    func testCommentsAskForTombstones() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingServer.self]
        BlogAPI.client = APIClient(session: URLSession(configuration: config), viewerToken: { nil })

        let comments = try await BlogAPI.comments(postId: 42)

        XCTAssertTrue(comments.isEmpty)
        let url = try XCTUnwrap(RecordingServer.lastURL)
        XCTAssertTrue(url.path.hasSuffix("/public/posts/42/comments"), url.path)
        let tombstones = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "tombstones" }?.value
        XCTAssertEqual(tombstones, "1")
    }
}

private final class RecordingServer: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var lastURL: URL?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastURL = request.url
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("[]".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
