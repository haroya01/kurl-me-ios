//
//  TakenDownTests.swift
//  kurlTests
//
//  관리자가 내린 글(서버 #805) — 글은 status 그대로에 takenDown 만 붙어 오고, 공개 시도는 409 POST_TAKEN_DOWN,
//  정지·제한 계정의 공개 쓰기는 403 ACCOUNT_SUSPENDED/BANNED 다. 서버 detail(영어) 대신 사람 문구를 보인다.
//

import XCTest

@testable import kurl

final class TakenDownTests: XCTestCase {

    private func decode(_ json: String) throws -> MyPost {
        try JSONDecoder.blog.decode(MyPost.self, from: Data(json.utf8))
    }

    func testATakenDownPostKeepsItsStatusAndCarriesTheFlag() throws {
        let post = try decode(#"{"id":7,"slug":"p-7","title":"제목","status":"UNPUBLISHED","takenDown":true}"#)
        XCTAssertTrue(post.isUnpublished)
        XCTAssertTrue(post.isTakenDown)
    }

    func testAServerThatSendsNoFlagReadsAsNotTakenDown() throws {
        XCTAssertFalse(try decode(#"{"id":7,"slug":"p-7","title":"제목","status":"UNPUBLISHED"}"#).isTakenDown)
        XCTAssertFalse(try decode(#"{"id":7,"slug":"p-7","title":"제목","status":"DRAFT","takenDown":false}"#).isTakenDown)
    }

    func testRefusalsReadAsPeopleWordsNotTheServersDetail() {
        let takenDown = APIError.server(status: 409, code: "POST_TAKEN_DOWN", detail: "post was taken down by an admin")
        XCTAssertEqual(takenDown.localizedDescription, "운영 정책으로 내려진 글이라 다시 공개할 수 없어요.")
        let suspended = APIError.server(status: 403, code: "ACCOUNT_SUSPENDED", detail: "account is suspended")
        XCTAssertEqual(suspended.localizedDescription, "계정이 일시 정지된 동안에는 글을 쓰거나 반응할 수 없어요.")
        let other = APIError.server(status: 409, code: "SLUG_CONFLICT", detail: "slug already used: a")
        XCTAssertEqual(other.localizedDescription, "slug already used: a")
    }

    func testTheEditorSaysDraftsStillWorkForASuspendedWriter() {
        let suspended = APIError.server(status: 403, code: "ACCOUNT_SUSPENDED", detail: "account is suspended")
        XCTAssertEqual(
            ComposeView.composeReason(suspended),
            "계정이 일시 정지된 동안에는 글을 공개하거나 공개된 글을 고칠 수 없어요. 초안은 계속 쓸 수 있어요.")
        let banned = APIError.server(status: 403, code: "ACCOUNT_BANNED", detail: "account is banned")
        XCTAssertEqual(ComposeView.composeReason(banned), "이용이 제한된 계정이라 글을 공개하거나 공개된 글을 고칠 수 없어요.")
    }

    func testOnlyATakenDownRefusalMarksThePost() {
        XCTAssertTrue(ComposeView.isTakenDownRefusal(
            APIError.server(status: 409, code: "POST_TAKEN_DOWN", detail: "")))
        XCTAssertFalse(ComposeView.isTakenDownRefusal(
            APIError.server(status: 409, code: "POST_EDIT_CONFLICT", detail: "")))
        XCTAssertFalse(ComposeView.isTakenDownRefusal(APIError.http(status: 409)))
    }
}
