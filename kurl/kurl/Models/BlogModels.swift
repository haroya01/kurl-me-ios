//
//  BlogModels.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import Foundation

// MARK: 작가

struct Author: Decodable, Hashable, Identifiable {
    let id: Int64
    let username: String
    let bio: String?
    let avatarUrl: String?
    var displayName: String? = nil
    /// 다른 서버 계정 — username 자리에 아이디@서버가 오고, id 는 음수다(회원 id 와 겹치지 않게).
    var remoteId: Int64? = nil
    var url: String? = nil

    var isRemote: Bool { remoteId != nil }

    var shownName: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if isRemote, let local = username.split(separator: "@").first { return String(local) }
        return username
    }

    var hasDisplayName: Bool { !(displayName ?? "").isEmpty }

    /// 노트 행에서 이 사람에게 가는 길 — 회원은 노트 탭, 다른 서버 계정은 그 계정 화면.
    var notesRoute: Route {
        if let remoteId { return .remoteAccount(id: remoteId) }
        return .authorNotes(username: username)
    }
}

struct SuggestedAuthor: Decodable, Identifiable {
    let author: Author
    let postCount: Int

    var id: Int64 { author.id }
}

// MARK: 글

/// 전역 피드 카드. (/public/posts)
struct FeedItem: Decodable, Hashable, Identifiable {
    let id: Int64
    let author: Author
    let slug: String
    let title: String
    let excerpt: String?
    let ogImageUrl: String?
    let languageTag: String?
    let tags: [String]
    let publishedAt: Date?
    let viewCount: Int64
    let likeCount: Int64
}

struct PublicFeedView: Decodable {
    let items: [FeedItem]
    let page: Int
    let size: Int
    let hasNext: Bool
    /// 구독함 페이지에 걸린 구독 시리즈의 노트 — 글 사이에 시각으로 끼운다. 다른 피드·옛 서버는 nil.
    var seriesNotes: [FeedSeriesNote]? = nil
}

/// 구독한 시리즈에 들어온 노트 한 편(구독함 전용). 본문 대신 발췌·경고만 카드에 쓴다.
struct FeedSeriesNote: Decodable, Hashable, Identifiable {
    let id: Int64
    let author: Author
    let body: String
    let contentWarning: String?
    let excerpt: String
    let createdAt: Date?
    let series: Ref

    struct Ref: Decodable, Hashable {
        let id: Int64
        let slug: String
        let title: String
    }
}

/// 작가 글 목록/상세 헤더 아이템.
struct PostListItem: Decodable, Hashable, Identifiable {
    let id: Int64
    let slug: String
    let title: String
    let excerpt: String?
    let ogImageUrl: String?
    let languageTag: String?
    let tags: [String]
    let likeCount: Int64
    let publishedAt: Date?
    let lastEditedAt: Date?
    let pinned: Bool

    func withTitle(_ title: String) -> PostListItem {
        PostListItem(
            id: id, slug: slug, title: title, excerpt: excerpt, ogImageUrl: ogImageUrl, languageTag: languageTag,
            tags: tags, likeCount: likeCount, publishedAt: publishedAt, lastEditedAt: lastEditedAt, pinned: pinned)
    }
}

struct PublicPostListView: Decodable {
    let author: Author
    let posts: [PostListItem]
    /// 보는 사람과 작가 사이의 차단 — 어느 쪽이든 서버는 글 목록을 비워 보낸다. 익명·옛 서버는 없음(nil).
    let blockedByViewer: Bool?
    let blocksViewer: Bool?
}

// MARK: 글 상세 + 블록

struct PublicPostDetail: Decodable {
    let author: Author
    let post: PostListItem
    let blocks: [PostBlock]
    let series: PostSeriesNav?

    private enum CodingKeys: String, CodingKey {
        case author, post, blocks, series
    }

    init(author: Author, post: PostListItem, blocks: [PostBlock], series: PostSeriesNav?) {
        self.author = author
        self.post = post
        self.blocks = blocks
        self.series = series
    }

