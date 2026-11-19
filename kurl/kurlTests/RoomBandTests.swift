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

@MainActor
final class QuoteReachTests: XCTestCase {
    private let club = NoteRoom(id: 1, name: "동아리 사람들")
    private let classmates = NoteRoom(id: 2, name: "대학 동기")

    private func note(_ visibility: String, room: NoteRoom? = nil) -> Note {
        var note = Note(
            id: 9000, body: "", createdAt: nil, editedAt: nil, likeCount: nil, likedByMe: nil,
            author: Author(id: 1, username: "honggildong", bio: nil, avatarUrl: nil), media: [], quotedPost: nil,
            inReplyToId: nil, replyCount: 0, repostCount: nil, repostedByMe: nil, quotedNote: nil)
        note.visibility = visibility
        note.room = room
        return note
    }

    func testAPublicNoteGoesOutsideRoomsAndIntoAnyRoom() {
        for visibility in ["public", "unlisted"] {
            let reach = QuoteReach(note: note(visibility))
            XCTAssertEqual(reach, .anywhere, visibility)
            XCTAssertNil(reach.room, "공개 노트 인용이 한 방에 묶임")
            XCTAssertTrue(reach.allows(roomId: nil))
            XCTAssertTrue(reach.allows(roomId: club.id))
            XCTAssertTrue(reach.allows(roomId: classmates.id))
        }
    }

    func testARoomNoteGoesOnlyIntoItsOwnRoom() {
        let reach = QuoteReach(note: note("room", room: club))
        XCTAssertEqual(reach.room, club, "방 노트 인용이 그 방에 묶이지 않음")
        XCTAssertTrue(reach.allows(roomId: club.id))
        XCTAssertFalse(reach.allows(roomId: nil), "방 노트가 방 밖으로 나감")
        XCTAssertFalse(reach.allows(roomId: classmates.id), "방 노트가 다른 방으로 나감")
    }

    func testAFollowersOnlyOrDirectNoteGoesNowhere() {
        for visibility in ["private", "direct"] {
            let reach = QuoteReach(note: note(visibility))
            XCTAssertEqual(reach, .nowhere, visibility)
            XCTAssertFalse(reach.allows(roomId: nil))
            XCTAssertFalse(reach.allows(roomId: club.id))
        }
    }

    func testAnOpenPostGoesAnywhereAndARoomPostOnlyIntoItsRoom() {
        for audience in [PostAudience.everyone, .followers, .password] {
            XCTAssertEqual(QuoteReach(post: audience, room: nil), .anywhere, audience.rawValue)
        }
        XCTAssertEqual(QuoteReach(post: nil, room: nil), .anywhere)
        XCTAssertEqual(QuoteReach(post: .unlisted, room: nil), .nowhere)

        let reach = QuoteReach(post: .room, room: club)
        XCTAssertEqual(reach.room, club)
        XCTAssertTrue(reach.allows(roomId: club.id))
        XCTAssertFalse(reach.allows(roomId: nil), "방 글이 방 밖 노트에 인용됨")
        XCTAssertFalse(reach.allows(roomId: classmates.id), "방 글이 다른 방 노트에 인용됨")
        XCTAssertEqual(QuoteReach(post: .room, room: nil), .nowhere, "어느 방 글인지 모르는데 인용을 내놓음")
    }

    func testAQuoteIsListedOnlyInsideTheSameWall() {
        let open = QuoteReach(post: .everyone, room: nil)
        XCTAssertTrue(open.lists(note("public")))
        XCTAssertTrue(open.lists(note("unlisted")))
        XCTAssertFalse(open.lists(note("private")), "팔로워만 보는 인용이 공개 글의 노트 목록에 듦")
        XCTAssertFalse(open.lists(note("room", room: club)), "방 안에서 한 인용이 방 밖 목록에 듦")

        let inRoom = QuoteReach(post: .room, room: club)
        XCTAssertTrue(inRoom.lists(note("room", room: club)))
        XCTAssertFalse(inRoom.lists(note("room", room: classmates)))
        XCTAssertFalse(inRoom.lists(note("public")))
        XCTAssertFalse(QuoteReach.nowhere.lists(note("public")))
    }

