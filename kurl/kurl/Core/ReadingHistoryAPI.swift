//
//  ReadingHistoryAPI.swift
//  kurl
//

import Foundation

/// 읽기 기록 — 로그인 독자가 발행 글을 읽으면 서버에 남고 기기를 넘어 이어진다(Medium식).
/// 익명 뷰 비콘과 별개의 사적 기록이라 전부 인증. 비콘은 실패해도 읽기를 끊지 않는다.
enum ReadingHistoryAPI {
    private static let client = APIClient.shared

    /// 읽음 비콘 — 글을 열면 한 번. 다시 열면 read_at 만 갱신돼 최신으로 떠오른다.
    static func record(postId: Int64) async {
        try? await client.post("/posts/\(postId)/read", body: Empty(), authenticated: true)
    }

    static func list(page: Int = 0, size: Int = 20) async throws -> ReadingHistoryPage {
        try await client.get(
            "/users/me/reading-history",
            query: ["page": String(page), "size": String(size)],
            authenticated: true)
    }

    /// 전체 기록 지우기.
    static func clear() async throws {
        try await client.deleteVoid("/users/me/reading-history", authenticated: true)
    }

    /// 한 건 잊기.
    static func forget(postId: Int64) async throws {
        try await client.deleteVoid("/users/me/reading-history/\(postId)", authenticated: true)
    }

    private struct Empty: Encodable {}
}

/// 읽기 기록 한 행 — 글 + 작가 + 마지막으로 읽은 시각.
struct ReadingHistoryEntry: Decodable, Identifiable, Hashable {
    let postId: Int64
    let username: String
    let avatarUrl: String?
    let title: String
    let slug: String
    let excerpt: String?
    let ogImageUrl: String?
    let readAt: Date?

    var id: Int64 { postId }

    /// AvatarView 가 쓰는 Author 로(이름·아바타만).
    var asAuthor: Author {
        Author(id: 0, username: username, bio: nil, avatarUrl: avatarUrl)
    }
}

struct ReadingHistoryPage: Decodable {
    let items: [ReadingHistoryEntry]
    let page: Int
    let size: Int
    let hasNext: Bool
}
