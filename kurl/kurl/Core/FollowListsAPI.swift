//
//  FollowListsAPI.swift
//  kurl
//

import Foundation

/// 작가의 팔로워 / 팔로잉 *목록* — 공개 읽기(카운트는 이미 /follow 로 공개였고, 여기선 누구를 연다).
/// 비로그인도 읽되 행별 followedByMe 는 false. 로그인 상태면 토큰을 붙여 내 팔로우 여부를 받는다.
enum FollowListsAPI {
    private static let client = APIClient.shared

    static func followers(username: String, page: Int = 0, size: Int = 20) async throws -> FollowListPage {
        let signedIn = await AuthStore.shared.isSignedIn
        return try await client.get(
            "/users/\(username)/followers",
            query: ["page": String(page), "size": String(size)],
            authenticated: signedIn)
    }

    static func following(username: String, page: Int = 0, size: Int = 20) async throws -> FollowListPage {
        let signedIn = await AuthStore.shared.isSignedIn
        return try await client.get(
            "/users/\(username)/following",
            query: ["page": String(page), "size": String(size)],
            authenticated: signedIn)
    }
}

/// 목록 한 행 — 작가 정보 + 행별 팔로워 수 + 내 팔로우 여부(팔로우 버튼 시드).
struct FollowUser: Decodable, Identifiable, Hashable {
    let id: Int64
    let username: String
    let bio: String?
    let avatarUrl: String?
    let followerCount: Int64
    let followedByMe: Bool

    /// AvatarView·라우팅이 쓰는 Author 로.
    var asAuthor: Author {
        Author(id: id, username: username, bio: bio, avatarUrl: avatarUrl)
    }
}

struct FollowListPage: Decodable {
    let items: [FollowUser]
    let page: Int
    let size: Int
    let hasNext: Bool
}
