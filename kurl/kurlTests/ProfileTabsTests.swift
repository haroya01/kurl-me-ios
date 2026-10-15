//
//  ProfileTabsTests.swift
//  kurlTests
//

import XCTest

@testable import kurl

@MainActor
final class ProfileTabsTests: XCTestCase {

    private let note = #"""
        {"id":%d,"body":"답글","createdAt":"2026-10-10T00:00:00Z","editedAt":null,"likeCount":null,
         "likedByMe":null,"author":{"id":3,"username":"reader","bio":null,"avatarUrl":null},"media":[],
         "quotedPost":null,"inReplyToId":%@,"replyCount":0,"repostCount":null,"repostedByMe":null,
         "quotedNote":null}
        """#

    private func replies(_ json: String) throws -> ProfileReplies {
        try JSONDecoder.blog.decode(ProfileReplies.self, from: Data(json.utf8))
    }

    func testAReplyCarriesWhatItAnsweredOrNothingWhenTheParentCannotBeShown() throws {
        let page = try replies(#"""
            {"items":[
              {"note":\#(String(format: note, 11, "7")),
               "replyingTo":{"id":7,"author":{"id":2,"username":"writer","bio":null,"avatarUrl":null},
                             "excerpt":"원래 노트 앞부분","contentWarning":null}},
              {"note":\#(String(format: note, 12, "8")),
               "replyingTo":{"id":8,"author":{"id":2,"username":"writer","bio":null,"avatarUrl":null},
                             "excerpt":null,"contentWarning":"결말 이야기"}},
              {"note":\#(String(format: note, 13, "null")),"replyingTo":null}
            ],"page":0,"hasNext":true}
            """#)

        XCTAssertEqual(page.items.map(\.id), [11, 12, 13])
        XCTAssertTrue(page.hasNext)
        guard case .to(let answered) = ReplyHeader(page.items[0].replyingTo) else {
            return XCTFail("원래 글이 있는 답글은 머리 줄이 그 글을 가리켜야 한다")
        }
        XCTAssertEqual(answered.id, 7)
        XCTAssertEqual(answered.author.username, "writer")
        XCTAssertEqual(answered.excerpt, "원래 노트 앞부분")
        guard case .to(let warned) = ReplyHeader(page.items[1].replyingTo) else {
            return XCTFail("경고가 있는 원래 글도 머리 줄이 그 글을 가리켜야 한다")
        }
        XCTAssertNil(warned.excerpt)
        XCTAssertEqual(warned.contentWarning, "결말 이야기")
        XCTAssertEqual(ReplyHeader(page.items[2].replyingTo), .unavailable)
    }

    func testAMediaCellCarriesItsFirstAttachmentCountAndSensitivity() throws {
        let page = try JSONDecoder.blog.decode(
            ProfileMedia.self,
            from: Data(#"""
                {"items":[
                  {"noteId":21,"createdAt":"2026-10-10T00:00:00Z",
                   "media":{"url":"https://cdn.example/a.webp","altText":"창밖","contentType":"image/webp","width":1200,"height":800},
                   "mediaCount":3,"sensitive":false,"contentWarning":null},
                  {"noteId":22,"createdAt":"2026-10-09T00:00:00Z",
                   "media":{"url":"https://cdn.example/b.webp","altText":null,"contentType":"image/webp"},
                   "mediaCount":1,"sensitive":true,"contentWarning":"수술 자국"}
                ],"page":0,"hasNext":false}
                """#.utf8))

        XCTAssertEqual(page.items.map(\.id), [21, 22])
        XCTAssertEqual(page.items[0].media.altText, "창밖")
        XCTAssertEqual(page.items[0].mediaCount, 3)
        XCTAssertFalse(page.items[0].sensitive)
        XCTAssertNil(page.items[1].media.width)
        XCTAssertTrue(page.items[1].sensitive)
        XCTAssertEqual(page.items[1].contentWarning, "수술 자국")
    }

    private struct Row: Identifiable, Hashable {
        let id: Int
    }

    func testThePagerAsksForTheNextPageOnlyAtTheLastRowAndUntilTheServerSaysStop() async {
        var asked: [Int] = []
        let pager = ProfilePager<Row> { page in
            asked.append(page)
            switch page {
            case 0: return ([Row(id: 1), Row(id: 2)], true)
            case 1: return ([Row(id: 2), Row(id: 3)], false)
            default: return ([], false)
            }
        }

        await pager.reload()
        await pager.loadMoreIfNeeded(current: Row(id: 1))
        XCTAssertEqual(asked, [0], "끝 행이 아니면 다음 장을 부르지 않는다")
        await pager.loadMoreIfNeeded(current: Row(id: 2))
        XCTAssertEqual(pager.items.map(\.id), [1, 2, 3], "겹친 행은 한 번만 남는다")
        await pager.loadMoreIfNeeded(current: Row(id: 3))
        XCTAssertEqual(asked, [0, 1], "서버가 다음이 없다고 하면 더 부르지 않는다")
        guard case .loaded = pager.phase else { return XCTFail("받은 뒤에는 loaded") }
    }

    func testAFailedFirstLoadShowsTheErrorAndAReplacedRowKeepsItsPlace() async {
        var fail = true
        let pager = ProfilePager<Row> { _ in
            if fail { throw URLError(.notConnectedToInternet) }
            return ([Row(id: 1), Row(id: 2)], false)
        }

        await pager.reload()
        guard case .failed = pager.phase else { return XCTFail("첫 장을 못 받으면 failed") }
        fail = false
        await pager.reload()
        pager.replace(Row(id: 2))
        pager.remove { $0.id == 1 }
        XCTAssertEqual(pager.items.map(\.id), [2])
    }
}

@MainActor
final class NoteReplyFlowTests: XCTestCase {

    private func note(
        _ id: Int64, author: Int64, replyingTo parent: Int64? = nil, replies: Int64 = 0,
        canReply: String = "null", policy: String = "null"
    ) -> String {
        #"""
        {"id":\#(id),"body":"노트 \#(id)","createdAt":"2026-10-13T00:00:00Z","editedAt":null,"likeCount":null,
         "likedByMe":null,"author":{"id":\#(author),"username":"user\#(author)","bio":null,"avatarUrl":null},
         "media":[],"quotedPost":null,"inReplyToId":\#(parent.map(String.init) ?? "null"),
         "replyCount":\#(replies),"repostCount":null,"repostedByMe":null,"quotedNote":null,
         "canReply":\#(canReply),"replyPolicy":\#(policy)}
        """#
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder.blog.decode(T.self, from: Data(json.utf8))
    }

    private func thread(continuation: [String] = []) throws -> NoteThread {
        try decode(#"""
            {"note":\#(note(1, author: 2, replies: 2)),
             "parent":\#(note(9, author: 4, replies: 1)),
             "replies":[\#(note(10, author: 3, replyingTo: 1)),\#(note(11, author: 5, replyingTo: 1))],
             "continuation":[\#(continuation.joined(separator: ","))]}
            """#)
    }

    func testAReplyToTheFocalNoteLandsAtTheTopOfTheReplies() throws {
        let reply: Note = try decode(note(20, author: 3, replyingTo: 1))
        let placed = try thread().adding(reply)

        XCTAssertEqual(placed.landing, .replies)
        XCTAssertEqual(placed.thread.replies.map(\.id), [20, 10, 11])
        XCTAssertEqual(placed.thread.note.replyCount, 3)
        XCTAssertEqual(placed.thread.continuation?.map(\.id), [])
    }

    func testTheWritersFirstReplyToTheirOwnNoteContinuesTheirThread() throws {
        let reply: Note = try decode(note(20, author: 2, replyingTo: 1))
        let placed = try thread().adding(reply)

        XCTAssertEqual(placed.landing, .continuation)
        XCTAssertEqual(placed.thread.continuation?.map(\.id), [20])
        XCTAssertEqual(placed.thread.replies.map(\.id), [10, 11])
        XCTAssertEqual(placed.thread.note.replyCount, 3)
    }

    func testTheWritersReplyToTheirLastPartExtendsTheirThread() throws {
        let parts = [note(5, author: 2, replyingTo: 1, replies: 1), note(6, author: 2, replyingTo: 5)]
        let reply: Note = try decode(note(20, author: 2, replyingTo: 6))
        let placed = try thread(continuation: parts).adding(reply)

        XCTAssertEqual(placed.landing, .continuation)
        XCTAssertEqual(placed.thread.continuation?.map(\.id), [5, 6, 20])
        XCTAssertEqual(placed.thread.continuation?.map(\.replyCount), [1, 1, 0])
        XCTAssertEqual(placed.thread.note.replyCount, 2)
    }

    func testTheWritersSecondReplyToTheirOwnNoteIsAnOrdinaryReply() throws {
        let reply: Note = try decode(note(20, author: 2, replyingTo: 1))
        let placed = try thread(continuation: [note(5, author: 2, replyingTo: 1)]).adding(reply)

        XCTAssertEqual(placed.landing, .replies)
        XCTAssertEqual(placed.thread.continuation?.map(\.id), [5])
        XCTAssertEqual(placed.thread.replies.first?.id, 20)
    }

    func testAReplyToAnotherNoteInTheThreadOnlyCountsWhereItWent() throws {
        let toReply: Note = try decode(note(20, author: 3, replyingTo: 11))
        let underReply = try thread().adding(toReply)
        XCTAssertEqual(underReply.landing, .elsewhere)
        XCTAssertEqual(underReply.thread.replies.map(\.id), [10, 11])
        XCTAssertEqual(underReply.thread.replies.map(\.replyCount), [0, 1])
        XCTAssertEqual(underReply.thread.note.replyCount, 2)

        let toParent: Note = try decode(note(21, author: 3, replyingTo: 9))
        let underParent = try thread().adding(toParent)
        XCTAssertEqual(underParent.landing, .elsewhere)
        XCTAssertEqual(underParent.thread.parent?.replyCount, 2)
        XCTAssertEqual(underParent.thread.replies.map(\.id), [10, 11])
    }

    func testReplyEntriesFollowTheThreadsReplyPolicy() throws {
        let open: Note = try decode(note(1, author: 2, canReply: "true", policy: #""following""#))
        let unknown: Note = try decode(note(1, author: 2))
        let following: Note = try decode(note(1, author: 2, canReply: "false", policy: #""following""#))
        let mentioned: Note = try decode(note(1, author: 2, canReply: "false", policy: #""mentioned""#))
        let unnamed: Note = try decode(note(1, author: 2, canReply: "false", policy: #""someday""#))

        XCTAssertEqual(NoteReplyAccess(open, signedIn: true), .open)
        XCTAssertEqual(NoteReplyAccess(unknown, signedIn: true), .open)
        XCTAssertEqual(NoteReplyAccess(following, signedIn: true), .closed(.following))
        XCTAssertEqual(NoteReplyAccess(mentioned, signedIn: true), .closed(.mentioned))
        XCTAssertEqual(NoteReplyAccess(unnamed, signedIn: true), .closed(nil))
        XCTAssertEqual(NoteReplyAccess(following, signedIn: false), .needsSignIn)
        XCTAssertTrue(NoteReplyAccess(mentioned, signedIn: true).isClosed)
        XCTAssertNotNil(NoteReplyAccess(unnamed, signedIn: true).notice)
        XCTAssertNil(NoteReplyAccess(open, signedIn: true).notice)
        XCTAssertNil(NoteReplyAccess(following, signedIn: false).notice)
    }
}
