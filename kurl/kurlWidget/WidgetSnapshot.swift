//
//  WidgetSnapshot.swift
//  kurlWidget
//

import Foundation

/// 앱의 AnalyticsSnapshot 과 같은 JSON 을 읽는 위젯 쪽 미러 — App Group defaults 의
/// 키·필드명이 계약이다(앱 쪽 kurl/Core/AnalyticsSnapshot.swift 와 짝, 한쪽 바꾸면 같이).
/// 위젯은 네트워크·Keychain 을 만지지 않는다: 앱이 남긴 스냅샷만 그린다.
struct WidgetSnapshot: Codable {
    let windowViews: Int64
    let windowDays: Int
    let lifetimeViews: Int64
    let lifetimeLikes: Int64
    let lifetimeFollows: Int64
    let publishedPosts: Int64
    let dailyViews: [Int64]
    let updatedAt: Date

    static let appGroupId = "group.focustime.kurl"
    private static let key = "analytics-snapshot"

    static func load() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let data = defaults.data(forKey: key)
        else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// placeholder / 미리보기용.
    static let sample = WidgetSnapshot(
        windowViews: 1284,
        windowDays: 30,
        lifetimeViews: 5421,
        lifetimeLikes: 132,
        lifetimeFollows: 48,
        publishedPosts: 23,
        dailyViews: [12, 30, 18, 44, 25, 61, 38, 52, 47, 70, 33, 58, 64, 41],
        updatedAt: Date()
    )
}
