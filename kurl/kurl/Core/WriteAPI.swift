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

    /// 메타데이터 부분 수정 — 백엔드 PATCH 는 null 필드를 무시하므로 바뀐 것만 보낸다.
    /// slug 는 절대 보내지 않는다(발행 후 frozen — 웹에서만 관리).
    @discardableResult
    static func updateMetadata(
        postId: Int64,
        title: String? = nil,
        excerpt: String? = nil,
        tags: [String]? = nil
    ) async throws -> MyPost {
        struct Body: Encodable {
            let title: String?
            let excerpt: String?
            let tags: [String]?
        }
        return try await client.patch(
            "/posts/\(postId)",
            body: Body(title: title, excerpt: excerpt, tags: tags),
            authenticated: true
        )
    }

    // MARK: 미리보기 / 예약 / 리비전

    /// 공유 토큰을 발급해 웹과 같은 미리보기 URL 을 만든다 — 발행 전 글을 브라우저로 확인.
    static func previewURL(slug: String, postId: Int64) async throws -> URL? {
        struct Response: Decodable { let token: String }
        let res: Response = try await client.post(
            "/posts/\(postId)/preview-token", body: EmptyBody(), authenticated: true)
        let username = await AuthStore.shared.me?.username ?? ""
        let locale = Config.preferredLanguageTag
        return URL(string: "\(Config.apiBase)/\(locale)/p/\(username)/\(slug)?preview=\(res.token)")
    }

    static func schedule(postId: Int64, at date: Date) async throws -> MyPost {
        struct Body: Encodable { let scheduledAt: String }
        return try await client.post(
            "/posts/\(postId)/schedule",
            body: Body(scheduledAt: ISO8601DateFormatter().string(from: date)),
            authenticated: true
        )
    }

    static func revisions(postId: Int64) async throws -> [PostRevision] {
        try await client.get("/posts/\(postId)/revisions", authenticated: true)
    }

    @discardableResult
    static func restoreRevision(postId: Int64, version: Int) async throws -> MyPost {
        try await client.post(
            "/posts/\(postId)/revisions/\(version)/restore", body: EmptyBody(), authenticated: true)
    }

    // MARK: 시리즈

    static func mySeries() async throws -> [MySeries] {
        try await client.get("/series", authenticated: true)
    }

    /// 시리즈 멤버십은 전체 교체(PUT postIds) — 지정/해제는 현재 목록을 읽어 더하고 빼서 보낸다.
    static func assign(postId: Int64, from oldSeriesId: Int64?, to newSeriesId: Int64?) async throws {
        guard oldSeriesId != newSeriesId else { return }
        if let old = oldSeriesId {
            var ids = try await memberIds(seriesId: old)
            ids.removeAll { $0 == postId }
            try await setMembers(seriesId: old, postIds: ids)
        }
        if let new = newSeriesId {
            var ids = try await memberIds(seriesId: new)
            if !ids.contains(postId) { ids.append(postId) }
            try await setMembers(seriesId: new, postIds: ids)
        }
    }

    private static func memberIds(seriesId: Int64) async throws -> [Int64] {
        struct Detail: Decodable {
            struct Member: Decodable { let id: Int64 }
            let posts: [Member]
        }
        let detail: Detail = try await client.get("/series/\(seriesId)", authenticated: true)
        return detail.posts.map(\.id)
    }

    private static func setMembers(seriesId: Int64, postIds: [Int64]) async throws {
        struct Body: Encodable { let postIds: [Int64] }
        struct Ignored: Decodable {}
        let _: Ignored = try await client.put(
            "/series/\(seriesId)/posts", body: Body(postIds: postIds), authenticated: true)
    }

    // MARK: 커버 이미지

    /// presign → S3 PUT → commit. JPEG 로 재인코딩해 올린다(HEIC 화이트리스트 이슈 회피).
    /// 반환 = 커버로 쓸 공개 URL 과 키 — 호출측이 PATCH(ogImageUrl/ogImageKey)로 마무리.
    static func uploadCover(postId: Int64, jpegData: Data) async throws -> (url: String, key: String) {
        struct PresignBody: Encodable { let contentType: String }
        struct Presign: Decodable {
            let uploadUrl: String
            let publicUrl: String
            let key: String
            let maxBytes: Int64
        }
        struct CommitBody: Encodable { let key: String }
        struct Commit: Decodable { let imageUrl: String, key: String }

        let presign: Presign = try await client.post(
            "/posts/\(postId)/images/presign",
            body: PresignBody(contentType: "image/jpeg"), authenticated: true)
        guard jpegData.count <= presign.maxBytes else { throw APIError.invalidURL }

        // S3 직행 PUT — 목 모드는 가짜 uploadUrl 이므로 건너뛴다.
        if !Config.useMocks, let url = URL(string: presign.uploadUrl) {
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            let (_, response) = try await URLSession.shared.upload(for: request, from: jpegData)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw APIError.http(status: (response as? HTTPURLResponse)?.statusCode ?? -1)
            }
        }

        let commit: Commit = try await client.post(
            "/posts/\(postId)/images/commit",
            body: CommitBody(key: presign.key), authenticated: true)
        return (commit.imageUrl, commit.key)
    }

    @discardableResult
    static func updateCover(postId: Int64, url: String, key: String) async throws -> MyPost {
        struct Body: Encodable { let ogImageUrl: String, ogImageKey: String }
        return try await client.patch(
            "/posts/\(postId)", body: Body(ogImageUrl: url, ogImageKey: key), authenticated: true)
    }

    private struct EmptyBody: Encodable {}
}

struct MySeries: Decodable, Identifiable, Hashable {
    let id: Int64
    let slug: String
    let title: String
    let postCount: Int
}

struct PostRevision: Decodable, Identifiable {
    let id: Int64
    let versionNumber: Int
    let titleSnapshot: String
    let createdAt: Date?
}

/// GET /posts (내 글) 응답의 앱이 쓰는 부분집합.
struct MyPost: Decodable, Identifiable, Hashable {
    let id: Int64
    let slug: String
    let title: String
    let status: String
    let publishedAt: Date?
    let scheduledAt: Date?
    let updatedAt: Date?
    let tags: [String]?
    let excerpt: String?
    let ogImageUrl: String?
    let seriesId: Int64?

    var isDraft: Bool { status == "DRAFT" }
    var isScheduled: Bool { status == "SCHEDULED" }
}
