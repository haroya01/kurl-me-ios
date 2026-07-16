//
//  CollectionsAPI.swift
//  kurl
//
//  컬렉션(연결 그래프) — 백엔드 `CollectionController` 와 1:1. 전부 인증 면(내 큐레이션).
//

import Foundation

enum CollectionsAPI {
    private static let client = APIClient.shared

    /// 내 컬렉션 목록(최근 손댄 순). blockType·refId 를 주면 "이 블록을 어디에 남길까"를 물으며 부르는
    /// 것으로, 각 컬렉션에 그 블록이 이미 연결돼 있으면 connectionId 가 채워져 온다("연결됨" 표시·해제용).
    static func mine(blockType: ConnectionBlockKind? = nil, refId: Int64? = nil)
        async throws -> [CollectionSummary]
    {
        var query: [String: String?] = [:]
        if let blockType, let refId {
            query["blockType"] = blockType.rawValue
            query["refId"] = String(refId)
        }
        return try await client.get("/users/me/collections", query: query, authenticated: true)
    }

    /// 한 큐레이터의 공개 컬렉션 목록(최근 손댄 순) — 남의 프로필에서 엮은 길들을 본다. 미로그인도 본다.
    static func publicByUsername(_ username: String) async throws -> [CollectionSummary] {
        try await client.get("/public/profiles/\(username)/collections")
    }

    /// 발견 — 내가 팔로우한 큐레이터들의 공개 컬렉션 연결 흐름(최신순). 로그인했지만 팔로우 0/활동
    /// 0이면 서버가 전역 공개 흐름으로 폴백해 `source: "global"` 로 내려준다(빈 배열 대신). 폴백이
    /// 활성이면(page 0 source=global) 이후 요청에 `scope=global` 을 고정해 개인화 페이지와 안 섞이게 한다.
    static func discoverFeed(scope: DiscoverScope? = nil) async throws -> DiscoverFeedResponse {
        var query: [String: String?] = [:]
        if scope == .global { query["scope"] = "global" }
        return try await client.get("/feed/connections", query: query, authenticated: true)
    }

    /// 공개 연결 흐름 — 비로그인 첫 피드에 인터리브할 최근 공개 연결(누가 무엇을 어느 컬렉션에 이었나).
    /// 게이트 없는 공개 엔드포인트라 미로그인도 본다. 실패는 호출측에서 빈 배열로 조용히 흡수한다(피드를 막지 않게).
    static func publicConnectionFeed(page: Int = 0, size: Int = 6) async throws -> [ConnectionEvent] {
        let view: DiscoverFeedResponse = try await client.get(
            "/public/feed/connections",
            query: ["page": String(page), "size": String(size)])
        return view.items
    }

    /// "이 글이 담긴 곳" — 여러 글의 소속 공개 컬렉션을 한 번에(피드 카드 아래 소속 한 올). 게이트 없는
    /// 공개 표면(미로그인도 본다). 상한 50 — 보이는 카드 id 를 모아 한 요청으로 긁는다(per-card 요청 금지).
    /// 응답은 요청 순서를 지키고, 담긴 곳 없는 글은 빈 배열. 실패는 호출측에서 조용히 흡수한다(피드를 막지 않게).
    static func publicPostCollectionsBatch(ids: [Int64]) async throws -> [PostCollections] {
        guard !ids.isEmpty else { return [] }
        let capped = ids.prefix(50).map(String.init).joined(separator: ",")
        return try await client.get("/public/posts/collections", query: ["ids": capped])
    }

    /// 컬렉션 상세 — 연결된 블록(글·하이라이트·노트) 해석 포함.
    static func detail(id: Int64) async throws -> CollectionDetail {
        try await client.get("/collections/\(id)", authenticated: true)
    }

    /// "이 문장이 속한 길" — 이 하이라이트를 담은 공개 컬렉션/길(최근순). 미로그인도 본다(A 척추 발견 고리).
    static func collectionsContaining(highlightId: Int64) async throws -> [CollectionSummary] {
        try await client.get("/public/highlights/\(highlightId)/collections")
    }

    /// "이것과 이어진 것" — 이 블록과 같은 공개 컬렉션에 함께 놓인 다른 블록들(공동 등장 큰 순). 미로그인도 본다.
    /// blockType = "POST" | "HIGHLIGHT" | "NOTE".
    static func relatedBlocks(blockType: String, refId: Int64) async throws -> [RelatedBlock] {
        try await client.get("/public/graph/blocks/\(blockType)/\(refId)/related")
    }

    /// "취향이 겹치는 큐레이터" — 같은 블록을 자기 공개 컬렉션에도 엮은 다른 큐레이터들(겹침 큰 순). 미로그인도 본다.
    static func kindredCurators(username: String) async throws -> [KindredCurator] {
        try await client.get("/public/profiles/\(username)/kindred")
    }

    /// 새 컬렉션/길 — 생성된 요약을 그대로 돌려받는다(count 0). kind=path 면 reading path.
    @discardableResult
    static func create(
        title: String, description: String?, visibility: CollectionVisibility,
        kind: CollectionKind = .collection
    ) async throws -> CollectionSummary {
        try await client.post(
            "/collections",
            body: NewCollectionBody(
                title: title, description: description, visibility: visibility.rawValue,
                kind: kind.rawValue),
            authenticated: true)
    }

    /// 길(PATH)의 연결 순서 재배치 — 연결 id 전체를 원하는 순서대로. 논증의 흐름을 짠다(204).
    static func reorder(collectionId: Int64, connectionIds: [Int64]) async throws {
        try await client.putVoid(
            "/collections/\(collectionId)/connections/order",
            body: ReorderBody(connectionIds: connectionIds),
            authenticated: true)
    }

    /// 컬렉션 수정 — 이름·소개·공개 범위. 갱신된 요약을 돌려받는다.
    @discardableResult
    static func edit(
        id: Int64, title: String, description: String?, visibility: CollectionVisibility
    ) async throws -> CollectionSummary {
        try await client.put(
            "/collections/\(id)",
            body: CreateCollectionBody(
                title: title, description: description, visibility: visibility.rawValue),
            authenticated: true)
    }

    /// 블록을 컬렉션에 연결(멱등). 본문 응답 없음(201).
    static func connect(
        collectionId: Int64, blockType: ConnectionBlockKind, refId: Int64, why: String?
    ) async throws {
        try await client.post(
            "/collections/\(collectionId)/connections",
            body: ConnectBlockBody(blockType: blockType, refId: refId, why: why),
            authenticated: true)
    }

    /// 연결 끊기.
    static func disconnect(collectionId: Int64, connectionId: Int64) async throws {
        try await client.deleteVoid(
            "/collections/\(collectionId)/connections/\(connectionId)", authenticated: true)
    }

    /// 컬렉션 삭제(연결도 함께).
    static func delete(id: Int64) async throws {
        try await client.deleteVoid("/collections/\(id)", authenticated: true)
    }

    /// 수정 바디 — kind 는 보내지 않는다(생성 시 고정, edit 엔드포인트는 kind 모름).
    private struct CreateCollectionBody: Encodable {
        let title: String
        let description: String?
        let visibility: String
    }

    /// 생성 바디 — kind 포함(COLLECTION | PATH).
    private struct NewCollectionBody: Encodable {
        let title: String
        let description: String?
        let visibility: String
        let kind: String
    }

    private struct ConnectBlockBody: Encodable {
        let blockType: ConnectionBlockKind
        let refId: Int64
        let why: String?
    }

    private struct ReorderBody: Encodable {
        let connectionIds: [Int64]
    }
}
