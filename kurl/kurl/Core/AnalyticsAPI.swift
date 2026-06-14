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

    /// 시리즈 하나의 상세 — 구독자 추이 + 회차별 완주 funnel(웹 시리즈 분석 patity).
    static func seriesDetail(seriesId: Int64, days: Int = 30) async throws -> SeriesAnalyticsDetail {
        try await client.get(
            "/posts/analytics/series/\(seriesId)",
            query: ["days": String(days)],
            authenticated: true
        )
    }

    /// 글 하나의 분석 — 수명 합계 + 윈도우 추이(글 facet).
    static func postAnalytics(postId: Int64, days: Int = 30) async throws -> PostAnalyticsDetail {
        try await client.get(
            "/posts/\(postId)/analytics",
            query: ["days": String(days)],
            authenticated: true
        )
    }

    /// 독자 분석 — 고유 방문·유입 채널·국가·기기(웹과 같은 PostReadStats).
    static func readStats(postId: Int64) async throws -> PostReadStats {
        try await client.get("/posts/\(postId)/stats", authenticated: true)
    }
}

/// GET /posts/{id}/stats — 독자 breakdown. 헤드라인 지표만 디코드(나머지 키는 무시).
struct PostReadStats: Decodable {
    let totalVisits: Int64
    let humanVisits: Int64
    let botVisits: Int64
    let uniqueVisits: Int64
    let countryVisits: [CountryVisit]
    let deviceVisits: [DeviceVisit]
    let sourceChannelVisits: [SourceChannelVisit]
    let referrerHostVisits: [ReferrerHostVisit]

    struct CountryVisit: Decodable, Identifiable { let country: String; let count: Int64; var id: String { country } }
    struct DeviceVisit: Decodable, Identifiable { let device: String; let count: Int64; var id: String { device } }
    struct SourceChannelVisit: Decodable, Identifiable { let source: String; let count: Int64; var id: String { source } }
    struct ReferrerHostVisit: Decodable, Identifiable { let host: String; let count: Int64; var id: String { host } }
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

struct SeriesAnalyticsRow: Decodable, Identifiable, Hashable {
    let seriesId: Int64
    let slug: String
    let title: String
    let postCount: Int64
    let subscriberCount: Int64
    let totalViews: Int64
    let totalLikes: Int64

    var id: Int64 { seriesId }
}

/// GET /posts/analytics/series/{id} — 구독자 추이 + 회차별 funnel.
struct SeriesAnalyticsDetail: Decodable {
    let series: SeriesAnalyticsRow
    let windowDays: Int
    /// 일별 누적 구독자(DailyPoint.views 가 구독자 수를 나른다).
    let subscriberDaily: [AuthorAnalyticsOverview.DailyPoint]
    let members: [SeriesMemberStat]
}

struct SeriesMemberStat: Decodable, Identifiable {
    let postId: Int64
    let slug: String
    let title: String
    let episode: Int
    let views: Int64
    let likes: Int64
    let follows: Int64
    /// 이 회차를 읽은 고유 독자.
    let uniqueReaders: Int64
    /// 이 회차 독자 중 다음 화도 읽은 수(마지막 화는 0).
    let continuedToNext: Int64

    var id: Int64 { postId }
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

        /// "yyyy-MM-dd" → Date(자정, Asia/Seoul). 날짜 축·스크럽 선택에 쓴다.
        var day: Date? { DailyPoint.parser.date(from: date) }
        private static let parser: DateFormatter = {
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "Asia/Seoul")
            f.dateFormat = "yyyy-MM-dd"
            return f
        }()
    }

    struct ReferrerPoint: Decodable, Identifiable {
        let host: String
        let views: Int64

        var id: String { host }
    }
}