    func testANewQuoteJoinsTheListOfTheQuotedNoteOnlyInTheSamePlace() {
        XCTAssertTrue(QuoteReach.landsBeside(note("public"), note("public")))
        XCTAssertTrue(QuoteReach.landsBeside(note("public"), note("private")))
        XCTAssertTrue(QuoteReach.landsBeside(note("room", room: club), note("room", room: club)))
        XCTAssertFalse(
            QuoteReach.landsBeside(note("public"), note("room", room: club)),
            "방에 올린 인용이 공개 목록에 끼어듦")
        XCTAssertFalse(QuoteReach.landsBeside(note("room", room: club), note("room", room: classmates)))
    }
}

@MainActor
final class RoomQuoteMockTests: XCTestCase {
    private func send<T: Decodable>(_ method: String, _ path: String, _ body: [String: Any]? = nil) throws -> T {
        let data = try MockBackend.respond(
            path: path, method: method, body: try body.map { try JSONSerialization.data(withJSONObject: $0) })
        return try JSONDecoder.blog.decode(T.self, from: try XCTUnwrap(data, "\(method) \(path) 를 목이 모름"))
    }

    private func post(_ draft: [String: Any]) throws -> Note { try send("POST", "notes", draft) }

    private func refusal(_ path: String = "notes", body: [String: Any]) -> String? {
        do {
            _ = try MockBackend.respond(path: path, method: "POST", body: try JSONSerialization.data(withJSONObject: body))
            return nil
        } catch let APIError.server(_, code, _) {
            return code
        } catch {
            return "\(error)"
        }
    }

    func testARoomNoteIsQuotedInItsOwnRoomAndCountedThere() throws {
        let made = try post(["body": "나도 어제 갔는데", "quotedNoteId": 9901, "roomId": 1])
        XCTAssertEqual(made.room?.id, 1)
        XCTAssertEqual(made.quotedNote?.id, 9901)

        let quotes: NoteFeed = try send("GET", "public/notes/9901/quotes")
        XCTAssertTrue(quotes.items.contains { $0.id == made.id })
        let quoted: NoteThread = try send("GET", "public/notes/9901")
        XCTAssertEqual(quoted.note.quoteCount, Int64(quotes.items.count))
        let timeline: HomeFeedBatch = try send("GET", "rooms/1/items")
        XCTAssertEqual(timeline.items.first?.note?.id, made.id)
    }

    func testARoomNoteIsRefusedOutsideItsRoom() {
        XCTAssertEqual(refusal(body: ["body": "밖으로", "quotedNoteId": 9901]), "NOTE_NOT_SHAREABLE")
        XCTAssertEqual(refusal(body: ["body": "다른 방으로", "quotedNoteId": 9901, "roomId": 2]), "NOTE_NOT_SHAREABLE")
    }

    func testARoomPostIsQuotedInItsOwnRoomAndRefusedElsewhere() throws {
        let made = try post(["body": "이 글 좋았다", "quotedPostId": 8801, "roomId": 1])
        XCTAssertEqual(made.quotedPost?.id, 8801)
        XCTAssertEqual(made.quotedPost?.audience, .room)
        XCTAssertNil(made.quotedPost?.locked)
        XCTAssertEqual(made.quotedPost?.cardMarks.isMarked, false, "방 글 인용 카드에 자물쇠나 표시가 붙음")
        XCTAssertTrue(
            QuotedPost(id: 1, title: "", slug: "", authorUsername: "", audience: .followers).cardMarks.isMarked,
            "팔로워만 글의 인용 카드 표시가 사라짐")
        let quotes: PostQuotesPage = try send("GET", "public/posts/8801/quotes")
        XCTAssertTrue(quotes.items.contains { $0.id == made.id })
        XCTAssertEqual(quotes.total, quotes.items.count)

        XCTAssertEqual(refusal(body: ["body": "밖으로", "quotedPostId": 8801]), "NOTE_QUOTE_NOT_FOUND")
        XCTAssertEqual(refusal(body: ["body": "다른 방으로", "quotedPostId": 8801, "roomId": 2]), "NOTE_QUOTE_NOT_FOUND")
    }