    func replacing(title: String, blocks: [PostBlock]) -> PublicPostDetail {
        PublicPostDetail(author: author, post: post.withTitle(title), blocks: blocks, series: series)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        author = try container.decode(Author.self, forKey: .author)
        post = try container.decode(PostListItem.self, forKey: .post)
        series = try container.decodeIfPresent(PostSeriesNav.self, forKey: .series)
        // 디코드 순서를 안정 식별자로 못박는다 — blockOrder 가 nil 이어도 id 가 매 렌더 흔들리지 않게.
        let raw = try container.decode([PostBlock].self, forKey: .blocks)
        blocks = raw.enumerated().map { index, block in
            block.withDecodeIndex(index)
        }
    }
}

struct PostBlock: Decodable, Identifiable {
    let type: String
    private(set) var content: String?
    let blockOrder: Int?
    let cta: CtaInfo?
    /// 디코드 시점에 배열 인덱스로 박는 안정 식별자. blockOrder 가 nil 이어도 TOC 점프·딥링크가 안 깨진다.
    private(set) var decodeIndex: Int = 0

    private enum CodingKeys: String, CodingKey {
        case type, content, blockOrder, cta
    }

    var id: Int { blockOrder ?? decodeIndex }
    var kind: BlockKind { BlockKind(rawValue: type) ?? .unknown }

    func withDecodeIndex(_ index: Int) -> PostBlock {
        var copy = self
        copy.decodeIndex = index
        return copy
    }

    func withContent(_ content: String) -> PostBlock {
        var copy = self
        copy.content = content
        return copy
    }
}

struct CtaInfo: Decodable, Hashable {
    let label: String
    let url: String
    let style: String?
    let purpose: String?
    let deleted: Bool
}

enum BlockKind: String {
    case paragraph = "PARAGRAPH"
    case h1 = "H1"
    case h2 = "H2"
    case h3 = "H3"
    case image = "IMAGE"
    case ctaRef = "CTA_REF"
    case divider = "DIVIDER"
    case quote = "QUOTE"
    case listBullet = "LIST_BULLET"
    case listNumbered = "LIST_NUMBERED"
    case embed = "EMBED"
    case code = "CODE"
    case table = "TABLE"
    case unknown
}

struct PostSeriesNav: Decodable, Hashable {
    let slug: String
    let title: String
    let position: Int
    let total: Int
    let prev: NavLink?
    let next: NavLink?
    /// 글·노트를 함께 센 자리(서버가 노트를 담기 시작한 뒤). 없으면 글만 센 위 필드로 폴백.
    var itemPosition: Int? = nil
    var itemTotal: Int? = nil
    var prevItem: SeriesItemLink? = nil
    var nextItem: SeriesItemLink? = nil

    struct NavLink: Decodable, Hashable {
        let slug: String
        let title: String
    }

    /// 배너·다음 편 카드가 읽는 한 모양 — 글과 노트를 함께 걷는다.
    var trail: SeriesTrail {
        SeriesTrail(
            slug: slug, title: title,
            position: itemPosition ?? position, total: itemTotal ?? total,
            prev: prevItem ?? prev.map { SeriesItemLink(post: $0.slug, title: $0.title) },
            next: nextItem ?? next.map { SeriesItemLink(post: $0.slug, title: $0.title) })
    }
}

/// 시리즈의 이웃 한 편 — 글은 slug 로, 노트는 id 로 연다.
struct SeriesItemLink: Decodable, Hashable {
    let type: String
    let slug: String?
    let noteId: Int64?
    let title: String

    init(post slug: String, title: String) {
        type = "POST"
        self.slug = slug
        noteId = nil
        self.title = title
    }

    var isNote: Bool { type == "NOTE" }

    func route(username: String) -> Route? {
        if isNote, let noteId { return .note(id: noteId) }
        if let slug { return .post(username: username, slug: slug) }
        return nil
    }
}

/// 글·노트 공통의 시리즈 내 위치(배너·다음 편 카드). 노트 상세는 서버가 이 모양 그대로 준다.
struct SeriesTrail: Decodable, Hashable {
    let slug: String
    let title: String
    let position: Int
    let total: Int
    let prev: SeriesItemLink?
    let next: SeriesItemLink?
}

