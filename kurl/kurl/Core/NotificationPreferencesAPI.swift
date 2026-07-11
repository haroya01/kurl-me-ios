//
//  NotificationPreferencesAPI.swift
//  kurl
//

import Foundation

/// 알림 종류별 켬/끔 — 웹과 같은 계약(GET 은 7타입 맵, PUT 은 한 타입씩).
/// 서버에 기록이 없으면 기본 켜짐(true)으로 온다.
enum NotificationPreferencesAPI {
    private static let client = APIClient.shared

    /// 7타입 전부의 현재 상태. 서버가 일부만 보내도 빠진 타입은 기본 켜짐으로 채운다.
    static func load() async throws -> [NotificationKind: Bool] {
        let raw: [String: Bool] = try await client.get(
            "/notifications/blog-preferences", authenticated: true)
        var result: [NotificationKind: Bool] = [:]
        for kind in NotificationKind.allCases {
            result[kind] = raw[kind.rawValue] ?? true
        }
        return result
    }

    /// 한 타입의 켬/끔을 저장(204). 낙관적 UI 뒤에서 확정하는 자리.
    static func update(_ kind: NotificationKind, enabled: Bool) async throws {
        struct Body: Encodable {
            let type: String
            let enabled: Bool
        }
        try await client.putVoid(
            "/notifications/blog-preferences",
            body: Body(type: kind.rawValue, enabled: enabled),
            authenticated: true)
    }
}

/// 뮤트 가능한 알림 종류 — 인앱 알림 벨과 같은 어휘(NotificationsAPI 의 type 문자열과 동일).
/// 순서 = 화면에 서는 순서(사람 행동 → 시스템 발행). 라벨·아이콘은 화면 레이어의 확장으로
/// 나눠 둔다 — 이 파일은 계약(rawValue)만 안다(Foundation only).
enum NotificationKind: String, CaseIterable, Identifiable {
    case like = "LIKE"
    case comment = "COMMENT"
    case reply = "REPLY"
    case mention = "MENTION"
    case follow = "FOLLOW"
    case seriesSubscribe = "SERIES_SUBSCRIBE"
    case newPost = "NEW_POST"

    var id: String { rawValue }
}
