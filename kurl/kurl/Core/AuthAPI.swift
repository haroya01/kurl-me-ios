//
//  AuthAPI.swift
//  kurl
//

import Foundation

/// 모바일 인증 엔드포인트 모음. 웹과 달리 쿠키 없이 토큰을 바디로 주고받는다
/// (`/api/v1/auth/mobile/*`). 여기 호출들은 절대 `authenticated:` 경로를 타지 않는다 —
/// 401 리프레시 재시도가 자기 자신을 다시 부르는 순환을 만들기 때문.
enum AuthAPI {
    private static let client = APIClient.shared

    static func exchange(code: String) async throws -> TokenPair {
        try await client.post("/auth/mobile/exchange", body: ["code": code])
    }

    static func refresh(refreshToken: String) async throws -> TokenPair {
        try await client.post("/auth/mobile/refresh", body: ["refreshToken": refreshToken])
    }

    static func verifyTwoFactor(challenge: String, code: String, recovery: Bool) async throws -> TokenPair {
        struct Body: Encodable {
            let challenge: String
            let code: String
            let recovery: Bool
        }
        return try await client.post(
            "/auth/mobile/2fa/verify",
            body: Body(challenge: challenge, code: code, recovery: recovery)
        )
    }

    static func logout(refreshToken: String) async throws {
        try await client.post("/auth/mobile/logout", body: ["refreshToken": refreshToken])
    }

    static func me() async throws -> Me {
        try await client.get("/users/me", authenticated: true)
    }
}

struct TokenPair: Decodable {
    let accessToken: String
    let refreshToken: String
}

struct Me: Decodable, Equatable {
    let email: String
    let username: String?
    let avatarUrl: String?
}
