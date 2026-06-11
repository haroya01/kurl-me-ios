//
//  LibraryAPI.swift
//  kurl
//

import Foundation

/// 내 서재 — 행동(좋아요·북마크·구독·팔로우)의 "모아 보기" 면. 전부 인증.
enum LibraryAPI {
    private static let client = APIClient.shared

    static func bookmarks() async throws -> [BookmarkItem] {
        try await client.get("/bookmarks", authenticated: true)
    }

    static func likedPosts() async throws -> [FeedItem] {
        try await client.get("/users/me/likes", authenticated: true)
    }

    static func subscribedSeries() async throws -> [PublicSeriesCard] {
        try await client.get("/users/me/subscribed-series", authenticated: true)
    }

    /// 팔로우한 작가·주제·구독 시리즈의 글이 모이는 피드.
    static func followingFeed(page: Int = 0, size: Int = 20) async throws -> PublicFeedView {
        try await client.get(
            "/feed/following",
            query: ["page": String(page), "size": String(size)],
            authenticated: true
        )
    }
}

struct BookmarkItem: Decodable, Identifiable {
    let id: Int64
    let username: String
    let title: String
    let slug: String
}
