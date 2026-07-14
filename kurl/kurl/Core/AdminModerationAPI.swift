//
//  AdminModerationAPI.swift
//  kurl
//
//  관리자 모더레이션 — 타인 글의 내리기·편집(제목·태그)·영구 삭제. /admin/** 는 서버 보안
//  레이어가 ADMIN 역할로 게이트하므로 클라이언트 가드(isAdmin)는 진입로 노출용일 뿐이다.
//

import Foundation

enum AdminModerationAPI {
    private static let client = APIClient.shared

    /// 테이크다운 — 글을 비공개(UNPUBLISHED)로 내린다. 멱등(이미 비공개면 무동작).
    static func unpublish(postId: Int64) async throws {
        struct EmptyBody: Encodable {}
        try await client.post(
            "/admin/posts/\(postId)/unpublish", body: EmptyBody(), authenticated: true)
    }

    /// 모더레이션 편집 — 제목·태그만(PATCH 의미: nil = 무변경). 본문·주소·커버는 작가의 것.
    static func update(postId: Int64, title: String?, tags: [String]?) async throws {
        struct Body: Encodable { let title: String?; let tags: [String]? }
        struct Ignored: Decodable {}
        let _: Ignored = try await client.patch(
            "/admin/posts/\(postId)", body: Body(title: title, tags: tags), authenticated: true)
    }

    /// 영구 삭제 — 소유자 경로와 같은 캐스케이드(본문·댓글·좋아요·하이라이트·연결까지).
    static func delete(postId: Int64) async throws {
        try await client.deleteVoid("/admin/posts/\(postId)", authenticated: true)
    }
}
