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
        /// 작가가 팔로워 수를 숨기면 서버가 이 키를 빼고 내려준다 → 부재=nil(숫자 감춤).
        let followerCount: Int64?
        let followingCount: Int64?
        /// 숨김 의사 신호 — 카운트가 nil 인 이유가 "숨김"인지 "못 받음"인지 가른다.
        /// 아직 이 키를 안 내리는 서버(배포 전)를 위해 부재 시 false.
        let hideFollowerCount: Bool

        enum CodingKeys: String, CodingKey {
            case following, followerCount, followingCount, hideFollowerCount
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            following = try c.decodeIfPresent(Bool.self, forKey: .following) ?? false
            followerCount = try c.decodeIfPresent(Int64.self, forKey: .followerCount)
            followingCount = try c.decodeIfPresent(Int64.self, forKey: .followingCount)
            hideFollowerCount = try c.decodeIfPresent(Bool.self, forKey: .hideFollowerCount) ?? false
        }
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

    // MARK: 시리즈 구독

    struct SeriesSubscriptionStatus: Decodable {
        let subscribed: Bool
        let subscriberCount: Int64
    }

    /// 구독 표면은 전부 인증 필요 — 비로그인은 hydrate 하지 않는다.
    static func subscriptionStatus(seriesId: Int64) async throws -> SeriesSubscriptionStatus {
        try await client.get("/series/\(seriesId)/subscription", authenticated: true)
    }

    static func setSubscription(seriesId: Int64, on: Bool) async throws -> SeriesSubscriptionStatus {
        on
            ? try await client.put("/series/\(seriesId)/subscription", authenticated: true)
            : try await client.delete("/series/\(seriesId)/subscription", authenticated: true)
    }

    // MARK: 댓글

    /// 작성 후 목록은 공개 엔드포인트로 다시 읽는다 — 생성 응답 형태에 묶이지 않게.
    static func createComment(postId: Int64, body: String, parentId: Int64? = nil) async throws {
        struct Body: Encodable {
            let body: String
            let parentId: Int64?
        }
        try await client.post(
            "/posts/\(postId)/comments",
            body: Body(body: body, parentId: parentId), authenticated: true)
    }

    struct CommentLikeStatus: Decodable {
        let likeCount: Int64
        let liked: Bool
    }

    static func setCommentLike(commentId: Int64, on: Bool) async throws -> CommentLikeStatus {
        on
            ? try await client.post("/comments/\(commentId)/like", body: Empty(), authenticated: true)
            : try await client.delete("/comments/\(commentId)/like", authenticated: true)
    }

    /// 공개 댓글 목록은 비인증 — 보는 사람의 likedByMe 만 이 인증 엔드포인트가 따로 답한다(#538).
    static func likedCommentIds(postId: Int64) async throws -> [Int64] {
        try await client.get("/posts/\(postId)/comments/liked", authenticated: true)
    }

    static func deleteComment(commentId: Int64) async throws {
        try await client.deleteVoid("/comments/\(commentId)", authenticated: true)
    }

    // MARK: 태그 구독(팔로우)

    /// 내 태그 환경설정 — 구독(followed)/숨김(hidden) 태그 목록. 구독한 태그의 새 글이
    /// 구독함 피드로 들어온다(웹 parity). 전부 인증 필요.
    struct TagPrefs: Decodable {
        let followed: [String]
        let hidden: [String]
    }

    static func tagPrefs() async throws -> TagPrefs {
        try await client.get("/users/me/tag-prefs", authenticated: true)
    }

    /// 태그는 경로 변수 — 한글/특수문자는 URL 빌더(appendingPathComponent)가 인코딩한다.
    static func setTagFollow(tag: String, on: Bool) async throws -> TagPrefs {
        on
            ? try await client.put("/users/me/tag-prefs/followed/\(tag)", authenticated: true)
            : try await client.delete("/users/me/tag-prefs/followed/\(tag)", authenticated: true)
    }

    /// 태그 숨기기(mute) — 숨긴 태그의 글은 피드에서 빠진다(구독의 반대).
    static func setTagHidden(tag: String, on: Bool) async throws -> TagPrefs {
        on
            ? try await client.put("/users/me/tag-prefs/hidden/\(tag)", authenticated: true)
            : try await client.delete("/users/me/tag-prefs/hidden/\(tag)", authenticated: true)
    }

    // MARK: 신고(abuse report)

    /// 글·작가 신고 — `POST /public/abuse-reports`(202). subjectType = POST | USER.
    /// 익명 허용(permitAll) 이라 로그인 안 해도 보내되, 로그인 상태면 토큰을 붙인다.
    static func report(subjectType: String, subjectId: Int64, reason: String) async throws {
        struct Body: Encodable {
            let subjectType: String
            let subjectId: Int64
            let reason: String
        }
        let signedIn = await AuthStore.shared.isSignedIn
        try await client.post(
            "/public/abuse-reports",
            body: Body(subjectType: subjectType, subjectId: subjectId, reason: reason),
            authenticated: signedIn)
    }

    // MARK: 차단(block) — App Store 1.2(UGC). 차단하면 그 사용자의 글·댓글·노트를 더는 안 본다.

    struct BlockedUser: Decodable, Identifiable {
        let id: Int64
        let username: String
        let avatarUrl: String?
    }

    /// 작가 차단 — `PUT /users/{username}/block`(204, 멱등).
    static func block(username: String) async throws {
        try await client.putVoid("/users/\(username)/block", authenticated: true)
    }

    /// 차단 해제 — `DELETE /users/{username}/block`(204).
    static func unblock(username: String) async throws {
        try await client.deleteVoid("/users/\(username)/block", authenticated: true)
    }

    /// 내가 차단한 사용자 목록 — 관리 화면 + 클라이언트 콘텐츠 필터의 소스.
    static func listBlocked() async throws -> [BlockedUser] {
        try await client.get("/users/me/blocks", authenticated: true)
    }

    private struct Empty: Encodable {}
}
