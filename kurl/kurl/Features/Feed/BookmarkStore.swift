//
//  BookmarkStore.swift
//  kurl
//

import Foundation

/// 내가 북마크한 글 집합 — 카드에서 북마크 여부를 표시하려고 한 번 받아 둔다.
/// 서버에 "내 북마크 id 배치" 엔드포인트가 없어 `GET /bookmarks` 목록에서 추린다.
/// `@Observable` 이라 토글하면 카드 글리프가 곧바로 갱신된다. 토글(독·카드 퀵액션)이
/// 여기를 같이 갱신해 단일 진실원이 된다.
///
/// 두 갈래로 키를 든다: 카드(FeedItem)는 postId 가 있어 `ids`(id 집합)로 대조하고,
/// 발견 미리보기(연결 응답엔 postId 가 없다)는 "username/slug"(`refToId`)로 대조한다.
/// 목록 응답이 두 값을 다 줘서(BookmarkItem = id + username + slug) 같은 소스로 둘을 채운다.
@MainActor
@Observable
final class BookmarkStore {
    static let shared = BookmarkStore()

    private(set) var ids: Set<Int64> = []
    /// "username/slug" → postId — postId 를 모르는 미리보기가 여부·id 를 함께 대조한다.
    private var refToId: [String: Int64] = [:]
    private var hydrated = false
    private var hydrating = false

    private init() {}

    func contains(_ id: Int64) -> Bool { ids.contains(id) }

    func contains(username: String, slug: String) -> Bool {
        refToId[Self.key(username, slug)] != nil
    }

    /// 아는 postId — 미리보기의 북마크 토글이 끌 때(이미 담긴 글) 상세 재조회 없이 바로 쓴다.
    /// 낙관 켜기 직후의 자리값(id 미상)은 nil — 그대로 반환하면 sentinel 이 실제 id 로 서버에
    /// 나가므로, 호출부가 상세 조회로 id 를 푼 뒤 보내게 한다.
    func postId(username: String, slug: String) -> Int64? {
        guard let mapped = refToId[Self.key(username, slug)], mapped != Self.unknownId else { return nil }
        return mapped
    }

    func set(_ id: Int64, on: Bool) {
        if on {
            ids.insert(id)
        } else {
            ids.remove(id)
            // postId 로만 끄는 경로(독)도 미리보기 표식과 어긋나지 않게 — 그 id 를 가리키던 ref 를 함께 지운다.
            for (key, mapped) in refToId where mapped == id { refToId.removeValue(forKey: key) }
        }
    }

    /// username/slug 로 갱신 — 미리보기·독·퀵액션이 postId 를 알 때 두 대조 경로를 함께 맞춘다.
    /// 낙관 켜기 시 id 를 아직 모르면(nil) 여부만 표시하고, 응답으로 id 가 오면 다시 불러 backfill.
    func set(username: String, slug: String, id: Int64?, on: Bool) {
        let key = Self.key(username, slug)
        if on {
            refToId[key] = id ?? refToId[key] ?? Self.unknownId
            if let id { ids.insert(id) }
        } else {
            if let mapped = refToId[key], mapped != Self.unknownId { ids.remove(mapped) }
            if let id { ids.remove(id) }
            refToId.removeValue(forKey: key)
        }
    }

    /// 로그아웃 시 — 다음 로그인 사용자가 이전 사용자의 북마크 표식을 보지 않게.
    func reset() {
        ids = []
        refToId = [:]
        hydrated = false
    }

    /// 카드가 처음 뜰 때 한 번 — 로그아웃이면 비우고, 로그인 후 첫 성공까지 목록을 받는다.
    /// hydrated 는 성공 시에만 서므로 첫 요청이 실패해도 다음 호출이 자연 재시도한다
    /// (동시 호출 중복 요청은 hydrating 으로 막는다).
    func hydrateIfNeeded() async {
        guard AuthStore.shared.isSignedIn else {
            // 카드 등장마다 불리는데 @Observable 은 같은 값 대입도 mutation 으로 발화해
            // ids 를 보는 카드 전부를 무효화한다 — 이미 빈 상태면 대입을 생략.
            if !ids.isEmpty || !refToId.isEmpty || hydrated {
                reset()
            }
            return
        }
        guard !hydrated, !hydrating else { return }
        hydrating = true
        defer { hydrating = false }
        if let items = try? await LibraryAPI.bookmarks() {
            ids = Set(items.map(\.id))
            refToId = Dictionary(
                items.map { (Self.key($0.username, $0.slug), $0.id) },
                uniquingKeysWith: { first, _ in first })
            hydrated = true
        }
    }

    /// 낙관 켜기에서 아직 postId 를 모를 때 자리만 잡는 값(여부는 참, id 는 미상).
    private static let unknownId: Int64 = -1
    private static func key(_ username: String, _ slug: String) -> String { "\(username)/\(slug)" }
}
