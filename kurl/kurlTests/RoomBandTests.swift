//
//  RoomBandTests.swift
//  kurlTests
//

import XCTest

@testable import kurl

@MainActor
final class RoomBandTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func room(_ id: Int64, daysAgo: Double?, pinned: Bool = false) -> RoomListItem {
        let at = daysAgo.map { now.addingTimeInterval(-$0 * 86_400) }
        let last = at.map {
            RoomListItem.LastNote(
                id: id * 10, excerpt: "글", author: RoomPerson(id: 9, username: "minji", displayName: nil, avatarUrl: nil),
                createdAt: $0)
        }
        return RoomListItem(
            id: id, name: "방 \(id)", memberCount: 3, role: "MEMBER", hiddenFromFeed: false, unreadCount: 0,
            lastActivityAt: at, lastNote: last, faces: [], pinned: pinned)
    }

    func testARoomWithAPostThisWeekIsLivelyAndAnOlderOrEmptyOneIsQuiet() {
        XCTAssertTrue(RoomBand.isLively(room(1, daysAgo: 0.1), now: now))
        XCTAssertTrue(RoomBand.isLively(room(2, daysAgo: 6.9), now: now))
        XCTAssertFalse(RoomBand.isLively(room(3, daysAgo: 7.1), now: now))
        XCTAssertFalse(RoomBand.isLively(room(4, daysAgo: nil), now: now))
    }

    func testPinnedRoomsComeFirstWhateverTheirActivity() {
        let bands = RoomBand.split([room(1, daysAgo: 0.1), room(2, daysAgo: 30, pinned: true), room(3, daysAgo: nil)], now: now)
        XCTAssertEqual(bands.map(\.kind), [.pinned, .today, .quiet])
        XCTAssertEqual(bands.first?.rooms.map(\.id), [2])
    }

    func testReadsAreSentOncePerRoomUpToTheNewestSeen() {
        var reads = RoomReads()
        reads.saw(room: 1, note: 10)
        reads.saw(room: 1, note: 12)
        reads.saw(room: 2, note: 5)
        XCTAssertEqual(reads.takeDue(), [1: 12, 2: 5])
        reads.saw(room: 1, note: 11)
        XCTAssertEqual(reads.takeDue(), [:])
        reads.saw(room: 1, note: 13)
        XCTAssertEqual(reads.takeDue(), [1: 13])
    }
}
