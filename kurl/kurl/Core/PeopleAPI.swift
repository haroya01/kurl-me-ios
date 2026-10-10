//
//  PeopleAPI.swift
//  kurl
//

import Foundation

struct PersonMatch: Decodable, Identifiable, Hashable {
    let username: String
    let displayName: String?
    let avatarUrl: String?
    let bio: String?
    /// 숨긴 사람은 비어 온다.
    let followerCount: Int64?
    let following: Bool
    let requested: Bool

    var id: String { username }

    var shownName: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return username
    }

    var asAuthor: Author { Author(id: 0, username: username, bio: bio, avatarUrl: avatarUrl) }

    var followSeed: InteractionsAPI.FollowStatus {
        InteractionsAPI.FollowStatus(following: following, requested: requested, locked: requested)
    }
}

struct PeoplePage: Decodable {
    let items: [PersonMatch]
    let page: Int
    let size: Int
    let hasNext: Bool
}

enum PeopleAPI {
    static var client = APIClient.shared

    static let minQuery = 2
    private static let maxQuery = 30

    /// 서버와 같은 읽기 — 앞뒤 공백을 떼고 맨 앞 @ 하나를 떼고 30자에서 자른다.
    static func normalized(_ raw: String) -> String {
        var q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.hasPrefix("@") { q = String(q.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines) }
        return String(q.prefix(maxQuery))
    }

    static func isSearchable(_ raw: String) -> Bool {
        normalized(raw).count >= minQuery
    }

    static func search(_ raw: String, page: Int = 0, size: Int = 20) async throws -> PeoplePage {
        let q = normalized(raw)
        guard q.count >= minQuery else { return PeoplePage(items: [], page: page, size: size, hasNext: false) }
        return try await client.getAsViewer(
            "/public/users/search",
            query: ["q": q, "page": String(page), "size": String(size)])
    }
}