    func testAPublicNoteIsQuotedIntoARoomWithoutBeingCountedOutside() throws {
        let before: NoteThread = try send("GET", "public/notes/9501")
        let made = try post(["body": "방에 가져옴", "quotedNoteId": 9501, "roomId": 2])
        XCTAssertEqual(made.room?.id, 2)
        XCTAssertEqual(made.quotedNote?.id, 9501)

        let after: NoteThread = try send("GET", "public/notes/9501")
        XCTAssertEqual(after.note.quoteCount, before.note.quoteCount, "방 안의 인용이 방 밖 수에 잡힘")
        let quotes: NoteFeed = try send("GET", "public/notes/9501/quotes")
        XCTAssertFalse(quotes.items.contains { $0.id == made.id }, "방 안의 인용이 방 밖 목록에 보임")
        let everyone: NoteFeed = try send("GET", "public/notes")
        XCTAssertFalse(everyone.items.contains { $0.id == made.id }, "방 노트가 공개 피드에 섞임")
    }

    func testAnOpenPostIsQuotedIntoARoom() throws {
        let made = try post(["body": "같이 읽자", "quotedPostId": 9301, "roomId": 1])
        XCTAssertEqual(made.room?.id, 1)
        XCTAssertEqual(made.quotedPost?.slug, "picking-mt-photos")
    }

    func testARoomIAmNotInTakesNoNote() {
        XCTAssertEqual(refusal(body: ["body": "초대만 받은 방", "roomId": 4]), "NOTE_ROOM_NOT_FOUND")
        XCTAssertEqual(
            refusal(body: ["body": "방도 인용도 안 됨", "quotedNoteId": 9901, "roomId": 4]), "NOTE_ROOM_NOT_FOUND",
            "방 확인이 인용 확인보다 먼저가 아님")
    }

    func testAfterLeavingTheRoomMyNoteStillReadsWithoutItsQuotedRoomPost() throws {
        let made = try post(["body": "레시피 고마워", "quotedPostId": 8803, "roomId": 5])
        XCTAssertEqual(made.quotedPost?.id, 8803)

        _ = try MockBackend.respond(path: "rooms/5/leave", method: "POST", body: nil)
        let mine: NoteThread = try send("GET", "public/notes/\(made.id)")
        XCTAssertEqual(mine.note.body, "레시피 고마워")
        XCTAssertNil(mine.note.quotedPost, "방을 나간 사람에게 방 글 카드가 남음")
    }

    func testThreadsAndScheduledNotesGetTheSameAnswer() {
        let outside: [String: Any] = ["body": "밖으로", "quotedNoteId": 9901]
        XCTAssertEqual(refusal("notes/threads", body: ["notes": [outside, ["body": "이어서"]]]), "NOTE_NOT_SHAREABLE")
        XCTAssertEqual(
            refusal("notes/scheduled", body: ["note": outside, "scheduledAt": "2030-01-01T00:00:00Z"]),
            "NOTE_NOT_SHAREABLE")
    }

    func testARoomPostCarriesItsRoomAndANoteOfThatRoom() throws {
        let inside: PublicPostDetail = try send("GET", "public/profiles/yuki_dev/posts/rainy-mt-night")
        XCTAssertEqual(inside.post.room?.id, 1)
        XCTAssertEqual(inside.post.audience, .room)
        let address = try XCTUnwrap(inside.blocks.first { $0.kind == .embed }?.content)
        XCTAssertEqual(NoteURL.id(from: address), 9903)

        let outside: PublicPostDetail = try send("GET", "public/profiles/yuki_dev/posts/picking-mt-photos")
        XCTAssertNil(outside.post.room)
        XCTAssertEqual(outside.blocks.first { $0.kind == .embed }?.content, address)

        let embedded: NoteThread = try send("GET", "public/notes/9903")
        XCTAssertTrue(QuoteReach(note: embedded.note).allows(roomId: inside.post.room?.id), "같은 방 글에서 카드가 아님")
        XCTAssertFalse(QuoteReach(note: embedded.note).allows(roomId: outside.post.room?.id), "방 밖 글에서 카드로 그려짐")
        let carrying: PublicFeedView = try send("GET", "public/notes/9903/posts")
        XCTAssertEqual(carrying.items.map(\.id), [8801])
    }
}
