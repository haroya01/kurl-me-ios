//
//  BookmarkStore.swift
//  kurl
//

import Foundation

/// 내가 북마크한 글 id 집합 — 카드에서 북마크 여부를 표시하려고 한 번 받아 둔다.
/// 서버에 "내 북마크 id 배치" 엔드포인트가 없어 `GET /bookmarks` 목록에서 id 만 추린다.
/// `@Observable` 이라 토글하면 카드 글리프가 곧바로 갱신된다. 토글(독·카드 퀵액션)이
/// 여기를 같이 갱신해 단일 진실원이 된다.
@MainActor
@Observable
final class BookmarkStore {
    static let shared = BookmarkStore()

    private(set) var ids: Set<Int64> = []
    private var hydrated = false

    private init() {}

    func contains(_ id: Int64) -> Bool { ids.contains(id) }

    func set(_ id: Int64, on: Bool) {
        if on { ids.insert(id) } else { ids.remove(id) }
    }

    /// 카드가 처음 뜰 때 한 번 — 로그아웃이면 비우고, 로그인 후 첫 호출에만 목록을 받는다.
    func hydrateIfNeeded() async {
        guard AuthStore.shared.isSignedIn else {
            ids = []
            hydrated = false
            return
        }
        guard !hydrated else { return }
        hydrated = true
        if let items = try? await LibraryAPI.bookmarks() {
            ids = Set(items.map(\.id))
        }
    }
}
