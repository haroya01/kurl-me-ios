//
//  LikeStoreTests.swift
//  kurlTests
//
//  퀵액션 좋아요의 낙관 카운트 회귀 — 기준값이 살아 있는 동안만 +1 하고, 서버가 새 숫자를
//  들고 오면 그 값을 믿는다(중복 가산 금지). 0→1 등장(하트가 없던 카드)도 고정한다.
//

import XCTest

@testable import kurl

@MainActor
final class LikeStoreTests: XCTestCase {

    override func setUp() async throws {
        LikeStore.shared.reset()
    }

    func testDisplayCountWithoutBumpReturnsServerValue() {
        XCTAssertEqual(LikeStore.shared.displayCount(username: "a", slug: "s", server: 5), 5)
    }

    func testBumpAddsOneWhileServerIsStale() {
        LikeStore.shared.bumpCount(username: "a", slug: "s", baseline: 5)
        XCTAssertEqual(LikeStore.shared.displayCount(username: "a", slug: "s", server: 5), 6)
    }

    func testZeroLikeCardShowsOneAfterBump() {
        LikeStore.shared.bumpCount(username: "a", slug: "s", baseline: 0)
        XCTAssertEqual(LikeStore.shared.displayCount(username: "a", slug: "s", server: 0), 1)
    }

    func testFreshServerCountRetiresBump() {
        LikeStore.shared.bumpCount(username: "a", slug: "s", baseline: 5)
        // 내 좋아요가 반영된 새 응답(6) — 그대로 믿고 +1 하지 않는다.
        XCTAssertEqual(LikeStore.shared.displayCount(username: "a", slug: "s", server: 6), 6)
        // 그 사이 다른 사람 좋아요까지 실려 와도(9) 서버 값 그대로.
        XCTAssertEqual(LikeStore.shared.displayCount(username: "a", slug: "s", server: 9), 9)
    }

    func testBumpIsKeyedPerPost() {
        LikeStore.shared.bumpCount(username: "a", slug: "s", baseline: 5)
        XCTAssertEqual(LikeStore.shared.displayCount(username: "a", slug: "other", server: 5), 5)
        XCTAssertEqual(LikeStore.shared.displayCount(username: "b", slug: "s", server: 5), 5)
    }

    func testResetClearsBumps() {
        LikeStore.shared.bumpCount(username: "a", slug: "s", baseline: 5)
        LikeStore.shared.reset()
        XCTAssertEqual(LikeStore.shared.displayCount(username: "a", slug: "s", server: 5), 5)
    }
}
