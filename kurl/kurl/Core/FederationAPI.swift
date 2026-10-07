//
//  FederationAPI.swift
//  kurl
//

import Foundation

struct RemoteAccount: Codable, Identifiable, Hashable {
    let id: Int64
    let acct: String
    let username: String
    let domain: String
    let displayName: String?
    let avatarUrl: String?
    let url: String
    var following: Bool
    var requested: Bool

    var shownName: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return username.isEmpty ? acct : username
    }

    var asAuthor: Author {
        Author(id: -id, username: acct, bio: nil, avatarUrl: avatarUrl)
    }
}

enum FederationAPI {
    private static let client = APIClient.shared

    private struct Empty: Encodable {}

    static func looksLikeHandle(_ text: String) -> Bool {
        let handle = #/@?[A-Za-z0-9_][A-Za-z0-9_.\-]{0,63}@[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)+(:[0-9]{1,5})?/#
        return text.trimmingCharacters(in: .whitespacesAndNewlines).wholeMatch(of: handle) != nil
    }

    static func lookup(_ handle: String) async throws -> RemoteAccount {
        try await client.get(
            "/federation/accounts/lookup",
            query: ["acct": handle.trimmingCharacters(in: .whitespacesAndNewlines)],
            authenticated: true)
    }

    static func account(id: Int64) async throws -> RemoteAccount {
        try await client.get("/federation/accounts/\(id)", authenticated: true)
    }

    static func setFollowing(_ on: Bool, id: Int64) async throws -> RemoteAccount {
        on
            ? try await client.post("/federation/accounts/\(id)/follow", body: Empty(), authenticated: true)
            : try await client.delete("/federation/accounts/\(id)/follow", authenticated: true)
    }

    static func following(page: Int = 0) async throws -> [RemoteAccount] {
        try await client.get(
            "/federation/following", query: ["page": String(page), "size": "30"], authenticated: true)
    }

    static func message(for error: Error) -> String {
        if case let APIError.server(_, code, _) = error {
            switch code {
            case "FEDERATION_DISABLED":
                return String(localized: "설정 > 노트 연합을 켜야 다른 서버 계정을 팔로우할 수 있어요")
            case "REMOTE_ACCOUNT_NOT_FOUND":
                return String(localized: "그 서버에서 계정을 찾지 못했어요")
            case "REMOTE_ACCOUNT_INVALID":
                return String(localized: "아이디@서버 모양으로 적어 주세요")
            default:
                break
            }
        }
        return String(localized: "연결을 확인하고 다시 시도해 주세요.")
    }
}
