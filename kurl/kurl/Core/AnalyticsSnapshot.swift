//
//  AnalyticsSnapshot.swift
//  kurl
//

import Foundation

/// 홈 위젯에 보여줄 분석 스냅샷. 위젯은 네트워크도 Keychain 도 만지지 않는다 —
/// 앱이 분석을 성공적으로 읽을 때마다 App Group defaults 에 남기고, 위젯은 그걸 그릴 뿐.
/// (위젯 프로세스에서 토큰 공유·리프레시 경쟁을 만들지 않기 위한 의도적 단방향 설계.)
struct AnalyticsSnapshot: Codable {
    let windowViews: Int64
    let windowDays: Int
    let lifetimeViews: Int64
    let lifetimeLikes: Int64
    let lifetimeFollows: Int64
    let publishedPosts: Int64
    /// 최근 일별 조회 — 위젯 미니 막대용 (마지막 14개만 저장).
    let dailyViews: [Int64]
    let updatedAt: Date

    static let appGroupId = "group.focustime.kurl"
    private static let key = "analytics-snapshot"

    static func save(from overview: AuthorAnalyticsOverview) {
        let snapshot = AnalyticsSnapshot(
            windowViews: overview.windowViews,
            windowDays: overview.windowDays,
            lifetimeViews: overview.lifetimeViews,
            lifetimeLikes: overview.lifetimeLikes,
            lifetimeFollows: overview.lifetimeFollows,
            publishedPosts: overview.publishedPosts,
            dailyViews: overview.daily.suffix(14).map(\.views),
            updatedAt: Date()
        )
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let data = try? JSONEncoder().encode(snapshot)
        else { return }
        defaults.set(data, forKey: key)
    }

    static func load() -> AnalyticsSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let data = defaults.data(forKey: key)
        else { return nil }
        return try? JSONDecoder().decode(AnalyticsSnapshot.self, from: data)
    }

    static func clear() {
        UserDefaults(suiteName: appGroupId)?.removeObject(forKey: key)
    }
}
