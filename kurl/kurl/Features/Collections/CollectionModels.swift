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
    let count: Int

    private enum CodingKeys: String, CodingKey {
        case id, title, description, visibility, count
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        blurb = try c.decodeIfPresent(String.self, forKey: .description)
        let vis = try c.decode(String.self, forKey: .visibility)
        visibility = CollectionVisibility(rawValue: vis) ?? .private
        count = try c.decode(Int.self, forKey: .count)
    }

    /// 로컬 생성(낙관) — 새 컬렉션을 목록에 즉시 끼워 넣을 때.
    init(id: Int64, title: String, blurb: String?, visibility: CollectionVisibility, count: Int) {
        self.id = id
        self.title = title
        self.blurb = blurb
        self.visibility = visibility
        self.count = count
    }
}

/// 컬렉션 상세 — 헤더 + 연결된 블록들. 백엔드 `CollectionDetailView`.
struct CollectionDetail: Decodable, Identifiable, Hashable {
    let id: Int64
    let title: String
    let blurb: String?
    let visibility: CollectionVisibility
    let curatorUsername: String?
    let connections: [ConnectionItem]

    private enum CodingKeys: String, CodingKey {
        case id, title, description, visibility, curatorUsername, connections
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        blurb = try c.decodeIfPresent(String.self, forKey: .description)
        let vis = try c.decode(String.self, forKey: .visibility)
        visibility = CollectionVisibility(rawValue: vis) ?? .private
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
    let block: ConnectionBlock
    let why: String?
    let connectedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, curator, collectionId, collectionTitle, why, connectedAt
        case blockType, title, excerpt, slug, username, quote, body
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        curator = try c.decode(Author.self, forKey: .curator)
        collectionId = try c.decode(Int64.self, forKey: .collectionId)
        collectionTitle = try c.decode(String.self, forKey: .collectionTitle)
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
