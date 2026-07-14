//
//  AnalyticsSnapshot.swift
//  kurl
//

import Foundation
import WidgetKit

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
        // 갱신을 위젯에 바로 알린다 — 이게 없으면 위젯은 다음 시간 틱까지 옛 그림을 든다.
        WidgetCenter.shared.reloadTimelines(ofKind: "AnalyticsWidget")
    }

    /// 앱이 열릴 때 위젯 몫의 분석을 조용히 당겨 온다 — 분석 화면을 열어야만 위젯이 채워지던
    /// 구조가 "위젯이 안 돈다"의 뿌리였다. 마지막 스냅샷이 충분히 새것이면(45분) 네트워크를
    /// 타지 않고, 실패는 조용히 넘어간다 — 위젯은 어시스트라 본 흐름을 방해하면 안 된다.
    @MainActor
    static func refreshIfStale(maxAge: TimeInterval = 45 * 60) async {
        guard AuthStore.shared.isSignedIn else { return }
        if let existing = load(), Date().timeIntervalSince(existing.updatedAt) < maxAge { return }
        guard let overview = try? await AnalyticsAPI.overview(days: 30) else { return }
        save(from: overview)
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
