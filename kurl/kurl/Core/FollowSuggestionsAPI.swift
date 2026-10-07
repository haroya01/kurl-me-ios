//
//  FollowSuggestionsAPI.swift
//  kurl
//

import Foundation

/// 마스토돈 팔로우 추천 — 내가 팔로우하는 사람들이 팔로우하는 계정, 없으면 요즘 활발한 인기 계정.
struct FollowSuggestion: Decodable, Identifiable, Hashable {
    enum Reason: String, Decodable {
        case friends = "FRIENDS"
        case popular = "POPULAR"
    }

    let username: String
    let displayName: String?
    let avatarUrl: String?
    let bio: String?
    let mutuals: Int
    let reason: Reason
    let locked: Bool?

    var id: String { username }

    var shownName: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return username
    }

    var asAuthor: Author { Author(id: 0, username: username, bio: bio, avatarUrl: avatarUrl) }

    /// 추천에 오른 사람은 아직 팔로우하지 않은 사람이다 — 버튼이 상태를 또 묻지 않게 시드한다.
    var followSeed: InteractionsAPI.FollowStatus {
        InteractionsAPI.FollowStatus(following: false, locked: locked ?? false)
    }
}

enum FollowSuggestionsAPI {
    private static let client = APIClient.shared

    static func suggestions(limit: Int = 10) async throws -> [FollowSuggestion] {
        try await client.get(
            "/users/me/suggestions", query: ["limit": String(limit)], authenticated: true)
    }

    static func dismiss(_ username: String) async throws {
        try await client.deleteVoid(
            "/users/me/suggestions/\(username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username)",
            authenticated: true)
    }
}
