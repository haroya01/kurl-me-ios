//
//  NotificationsAPI.swift
//  kurl
//

import Foundation

/// 인앱 알림 — 좋아요·댓글·답글·팔로우·시리즈 구독·새 글·멘션, 그리고 연결 그래프
/// (내 글이 컬렉션에 엮임 · 내 글이 엮인 컬렉션에 새 글). 커서 페이지네이션(before).
enum NotificationFilter: Hashable {
    case all, mentions

    var queryValue: String? { self == .mentions ? "mentions" : nil }
}

enum NotificationsAPI {
    static var client = APIClient.shared

    static func list(
        before: Int64? = nil, limit: Int = 20, filter: NotificationFilter = .all
    ) async throws -> NotificationsPage {
        try await client.get(
            "/notifications",
            query: ["before": before.map(String.init), "limit": String(limit), "filter": filter.queryValue],
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

    /// 남은 안 읽은 수를 돌려준다 — 멘션만 읽으면 나머지가 남는다.
    @discardableResult
    static func markAllRead(filter: NotificationFilter = .all) async throws -> Int64 {
        struct Response: Decodable { let count: Int64 }
        let res: Response = try await client.postWithQuery(
            "/notifications/read-all", query: ["filter": filter.queryValue], authenticated: true)
        return res.count
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
    let commentId: Int64?
    let highlightId: Int64?
    let seriesId: Int64?
    let seriesSlug: String?
    let seriesTitle: String?
    /// 연결 그래프 알림(CONNECTED·PATH_GREW)의 딥링크 대상 = 컬렉션. 다른 종류에선 비어 온다.
    let collectionId: Int64?
    let collectionName: String?
    var read: Bool
    let createdAt: Date?
    /// 다른 서버 계정이면 그 서버의 프로필 — 보낸 사람 이름은 name@domain 핸들로 온다.
    var actorProfileUrl: String? = nil
    /// 다른 서버 계정의 이 서버 안 id — 앱 안 계정 화면과 요청 승인에 쓴다.
    var actorRemoteId: Int64? = nil
    /// 노트 알림 — 내 노트, 답글·인용이면 그 답글·인용 노트.
    var noteId: Int64? = nil
    var noteExcerpt: String? = nil
    var sourceNoteId: Int64? = nil
    var sourceExcerpt: String? = nil
    /// 같은 노트의 좋아요·리포스트는 날마다 묶여 온다 — 행은 가장 최근 것, count 는 묶음 크기.
    var count: Int? = nil
}
