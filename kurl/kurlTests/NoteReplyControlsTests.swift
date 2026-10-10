//
//  NoteReplyControlsTests.swift
//  kurlTests
//
//  답글 제어 필드와 스레드의 숨긴 답글 수·관리 여부 디코딩(옛 서버 포함), 답할 수 없는 이유,
//  초안에 실리는 답글 권한.
//

import XCTest

@testable import kurl

final class NoteReplyControlsTests: XCTestCase {

    private func note(_ extra: String) throws -> Note {
        try JSONDecoder.blog.decode(
            Note.self,
            from: Data(#"""
            {"id":1,"body":"b","createdAt":null,"editedAt":null,"likeCount":null,"likedByMe":null,
             "author":{"id":2,"username":"w","bio":null,"avatarUrl":null},"media":[],"quotedPost":null,
             "inReplyToId":null,"replyCount":0,"repostCount":null,"repostedByMe":null,"quotedNote":null,
             "linkPreview":null\#(extra)}
            """#.utf8))
    }

    func testAnOlderServerWithoutReplyControlsReadsAsOpen() throws {
        let old = try note("")
        XCTAssertNil(old.replyPolicy)
        XCTAssertNil(old.canReply)
        XCTAssertNil(old.hidden)
        XCTAssertEqual(old.noteReplyPolicy, .everyone)
    }

    func testReplyControlsDecode() throws {
        let closed = try note(#","replyPolicy":"mentioned","canReply":false,"hidden":true"#)
        XCTAssertEqual(closed.noteReplyPolicy, .mentioned)
        XCTAssertEqual(closed.canReply, false)
        XCTAssertEqual(closed.hidden, true)

        let anonymous = try note(#","replyPolicy":"following","canReply":null,"hidden":false"#)
        XCTAssertEqual(anonymous.noteReplyPolicy, .following)
        XCTAssertNil(anonymous.canReply)
    }

    func testAPolicyThisAppDoesNotKnowFallsBackToEveryone() throws {
        XCTAssertEqual(try note(#","replyPolicy":"circle""#).noteReplyPolicy, .everyone)
    }

    func testEachPolicyGivesItsOwnReasonForAClosedThread() {
        XCTAssertEqual(
            NoteReplyPolicy.following.closedReason,
            String(localized: "작성자가 팔로우하거나 멘션한 사람만 답글을 달 수 있어요"))
        XCTAssertEqual(
            NoteReplyPolicy.mentioned.closedReason, String(localized: "작성자가 멘션한 사람만 답글을 달 수 있어요"))
        XCTAssertEqual(NoteReplyPolicy.everyone.closedReason, String(localized: "이 스레드에는 답글을 달 수 없어요"))
    }

    private func thread(_ extra: String) throws -> NoteThread {
        let note = #"{"id":1,"body":"b","author":{"id":2,"username":"w","bio":null,"avatarUrl":null},"media":[],"replyCount":0}"#
        return try JSONDecoder.blog.decode(
            NoteThread.self, from: Data(#"{"note":\#(note),"parent":null,"replies":[]\#(extra)}"#.utf8))
    }

    func testAThreadTellsItsHiddenReplyCountAndWhetherTheViewerModeratesIt() throws {
        let fresh = try thread(#","hiddenReplyCount":2,"viewerCanModerate":true"#)
        XCTAssertEqual(fresh.hiddenReplyCount, 2)
        XCTAssertEqual(fresh.viewerCanModerate, true)

        let old = try thread("")
        XCTAssertNil(old.hiddenReplyCount, "옛 서버 — 숨긴 답글 줄을 그리지 않는다")
        XCTAssertNil(old.viewerCanModerate, "옛 서버 — 첫 노트가 보일 때만 추론한다")
    }

    func testTheHiddenRepliesRowCountsInEnglish() {
        let english = Bundle(path: Bundle.main.path(forResource: "en", ofType: "lproj")!)!
        func en(_ value: String.LocalizationValue) -> String {
            String(localized: value, bundle: english, locale: Locale(identifier: "en_US"))
        }
        XCTAssertEqual(en("숨긴 답글 \(1)개 보기"), "Show 1 hidden reply")
        XCTAssertEqual(en("숨긴 답글 \(3)개 보기"), "Show 3 hidden replies")
    }

    func testTheDraftSendsAReplyPolicyOnlyWhenOneIsSet() throws {
        func encoded(_ draft: NoteDraft) throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
        }
        let open = NoteDraft(body: "b", images: [], quotedPostId: nil, inReplyToId: nil)
        XCTAssertNil(try encoded(open)["replyPolicy"], "답글 권한을 안 골랐는데 키가 실림 — 옛 서버와 어긋날 수 있다")

        var limited = open
        limited.replyPolicy = NoteReplyPolicy.following.rawValue
        XCTAssertEqual(try encoded(limited)["replyPolicy"] as? String, "following")
    }
}
