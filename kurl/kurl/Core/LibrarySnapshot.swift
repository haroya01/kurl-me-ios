//
//  LibrarySnapshot.swift
//  kurl
//

import Foundation

/// 홈 위젯 "서재"에 보여줄 스냅샷. 위젯은 네트워크도 Keychain 도 만지지 않는다 —
/// 기기에 보장된 북마크 사본(OfflineStore)이 바뀔 때마다 App Group defaults 에 제목·작가만
/// 남기고, 위젯은 그걸 그릴 뿐(본문·커버 이미지는 넘기지 않는다: 용량·프라이버시).
/// AnalyticsSnapshot 과 같은 의도적 단방향 계약 — 위젯 프로세스에서 토큰 공유·리프레시
/// 경쟁을 만들지 않는다. 키·필드명이 위젯 쪽 미러와의 계약이다(한쪽 바꾸면 같이).
struct LibrarySnapshot: Codable, Sendable {
    /// 위젯 한 행 — 제목·작가·저장 시각만. savedAt 은 오프라인 사본 파일의 수정 시각(최근 저장 순).
    struct Item: Codable, Sendable, Hashable {
        let username: String
        let title: String
        let slug: String
        let savedAt: Date
    }

    /// 최근 저장 순으로 자른 목록(위젯이 훑을 만큼만).
    let items: [Item]
    /// 서재 전체 보관 수 — items 상한을 넘을 수 있어 위젯 카운터는 이 값을 쓴다.
    let totalCount: Int
    let updatedAt: Date

    static let appGroupId = "group.focustime.kurl"
    private static let key = "library-snapshot"
    /// 위젯에 실어 보낼 최대 개수 — 작은 위젯 회전 + 중간 위젯 목록에 넉넉한 상한.
    static let maxItems = 12

    static func save(items: [Item], totalCount: Int) {
        let snapshot = LibrarySnapshot(
            items: Array(items.prefix(maxItems)),
            totalCount: totalCount,
            updatedAt: Date())
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let data = try? JSONEncoder().encode(snapshot)
        else { return }
        defaults.set(data, forKey: key)
    }

    static func load() -> LibrarySnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let data = defaults.data(forKey: key)
        else { return nil }
        return try? JSONDecoder().decode(LibrarySnapshot.self, from: data)
    }

    static func clear() {
        UserDefaults(suiteName: appGroupId)?.removeObject(forKey: key)
    }
}
