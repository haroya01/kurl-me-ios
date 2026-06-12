//
//  AnalyticsAPI.swift
//  kurl
//

import Foundation

/// 작가 분석 — 전체 합계 + 윈도우(기본 30일) 추이 + 유입 경로. 전부 인증 필요.
enum AnalyticsAPI {
    private static let client = APIClient.shared

    static func overview(days: Int = 30) async throws -> AuthorAnalyticsOverview {
        try await client.get(
            "/posts/analytics/overview",
            query: ["days": String(days)],
            authenticated: true
        )
    }

    /// 글별 성과 테이블 — sort: views|likes|recent.
    static func postPerformance(sort: String = "views", page: Int = 0, size: Int = 10)
        async throws -> PostPerformanceResult
    {
        try await client.get(
            "/posts/analytics/posts",
            query: ["sort": sort, "page": String(page), "size": String(size)],
            authenticated: true
        )
    }

    static func seriesAnalytics() async throws -> [SeriesAnalyticsRow] {
        try await client.get("/posts/analytics/series", authenticated: true)
    }

    /// 글 하나의 분석 — 수명 합계 + 윈도우 추이(글 facet).
    static func postAnalytics(postId: Int64, days: Int = 30) async throws -> PostAnalyticsDetail {
        try await client.get(
            "/posts/\(postId)/analytics",
            query: ["days": String(days)],
            authenticated: true
        )
    }
}

/// GET /posts/{id}/analytics — linkBreakdown 은 아직 안 쓴다(미디코딩 키는 무시됨).
struct PostAnalyticsDetail: Decodable {
    let postId: Int64
    let slug: String
    let title: String
    let status: String
    let lifetimeViews: Int64
    let lifetimeLikes: Int64
    let windowDays: Int
    let windowViews: Int64
    let lifetimeLinkClicks: Int64
    let windowLinkClicks: Int64
    let lifetimeFollows: Int64
    let windowFollows: Int64
    let daily: [AuthorAnalyticsOverview.DailyPoint]
}

struct PostPerformanceResult: Decodable {
    let items: [TopPostView]
    let page: Int
    let hasNext: Bool
}

struct TopPostView: Decodable, Identifiable, Hashable {
    let postId: Int64
    let slug: String
    let title: String
    let viewCount: Int64
    let likeCount: Int64
    let followsGained: Int64

    var id: Int64 { postId }
}

struct SeriesAnalyticsRow: Decodable, Identifiable {
    let seriesId: Int64
    let slug: String
    let title: String
    let postCount: Int64
    let subscriberCount: Int64
    let totalViews: Int64
    let totalLikes: Int64

    var id: Int64 { seriesId }
}

struct AuthorAnalyticsOverview: Decodable {
    let totalPosts: Int64
    let publishedPosts: Int64
    let lifetimeViews: Int64
    let lifetimeLikes: Int64
    let windowDays: Int
    let windowViews: Int64
    let lifetimeLinkClicks: Int64
    let windowLinkClicks: Int64
    let lifetimeFollows: Int64
    let windowFollows: Int64
    let daily: [DailyPoint]
    let referrers: [ReferrerPoint]

    /// LocalDate("yyyy-MM-dd") — 앱의 ISO datetime 디코더와 형식이 달라 문자열로 받는다.
    struct DailyPoint: Decodable, Identifiable {
        let date: String
        let views: Int64

        var id: String { date }
        /// "06-11" → 차트 축 라벨용 일(day) 숫자.
        var dayLabel: String { String(date.suffix(2)) }
    }

    struct ReferrerPoint: Decodable, Identifiable {
        let host: String
        let views: Int64

        var id: String { host }
    }
}
