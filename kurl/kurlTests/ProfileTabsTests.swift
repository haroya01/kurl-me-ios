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
