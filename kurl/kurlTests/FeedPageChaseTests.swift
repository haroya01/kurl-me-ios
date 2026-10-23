import XCTest
@testable import kurl

/// 노트 피드 이어받기(collectVisible) — 키워드 필터가 한 페이지를 통째로 숨겨도 다음 페이지 트리거가
/// 소진돼 피드가 멈추지 않는다. 숨겨진 노트도 모아 둔다(필터를 풀면 다시 보이게).
@MainActor
final class NotePageChaseTests: XCTestCase {

    private func note(_ id: Int64) -> Note {
        Note(
            id: id, body: "노트 \(id)", createdAt: nil, editedAt: nil, likeCount: nil, likedByMe: nil,
            author: Author(id: 1, username: "author", bio: nil, avatarUrl: nil), media: [], quotedPost: nil,
            inReplyToId: nil, replyCount: 0, repostCount: nil, repostedByMe: nil, quotedNote: nil)
    }

    private func feed(_ ids: [Int64], hasNext: Bool) -> NoteFeed {
        NoteFeed(items: ids.map(note), page: 0, hasNext: hasNext)
    }

    func testChasesPastPagesHiddenByFilter() async throws {
        let pages = [
            feed([1, 2, 3], hasNext: true),
            feed([4, 5], hasNext: true),
            feed([6, 7], hasNext: true),
        ]
        let hidden: Set<Int64> = [1, 2, 3, 4, 5, 7]
        var fetched: [Int] = []
        let result = try await NotesViewModel.collectVisible(
            from: 0, seen: [], isVisible: { !hidden.contains($0.id) }
        ) { p in
            fetched.append(p)
            return pages[p]
        }
        XCTAssertEqual(fetched, [0, 1, 2])
        XCTAssertEqual(result.notes.map(\.id), [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(result.page, 2)
        XCTAssertTrue(result.hasNext)
    }

    func testStopsAtFirstPageWithAVisibleNote() async throws {
        var fetched = 0
        let result = try await NotesViewModel.collectVisible(
            from: 3, seen: [], isVisible: { $0.id == 2 }
        ) { _ in
            fetched += 1
            return self.feed([1, 2], hasNext: true)
        }
        XCTAssertEqual(fetched, 1)
        XCTAssertEqual(result.page, 3)
        XCTAssertEqual(result.notes.map(\.id), [1, 2])
    }

    func testStopsAtFeedEndWhenAllHidden() async throws {
        let result = try await NotesViewModel.collectVisible(
            from: 0, seen: [], isVisible: { _ in false }
        ) { _ in
            self.feed([1], hasNext: false)
        }
        XCTAssertFalse(result.hasNext)
        XCTAssertEqual(result.notes.map(\.id), [1])
    }

    func testCapBoundsChase() async throws {
        var fetched = 0
        let result = try await NotesViewModel.collectVisible(
            from: 0, seen: [], isVisible: { _ in false }
        ) { p in
            fetched += 1
            return self.feed([Int64(p)], hasNext: true)
        }
        XCTAssertEqual(fetched, 5)
        XCTAssertEqual(result.page, 4)
        XCTAssertTrue(result.hasNext)
    }

    func testAlreadySeenNotesDoNotCountAsVisible() async throws {
        let pages = [
            feed([1, 2], hasNext: true),
            feed([3], hasNext: true),
        ]
        let result = try await NotesViewModel.collectVisible(
            from: 0, seen: [1], isVisible: { $0.id != 2 }
        ) { p in pages[p] }
        XCTAssertEqual(result.notes.map(\.id), [2, 3])
        XCTAssertEqual(result.page, 1)
    }
}
