//
//  CollectionModels.swift
//  kurl
//
//  컬렉션(Are.na 채널) — 읽기의 연결 그래프(§0). 백엔드 `post.collection` 슬라이스와 1:1.
//  글·하이라이트·노트를 주제 채널에 "연결". connect not broadcast(docs/collections-design.md).
//

import SwiftUI

enum CollectionVisibility: String, Hashable {
    case `private` = "PRIVATE"
    case unlisted = "UNLISTED"
    case `public` = "PUBLIC"

    var label: LocalizedStringKey {
        switch self {
        case .private: "비공개"
        case .unlisted: "링크 공유"
        case .public: "공개"
        }
    }
    var icon: String {
        switch self {
        case .private: "lock"
        case .unlisted: "link"
        case .public: "globe"
        }
    }
}

/// 컬렉션 종류 — collection(주제 묶음) | path(순서로 엮은 reading path, A 척추). path 는 리스트가 아니라
/// 가이드 워크(문장→왜→문장)로 읽는다. 백엔드 `CollectionKind` 와 같은 와이어 값.
enum CollectionKind: String, Hashable, Encodable {
    case collection = "COLLECTION"
    case path = "PATH"
}

/// 컬렉션에 "연결"된 한 블록 — 글·하이라이트·노트. 같은 것이 여러 컬렉션에 걸릴 수 있다.
enum ConnectionBlock: Hashable {
    case post(title: String, excerpt: String, username: String, slug: String, tags: [String])
    case highlight(quote: String, postTitle: String, username: String, slug: String)
    case note(body: String)

    var kindLabel: LocalizedStringKey {
        switch self {
        case .post: "글"
        case .highlight: "하이라이트"
        case .note: "노트"
        }
    }
}

/// 블록 종류 — 연결 요청 시 백엔드 `ConnectionBlockType` 와 같은 와이어 값.
enum ConnectionBlockKind: String, Encodable {
    case post = "POST"
    case highlight = "HIGHLIGHT"
    case note = "NOTE"
}

/// 연결 = (컬렉션 × 블록) 한 줄. `why` = 왜 연결했는지(큐레이터의 목소리, 선택).
/// 백엔드 `ConnectionView`(평면)를 블록 enum 으로 접어 디코드한다.
struct ConnectionItem: Decodable, Identifiable, Hashable {
    let id: Int64
    let block: ConnectionBlock
    let why: String?

    private enum CodingKeys: String, CodingKey {
        case id, blockType, why, title, excerpt, slug, username, quote, body
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        why = try c.decodeIfPresent(String.self, forKey: .why)
        let type = try c.decode(String.self, forKey: .blockType)
        let title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        let username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        let slug = try c.decodeIfPresent(String.self, forKey: .slug) ?? ""
        switch type {
        case "POST":
            block = .post(
                title: title,
                excerpt: try c.decodeIfPresent(String.self, forKey: .excerpt) ?? "",
                username: username, slug: slug, tags: [])
        case "HIGHLIGHT":
            block = .highlight(
                quote: try c.decodeIfPresent(String.self, forKey: .quote) ?? "",
                postTitle: title, username: username, slug: slug)
        default:  // NOTE
            block = .note(body: try c.decodeIfPresent(String.self, forKey: .body) ?? "")
        }
    }
}

/// 컬렉션 목록 한 줄 — 제목·소개·공개범위·담긴 수만(허영 지표 없음, §0). 백엔드 `CollectionSummaryView`.
struct CollectionSummary: Decodable, Identifiable, Hashable {
    let id: Int64
    let title: String
    let blurb: String?
    let visibility: CollectionVisibility
    let kind: CollectionKind
    let count: Int
    /// 최근 담긴 항목 라벨 몇 개 — "안에 뭐가 들었는지" 떠올리게(어디 넣을지 결정 보조).
    let preview: [String]
    /// "이 글이 놓인 길"(PostEdges)의 리치 소속 — 이 길을 엮은 큐레이터 · 이 글이 그 안에서 몇 번째(position)
    /// / 전체 몇 편(total). 글 단위 소속 응답(#607)에만 오고, 다른 목록 표면엔 없어 nil 로 조용히 빠진다.
    let curatorUsername: String?
    /// 이 글이 길 안에서 몇 번째인가(1부터). total 과 함께 "N of M"으로 읽힌다. 없으면 count 폴백.
    let position: Int?
    /// 이 길의 전체 편 수. count(담긴 수)와 같을 수 있으나, position 과 짝지어 순서 맥락을 준다.
    let total: Int?

