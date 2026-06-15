//
//  CollectionsAPI.swift
//  kurl
//
//  컬렉션(연결 그래프) — 백엔드 `CollectionController` 와 1:1. 전부 인증 면(내 큐레이션).
//

import Foundation

enum CollectionsAPI {
    private static let client = APIClient.shared

    /// 내 컬렉션 목록(최근 손댄 순).
    static func mine() async throws -> [CollectionSummary] {
        try await client.get("/users/me/collections", authenticated: true)
    }

    /// 발견 — 내가 팔로우한 큐레이터들의 공개 컬렉션 연결 흐름(최신순). 팔로우 0이면 빈 배열.
    static func discoverFeed() async throws -> [ConnectionEvent] {
        let view: DiscoverFeedResponse = try await client.get(
            "/feed/connections", authenticated: true)
        return view.items
    }

    /// 컬렉션 상세 — 연결된 블록(글·하이라이트·노트) 해석 포함.
    static func detail(id: Int64) async throws -> CollectionDetail {
        try await client.get("/collections/\(id)", authenticated: true)
    }

    /// 새 컬렉션 — 생성된 요약을 그대로 돌려받는다(count 0).
    @discardableResult
    static func create(
        title: String, description: String?, visibility: CollectionVisibility
    ) async throws -> CollectionSummary {
        try await client.post(
            "/collections",
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

    private struct CreateCollectionBody: Encodable {
        let title: String
        let description: String?
        let visibility: String
    }

    private struct ConnectBlockBody: Encodable {
        let blockType: ConnectionBlockKind
        let refId: Int64
        let why: String?
    }
}
