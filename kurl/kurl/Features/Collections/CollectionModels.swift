//
//  CollectionModels.swift
//  kurl
//
//  컬렉션(Are.na 채널) 프로토타입 — 목 데이터. 백엔드 엔티티/API 확정 전 화면으로 §0를
//  먼저 느껴보는 단계(docs/collections-design.md). connect not broadcast.
//

import SwiftUI

enum CollectionVisibility: Hashable {
    case `private`, unlisted, `public`

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

/// 연결 = (컬렉션 × 블록) 한 줄. `why` = 왜 연결했는지(큐레이터의 목소리, 선택).
struct ConnectionItem: Identifiable, Hashable {
    let id: Int64
    let block: ConnectionBlock
    let why: String?
    let curator: Author
}

struct CollectionSummary: Identifiable, Hashable {
    let id: Int64
    let title: String
    let blurb: String?
    let visibility: CollectionVisibility
    let curator: Author
    let items: [ConnectionItem]

    var count: Int { items.count }
}

// MARK: 목 데이터

/// 발견 = 큐레이터 연결 흐름의 한 이벤트. "누가 무엇을 어느 컬렉션에 이었나 + 왜."
struct ConnectionEvent: Identifiable, Hashable {
    let id: Int64
    let curator: Author
    let collectionTitle: String
    let collectionId: Int64
    let block: ConnectionBlock
    let why: String?
    let connectedAt: Date
}

enum CollectionsMock {
    static let hong = Author(id: 1, username: "honggildong", bio: nil, avatarUrl: nil)
    static let minji = Author(id: 2, username: "minji", bio: nil, avatarUrl: nil)
    static let sori = Author(id: 3, username: "sori", bio: nil, avatarUrl: nil)

    static var mine: [CollectionSummary] { [slowThinking, boundaries, reread] }

    /// 내가 따르는 큐레이터들이 최근 이은 것 — 발견 1차 표면(broadcast 아니라 큐레이션 흐름).
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

    static let slowThinking = CollectionSummary(
        id: 101,
        title: "느린 사고",
        blurb: "빨리 답하지 않고 오래 머문 글들.",
        visibility: .public,
        curator: hong,
        items: [
            ConnectionItem(
                id: 1,
                block: .highlight(
                    quote: "경계를 먼저 긋고, 구현은 그 바깥으로 민다.",
                    postTitle: "헥사고날로 갈아탄 지 석 달",
                    username: "honggildong", slug: "hexagonal-after-3-months"),
                why: "추상이 먼저가 아니라 경계가 먼저라는 한 문장. 여기서 시작.",
                curator: hong),
            ConnectionItem(
                id: 2,
                block: .post(
                    title: "토큰이 사라진 밤",
                    excerpt: "디자인 토큰을 지웠더니 오히려 화면이 선명해졌다. 덜어내기의 기록.",
                    username: "honggildong", slug: "the-night-tokens-vanished",
                    tags: ["디자인", "절제"]),
                why: "더 지울 게 없을 때 완성된다 — 느린 사고의 다른 얼굴.",
                curator: hong),
            ConnectionItem(
                id: 3,
                block: .note(body: "결정을 미루는 건 게으름이 아니라, 더 나은 질문을 기다리는 일일 때가 있다."),
                why: nil,
                curator: hong),
        ])

    static let boundaries = CollectionSummary(
        id: 102,
        title: "경계 긋기",
        blurb: "도메인·관계·코드에서 선을 긋는 법.",
        visibility: .private,
        curator: hong,
        items: [
            ConnectionItem(
                id: 11,
                block: .post(
                    title: "유리 위에 유리를 얹지 않기",
                    excerpt: "겹치는 순간 둘 다 탁해진다. 레이어는 하나씩.",
                    username: "honggildong", slug: "liquid-glass-without-glass-on-glass",
                    tags: ["iOS", "디자인"]),
                why: "레이어의 경계 = 관심사의 경계.",
                curator: hong),
            ConnectionItem(
                id: 12,
                block: .highlight(
                    quote: "포트와 어댑터 — 경계를 먼저 긋고 구현은 그 바깥으로.",
                    postTitle: "헥사고날로 갈아탄 지 석 달",
                    username: "honggildong", slug: "hexagonal-after-3-months"),
                why: nil,
                curator: hong),
        ])

    static let reread = CollectionSummary(
        id: 103,
        title: "다시 읽고 싶은",
        blurb: nil,
        visibility: .unlisted,
        curator: hong,
        items: [
            ConnectionItem(
                id: 21,
                block: .note(body: "좋은 글은 두 번째 읽을 때 다른 문장이 밑줄 쳐진다."),
                why: nil,
                curator: hong),
        ])
}
