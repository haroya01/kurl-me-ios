//
//  WriteAPI.swift
//  kurl
//

import Foundation

/// 글쓰기(작성·발행) 엔드포인트. 본문은 마크다운 하나로 다룬다 — md↔blocks 변환은
/// 서버가 소유(PUT /posts/{id}/markdown)해서 웹 에디터와 동일한 블록 스트림이 만들어진다.
enum WriteAPI {
    private static let client = APIClient.shared

    /// 새 글(임시저장 상태) 생성. 슬러그는 앱에서 시각 기반으로 자동 생성 —
    /// 백엔드 규칙 ^[a-z0-9]+(-[a-z0-9]+)*$ 을 항상 만족하고, 웹 에디터에서 언제든 바꿀 수 있다.
    static func createDraft(title: String) async throws -> MyPost {
        struct Body: Encodable {
            let slug: String
            let title: String
            let languageTag: String
        }
        let slug = "p-\(Int(Date().timeIntervalSince1970))"
        return try await client.post(
            "/posts",
            body: Body(slug: slug, title: title, languageTag: Config.preferredLanguageTag),
            authenticated: true
        )
    }

    static func myPosts() async throws -> [MyPost] {
        try await client.get("/posts", authenticated: true)
    }

    static func markdown(postId: Int64) async throws -> String {
        struct Response: Decodable { let markdown: String }
        let res: Response = try await client.get("/posts/\(postId)/markdown", authenticated: true)
        return res.markdown
    }

    /// 본문 교체 — 응답은 서버가 왕복 정규화한 마크다운(이걸 채택해 편집 상태를 canonical 로 유지).
    @discardableResult
    static func replaceMarkdown(postId: Int64, markdown: String) async throws -> String {
        struct Body: Encodable { let markdown: String }
        struct Response: Decodable { let markdown: String }
        let res: Response = try await client.put(
            "/posts/\(postId)/markdown",
            body: Body(markdown: markdown),
            authenticated: true
        )
        return res.markdown
    }

    static func publish(postId: Int64) async throws -> MyPost {
        try await client.post("/posts/\(postId)/publish", body: EmptyBody(), authenticated: true)
    }

    private struct EmptyBody: Encodable {}
}

/// GET /posts (내 글) 응답의 앱이 쓰는 부분집합.
struct MyPost: Decodable, Identifiable, Hashable {
    let id: Int64
    let slug: String
    let title: String
    let status: String
    let publishedAt: Date?
    let updatedAt: Date?

    var isDraft: Bool { status == "DRAFT" }
}
