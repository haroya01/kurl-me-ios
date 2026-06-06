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
        as type: T.Type = T.self
    ) async throws -> T {
        let request = try makeRequest(path: path, query: query, method: "GET")
        return try await send(request)
    }

    /// 응답 본문이 없는 POST (예: 조회 비콘). 실패해도 호출측에서 무시할 수 있다.
    func post(_ path: String, query: [String: String?] = [:]) async throws {
        let request = try makeRequest(path: path, query: query, method: "POST")
        _ = try await rawData(request)
    }

    private func makeRequest(path: String, query: [String: String?], method: String) throws -> URLRequest {
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
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data = try await rawData(request)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
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
