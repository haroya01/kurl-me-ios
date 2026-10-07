//
//  NoteAPI.swift
//  kurl
//

import Foundation
import SwiftUI

/// 노트 — 블로그 글과 분리한 짧은 글. 공개 읽기도 로그인 상태면 토큰을 실어 보내야 내 좋아요와
/// 내 노트의 좋아요 수가 채워진다(남의 노트 좋아요 수는 서버가 숨긴다).
enum NoteAPI {
    static let maxLength = 500
    static let maxImages = 4
    static let maxWarningLength = 100
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

    static func tagged(_ tag: String, page: Int = 0) async throws -> NoteFeed {
        try await client.get(
            "/public/notes/tags/\(tag)", query: ["page": String(page), "size": "20"],
            authenticated: signedIn)
    }

    static func direct(page: Int = 0) async throws -> NoteFeed {
        try await client.get(
            "/notes/direct", query: ["page": String(page), "size": "20"], authenticated: true)
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

    static func edit(id: Int64, body: String, contentWarning: String, sensitive: Bool) async throws -> Note {
        struct Body: Encodable {
            let body: String
            let contentWarning: String
            let sensitive: Bool
        }
        return try await client.patch(
            "/notes/\(id)", body: Body(body: body, contentWarning: contentWarning, sensitive: sensitive),
            authenticated: true)
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

    static func history(of id: Int64) async throws -> NoteHistory {
        try await client.get("/public/notes/\(id)/history", authenticated: signedIn)
    }

    static func setPin(id: Int64, on: Bool) async throws -> NotePinStatus {
        on
            ? try await client.put("/notes/\(id)/pin", body: EmptyBody(), authenticated: true)
            : try await client.delete("/notes/\(id)/pin", authenticated: true)
    }

    static func setBookmark(id: Int64, on: Bool) async throws -> NoteBookmarkStatus {
        on
            ? try await client.put("/notes/\(id)/bookmark", body: EmptyBody(), authenticated: true)
            : try await client.delete("/notes/\(id)/bookmark", authenticated: true)
    }

    static func feedPreferences() async throws -> NoteFeedPreferencesBody {
        try await client.get("/notes/feed-preferences", authenticated: true)
    }

    static func setShowReposts(_ on: Bool) async throws -> NoteFeedPreferencesBody {
        try await client.put(
            "/notes/feed-preferences", body: NoteFeedPreferencesBody(showReposts: on),
            authenticated: true)
    }

    static func repostVisibility(of username: String) async throws -> NoteRepostVisibility {
        try await client.get("/notes/repost-visibility/\(username)", authenticated: true)
    }

    static func setRepostsHidden(of username: String, hidden: Bool) async throws -> NoteRepostVisibility {
        hidden
            ? try await client.put(
                "/notes/repost-visibility/\(username)", body: EmptyBody(), authenticated: true)
            : try await client.delete("/notes/repost-visibility/\(username)", authenticated: true)
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
    var contentWarning: String? = nil
    var sensitive: Bool? = nil
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
    /// 본문에서 언급한 kurl 회원 중 실제로 있는 사람만 — 이 이름들만 프로필로 링크한다.
    var mentions: [String]? = nil
    /// 열람 주의 문구 — 있으면 본문·사진·카드를 이 문구 뒤로 접는다(마스토돈 CW).
    var contentWarning: String? = nil
    /// 사진을 흐리게 가린다. 경고 문구가 있으면 서버가 늘 켠다.
    var sensitive: Bool? = nil
    /// 작성자가 프로필 위에 고정했다(최대 5개, 마스토돈 pin).
    var pinned: Bool? = nil
    /// public · unlisted · private · direct — 마스토돈 공개 범위.
    var visibility: String? = nil

    var noteVisibility: NoteVisibility { NoteVisibility(rawValue: visibility ?? "public") ?? .public }
}

/// 마스토돈의 네 가지. 리포스트·인용은 공개와 조용한 공개만 된다.
enum NoteVisibility: String, CaseIterable, Identifiable {
    case `public`, unlisted, `private`, direct

    var id: String { rawValue }

    var shareable: Bool { self == .public || self == .unlisted }

    var title: LocalizedStringKey {
        switch self {
        case .public: "공개"
        case .unlisted: "조용한 공개"
        case .private: "팔로워만"
        case .direct: "멘션한 사람만"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .public: "누구나 볼 수 있어요"
        case .unlisted: "누구나 볼 수 있지만 모든 노트·인기·태그에는 안 나와요"
        case .private: "팔로워와 멘션한 회원만 볼 수 있어요"
        case .direct: "멘션한 회원만 볼 수 있어요"
        }
    }

    var symbol: String {
        switch self {
        case .public: "globe"
        case .unlisted: "moon"
        case .private: "lock"
        case .direct: "at"
        }
    }
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
    var contentWarning: String? = nil
    var sensitive: Bool = false
    var visibility: String? = nil
}

struct NoteLikeStatus: Decodable {
    let liked: Bool
    let likeCount: Int64
}

struct NoteBookmarkStatus: Decodable {
    let bookmarked: Bool
}

struct NotePinStatus: Decodable {
    let pinned: Bool
}

/// 마스토돈 수정 기록 — 지금 판이 첫째, 그 앞의 판들이 최신순으로 뒤따른다.
struct NoteHistory: Decodable {
    struct Version: Decodable, Hashable {
        let body: String
        let contentWarning: String?
        let sensitive: Bool
        let at: Date?
    }

    let noteId: Int64
    let versions: [Version]
}

struct NoteFeedPreferencesBody: Codable {
    let showReposts: Bool
}

struct NoteRepostVisibility: Decodable {
    let hidden: Bool
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
