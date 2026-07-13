//
//  APIClient.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case http(status: Int)
    /// 서버가 RFC-7807 ProblemDetail 로 보낸 사람이 읽을 수 있는 사유(detail) + 기계 코드.
    /// 작성 흐름의 알럿이 "서버 오류 (400)" 대신 실제 메시지를 보여줄 수 있게 한다.
    case server(status: Int, code: String?, detail: String)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return String(localized: "잘못된 요청입니다.")
        case .http(let status): return String(localized: "서버 오류 (\(status))")
        case .server(_, _, let detail): return detail
        case .decoding: return String(localized: "응답을 읽지 못했습니다.")
        case .transport: return String(localized: "네트워크에 연결할 수 없습니다.")
        }
    }

    /// .http·.server 공통 HTTP 상태 코드 — 호출측이 두 케이스를 따로 풀지 않게(409·400 분기 등).
    var statusCode: Int? {
        switch self {
        case .http(let status): return status
        case .server(let status, _, _): return status
        default: return nil
        }
    }
}

/// 백엔드 ProblemDetails.of 가 내는 본문 — title/detail/code 만 골라 읽는다.
private struct ProblemDetailBody: Decodable {
    let title: String?
    let detail: String?
    let code: String?
}

struct APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder.blog
    }

    func get<T: Decodable>(
        _ path: String,
        query: [String: String?] = [:],
        as type: T.Type = T.self,
        authenticated: Bool = false
    ) async throws -> T {
        let request = try makeRequest(path: path, query: query, method: "GET")
        let data = try await perform(request, authenticated: authenticated)
        return try decode(data)
    }

    /// 응답 원문이 필요한 GET — 오프라인 저장소가 서버 바이트를 그대로 보관할 때.
    func getData(_ path: String, query: [String: String?] = [:]) async throws -> Data {
        try await rawData(try makeRequest(path: path, query: query, method: "GET"))
    }

    /// 응답 본문이 없는 POST (예: 조회 비콘). 실패해도 호출측에서 무시할 수 있다.
    func post(_ path: String, query: [String: String?] = [:]) async throws {
        let request = try makeRequest(path: path, query: query, method: "POST")
        _ = try await rawData(request)
    }

    /// JSON 바디 POST + 디코딩 응답.
    func post<B: Encodable, T: Decodable>(
        _ path: String,
        body: B,
        as type: T.Type = T.self,
        authenticated: Bool = false
    ) async throws -> T {
        let request = try makeRequest(path: path, query: [:], method: "POST", body: try encode(body))
        let data = try await perform(request, authenticated: authenticated)
        return try decode(data)
    }

    /// JSON 바디 POST, 응답 본문 무시 (204 등).
    func post<B: Encodable>(
        _ path: String,
        body: B,
        authenticated: Bool = false
    ) async throws {
        let request = try makeRequest(path: path, query: [:], method: "POST", body: try encode(body))
        _ = try await perform(request, authenticated: authenticated)
    }

    /// 바디 없는 PUT — 멱등 토글 온 (좋아요/북마크/팔로우).
    func put<T: Decodable>(
        _ path: String,
        as type: T.Type = T.self,
        authenticated: Bool = false
    ) async throws -> T {
        let request = try makeRequest(path: path, query: [:], method: "PUT")
        let data = try await perform(request, authenticated: authenticated)
        return try decode(data)
    }

    /// JSON 바디 PATCH (메타데이터 부분 수정 — 빠진 키는 서버가 무시).
    func patch<B: Encodable, T: Decodable>(
        _ path: String,
        body: B,
        as type: T.Type = T.self,
        authenticated: Bool = false
    ) async throws -> T {
        let request = try makeRequest(path: path, query: [:], method: "PATCH", body: try encode(body))
        let data = try await perform(request, authenticated: authenticated)
        return try decode(data)
    }

    /// JSON 바디 PUT, 응답 없음(204) — 순서 재배치처럼 본문만 보내고 결과를 안 받는 자리.
    func putVoid<B: Encodable>(
        _ path: String,
        body: B,
        authenticated: Bool = false
    ) async throws {
        let request = try makeRequest(path: path, query: [:], method: "PUT", body: try encode(body))
        _ = try await perform(request, authenticated: authenticated)
    }

    /// 바디·응답 없는 PUT (204) — 멱등 토글 온(차단 등).
    func putVoid(_ path: String, authenticated: Bool = false) async throws {
        let request = try makeRequest(path: path, query: [:], method: "PUT")
        _ = try await perform(request, authenticated: authenticated)
    }

    /// JSON 바디 PUT (본문 교체 등).
    func put<B: Encodable, T: Decodable>(
        _ path: String,
        body: B,
        as type: T.Type = T.self,
        authenticated: Bool = false
    ) async throws -> T {
        let request = try makeRequest(path: path, query: [:], method: "PUT", body: try encode(body))
        let data = try await perform(request, authenticated: authenticated)
        return try decode(data)
    }

    /// 바디·응답 없는 DELETE (204).
    func deleteVoid(_ path: String, authenticated: Bool = false) async throws {
        let request = try makeRequest(path: path, query: [:], method: "DELETE")
        _ = try await perform(request, authenticated: authenticated)
    }

    /// 명시 bearer 의 JSON 바디 DELETE — 로그아웃 뒷정리처럼 저장소가 이미 비워진 뒤
    /// 스냅샷해 둔 토큰으로 마지막 요청을 보내야 하는 자리(401 리프레시 재시도 없음).
    func delete<B: Encodable>(_ path: String, body: B, bearer: String) async throws {
        var request = try makeRequest(path: path, query: [:], method: "DELETE", body: try encode(body))
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        _ = try await rawData(request)
    }

    /// 바디 없는 DELETE — 멱등 토글 오프.
    func delete<T: Decodable>(
        _ path: String,
        as type: T.Type = T.self,
        authenticated: Bool = false
    ) async throws -> T {
        let request = try makeRequest(path: path, query: [:], method: "DELETE")
        let data = try await perform(request, authenticated: authenticated)
        return try decode(data)
    }

    /// 인증 요청 공통 경로: Bearer 를 싣고, 401 이면 리프레시 한 번 후 재시도 한 번.
    /// 리프레시 자체는 AuthStore 가 단일 비행으로 직렬화한다.
    private func perform(_ request: URLRequest, authenticated: Bool) async throws -> Data {
        guard authenticated else { return try await rawData(request) }
        var authorized = request
        if let token = await AuthStore.shared.bearerToken {
            authorized.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            return try await rawData(authorized)
        } catch APIError.http(let status) where status == 401 {
            try await AuthStore.shared.refreshTokens()
            guard let token = await AuthStore.shared.bearerToken else {
                throw APIError.http(status: 401)
            }
            authorized.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return try await rawData(authorized)
        }
    }

    private func encode<B: Encodable>(_ body: B) throws -> Data {
        do {
            return try JSONEncoder().encode(body)
        } catch {
            throw APIError.invalidURL
        }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func makeRequest(
        path: String,
        query: [String: String?],
        method: String,
        body: Data? = nil
    ) throws -> URLRequest {
        var components = URLComponents(
            url: Config.apiBase.appendingPathComponent(Config.apiPrefix + path),
            resolvingAgainstBaseURL: false
        )
        let items = query.compactMap { key, value -> URLQueryItem? in
            guard let value else { return nil }
            return URLQueryItem(name: key, value: value)
        }
        if !items.isEmpty { components?.queryItems = items }

        guard let url = components?.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Config.preferredLanguageTag, forHTTPHeaderField: "Accept-Language")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    @discardableResult
    private func rawData(_ request: URLRequest) async throws -> Data {
        #if DEBUG
        // `--offline` — 비행기 모드 시뮬레이션(오프라인 폴백 검증 진입로).
        if Config.simulateOffline {
            throw APIError.transport(URLError(.notConnectedToInternet))
        }
        #endif
        // 목 모드: 목 백엔드가 아는 경로면 네트워크를 건너뛴다(공개 읽기는 fall-through).
        if Config.useMocks,
           let url = request.url,
           let mocked = await MockBackend.respond(
               path: String(url.path.dropFirst(Config.apiPrefix.count + 1)),
               method: request.httpMethod ?? "GET",
               query: URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
               body: request.httpBody
           ) {
            return mocked
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(status: -1)
        }
        guard (200..<300).contains(http.statusCode) else {
            // 401 은 리프레시 로직(get/send 의 catch)이 가로채야 하므로 그대로 둔다.
            if http.statusCode == 401 {
                throw APIError.http(status: 401)
            }
            // 서버가 ProblemDetail 로 사유를 줬으면 그 사람이 읽을 메시지를 그대로 올린다.
            if let problem = try? JSONDecoder().decode(ProblemDetailBody.self, from: data),
                let detail = (problem.detail ?? problem.title)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
                throw APIError.server(status: http.statusCode, code: problem.code, detail: detail)
            }
            throw APIError.http(status: http.statusCode)
        }
        return data
    }
}

extension JSONDecoder {
    /// 백엔드 Instant 는 ISO-8601(소수초 포함/미포함 혼재)로 직렬화된다.
    static let blog: JSONDecoder = {
        let decoder = JSONDecoder()
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]

        decoder.dateDecodingStrategy = .custom { container in
            let raw = try container.singleValueContainer().decode(String.self)
            if let date = withFraction.date(from: raw) ?? plain.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorrupted(
                .init(codingPath: container.codingPath, debugDescription: "Unrecognized date: \(raw)")
            )
        }
        return decoder
    }()
}