    private enum CodingKeys: String, CodingKey {
        case id, title, description, visibility, kind, count, preview
        case curatorUsername, position, total
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        blurb = try c.decodeIfPresent(String.self, forKey: .description)
        let vis = try c.decode(String.self, forKey: .visibility)
        visibility = CollectionVisibility(rawValue: vis) ?? .private
        kind = CollectionKind(rawValue: try c.decodeIfPresent(String.self, forKey: .kind) ?? "")
            ?? .collection
        count = try c.decode(Int.self, forKey: .count)
        preview = try c.decodeIfPresent([String].self, forKey: .preview) ?? []
        curatorUsername = try c.decodeIfPresent(String.self, forKey: .curatorUsername)
        position = try c.decodeIfPresent(Int.self, forKey: .position)
        total = try c.decodeIfPresent(Int.self, forKey: .total)
    }

    /// 로컬 생성(낙관) — 새 컬렉션을 목록에 즉시 끼워 넣을 때.
    init(
        id: Int64, title: String, blurb: String?, visibility: CollectionVisibility,
        kind: CollectionKind = .collection, count: Int
    ) {
        self.id = id
        self.title = title
        self.blurb = blurb
        self.visibility = visibility
        self.kind = kind
        self.count = count
        self.preview = []
        self.curatorUsername = nil
        self.position = nil
        self.total = nil
    }
}

/// "이 글이 담긴 곳" — 한 글(postId)이 속한 공개 컬렉션들. 피드 카드 아래 소속 한 올이 읽는다.
/// 배치 응답 `[{ postId, collections }]` 의 한 줄 — 컬렉션은 `CollectionSummary` 와 같은 와이어(updatedAt 은
/// 무시). 담긴 곳 없으면 `collections` 는 빈 배열(그러면 카드에 소속 줄이 서지 않는다).
struct PostCollections: Decodable, Identifiable, Hashable {
    let postId: Int64
    let collections: [CollectionSummary]

    var id: Int64 { postId }

    private enum CodingKeys: String, CodingKey {
        case postId, collections
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        postId = try c.decode(Int64.self, forKey: .postId)
        collections = try c.decodeIfPresent([CollectionSummary].self, forKey: .collections) ?? []
    }
}

/// 컬렉션 상세 — 헤더 + 연결된 블록들. 백엔드 `CollectionDetailView`.
struct CollectionDetail: Decodable, Identifiable, Hashable {
    let id: Int64
    let title: String
    let blurb: String?
    let visibility: CollectionVisibility
    let kind: CollectionKind
    let curatorUsername: String?
    let connections: [ConnectionItem]

    private enum CodingKeys: String, CodingKey {
        case id, title, description, visibility, kind, curatorUsername, connections
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        blurb = try c.decodeIfPresent(String.self, forKey: .description)
        let vis = try c.decode(String.self, forKey: .visibility)
        visibility = CollectionVisibility(rawValue: vis) ?? .private
        kind = CollectionKind(rawValue: try c.decodeIfPresent(String.self, forKey: .kind) ?? "")
            ?? .collection
        curatorUsername = try c.decodeIfPresent(String.self, forKey: .curatorUsername)
        connections = try c.decodeIfPresent([ConnectionItem].self, forKey: .connections) ?? []
    }
}

// MARK: 발견 흐름 — 큐레이터 연결 이벤트

