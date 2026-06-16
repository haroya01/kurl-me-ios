//
//  HighlightsAPI.swift
//  kurl
//

import Foundation

/// 리더 소셜 하이라이트 — 공개 읽기(누가 어디를)는 인증 없이, 생성/삭제·답글·내 서재는 인증.
/// 백엔드 `PostHighlightController`/`PublicHighlightController`/`HighlightReplyController` 와 1:1.
enum HighlightsAPI {
    private static let client = APIClient.shared

    /// 공개 — 이 글의 모든 하이라이트(attributed). 미로그인도 읽는다.
    static func list(postId: Int64) async throws -> [HighlightView] {
        try await client.get("/public/posts/\(postId)/highlights")
    }

    /// 인증 — 발행된 글에 하이라이트 생성(선택적 공개 메모 포함). 생성된 것을 그대로 돌려받는다.
    @discardableResult
    static func create(postId: Int64, _ payload: NewHighlight) async throws -> HighlightRef {
        try await client.post("/posts/\(postId)/highlights", body: payload, authenticated: true)
    }

    /// 인증 — 내가 그은 하이라이트 삭제(본인만).
    static func delete(id: Int64) async throws {
        try await client.deleteVoid("/highlights/\(id)", authenticated: true)
    }

    /// 인증 — 내 하이라이트 서재(원문 참조 포함).
    static func mine() async throws -> [MyHighlightView] {
        try await client.get("/users/me/highlights", authenticated: true)
    }

    /// 공개 — 한 하이라이트의 답글 스레드(오래된 순). 작성자 메모가 오프너, 답글이 그 아래.
    static func replies(highlightId: Int64) async throws -> [HighlightReplyView] {
        try await client.get("/public/highlights/\(highlightId)/replies")
    }

    /// 인증 — 하이라이트에 답글(작성자·@멘션에게 알림).
    @discardableResult
    static func reply(highlightId: Int64, body: String) async throws -> HighlightReplyView {
        struct Body: Encodable { let body: String }
        return try await client.post(
            "/highlights/\(highlightId)/replies", body: Body(body: body), authenticated: true)
    }

    /// 인증 — 내 답글 삭제(또는 글주인).
    static func deleteReply(id: Int64) async throws {
        try await client.deleteVoid("/highlight-replies/\(id)", authenticated: true)
    }
}

/// 공개·attributed 하이라이트 — 누가 어느 구간(블록 + 문자 오프셋 + 인용)을 그었나 + 공개 메모 + 답글 수.
struct HighlightView: Decodable, Identifiable, Hashable {
    let id: Int64
    /// 누가 그었는지 — 공개 면이라 attribution. 낙관적 추가분은 nil.
    let author: Author?
    let blockOrder: Int?
    let startOffset: Int?
    let endOffset: Int?
    let quote: String
    /// 작성자의 공개 메모(여백 노트) — 스레드의 오프너. 없으면 nil.
    let note: String?
    /// 답글 수 — "대화 있음" 표식 + 스레드 진입 신호.
    let replyCount: Int
    let createdAt: Date?
}

/// 생성 페이로드 — 블록 인덱스 + 문자 오프셋 + 인용문 + 선택적 메모.
struct NewHighlight: Encodable {
    let blockOrder: Int
    let startOffset: Int
    let endOffset: Int
    let quote: String
    var note: String?
}

/// 방금 만든 하이라이트의 에코 — 내 것이라 attribution 불필요.
struct HighlightRef: Decodable {
    let id: Int64
    let blockOrder: Int?
    let startOffset: Int?
    let endOffset: Int?
    let quote: String
    let note: String?
    let createdAt: Date?
}

/// 한 하이라이트의 답글 하나.
struct HighlightReplyView: Decodable, Identifiable, Hashable {
    let id: Int64
    let author: Author?
    let body: String
    let createdAt: Date?
}

/// 내 서재의 하이라이트 — 원문(작가·슬러그·제목)으로 돌아가는 참조를 함께 싣는다.
struct MyHighlightView: Decodable, Identifiable, Hashable {
    let id: Int64
    let quote: String
    let blockOrder: Int?
    let postUsername: String
    let postSlug: String
    let postTitle: String
    let createdAt: Date?
}
