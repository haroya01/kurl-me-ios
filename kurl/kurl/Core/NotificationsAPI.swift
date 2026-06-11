//
//  NotificationsAPI.swift
//  kurl
//

import Foundation

/// 인앱 알림 — 좋아요·댓글·답글·팔로우·시리즈 구독·새 글·멘션. 커서 페이지네이션(before).
enum NotificationsAPI {
    private static let client = APIClient.shared

    static func list(before: Int64? = nil, limit: Int = 20) async throws -> NotificationsPage {
        try await client.get(
            "/notifications",
            query: ["before": before.map(String.init), "limit": String(limit)],
            authenticated: true
        )
    }

    static func unreadCount() async throws -> Int64 {
        struct Response: Decodable { let count: Int64 }
        let res: Response = try await client.get("/notifications/unread-count", authenticated: true)
        return res.count
    }

    static func markRead(id: Int64) async throws {
        struct Empty: Encodable {}
        try await client.post("/notifications/\(id)/read", body: Empty(), authenticated: true)
    }

    static func markAllRead() async throws {
        struct Empty: Encodable {}
        try await client.post("/notifications/read-all", body: Empty(), authenticated: true)
    }
}

struct NotificationsPage: Decodable {
    let items: [AppNotification]
    let nextCursor: Int64?
    let hasMore: Bool
}

struct AppNotification: Decodable, Identifiable {
    let id: Int64
    let type: String
    let actorUsername: String?
    let actorAvatarUrl: String?
    let postId: Int64?
    let postSlug: String?
    let postTitle: String?
    let postAuthorUsername: String?
    let seriesId: Int64?
    let seriesSlug: String?
    let seriesTitle: String?
    let read: Bool
    let createdAt: Date?
}
