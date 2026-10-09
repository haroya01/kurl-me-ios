//
//  PostLimitsTests.swift
//  kurlTests
//
//  글 입력 한도 — 서버(@Size = UTF-16 길이, 태그 10개·40자)를 넘는 입력을 보내 400(새 글이면 초안 생성
//  실패로 자동저장이 계속 실패)이나 조용한 태그 잘림을 당하지 않게 입력 단계에서 같은 기준으로 막는다.
//

import XCTest

@testable import kurl

final class PostLimitsTests: XCTestCase {

    func testClampKeepsTextWithinLimit() {
        XCTAssertEqual(PostLimits.clamped("짧은 제목", to: PostLimits.title), "짧은 제목")
        let long = String(repeating: "가", count: 205)
        XCTAssertEqual(PostLimits.clamped(long, to: PostLimits.title).utf16.count, 200)
    }

    func testClampCountsUTF16LikeTheServerAndNeverSplitsACharacter() {
        let text = "ab😀c"
        XCTAssertEqual(text.utf16.count, 5)
        XCTAssertEqual(PostLimits.clamped(text, to: 3), "ab")
        XCTAssertEqual(PostLimits.clamped(text, to: 4), "ab😀")
        let emoji = String(repeating: "😀", count: 101)
        XCTAssertEqual(PostLimits.clamped(emoji, to: PostLimits.title).count, 100)
    }

    func testNormalizedTagStripsHashTrimsAndCapsAt40UTF16() {
        XCTAssertEqual(PostLimits.normalizedTag("  #개발 "), "개발")
        XCTAssertEqual(PostLimits.normalizedTag(String(repeating: "a", count: 45)).utf16.count, 40)
        XCTAssertEqual(PostLimits.normalizedTag(String(repeating: "😀", count: 25)).utf16.count, 40)
        XCTAssertEqual(PostLimits.normalizedTag(String(repeating: "a", count: 39) + " b"), String(repeating: "a", count: 39))
    }

    func testAddingSplitsCommasAndSkipsCaseInsensitiveDuplicates() {
        XCTAssertEqual(PostLimits.adding("Swift, swift,#iOS,,", to: ["개발"]), ["개발", "Swift", "iOS"])
    }

    func testAddingStopsAtTenTags() {
        let nine = (1...9).map { "t\($0)" }
        XCTAssertEqual(PostLimits.adding("t10,t11,t12", to: nine), nine + ["t10"])
        let ten = nine + ["t10"]
        XCTAssertEqual(PostLimits.adding("more", to: ten), ten)
    }
}
