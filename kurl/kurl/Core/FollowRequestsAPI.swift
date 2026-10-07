//
//  FollowRequestsAPI.swift
//  kurl
//

import Foundation

/// 잠긴 계정(마스토돈 locked)에 온 팔로우 요청 하나 — 이 서버 회원이거나 다른 서버 계정.
struct FollowRequest: Identifiable, Hashable {
    enum Origin: Hashable {
        case member(username: String)
        case remote(id: Int64)
    }

    let origin: Origin
    let handle: String
    let displayName: String?
    let avatarUrl: String?
    let requestedAt: Date?

    var id: String {
        switch origin {
        case let .member(username): "member:\(username)"
        case let .remote(id): "remote:\(id)"
        }
    }

    var shownName: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return handle
    }

    var asAuthor: Author {
        switch origin {
        case .member: Author(id: 0, username: handle, bio: nil, avatarUrl: avatarUrl)
        case let .remote(id): Author(id: -id, username: handle, bio: nil, avatarUrl: avatarUrl)
        }
    }

    var route: Route {
        switch origin {
        case let .member(username): .author(username: username)
        case let .remote(id): .remoteAccount(id: id)
        }
    }
}

enum FollowRequestsAPI {
    private static let client = APIClient.shared

    private struct Empty: Encodable {}

    private struct MemberRow: Decodable {
        let username: String
        let displayName: String?
        let avatarUrl: String?
        let requestedAt: Date?
    }

    private struct RemoteRow: Decodable {
        let id: Int64
        let acct: String
        let displayName: String?
        let avatarUrl: String?
        let requestedAt: Date?
    }

    /// 두 목록의 첫 쪽(각 40)을 함께 받아 요청 시각 최신순으로 섞는다.
    static func pending() async throws -> [FollowRequest] {
        async let members: [MemberRow] = client.get("/users/me/follow-requests", authenticated: true)
        async let remotes: [RemoteRow] = client.get("/federation/follow-requests", authenticated: true)
        let all =
            try await members.map {
                FollowRequest(
                    origin: .member(username: $0.username), handle: $0.username,
                    displayName: $0.displayName, avatarUrl: $0.avatarUrl, requestedAt: $0.requestedAt)
            }
            + remotes.map {
                FollowRequest(
                    origin: .remote(id: $0.id), handle: $0.acct, displayName: $0.displayName,
                    avatarUrl: $0.avatarUrl, requestedAt: $0.requestedAt)
            }
        return all.sorted { ($0.requestedAt ?? .distantPast) > ($1.requestedAt ?? .distantPast) }
    }

    static func authorize(_ origin: FollowRequest.Origin) async throws {
        try await client.post(path(origin) + "/authorize", body: Empty(), authenticated: true)
    }

    static func reject(_ origin: FollowRequest.Origin) async throws {
        try await client.post(path(origin) + "/reject", body: Empty(), authenticated: true)
    }

    private static func path(_ origin: FollowRequest.Origin) -> String {
        switch origin {
        case let .member(username):
            "/users/me/follow-requests/\(username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username)"
        case let .remote(id): "/federation/follow-requests/\(id)"
        }
    }
}
