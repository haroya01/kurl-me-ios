//
//  NoteAPI.swift
//  kurl
//

import Foundation

/// 노트 — 블로그 글과 분리한 짧은 글. 공개 읽기도 로그인 상태면 토큰을 실어 보내야 내 좋아요와
/// 내 노트의 좋아요 수가 채워진다(남의 노트 좋아요 수는 서버가 숨긴다).
enum NoteAPI {
    static let maxLength = 500
    static let maxImages = 4
    static let maxAltLength = 1500

    private static let client = APIClient.shared

    private static var signedIn: Bool { AuthStore.shared.isSignedIn }

    static func everyone(page: Int = 0) async throws -> NoteFeed {
        try await client.get(
            "/public/notes", query: ["page": String(page), "size": "20"], authenticated: signedIn)
    }

    static func trending(page: Int = 0) async throws -> NoteFeed {
        try await client.get(
            "/public/notes", query: ["sort": "trending", "page": String(page), "size": "20"],
            authenticated: signedIn)
    }

    static func bookmarks(page: Int = 0) async throws -> NoteFeed {
        try await client.get(
            "/notes/bookmarks", query: ["page": String(page), "size": "20"], authenticated: true)
    }

    static func quotes(of id: Int64, page: Int = 0) async throws -> NoteFeed {
        try await client.get(
            "/public/notes/\(id)/quotes", query: ["page": String(page), "size": "20"],
            authenticated: signedIn)
    }

    static func following(page: Int = 0) async throws -> NoteFeed {
        try await client.get(
            "/notes/following", query: ["page": String(page), "size": "20"], authenticated: true)
    }

    static func byAuthor(_ username: String, page: Int = 0) async throws -> NoteFeed {
        try await client.get(
            "/public/profiles/\(username)/notes", query: ["page": String(page), "size": "20"],
            authenticated: signedIn)
    }

    static func reposts(_ username: String, page: Int = 0) async throws -> NoteFeed {
        try await client.get(
            "/public/profiles/\(username)/reposts", query: ["page": String(page), "size": "20"],
            authenticated: signedIn)
    }

    static func linkPreview(url: String) async throws -> NoteLinkPreview {
        try await client.get("/public/link-preview", query: ["url": url], authenticated: false)
    }

    static func thread(id: Int64) async throws -> NoteThread {
        try await client.get("/public/notes/\(id)", authenticated: signedIn)
    }

    static func create(_ draft: NoteDraft) async throws -> Note {
        try await client.post("/notes", body: draft, authenticated: true)
    }

    static func edit(id: Int64, body: String) async throws -> Note {
        struct Body: Encodable { let body: String }
        return try await client.patch("/notes/\(id)", body: Body(body: body), authenticated: true)
    }

    static func delete(id: Int64) async throws {
        try await client.deleteVoid("/notes/\(id)", authenticated: true)
    }

    static func setLike(id: Int64, on: Bool) async throws -> NoteLikeStatus {
        on
            ? try await client.put("/notes/\(id)/like", body: EmptyBody(), authenticated: true)
            : try await client.delete("/notes/\(id)/like", authenticated: true)
    }

    static func setRepost(id: Int64, on: Bool) async throws -> NoteRepostStatus {
        on
            ? try await client.put("/notes/\(id)/repost", body: EmptyBody(), authenticated: true)
            : try await client.delete("/notes/\(id)/repost", authenticated: true)
    }

    static func setBookmark(id: Int64, on: Bool) async throws -> NoteBookmarkStatus {
        on
            ? try await client.put("/notes/\(id)/bookmark", body: EmptyBody(), authenticated: true)
            : try await client.delete("/notes/\(id)/bookmark", authenticated: true)
    }

