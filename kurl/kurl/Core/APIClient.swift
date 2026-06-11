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
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return String(localized: "잘못된 요청입니다.")
        case .http(let status): return String(localized: "서버 오류 (\(status))")
        case .decoding: return String(localized: "응답을 읽지 못했습니다.")
        case .transport: return String(localized: "네트워크에 연결할 수 없습니다.")
        }
    }
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
