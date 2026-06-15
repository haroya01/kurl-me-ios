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

// MARK: 발견 흐름 — 큐레이터 연결 이벤트 (Phase 2 백엔드, 현재 목)

/// 발견 = 큐레이터 연결 흐름의 한 이벤트. "누가 무엇을 어느 컬렉션에 이었나 + 왜."
/// 큐레이터 팔로우 발견 피드는 Phase 2라 아직 목 데이터로 흐른다.
struct ConnectionEvent: Identifiable, Hashable {
    let id: Int64
    let curator: Author
    let collectionTitle: String
    let collectionId: Int64
    let block: ConnectionBlock
    let why: String?
    let connectedAt: Date
}

/// 컬렉션 상세로 가는 내비 값 — id 만 들고 가서 상세에서 API 로 불러온다.
struct CollectionRef: Hashable {
    let id: Int64
}

enum CollectionsMock {
    static let hong = Author(id: 1, username: "honggildong", bio: nil, avatarUrl: nil)
    static let minji = Author(id: 2, username: "minji", bio: nil, avatarUrl: nil)
    static let sori = Author(id: 3, username: "sori", bio: nil, avatarUrl: nil)

    /// 내가 따르는 큐레이터들이 최근 이은 것 — 발견 1차 표면(Phase 2 백엔드 전까지 목).
    static var discoverFeed: [ConnectionEvent] {
        [
            ConnectionEvent(
                id: 1, curator: minji, collectionTitle: "느린 사고", collectionId: 101,
                block: .post(
                    title: "헥사고날로 갈아탄 지 석 달",
                    excerpt: "결론부터 적는다. 다시 돌아가라면 또 갈아탄다.",
                    username: "honggildong", slug: "hexagonal-after-3-months",
                    tags: ["아키텍처"]),
                why: "구현보다 경계를 먼저 세우는 사람의 기록. 두고두고 다시 본다.",
                connectedAt: Date(timeIntervalSinceNow: -3600)),
            ConnectionEvent(
                id: 2, curator: sori, collectionTitle: "오늘의 문장", collectionId: 201,
                block: .highlight(
                    quote: "좋은 추상은 더 지울 게 없을 때 완성된다.",
                    postTitle: "토큰이 사라진 밤",
                    username: "honggildong", slug: "the-night-tokens-vanished"),
                why: "덜어내기에 대해 이보다 정확한 한 줄을 못 봤다.",
                connectedAt: Date(timeIntervalSinceNow: -7200)),
            ConnectionEvent(
                id: 3, curator: minji, collectionTitle: "경계 긋기", collectionId: 102,
                block: .note(body: "결정을 미루는 건 게으름이 아니라, 더 나은 질문을 기다리는 일일 때가 있다."),
                why: nil,
                connectedAt: Date(timeIntervalSinceNow: -86_400)),
            ConnectionEvent(
                id: 4, curator: sori, collectionTitle: "다시 읽고 싶은", collectionId: 202,
                block: .post(
                    title: "유리 위에 유리를 얹지 않기",
                    excerpt: "겹치는 순간 둘 다 탁해진다. 레이어는 하나씩.",
                    username: "honggildong", slug: "liquid-glass-without-glass-on-glass",
                    tags: ["디자인"]),
                why: "레이어링을 관심사 분리로 읽어낸 글. 코드에도 그대로 적용된다.",
                connectedAt: Date(timeIntervalSinceNow: -172_800)),
        ]
    }
}
