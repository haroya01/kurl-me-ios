//
//  BlogAPI.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import Foundation

/// 공개(비인증) 블로그 엔드포인트 모음.
enum BlogAPI {
    private static let client = APIClient.shared

    // MARK: 전역 피드 / 검색

    static func feed(
        sort: FeedSort = .recent,
        tag: String? = nil,
        query: String? = nil,
        page: Int = 0,
        size: Int = 20
    ) async throws -> PublicFeedView {
        try await client.get(
            "/public/posts",
            query: [
                "sort": sort.rawValue,
                "tag": tag,
                "q": query,
                "page": String(page),
                "size": String(size),
            ]
        )
    }

    // MARK: 발견

    static func trendingByTag(tagLimit: Int = 6, perTag: Int = 8) async throws -> [TrendingTagSection] {
        try await client.get(
            "/public/feed/trending-by-tag",
            query: ["tagLimit": String(tagLimit), "perTag": String(perTag)]
        )
    }

    static func popularTags(limit: Int = 50) async throws -> [TagCount] {
        try await client.get("/public/tags", query: ["limit": String(limit)])
    }

    static func suggestedAuthors(limit: Int = 5) async throws -> [SuggestedAuthor] {
        try await client.get("/public/authors", query: ["limit": String(limit)])
    }

    static func discoverSeries(limit: Int = 6) async throws -> [PublicSeriesCard] {
        try await client.get("/public/series", query: ["limit": String(limit)])
    }

    // MARK: 작가 블로그

    static func authorPosts(username: String) async throws -> PublicPostListView {
        try await client.get("/public/profiles/\(username)/posts")
    }

    static func authorSeries(username: String) async throws -> PublicSeriesListView {
        try await client.get("/public/profiles/\(username)/series")
    }

    static func seriesDetail(username: String, slug: String) async throws -> PublicSeriesDetail {
        try await client.get("/public/profiles/\(username)/series/\(slug)")
    }

    // MARK: 글 상세

    static func postDetail(username: String, slug: String) async throws -> PublicPostDetail {
        try await client.get("/public/profiles/\(username)/posts/\(slug)")
    }

    static func comments(postId: Int64) async throws -> [Comment] {
        try await client.get("/public/posts/\(postId)/comments")
    }

    /// 읽기 측정 비콘. 실패는 조용히 무시한다.
    static func recordView(username: String, slug: String, source: String? = "ios") async {
        try? await client.post(
            "/public/profiles/\(username)/posts/\(slug)/view",
            query: ["src": source]
        )
    }
}

enum FeedSort: String, CaseIterable, Identifiable {
    case recent
    case trending

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recent: return String(localized: "최신")
        case .trending: return String(localized: "인기")
        }
    }
}
