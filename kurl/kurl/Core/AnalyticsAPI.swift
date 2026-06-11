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
}

struct AuthorAnalyticsOverview: Decodable {
    let totalPosts: Int64
    let publishedPosts: Int64
    let lifetimeViews: Int64
    let lifetimeLikes: Int64
    let windowDays: Int
    let windowViews: Int64
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
