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
    var domainBlocked: Bool?

    var isDomainBlocked: Bool { domainBlocked ?? false }

    var shownName: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return username.isEmpty ? acct : username
    }

    var asAuthor: Author {
        Author(id: -id, username: acct, bio: nil, avatarUrl: avatarUrl)
    }
}

struct DomainBlock: Decodable, Identifiable, Hashable {
    let domain: String
    let createdAt: Date?

    var id: String { domain }
}

/// 운영자의 서버 차단(마스토돈 관리자 도메인 차단) — 제한은 발견(인기·태그)에서 빼고, 정지는 끊는다.
struct ServerBlock: Decodable, Identifiable, Hashable {
    enum Severity: String, Codable, CaseIterable {
        case limit = "LIMIT"
        case suspend = "SUSPEND"
    }

    let domain: String
    let severity: Severity
    let reason: String?
    let createdAt: Date?

    var id: String { domain }
}

struct RemoteAccountSearchPage: Decodable {
    let items: [RemoteAccount]
}

struct RemoteResolveBody: Decodable {
    let account: RemoteAccount?
    let note: Note?
}

enum RemoteResolution: Equatable {
    case account(RemoteAccount)
    case note(Note)
    case missing(domain: String)
    case unreachable(domain: String)
    case signIn
    case hidden
}

enum FederationAPI {
    static var client = APIClient.shared

    static let remoteSearchLimit = 5
    static let remoteSearchMinQuery = 2
    static let resolveTimeout: TimeInterval = 20

    private struct Empty: Encodable {}

    static func looksLikeHandle(_ text: String) -> Bool {
        let handle = #/@?[A-Za-z0-9_][A-Za-z0-9_.\-]{0,63}@[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)+(:[0-9]{1,5})?/#
        return text.trimmingCharacters(in: .whitespacesAndNewlines).wholeMatch(of: handle) != nil
    }

    static func queryDomain(_ text: String) -> String? {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if looksLikeHandle(query), let at = query.lastIndex(of: "@") {
            return query[query.index(after: at)...].lowercased()
        }
        guard query.lowercased().hasPrefix("https://"), !query.contains(where: \.isWhitespace),
              let host = URL(string: query)?.host(), host.contains(".")
        else { return nil }
        return host.lowercased()
    }

    static func remoteSearchQuery(_ raw: String) -> String {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.hasPrefix("@") else { return query }
        return String(query.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func searchAccounts(_ raw: String) async -> [RemoteAccount]? {
        let query = remoteSearchQuery(raw)
        guard query.count >= remoteSearchMinQuery else { return [] }
        do {
            let page: RemoteAccountSearchPage = try await client.get(
                "/federation/accounts/search",
                query: ["q": query, "limit": String(remoteSearchLimit)],
                authenticated: AuthStore.shared.isSignedIn)
            return page.items.filter { !$0.isDomainBlocked }
        } catch {
            return nil
        }
    }

    static func resolve(_ raw: String) async -> RemoteResolution {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let domain = queryDomain(query) else { return .hidden }
        do {
            let body: RemoteResolveBody = try await client.get(
                "/federation/resolve", query: ["q": query], authenticated: true, timeout: resolveTimeout)
            if let note = body.note { return .note(note) }
            if let account = body.account { return .account(account) }
            return .missing(domain: domain)
        } catch {
            guard isRouteMissing(error) else { return resolution(for: error, domain: domain) }
            guard looksLikeHandle(query) else { return .hidden }
            do {
                return .account(try await lookup(query))
            } catch {
                return resolution(for: error, domain: domain)
            }
        }
    }

    static func isRouteMissing(_ error: Error) -> Bool {
        switch error {
        case APIError.http(404): return true
        case APIError.server(404, let code, _): return code == nil || code == "NOT_FOUND"
        default: return false
        }
    }

    static func needsSignIn(_ error: Error) -> Bool {
        switch error {
        case AuthError.notSignedIn, APIError.http(401), APIError.server(401, _, _): return true
        default: return false
        }
    }

    static func resolution(for error: Error, domain: String) -> RemoteResolution {
        if needsSignIn(error) { return .signIn }
        switch error {
        case APIError.server(_, "REMOTE_ACCOUNT_NOT_FOUND", _), APIError.server(_, "REMOTE_ACCOUNT_INVALID", _):
            return .missing(domain: domain)
        case APIError.server(_, "REMOTE_SERVER_UNREACHABLE", _):
            return .unreachable(domain: domain)
        case APIError.transport(let underlying) where (underlying as? URLError)?.code == .timedOut:
            return .unreachable(domain: domain)
        default:
            return .hidden
        }
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

    static func domainBlocks() async throws -> [DomainBlock] {
        try await client.get("/federation/domain-blocks", authenticated: true)
    }

    static func setDomainBlocked(_ on: Bool, domain: String) async throws {
        let path = "/federation/domain-blocks/\(domain)"
        if on {
            let _: DomainBlock = try await client.put(path, authenticated: true)
        } else {
            try await client.deleteVoid(path, authenticated: true)
        }
    }

    static func serverBlocks() async throws -> [ServerBlock] {
        try await client.get("/admin/federation/servers", authenticated: true)
    }

    static func blockServer(_ domain: String, severity: ServerBlock.Severity, reason: String?) async throws
        -> ServerBlock
    {
        struct Body: Encodable {
            let severity: String
            let reason: String?
        }
        return try await client.put(
            "/admin/federation/servers/\(domain)",
            body: Body(severity: severity.rawValue, reason: reason),
            authenticated: true)
    }

    static func unblockServer(_ domain: String) async throws {
        try await client.deleteVoid("/admin/federation/servers/\(domain)", authenticated: true)
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
            case "REMOTE_DOMAIN_BLOCKED":
                return String(localized: "차단한 서버의 계정은 팔로우할 수 없어요")
            default:
                break
            }
        }
        return String(localized: "연결을 확인하고 다시 시도해 주세요.")
    }
}
