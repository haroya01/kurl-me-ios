//
//  NotificationPolicyAPI.swift
//  kurl
//

import Foundation

/// 마스토돈 알림 거르기 — 범주마다 받기·거르기·버리기. 거른 알림은 보낸 사람별로 따로 모인다.
struct NotificationPolicy: Codable, Equatable {
    enum Level: String, Codable, CaseIterable {
        case accept = "ACCEPT"
        case filter = "FILTER"
        case drop = "DROP"
    }

    var forNotFollowing: Level
    var forNotFollowers: Level
    var forNewAccounts: Level
    var forPrivateMentions: Level

    static let `default` = NotificationPolicy(
        forNotFollowing: .accept, forNotFollowers: .accept, forNewAccounts: .accept,
        forPrivateMentions: .filter)
}

/// 거른 알림을 보낸 사람 하나 — 이 서버 회원(actorUserId)이거나 다른 서버 계정(actorRemoteId).
struct FilteredSender: Decodable, Identifiable, Hashable {
    let actorUserId: Int64?
    let actorRemoteId: Int64?
    let username: String
    let avatarUrl: String?
    let profileUrl: String?
    let count: Int
    let lastAt: Date?

    var id: String { actorRemoteId.map { "remote:\($0)" } ?? "member:\(actorUserId ?? 0)" }

    var asAuthor: Author {
        Author(id: actorRemoteId.map { -$0 } ?? actorUserId ?? 0, username: username, bio: nil, avatarUrl: avatarUrl)
    }

    var route: Route? {
        if let actorRemoteId { return .remoteAccount(id: actorRemoteId) }
        return username.isEmpty ? nil : .author(username: username)
    }
}

enum NotificationPolicyAPI {
    private static let client = APIClient.shared

    private struct Sender: Encodable {
        let actorUserId: Int64?
        let actorRemoteId: Int64?
    }

    static func policy() async throws -> NotificationPolicy {
        try await client.get("/notifications/policy", authenticated: true)
    }

    static func update(_ policy: NotificationPolicy) async throws -> NotificationPolicy {
        try await client.put("/notifications/policy", body: policy, authenticated: true)
    }

    static func filtered() async throws -> [FilteredSender] {
        try await client.get("/notifications/requests", authenticated: true)
    }

    static func accept(_ sender: FilteredSender) async throws {
        try await client.post(
            "/notifications/requests/accept",
            body: Sender(actorUserId: sender.actorUserId, actorRemoteId: sender.actorRemoteId),
            authenticated: true)
    }

    static func dismiss(_ sender: FilteredSender) async throws {
        try await client.post(
            "/notifications/requests/dismiss",
            body: Sender(actorUserId: sender.actorUserId, actorRemoteId: sender.actorRemoteId),
            authenticated: true)
    }
}
