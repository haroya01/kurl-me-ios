//
//  FeedThumbnailTests.swift
//  kurlTests
//
//  피드 행 썸네일은 작성자가 고른 표지만(서버 #817) — 행은 ogImageUrl 이 아니라 thumbnailUrl 을 그리고,
//  표지 저장은 작성자가 고른 것인지(coverChosen)를 함께 보낸다. 본문 첫 이미지 자동 채움은 false.
//

import SwiftUI
import XCTest

@testable import kurl

@MainActor
final class FeedThumbnailTests: XCTestCase {

    override func setUp() async throws {
        ScriptedServer.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedServer.self]
        WriteAPI.client = APIClient(session: URLSession(configuration: config), viewerToken: { nil })
    }

    override func tearDown() async throws {
        WriteAPI.client = .shared
        ScriptedServer.reset()
    }

    private func item(og: String?, thumbnail: String?) -> FeedItem {
        FeedItem(
            id: 7,
            author: Author(id: 1, username: "eunseong", bio: nil, avatarUrl: nil),
            slug: "draft-j2kile9",
            title: "K-means clustering accelerator 설계 (3)",
            excerpt: "DATA_IO module은 BRAM에서 데이터를 받아온다.",
            ogImageUrl: og,
            thumbnailUrl: thumbnail,
            languageTag: "ko",
            tags: [],
            publishedAt: nil,
            viewCount: 0,
            likeCount: 0)
    }

    private func pixels(_ item: FeedItem) throws -> Data {
        let row = FeedRow(item: item)
            .frame(width: 362)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: row)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        return try XCTUnwrap(image.dataProvider?.data as Data?)
    }

    func testARowLeavesOutACoverTheAuthorDidNotChoose() throws {
        let bare = try pixels(item(og: nil, thumbnail: nil))
        let filledIn = try pixels(item(og: "https://example.invalid/code.png", thumbnail: nil))
        let chosen = try pixels(
            item(og: "https://example.invalid/photo.png", thumbnail: "https://example.invalid/photo.png"))

        XCTAssertEqual(filledIn, bare, "자동으로 채운 표지는 행에 자리를 차지하지 않는다")
        XCTAssertNotEqual(chosen, bare, "고른 표지는 썸네일 자리를 차지한다")
    }

    func testAnOlderServerWithoutTheFieldGivesNoThumbnail() throws {
        let json = #"""
            {"id":7,"author":{"id":1,"username":"a","bio":null,"avatarUrl":null},"slug":"s","title":"t",
             "excerpt":null,"ogImageUrl":"https://cdn/a.png","languageTag":"ko","tags":[],
             "publishedAt":null,"viewCount":0,"likeCount":0}
            """#
        let decoded = try JSONDecoder.blog.decode(FeedItem.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.ogImageUrl, "https://cdn/a.png")
        XCTAssertNil(decoded.thumbnailUrl)
    }

    func testCoverSavesSayWhetherTheAuthorChoseIt() async throws {
        let post = #"{"id":7,"slug":"p-7","title":"제목","status":"DRAFT","tags":[]}"#
        ScriptedServer.script("PATCH /posts/7", 200, post)
        ScriptedServer.script("PATCH /posts/7", 200, post)

        try await PostSave.cover(
            postId: 7, url: "https://img/body.jpg", key: "b", chosen: false, gate: PostVersionGate())
        try await PostSave.cover(
            postId: 7, url: "https://img/picked.jpg", key: "p", chosen: true, gate: PostVersionGate())

        XCTAssertEqual(ScriptedServer.requests.map { $0.json["coverChosen"] as? Bool }, [false, true])
    }
}
