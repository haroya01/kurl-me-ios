//
//  InteractionsAPI.swift
//  kurl
//

import Foundation

/// 인증 인터랙션 (좋아요·북마크·팔로우). 전부 멱등 PUT/DELETE 토글 — 낙관 UI 가
/// 중복 호출해도 서버 상태가 어긋나지 않는다. 응답이 곧 서버 기준 상태라
/// 토글 후 응답으로 로컬 상태를 한 번 더 맞춘다.
enum InteractionsAPI {
    private static let client = APIClient.shared

    struct LikeStatus: Decodable {
        let likeCount: Int64
        let liked: Bool
    }

    struct BookmarkStatus: Decodable {
        let bookmarked: Bool
    }

    struct FollowStatus: Decodable {
        let following: Bool
        let followerCount: Int64
        let followingCount: Int64
    }

    // MARK: 좋아요

    static func likeStatus(postId: Int64) async throws -> LikeStatus {
        try await client.get("/posts/\(postId)/like", authenticated: true)
    }

    static func setLike(postId: Int64, on: Bool) async throws -> LikeStatus {
        on
            ? try await client.put("/posts/\(postId)/like", authenticated: true)
            : try await client.delete("/posts/\(postId)/like", authenticated: true)
    }

    // MARK: 북마크

    static func bookmarkStatus(postId: Int64) async throws -> BookmarkStatus {
        try await client.get("/posts/\(postId)/bookmark", authenticated: true)
    }

    static func setBookmark(postId: Int64, on: Bool) async throws -> BookmarkStatus {
        on
            ? try await client.put("/posts/\(postId)/bookmark", authenticated: true)
            : try await client.delete("/posts/\(postId)/bookmark", authenticated: true)
    }

    // MARK: 팔로우

    /// GET 은 공개 — 비로그인이면 followerCount 만 의미 있고 following 은 항상 false.
    static func followStatus(username: String) async throws -> FollowStatus {
        let signedIn = await AuthStore.shared.isSignedIn
        return try await client.get("/users/\(username)/follow", authenticated: signedIn)
    }

    static func setFollow(username: String, on: Bool) async throws -> FollowStatus {
        on
            ? try await client.put("/users/\(username)/follow", authenticated: true)
            : try await client.delete("/users/\(username)/follow", authenticated: true)
    }
}
