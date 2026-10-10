//
//  BlogAPI.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import Foundation

/// 공개 블로그 엔드포인트 모음. 발견 경로(전역·태그·검색 피드, 추천 작가, 시리즈 발견, 주제별 인기)는
/// 로그인했으면 토큰을 실어 서버가 차단·뮤트한 작가를 거르게 한다.
enum BlogAPI {
    static var client = APIClient.shared

    // MARK: 전역 피드 / 검색

    static func feed(
        sort: FeedSort = .recent,
        tag: String? = nil,
        query: String? = nil,
        page: Int = 0,
        size: Int = 20
    ) async throws -> PublicFeedView {
        try await client.getAsViewer(
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
        try await client.getAsViewer(
            "/public/feed/trending-by-tag",
            query: ["tagLimit": String(tagLimit), "perTag": String(perTag)]
        )
    }

    static func popularTags(limit: Int = 50) async throws -> [TagCount] {
        try await client.get("/public/tags", query: ["limit": String(limit)])
    }

    static func suggestedAuthors(limit: Int = 5) async throws -> [SuggestedAuthor] {
        try await client.getAsViewer("/public/authors", query: ["limit": String(limit)])
    }

    static func discoverSeries(limit: Int = 6) async throws -> [PublicSeriesCard] {
        try await client.getAsViewer("/public/series", query: ["limit": String(limit)])
    }

    // MARK: 작가 블로그

    static func authorPosts(username: String) async throws -> PublicPostListView {
        try await client.getAsViewer("/public/profiles/\(username)/posts")
    }

    static func authorSeries(username: String) async throws -> PublicSeriesListView {
        try await client.get("/public/profiles/\(username)/series")
    }

    static func seriesDetail(username: String, slug: String) async throws -> PublicSeriesDetail {
        try await client.get("/public/profiles/\(username)/series/\(slug)")
    }

    // MARK: 글 상세

    static func postDetail(username: String, slug: String) async throws -> PublicPostDetail {
        try await client.getAsViewer("/public/profiles/\(username)/posts/\(slug)")
    }

    /// 상세 응답 원문 — 오프라인 저장소가 서버 바이트를 그대로 보관·재생하기 위한 경로.
    static func postDetailData(username: String, slug: String) async throws -> Data {
        try await client.getDataAsViewer("/public/profiles/\(username)/posts/\(slug)")
    }

    static func comments(postId: Int64) async throws -> [Comment] {
        try await client.getAsViewer("/public/posts/\(postId)/comments")
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
