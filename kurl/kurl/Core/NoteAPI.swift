//
//  NoteAPI.swift
//  kurl
//

import Foundation

/// 짧은 글(노트) — 읽기는 공개, 쓰기·좋아요는 인증. likedByMe 는 피드에 실리지 않고
/// 배치 상태 조회로 따로 온다(#538 댓글 좋아요와 같은 분리).
enum NoteAPI {
    private static let client = APIClient.shared

    static func feed(page: Int = 0, size: Int = 20) async throws -> NoteFeedView {
        try await client.get(
            "/public/notes", query: ["page": String(page), "size": String(size)])
    }

    static func create(body: String) async throws -> Note {
        try await client.post("/notes", body: ["body": body], authenticated: true)
    }

    static func delete(id: Int64) async throws {
        try await client.deleteVoid("/notes/\(id)", authenticated: true)
    }

    static func setLike(id: Int64, on: Bool) async throws -> NoteLikeStatus {
        on
            ? try await client.put("/notes/\(id)/like", body: EmptyBody(), authenticated: true)
            : try await client.delete("/notes/\(id)/like", authenticated: true)
    }

    static func likedIds(_ ids: [Int64]) async throws -> [Int64] {
        guard !ids.isEmpty else { return [] }
        let response: LikedIdsResponse = try await client.get(
            "/notes/like-status",
            query: ["ids": ids.map(String.init).joined(separator: ",")],
            authenticated: true)
        return response.likedIds
    }

    private struct EmptyBody: Encodable {}
    private struct LikedIdsResponse: Decodable { let likedIds: [Int64] }
}

struct Note: Decodable, Identifiable, Equatable {
    let id: Int64
    let body: String
    let createdAt: Date?
    let likeCount: Int64
    let author: Author
}

struct NoteFeedView: Decodable {
    let items: [Note]
    let page: Int
    let hasNext: Bool
}

struct NoteLikeStatus: Decodable {
    let liked: Bool
    let likeCount: Int64
}