    /// presign → 저장소 직행 PUT. 노트를 쓸 때 넘길 키를 돌려준다. JPEG 로 재인코딩해 올린다.
    static func uploadImage(jpegData: Data) async throws -> String {
        struct PresignBody: Encodable { let contentType: String }
        struct Presign: Decodable {
            let uploadUrl: String
            let key: String
            let maxBytes: Int64
        }
        let presign: Presign = try await client.post(
            "/notes/images/presign", body: PresignBody(contentType: "image/jpeg"),
            authenticated: true)
        guard jpegData.count <= presign.maxBytes else { throw APIError.invalidURL }
        if !Config.useMocks, let url = URL(string: presign.uploadUrl) {
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            let (_, response) = try await URLSession.shared.upload(for: request, from: jpegData)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw APIError.http(status: (response as? HTTPURLResponse)?.statusCode ?? -1)
            }
        }
        return presign.key
    }

    static func federationSettings() async throws -> FederationSettings {
        try await client.get("/federation/settings", authenticated: true)
    }

    @discardableResult
    static func updateFederationSettings(enabled: Bool? = nil, noticeSeen: Bool? = nil)
        async throws -> FederationSettings
    {
        struct Body: Encodable {
            let enabled: Bool?
            let noticeSeen: Bool?
        }
        return try await client.put(
            "/federation/settings", body: Body(enabled: enabled, noticeSeen: noticeSeen),
            authenticated: true)
    }

    private struct EmptyBody: Encodable {}
}

struct NoteMedia: Decodable, Hashable, Identifiable {
    var id: String { url }
    let url: String
    let altText: String?
    let contentType: String
}

struct QuotedPost: Codable, Hashable, Identifiable {
    let id: Int64
    let title: String
    let slug: String
    let authorUsername: String
}

struct NoteLinkPreview: Decodable, Hashable {
    let url: String
    let title: String?
    let description: String?
    let image: String?
}

struct QuotedNote: Decodable, Hashable, Identifiable {
    let id: Int64
    let body: String
    let createdAt: Date?
    let author: Author
    let media: [NoteMedia]
}

struct Note: Decodable, Identifiable, Hashable {
    let id: Int64
    let body: String
    let createdAt: Date?
    let editedAt: Date?
    /// 작성자 본인에게만 숫자, 남에게는 nil(좋아요 수 비공개).
    let likeCount: Int64?
    /// 비로그인 읽기면 nil.
    let likedByMe: Bool?
    let author: Author
    let media: [NoteMedia]
    let quotedPost: QuotedPost?
    let inReplyToId: Int64?
    let replyCount: Int64
    /// 좋아요 수처럼 작성자 본인에게만 숫자.
    let repostCount: Int64?
    let repostedByMe: Bool?
    let quotedNote: QuotedNote?
    /// 첫 주소의 Open Graph 카드 — 서버가 올린 뒤 비동기로 채운다.
    var linkPreview: NoteLinkPreview?
    /// 팔로잉 피드에서 이 노트가 리포스트로 들어왔을 때 리포스트한 사람.
    var repostedBy: Author? = nil
    var quoteCount: Int64? = nil
    /// 비로그인 읽기면 nil. 북마크는 본인만 안다.
    var bookmarkedByMe: Bool? = nil
}

struct NoteFeed: Decodable {
    let items: [Note]
    let page: Int
    let hasNext: Bool
}

struct NoteThread: Decodable {
    let note: Note
    let parent: Note?
    let replies: [Note]
}

struct NoteDraft: Encodable {
    struct Image: Encodable {
        let key: String
        let altText: String
    }

    let body: String
    let images: [Image]
    let quotedPostId: Int64?
    let inReplyToId: Int64?
    var quotedNoteId: Int64? = nil
}

struct NoteLikeStatus: Decodable {
    let liked: Bool
    let likeCount: Int64
}

struct NoteBookmarkStatus: Decodable {
    let bookmarked: Bool
}

struct NoteRepostStatus: Decodable {
    let reposted: Bool
    let repostCount: Int64
}

struct FederationSettings: Decodable {
    let enabled: Bool
    let noticeSeen: Bool
    let handle: String?
}