/// 발견 = 큐레이터 연결 흐름의 한 이벤트. "누가 무엇을 어느 컬렉션에 이었나 + 왜."
/// 백엔드 `DiscoverConnectionView`(평면) — curator 는 중첩, 블록은 평면 필드를 enum 으로 접는다.
struct ConnectionEvent: Decodable, Identifiable, Hashable {
    let id: Int64
    let curator: Author
    let collectionTitle: String
    let collectionId: Int64
    let collectionKind: CollectionKind
    let block: ConnectionBlock
    let why: String?
    let connectedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, curator, collectionId, collectionTitle, collectionKind, why, connectedAt
        case blockType, title, excerpt, slug, username, quote, body
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        curator = try c.decode(Author.self, forKey: .curator)
        collectionId = try c.decode(Int64.self, forKey: .collectionId)
        collectionTitle = try c.decode(String.self, forKey: .collectionTitle)
        collectionKind = CollectionKind(
            rawValue: try c.decodeIfPresent(String.self, forKey: .collectionKind) ?? "")
            ?? .collection
        why = try c.decodeIfPresent(String.self, forKey: .why)
        connectedAt = try c.decodeIfPresent(Date.self, forKey: .connectedAt)
        let type = try c.decode(String.self, forKey: .blockType)
        let title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        let username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        let slug = try c.decodeIfPresent(String.self, forKey: .slug) ?? ""
        switch type {
        case "POST":
            block = .post(
                title: title,
                excerpt: try c.decodeIfPresent(String.self, forKey: .excerpt) ?? "",
                username: username, slug: slug, tags: [])
        case "HIGHLIGHT":
            block = .highlight(
                quote: try c.decodeIfPresent(String.self, forKey: .quote) ?? "",
                postTitle: title, username: username, slug: slug)
        default:  // NOTE
            block = .note(body: try c.decodeIfPresent(String.self, forKey: .body) ?? "")
        }
    }
}

/// 발견 피드 한 페이지 — 백엔드 `DiscoverFeedView`.
struct DiscoverFeedResponse: Decodable {
    let items: [ConnectionEvent]
    let hasNext: Bool
}

/// 컬렉션 상세로 가는 내비 값 — id 만 들고 가서 상세에서 API 로 불러온다.
struct CollectionRef: Hashable {
    let id: Int64
}

// MARK: 큐레이션 그래프 — 공동 등장 + 취향 겹침

/// "이것과 이어진 것" — 같은 공개 컬렉션에 함께 놓인 다른 블록(자기 제외). 백엔드 `RelatedBlockView`.
/// `sharedCount` = 함께 놓인 공개 컬렉션 수(사람이 손으로 엮은 공동 등장 가중치). 평면 블록 필드를
/// `ConnectionBlock` enum 으로 접어 디코드한다(ConnectionItem 과 같은 결).
struct RelatedBlock: Decodable, Identifiable, Hashable {
    let block: ConnectionBlock
    let blockType: String
    let refId: Int64
    let sharedCount: Int

    var id: String { "\(blockType)_\(refId)" }

    private enum CodingKeys: String, CodingKey {
        case blockType, refId, title, excerpt, slug, username, quote, body, sharedCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blockType = try c.decode(String.self, forKey: .blockType)
        refId = try c.decode(Int64.self, forKey: .refId)
        sharedCount = try c.decodeIfPresent(Int.self, forKey: .sharedCount) ?? 0
        let title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        let username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        let slug = try c.decodeIfPresent(String.self, forKey: .slug) ?? ""
        switch blockType {
        case "POST":
            block = .post(
                title: title,
                excerpt: try c.decodeIfPresent(String.self, forKey: .excerpt) ?? "",
                username: username, slug: slug, tags: [])
        case "HIGHLIGHT":
            block = .highlight(
                quote: try c.decodeIfPresent(String.self, forKey: .quote) ?? "",
                postTitle: title, username: username, slug: slug)
        default:  // NOTE
            block = .note(body: try c.decodeIfPresent(String.self, forKey: .body) ?? "")
        }
    }
}

/// "취향이 겹치는 큐레이터" — 같은 블록을 자기 공개 컬렉션에도 엮은 다른 큐레이터. `sharedItems` = 겹치는
/// 블록 수. 팔로우가 아니라 *무엇을 엮었나* 로 잇는 발견(connect not broadcast). 백엔드 `KindredCuratorView`.
struct KindredCurator: Decodable, Identifiable, Hashable {
    let curator: Author
    let sharedItems: Int

    var id: Int64 { curator.id }
}
