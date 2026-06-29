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
        // 초 단위만 쓰면 같은 1초에 두 초안이 같은 slug 로 충돌(SLUG_CONFLICT)한다 — 무작위 토큰을 붙인다.
        let slug = "p-\(Int(Date().timeIntervalSince1970))-\(Int.random(in: 100...999))"
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

    /// 본문에 붙여넣은 외부 URL 을 kurl 단축링크로. 응답의 shortUrl(전체 주소)만 채택한다.
    static func shorten(_ url: String) async throws -> String {
        struct Body: Encodable { let url: String }
        struct Response: Decodable { let shortUrl: String }
        let res: Response = try await client.post("/links", body: Body(url: url), authenticated: true)
        return res.shortUrl
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
        // username 이 아직 안 실렸으면 /p//slug 처럼 깨진 URL 을 만들지 않는다 — nil 을 돌려 호출측이 건너뛴다.
        guard let username = await AuthStore.shared.me?.username, !username.isEmpty else {
            return nil
        }
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

    /// 새 시리즈 생성 후 갱신된 목록을 돌려준다 — 호출측은 방금 만든 slug 로 골라잡는다.
    /// slug 는 제목에서 파생(유저별 유니크) — 호출측이 충돌 안 나게 토큰을 붙여 넘긴다.
    @discardableResult
    static func createSeries(slug: String, title: String) async throws -> [MySeries] {
        struct Body: Encodable { let slug: String; let title: String }
        struct Ignored: Decodable {}
        let _: Ignored = try await client.post(
            "/series", body: Body(slug: slug, title: title), authenticated: true)
        return try await mySeries()
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

    // MARK: 이미지 업로드 (커버·본문 공용)

    /// presign → S3 PUT → commit. JPEG 로 재인코딩해 올린다(HEIC 화이트리스트 이슈 회피).
    /// 반환 = 공개 URL 과 키. 커버는 호출측이 PATCH(ogImageUrl/ogImageKey)로 마무리하고,
    /// 본문 이미지는 URL 을 마크다운으로 삽입하면 끝이다.
    static func uploadImage(postId: Int64, jpegData: Data) async throws -> (url: String, key: String) {
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

    /// 붙여넣은 외부 이미지 URL 을 서버가 우리 버킷으로 재호스팅 — 핫링크는 원본 만료/차단 시 발행 후
    /// 깨지므로. 응답은 업로드와 같은 모양(imageUrl·key). 본문엔 imageUrl 만 `![](…)` 로 넣는다.
    static func importImage(postId: Int64, url: String) async throws -> String {
        struct Body: Encodable { let url: String }
        struct Response: Decodable { let imageUrl: String; let key: String }
        let res: Response = try await client.post(
            "/posts/\(postId)/images/import", body: Body(url: url), authenticated: true)
        return res.imageUrl
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
    var isPublished: Bool { status == "PUBLISHED" }
    /// 웹에서 비공개로 내린 글 — 앱은 이 상태를 몰라 '라이브'로 잘못 표시하던 갭을 메운다.
    var isUnpublished: Bool { status == "UNPUBLISHED" }
}
