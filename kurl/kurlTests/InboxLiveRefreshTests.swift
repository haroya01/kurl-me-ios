import XCTest

@testable import kurl

@MainActor
final class InboxLiveRefreshTests: XCTestCase {
    private static var kept: [NotificationsViewModel] = []

    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_000)
    }

    private func row(_ id: Int64) -> AppNotification {
        AppNotification(
            id: id, type: "NOTE_REPLY", actorUsername: "yuki_dev", actorAvatarUrl: nil,
            postId: nil, postSlug: nil, postTitle: nil, postAuthorUsername: nil, commentId: nil, highlightId: nil,
            seriesId: nil, seriesSlug: nil, seriesTitle: nil, collectionId: nil, collectionName: nil,
            read: false, createdAt: Date(timeIntervalSince1970: TimeInterval(id)))
    }

    private func page(_ ids: [Int64], more: Bool = false) -> NotificationsPage {
        NotificationsPage(items: ids.map(row), nextCursor: more ? ids.last : nil, hasMore: more)
    }

    private func model(
        clock: Clock = Clock(),
        list: @escaping (Int64?, Int, NotificationFilter) async throws -> NotificationsPage
    ) -> NotificationsViewModel {
        let model = NotificationsViewModel(now: { clock.now }, companions: {}, hides: { _ in false }, list: list)
        Self.kept.append(model)
        return model
    }

    func testEveryForegroundPushBumpsTheArrivalWithItsType() async {
        let before = UnreadStore.shared.arrival.serial
        await UnreadStore.shared.arrived(type: "NOTE_REPLY")
        await UnreadStore.shared.arrived(type: "NOTE_REPLY")
        XCTAssertEqual(UnreadStore.shared.arrival.serial, before + 2)
        XCTAssertEqual(UnreadStore.shared.arrival.type, "NOTE_REPLY")
    }

    func testAnArrivalRefetchesTheInboxQuietlyWithTheNewRowOnTop() async {
        var asked: [Int] = []
        var answer = page([2, 1])
        let model = model { _, limit, _ in
            asked.append(limit)
            return answer
        }
        await model.load()
        answer = page([3, 2, 1])
        await model.catchUp()
        XCTAssertEqual(model.items.map(\.id), [3, 2, 1])
        XCTAssertEqual(asked, [20, 20])
        XCTAssertFalse(model.loading)
        XCTAssertNil(model.loadError)
    }

    func testArrivalsDuringARefetchCollapseIntoOneMore() async {
        var calls = 0
        var model: NotificationsViewModel!
        model = self.model { _, _, _ in
            calls += 1
            if calls == 2 {
                await model.catchUp()
                await model.catchUp()
                await model.catchUp()
            }
            return self.page([Int64(calls)])
        }
        await model.load()
        await model.catchUp()
        XCTAssertEqual(calls, 3)
        XCTAssertEqual(model.items.map(\.id), [3])
    }

    func testARefetchAsksForEveryLoadedRowUpToTheServerCap() async {
        var asked: [Int] = []
        let model = model { before, limit, _ in
            asked.append(limit)
            let top = before.map { $0 - 1 } ?? 1_000
            return self.page(Array(stride(from: top, to: top - Int64(limit), by: -1)), more: true)
        }
        await model.load()
        await model.loadMore()
        XCTAssertEqual(model.items.count, 40)
        await model.catchUp()
        XCTAssertEqual(asked.last, 40)
        XCTAssertEqual(model.items.count, 40)
        await model.loadMore()
        await model.loadMore()
        XCTAssertEqual(model.items.count, 80)
        await model.catchUp()
        XCTAssertEqual(asked.last, NotificationsViewModel.serverPageCap)
        XCTAssertEqual(model.items.count, NotificationsViewModel.serverPageCap)
        XCTAssertEqual(model.nextCursor, model.items.last?.id)
    }

    func testComingBackRefetchesOnlyWithUnreadAndNotTwiceWithinTheGap() async {
        let clock = Clock()
        var calls = 0
        let model = model(clock: clock) { _, _, _ in
            calls += 1
            return self.page([1])
        }
        await model.resume(unread: 3)
        XCTAssertEqual(calls, 0, "nothing loaded yet")
        await model.load()
        clock.now += 60
        await model.resume(unread: 0)
        XCTAssertEqual(calls, 1)
        await model.resume(unread: 3)
        XCTAssertEqual(calls, 2)
        clock.now += 1
        await model.resume(unread: 3)
        XCTAssertEqual(calls, 2)
        clock.now += NotificationsViewModel.resumeGap
        await model.resume(unread: 3)
        XCTAssertEqual(calls, 3)
    }

    func testAFailedRefetchKeepsTheRowsWithoutAnError() async {
        var fails = false
        let model = model { _, _, _ in
            if fails { throw URLError(.timedOut) }
            return self.page([2, 1])
        }
        await model.load()
        fails = true
        await model.catchUp()
        XCTAssertEqual(model.items.map(\.id), [2, 1])
        XCTAssertNil(model.loadError)
    }

    func testSwitchingTheFilterMidRefetchDropsTheStaleAnswer() async {
        var calls = 0
        var model: NotificationsViewModel!
        model = self.model { _, _, filter in
            calls += 1
            if calls == 2 {
                model.filter = .mentions
                model.switchedFilter()
                await model.load()
            }
            return filter == .mentions ? self.page([7]) : self.page([2, 1])
        }
        await model.load()
        await model.catchUp()
        XCTAssertEqual(model.items.map(\.id), [7])
    }

    private func note(_ id: Int64, by author: Int64) -> Note {
        Note(
            id: id, body: "노트 \(id)", createdAt: nil, editedAt: nil, likeCount: nil, likedByMe: nil,
            author: Author(id: author, username: "u\(author)", bio: nil, avatarUrl: nil), media: [], quotedPost: nil,
            inReplyToId: nil, replyCount: 0, repostCount: nil, repostedByMe: nil, quotedNote: nil)
    }

    func testOnlyAReplyPushReloadsAThreadWhoseNoteIsMine() {
        let me: Int64 = 5
        let mine = NoteThread(note: note(1, by: me), parent: nil, replies: [])
        XCTAssertTrue(mine.reloads(onPush: "NOTE_REPLY", me: me))
        XCTAssertFalse(mine.reloads(onPush: "NOTE_LIKE", me: me))
        XCTAssertFalse(mine.reloads(onPush: nil, me: me))
        XCTAssertFalse(mine.reloads(onPush: "NOTE_REPLY", me: nil))

        let continued = NoteThread(note: note(1, by: me), parent: nil, replies: [], continuation: [note(2, by: me)])
        XCTAssertTrue(continued.reloads(onPush: "NOTE_REPLY", me: me))

        let theirs = NoteThread(note: note(3, by: 6), parent: note(1, by: me), replies: [note(4, by: me)])
        XCTAssertFalse(theirs.reloads(onPush: "NOTE_REPLY", me: me))
    }
}
