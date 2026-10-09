//
//  FollowBlockRollbackTests.swift
//  kurlTests
//
//  낙관 토글의 실패 복귀 — 서버 재조회에 기대지 않고 누르기 전 상태로 되돌린다(재조회도 실패하는
//  오프라인에서 '팔로잉'·차단 해제가 화면에 남지 않게). 팔로우는 가는 중 연타를 받지 않는다.
//

import XCTest

@testable import kurl

@MainActor
final class FollowBlockRollbackTests: XCTestCase {

    private struct Offline: Error {}

    private func status(following: Bool, count: Int64, notifyNotes: Bool = false) throws -> InteractionsAPI.FollowStatus {
        let json = #"{"following":\#(following),"followerCount":\#(count),"notifyNotes":\#(notifyNotes)}"#
        return try JSONDecoder().decode(InteractionsAPI.FollowStatus.self, from: Data(json.utf8))
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func testFailedFollowRestoresStateBeforeTap() async throws {
        let model = FollowModel(username: "yuki", seed: try status(following: false, count: 12)) { _, _ in
            throw Offline()
        }
        do {
            try await model.toggle()
            XCTFail("실패가 호출측(토스트)까지 전해져야 한다")
        } catch {}
        XCTAssertFalse(model.following)
        XCTAssertEqual(model.followerCount, 12)
        XCTAssertFalse(model.busy)
    }

    func testFailedUnfollowRestoresFollowingCountAndBell() async throws {
        let model = FollowModel(
            username: "yuki", seed: try status(following: true, count: 12, notifyNotes: true)
        ) { _, _ in
            throw Offline()
        }
        try? await model.toggle()
        XCTAssertTrue(model.following)
        XCTAssertEqual(model.followerCount, 12)
        XCTAssertTrue(model.notifyNotes)
    }

    func testTapWhileFollowIsInFlightIsIgnored() async throws {
        let server = GatedFollowServer()
        let model = FollowModel(username: "yuki", seed: try status(following: false, count: 12)) { _, on in
            try await server.set(on)
        }

        let first = Task { try await model.toggle() }
        await waitUntil { server.calls == 1 }
        let secondReturned = Counter()
        let second = Task {
            try await model.toggle()
            secondReturned.count = 1
        }
        await waitUntil { secondReturned.count == 1 || server.calls == 2 }
        XCTAssertEqual(server.calls, 1)
        XCTAssertTrue(model.following)
        XCTAssertEqual(model.followerCount, 13)

        server.releaseAll(with: try status(following: true, count: 13))
        try await first.value
        try await second.value
        XCTAssertTrue(model.following)
        XCTAssertEqual(model.followerCount, 13)
        XCTAssertFalse(model.busy)
    }

    // MARK: 차단 해제

    private func blockedRows() throws -> [InteractionsAPI.BlockedUser] {
        let json = #"[{"id":1,"username":"a","avatarUrl":null},{"id":2,"username":"b","avatarUrl":null}]"#
        return try JSONDecoder().decode([InteractionsAPI.BlockedUser].self, from: Data(json.utf8))
    }

    func testFailedUnblockRestoresUserEvenWhenReloadAlsoFails() async throws {
        let rows = try blockedRows()
        let lists = Counter()
        var api = BlockStore.API()
        api.list = {
            lists.count += 1
            if lists.count > 1 { throw Offline() }
            return rows
        }
        api.unblock = { _ in throw Offline() }
        let store = BlockStore(api: api)
        let loaded = await store.reload()
        XCTAssertTrue(loaded)

        do {
            try await store.unblock(id: 1, username: "a")
            XCTFail("실패가 호출측(토스트)까지 전해져야 한다")
        } catch {}

        XCTAssertTrue(store.isBlocked("a"))
        XCTAssertTrue(store.isBlocked(id: 1))
        XCTAssertEqual(store.blocked.map(\.id), [1, 2])
    }

    func testSuccessfulUnblockRemovesUser() async throws {
        let rows = try blockedRows()
        var api = BlockStore.API()
        api.list = { rows }
        api.unblock = { _ in }
        let store = BlockStore(api: api)
        _ = await store.reload()

        try await store.unblock(id: 1, username: "a")

        XCTAssertFalse(store.isBlocked("a"))
        XCTAssertFalse(store.isBlocked(id: 1))
        XCTAssertEqual(store.blocked.map(\.id), [2])
    }
}

@MainActor
private final class Counter {
    var count = 0
}

/// 팔로우 서버 대역 — 요청을 붙잡아 두었다가 정해 준 응답으로 풀어 준다.
@MainActor
private final class GatedFollowServer {
    private(set) var calls = 0
    private var waiting: [CheckedContinuation<InteractionsAPI.FollowStatus, Never>] = []

    func set(_ on: Bool) async throws -> InteractionsAPI.FollowStatus {
        calls += 1
        return await withCheckedContinuation { waiting.append($0) }
    }

    func releaseAll(with status: InteractionsAPI.FollowStatus) {
        waiting.forEach { $0.resume(returning: status) }
        waiting = []
    }
}
