//
//  BlockStore.swift
//  kurl
//

import Foundation

/// 내가 차단한 사용자 — App Store 1.2(UGC) 요건. 차단하면 그 사용자의 글·댓글·노트를 클라이언트에서
/// 숨긴다(서버는 차단 관계만 저장·목록 제공). `@Observable` 이라 차단/해제하면 목록·콘텐츠가 곧바로
/// 갱신된다. 단일 진실원 — 차단 토글이 여기를 같이 갱신한다.
@MainActor
@Observable
final class BlockStore {
    static let shared = BlockStore()

    /// 콘텐츠는 작가 username 으로 표시되므로 필터는 username 기준이 1차(+id 보조).
    private(set) var blockedUsernames: Set<String> = []
    private(set) var blockedIds: Set<Int64> = []
    /// 관리 화면(차단 해제)용 — 서버 기준 최신순.
    private(set) var blocked: [InteractionsAPI.BlockedUser] = []
    private var hydrated = false
    private var hydrating = false

    private init() {}

    func isBlocked(_ username: String) -> Bool { blockedUsernames.contains(username) }
    func isBlocked(id: Int64) -> Bool { blockedIds.contains(id) }

    /// 처음 필요할 때 한 번 — 로그아웃이면 비우고, 로그인 후 첫 성공까지 목록을 받는다.
    /// hydrated 는 성공 시에만 서므로 첫 요청이 실패해도 다음 호출이 자연 재시도한다
    /// (동시 호출 중복 요청은 hydrating 으로 막는다).
    func hydrateIfNeeded() async {
        guard AuthStore.shared.isSignedIn else {
            // 이미 빈 상태면 @Observable 무효화를 피해 대입을 생략.
            if !blockedUsernames.isEmpty || !blockedIds.isEmpty || !blocked.isEmpty || hydrated {
                reset()
            }
            return
        }
        guard !hydrated, !hydrating else { return }
        hydrating = true
        defer { hydrating = false }
        await reload()
    }

    /// 성공하면 true, 실패(전송오류 등)면 false — 호출부가 '실패'와 '빈 목록'을 구분할 수 있게.
    @discardableResult
    func reload() async -> Bool {
        if let items = try? await InteractionsAPI.listBlocked() {
            blocked = items
            blockedUsernames = Set(items.map(\.username))
            blockedIds = Set(items.map(\.id))
            hydrated = true
            return true
        }
        return false
    }

    /// 차단 — 낙관적으로 목록에 넣고(콘텐츠 즉시 숨김), 실패하면 되돌린다.
    func block(id: Int64, username: String) async throws {
        let insertedName = blockedUsernames.insert(username).inserted
        let insertedId = blockedIds.insert(id).inserted
        do {
            try await InteractionsAPI.block(username: username)
            await reload() // 서버 기준 최신순 목록(관리 화면)으로 정렬.
        } catch {
            if insertedName { blockedUsernames.remove(username) }
            if insertedId { blockedIds.remove(id) }
            throw error
        }
    }

    /// 차단 해제 — 낙관적으로 빼고, 실패하면 서버 기준으로 재수화.
    func unblock(id: Int64, username: String) async throws {
        blockedUsernames.remove(username)
        blockedIds.remove(id)
        blocked.removeAll { $0.id == id }
        do {
            try await InteractionsAPI.unblock(username: username)
        } catch {
            await reload()
            throw error
        }
    }

    /// 로그아웃 시 — 다음 사용자가 이전 사용자의 차단 목록을 물려받지 않게.
    func reset() {
        blockedUsernames = []
        blockedIds = []
        blocked = []
        hydrated = false
    }
}
