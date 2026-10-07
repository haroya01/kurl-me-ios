//
//  AccountImportAPI.swift
//  kurl
//

import Foundation

/// 마스토돈 가져오기(합치기) — 내보내기 파일을 올리면 서버가 뒤에서 한 줄씩 적용한다.
struct AccountImport: Decodable, Identifiable, Hashable {
    let id: Int64
    let kind: String
    let total: Int
    let processed: Int
    let imported: Int
    let finished: Bool
    let createdAt: Date?

    var failed: Int { max(processed - imported, 0) }
}

enum AccountImportAPI {
    private static let client = APIClient.shared

    private struct Start: Encodable {
        let kind: String
        let csv: String
    }

    static func start(kind: String, csv: String) async throws -> AccountImport {
        try await client.post("/users/me/imports", body: Start(kind: kind, csv: csv), authenticated: true)
    }

    static func recent() async throws -> [AccountImport] {
        try await client.get("/users/me/imports", authenticated: true)
    }
}