// MARK: 시리즈

struct SeriesPostRef: Decodable, Hashable {
    let slug: String
    let title: String
    /// 에피소드 커버(있으면 시리즈 카드가 사진 변형으로 그린다). 백엔드가 안 주면 nil → 종이 변형.
    let ogImageUrl: String?
}

struct PublicSeriesCard: Decodable, Identifiable {
    let id: Int64
    let author: Author?
    let slug: String
    let title: String
    let postCount: Int
    let lastPublishedAt: Date?
    let posts: [SeriesPostRef]
    /// 글·노트 함께(서버가 노트를 담기 시작한 뒤). 옛 서버면 nil → 글만으로 폴백.
    var itemCount: Int? = nil
    var items: [SeriesItemPreview]? = nil

    var episodeCount: Int { itemCount ?? postCount }
}

/// 시리즈 카드의 한 편 미리보기 — 노트는 커버 없이 발췌가 제목 자리에 온다.
struct SeriesItemPreview: Decodable, Hashable {
    let type: String
    let slug: String?
    let noteId: Int64?
    let title: String
    let ogImageUrl: String?

    var isNote: Bool { type == "NOTE" }
}

struct SeriesListItem: Decodable, Hashable, Identifiable {
    let id: Int64
    let slug: String
    let title: String
    let postCount: Int
    let tags: [String]
    var itemCount: Int? = nil

    var episodeCount: Int { itemCount ?? postCount }
}

struct PublicSeriesListView: Decodable {
    let author: Author
    let series: [SeriesListItem]
}

struct PublicSeriesDetail: Decodable {
    let author: Author
    let series: SeriesListItem
    let posts: [PostListItem]
    /// 글·노트 혼합 목차(서버가 노트를 담기 시작한 뒤). 옛 서버면 nil → posts 로 폴백.
    var items: [PublicSeriesItem]? = nil

    var entries: [SeriesEntry] {
        guard let items else { return posts.map(SeriesEntry.post) }
        return items.compactMap { item in
            if let post = item.post { return .post(post) }
            if let note = item.note { return .note(note) }
            return nil
        }
    }
}

struct PublicSeriesItem: Decodable {
    let type: String
    let post: PostListItem?
    let note: SeriesNoteSummary?
}

struct SeriesNoteSummary: Decodable, Hashable {
    let id: Int64
    let body: String
    let contentWarning: String?
    let excerpt: String
    let createdAt: Date?
}

/// 시리즈 목차의 한 편 — 글 또는 노트.
enum SeriesEntry: Hashable, Identifiable {
    case post(PostListItem)
    case note(SeriesNoteSummary)

    var id: String {
        switch self {
        case .post(let post): "post-\(post.id)"
        case .note(let note): "note-\(note.id)"
        }
    }

    var title: String {
        switch self {
        case .post(let post): post.title
        case .note(let note): note.excerpt
        }
    }

    func route(username: String) -> Route {
        switch self {
        case .post(let post): .post(username: username, slug: post.slug)
        case .note(let note): .note(id: note.id)
        }
    }

    var date: Date? {
        switch self {
        case .post(let post): post.publishedAt
        case .note(let note): note.createdAt
        }
    }

    var isNoteEntry: Bool {
        if case .note = self { return true }
        return false
    }

    var isRead: Bool {
        switch self {
        case .post(let post): PostReadStore.shared.isRead(post.id)
        case .note(let note): PostReadStore.notes.isRead(note.id)
        }
    }
}

// MARK: 발견 / 태그 / 댓글

struct TagCount: Decodable, Identifiable {
    let tag: String
    let count: Int64

    var id: String { tag }
}

struct TrendingTagSection: Decodable, Identifiable {
    let tag: String
    let postCount: Int64
    let posts: [FeedItem]

    var id: String { tag }
}

struct Comment: Decodable, Identifiable, Equatable {
    let id: Int64
    let parentId: Int64?
    let author: Author
    let body: String
    let createdAt: Date?
    let likeCount: Int64?
    var mentions: [String]? = nil
}
