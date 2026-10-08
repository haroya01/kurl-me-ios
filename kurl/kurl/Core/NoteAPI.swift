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
    static let maxPollOptions = 4
    static let maxPollOptionLength = 50

    private static let client = APIClient.shared

    private static var signedIn: Bool { AuthStore.shared.isSignedIn }

    static func everyone(page: Int = 0) async throws -> NoteFeed {
        try await client.get(
            "/public/notes", query: ["page": String(page), "size": "20"], authenticated: signedIn)
    }

    /// 마스토돈의 다른 서버 실시간 피드 — 이 서버가 받은 공개 노트, 최신순. 회원만.
    static func federated(page: Int = 0) async throws -> NoteFeed {
        try await client.get(
            "/notes/federated", query: ["page": String(page), "size": "20"], authenticated: true)
    }

    /// 마스토돈 트렌드 — 이번 주 여러 계정이 쓴 노트 해시태그와 7일 동안 날마다 쓰인 수.
    static func trendingTags() async throws -> [TrendingNoteTag] {
        try await client.get("/public/notes/trending-tags", authenticated: false)
    }

    static func trendingLinks() async throws -> [TrendingNoteLink] {
        try await client.get("/public/notes/trending-links", authenticated: false)
    }

    static func linked(_ url: String, page: Int = 0) async throws -> NoteFeed {
        try await client.get(
            "/public/notes/links", query: ["url": url, "page": String(page), "size": "20"],
            authenticated: signedIn)
    }

    static func trending(page: Int = 0) async throws -> NoteFeed {
        try await client.get(
            "/public/notes", query: ["sort": "trending", "page": String(page), "size": "20"],
            authenticated: signedIn)
    }

    static func remoteAccountNotes(id: Int64, page: Int = 0) async throws -> NoteFeed {
        try await client.get(
            "/federation/accounts/\(id)/notes", query: ["page": String(page), "size": "20"],
            authenticated: true)
    }

    static func bookmarks(page: Int = 0) async throws -> NoteFeed {
        try await client.get(
            "/notes/bookmarks", query: ["page": String(page), "size": "20"], authenticated: true)
    }

    static func postQuotes(_ postId: Int64, page: Int = 0) async throws -> PostQuotesPage {
        try await client.get(
            "/public/posts/\(postId)/quotes", query: ["page": String(page), "size": "20"],
            authenticated: signedIn)
    }

    static func quotes(of id: Int64, page: Int = 0) async throws -> NoteFeed {
        try await client.get(
            "/public/notes/\(id)/quotes", query: ["page": String(page), "size": "20"],
            authenticated: signedIn)
    }

    /// 이 노트를 카드로 실은 공개 블로그 글, 최근 발행 순.
    static func quotingPosts(of id: Int64, page: Int = 0) async throws -> PublicFeedView {
        try await client.get("/public/notes/\(id)/posts", query: ["page": String(page)], authenticated: false)
    }

    static func tagged(_ tag: String, page: Int = 0) async throws -> NoteFeed {
        try await client.get(
            "/public/notes/tags/\(tag)", query: ["page": String(page), "size": "20"],
            authenticated: signedIn)
    }

    static func search(_ query: String, page: Int = 0) async throws -> NoteFeed {
        try await client.get(
            "/public/notes/search", query: ["q": query, "page": String(page), "size": "20"],
            authenticated: signedIn)
    }

    static func lists() async throws -> [NoteListSummary] {
        try await client.get("/notes/lists", authenticated: true)
    }

    static func createList(title: String) async throws -> NoteListSummary {
        try await client.post("/notes/lists", body: NoteListTitle(title: title), authenticated: true)
    }

    static func renameList(id: Int64, title: String) async throws -> NoteListSummary {
        try await client.patch("/notes/lists/\(id)", body: NoteListTitle(title: title), authenticated: true)
    }

    static func deleteList(id: Int64) async throws {
        try await client.deleteVoid("/notes/lists/\(id)", authenticated: true)
    }

    static func listMembers(id: Int64) async throws -> [Author] {
        try await client.get("/notes/lists/\(id)/members", authenticated: true)
    }

    static func setListMember(id: Int64, username: String, on: Bool) async throws {
        if on {
            try await client.putVoid("/notes/lists/\(id)/members/\(username)", authenticated: true)
        } else {
            try await client.deleteVoid("/notes/lists/\(id)/members/\(username)", authenticated: true)
        }
    }

    static func listNotes(id: Int64, page: Int = 0) async throws -> NoteFeed {
        try await client.get(
            "/notes/lists/\(id)/notes", query: ["page": String(page), "size": "20"], authenticated: true)
    }

    static func listMemberships(username: String) async throws -> NoteListMembership {
        try await client.get("/notes/list-memberships/\(username)", authenticated: true)
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

    /// 한 번에 올리는 스레드의 노트 수 상한(서버와 같은 값).
    static let maxThreadNotes = 10

    /// 이어 쓴 노트들을 한 번에 — 서버가 한 트랜잭션에서 앞 노트의 답글로 잇는다(전부 또는 하나도 없이).
    static func createThread(_ drafts: [NoteDraft]) async throws -> [Note] {
        struct Body: Encodable { let notes: [NoteDraft] }
        return try await client.post("/notes/threads", body: Body(notes: drafts), authenticated: true)
    }

    static func create(_ draft: NoteDraft) async throws -> Note {
        try await client.post("/notes", body: draft, authenticated: true)
    }

    static func schedule(_ draft: NoteDraft, at: Date) async throws -> ScheduledNote {
        struct Body: Encodable {
            let note: NoteDraft
            let scheduledAt: String
        }
        return try await client.post(
            "/notes/scheduled", body: Body(note: draft, scheduledAt: iso(at)), authenticated: true)
    }

    static func scheduled() async throws -> [ScheduledNote] {
        try await client.get("/notes/scheduled", authenticated: true)
    }

    static func reschedule(id: Int64, at: Date) async throws -> ScheduledNote {
        struct Body: Encodable { let scheduledAt: String }
        return try await client.patch(
            "/notes/scheduled/\(id)", body: Body(scheduledAt: iso(at)), authenticated: true)
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static func cancelScheduled(id: Int64) async throws {
        try await client.deleteVoid("/notes/scheduled/\(id)", authenticated: true)
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

    static func filters() async throws -> [NoteFilter] {
        try await client.get("/notes/filters", authenticated: true)
    }

    static func createFilter(_ draft: NoteFilterDraft) async throws -> NoteFilter {
        try await client.post("/notes/filters", body: draft, authenticated: true)
    }

    static func updateFilter(id: Int64, _ draft: NoteFilterDraft) async throws -> NoteFilter {
        try await client.put("/notes/filters/\(id)", body: draft, authenticated: true)
    }

    static func deleteFilter(id: Int64) async throws {
        try await client.deleteVoid("/notes/filters/\(id)", authenticated: true)
    }

    static func vote(id: Int64, choices: [Int]) async throws -> NotePoll {
        struct Body: Encodable { let choices: [Int] }
        return try await client.post("/notes/\(id)/poll/votes", body: Body(choices: choices), authenticated: true)
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

    static func setConversationMuted(id: Int64, on: Bool) async throws -> NoteConversationMuteStatus {
        on
            ? try await client.put("/notes/\(id)/conversation-mute", body: EmptyBody(), authenticated: true)
            : try await client.delete("/notes/\(id)/conversation-mute", authenticated: true)
    }

    static func feedPreferences() async throws -> NoteFeedPreferencesBody {
        try await client.get("/notes/feed-preferences", authenticated: true)
    }

    static func setLanguages(_ codes: [String]) async throws -> NoteFeedPreferencesBody {
        try await client.put(
            "/notes/feed-preferences", body: NoteFeedPreferencesBody(languages: codes),
            authenticated: true)
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
    var width: Int?
    var height: Int?

    /// 원본 비율 — 피드 타일이 이미지가 오기 전부터 제 모양으로 자리를 잡는다. 극단 비율은 잘라 쓴다.
    var ratio: CGFloat? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return min(max(CGFloat(width) / CGFloat(height), 0.5), 2)
    }
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
    var poll: NotePoll? = nil
    /// 이 노트가 든 대화의 알림을 껐다(마스토돈 대화 뮤트). 비로그인 읽기면 nil.
    var conversationMuted: Bool? = nil
    /// 작성자가 고른 언어(ISO 639-1). 정하지 않은 노트·다른 서버가 안 알려 준 노트는 nil.
    var language: String? = nil
    /// 피드에서 작성자가 이어 쓴 노트 — 전체 편 수와 바로 아래에 보일 다음 편.
    var thread: NoteSelfThread? = nil

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
        case .unlisted: "누구나 볼 수 있지만 최신·인기·태그에는 안 나와요"
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

/// 마스토돈 투표. 수는 공개이고, 작성자는 voted = true로 와서 결과만 본다.
struct NotePoll: Decodable, Hashable {
    struct Option: Decodable, Hashable {
        let title: String
        let votesCount: Int64
    }

    let expiresAt: Date?
    let expired: Bool
    let multiple: Bool
    let votesCount: Int64
    let votersCount: Int64
    let options: [Option]
    let voted: Bool?
    let ownVotes: [Int]?

    func share(of option: Option) -> Double {
        let base = multiple ? votersCount : votesCount
        return base > 0 ? Double(option.votesCount) / Double(base) : 0
    }
}

struct NoteFilter: Decodable, Identifiable, Hashable {
    let id: Int64
    let phrase: String
    let wholeWord: Bool
    let context: [String]
    let action: String
    let expiresAt: Date?
}

struct NoteFilterDraft: Encodable {
    let phrase: String
    let wholeWord: Bool
    let context: [String]
    let action: String
    let expiresIn: Int?
}

struct NoteFeed: Decodable {
    let items: [Note]
    let page: Int
    let hasNext: Bool
}

struct PostQuotesPage: Decodable {
    let items: [Note]
    let page: Int
    let hasNext: Bool
    let total: Int
}

struct TrendingNoteTag: Decodable, Hashable, Identifiable {
    let tag: String
    let accounts: Int
    let uses: Int
    let history: [Int]

    var id: String { tag }
}

struct TrendingNoteLink: Decodable, Hashable, Identifiable {
    let url: String
    let title: String?
    let description: String?
    let imageUrl: String?
    let accounts: Int
    let uses: Int
    let history: [Int]

    var id: String { url }

    var host: String {
        guard let host = URL(string: url)?.host() else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

struct NoteSelfThread: Decodable, Hashable {
    let total: Int
    let preview: [Note]
}

struct NoteThread: Decodable {
    let note: Note
    let parent: Note?
    let replies: [Note]
    /// 작성자가 이 노트 아래로 이어 쓴 노트들(순서대로). replies 에는 남의 답글만 남는다.
    var continuation: [Note]? = nil
}

struct NoteDraft: Encodable {
    struct Image: Encodable {
        let key: String
        let altText: String
        var width: Int?
        var height: Int?
    }

    let body: String
    let images: [Image]
    let quotedPostId: Int64?
    let inReplyToId: Int64?
    var quotedNoteId: Int64? = nil
    var contentWarning: String? = nil
    var sensitive: Bool = false
    var visibility: String? = nil
    var poll: Poll? = nil
    var language: String? = nil

    struct Poll: Encodable {
        let options: [String]
        let expiresIn: Int
        let multiple: Bool
    }
}

/// 마스토돈의 예약 노트 — 쓴 그대로 두었다가 그 시각에 올린다. failure 가 있으면 올리지 못한 이유.
struct ScheduledNote: Decodable, Identifiable, Hashable {
    let id: Int64
    let scheduledAt: Date
    let body: String?
    let contentWarning: String?
    let visibility: String?
    let imageCount: Int
    let poll: Bool
    let inReplyToId: Int64?
    let quotedNoteId: Int64?
    let quotedPostId: Int64?
    let failure: String?
}

struct NoteLikeStatus: Decodable {
    let liked: Bool
    let likeCount: Int64
}

struct NoteBookmarkStatus: Decodable {
    let bookmarked: Bool
}

struct NoteConversationMuteStatus: Decodable {
    let muted: Bool
}

struct NotePinStatus: Decodable {
    let pinned: Bool
}

struct NoteListSummary: Decodable, Hashable, Identifiable {
    let id: Int64
    var title: String
    var memberCount: Int64
}

struct NoteListTitle: Encodable {
    let title: String
}

struct NoteListMembership: Decodable {
    let listIds: [Int64]
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

/// 비운 칸은 보내지 않는다 — 한쪽 설정만 바꿀 수 있게.
struct NoteFeedPreferencesBody: Codable {
    var showReposts: Bool? = nil
    /// 모든 노트·인기에 보일 언어. 비면 모든 언어.
    var languages: [String]? = nil
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
