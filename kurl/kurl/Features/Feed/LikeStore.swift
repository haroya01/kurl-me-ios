//
//  LikeStore.swift
//  kurl
//

import Foundation
import Observation

/// 내가 좋아요한 글 — "username/slug" 집합. 목록·연결 응답엔 likedByMe 가 없어(카드·미리보기가
/// 내 좋아요 여부를 몰랐다) `GET /users/me/likes` 를 한 번 받아 대조한다. BookmarkStore 의 짝으로,
/// postId 없이도 미리보기 카드가 내 좋아요 표식을 그리게 한다. `@Observable` 이라 상태가 바뀌면
/// 표식이 곧바로 갱신된다. 표시 전용(끄기/켜기 토글은 독·상세가 든다) — 여기선 여부만 안다.
@MainActor
@Observable
final class LikeStore {
    static let shared = LikeStore()

    private(set) var refs: Set<String> = []
    private var hydrated = false

    private init() {}

    func contains(username: String, slug: String) -> Bool {
        refs.contains(Self.key(username, slug))
    }

    /// 좋아요 독·퀵액션이 여기를 같이 갱신해 미리보기 표식과 어긋나지 않게 한다.
    func set(username: String, slug: String, on: Bool) {
        let key = Self.key(username, slug)
        if on { refs.insert(key) } else { refs.remove(key) }
    }

    /// 로그아웃 시 — 다음 로그인 사용자가 이전 사용자의 좋아요 표식을 보지 않게.
    func reset() {
        refs = []
        hydrated = false
    }

    /// 미리보기가 처음 뜰 때 한 번 — 로그아웃이면 비우고, 로그인 후 첫 호출에만 목록을 받는다.
    func hydrateIfNeeded() async {
        guard AuthStore.shared.isSignedIn else {
            refs = []
            hydrated = false
            return
        }
        guard !hydrated else { return }
        hydrated = true
        if let items = try? await LibraryAPI.likedPosts() {
            refs = Set(items.map { Self.key($0.author.username, $0.slug) })
        }
    }

    private static func key(_ username: String, _ slug: String) -> String { "\(username)/\(slug)" }
}
