//
//  TableMarkdownTests.swift
//  kurlTests
//
//  GFM 표 파싱 회귀 — 빈 셀 보존과 헤더 기준 정렬을 고정한다. 빈 셀을 걸러 열이 왼쪽으로
//  밀리던 회귀(웹은 빈 칸 보존)를 막는다.
//

import XCTest

@testable import kurl

final class TableMarkdownTests: XCTestCase {

    func testKeepsInteriorEmptyCells() {
        let md = """
        | 항목 | 유리 | 대안 |
        | 본문 카드 | X | 종이 |
        | 떠 있는 액션 | O |  |
        """
        let rows = TableMarkdown.rows(md)
        XCTAssertEqual(rows.count, 3)
        // 빈 셋째 칸이 지워져 왼쪽으로 밀리지 않고 자리(빈 문자열)를 지킨다.
        XCTAssertEqual(rows[2], ["떠 있는 액션", "O", ""])
    }

    func testKeepsLeadingAndMiddleEmptyCells() {
        // 앞·중간 빈 칸도 보존 — `| a || c |` 같은 표기.
        let rows = TableMarkdown.rows("| a || c |")
        XCTAssertEqual(rows, [["a", "", "c"]])
    }

    func testDropsSeparatorRow() {
        let md = """
        | A | B |
        | --- | :---: |
        | 1 | 2 |
        """
        let rows = TableMarkdown.rows(md)
        // 구분선 행은 렌더 대상에서 빠진다.
        XCTAssertEqual(rows, [["A", "B"], ["1", "2"]])
    }

    func testPadsShortRowToHeaderWidth() {
        let md = """
        | A | B | C |
        | 1 | 2 |
        """
        let rows = TableMarkdown.rows(md)
        // 짧은 행은 헤더 열 수에 맞춰 빈 칸으로 채워 정렬을 지킨다.
        XCTAssertEqual(rows[1], ["1", "2", ""])
    }

    func testTruncatesOverflowRowToHeaderWidth() {
        let md = """
        | A | B |
        | 1 | 2 | 3 |
        """
        let rows = TableMarkdown.rows(md)
        // 넘치는 행은 헤더 열 수로 잘라 어긋남을 막는다.
        XCTAssertEqual(rows[1], ["1", "2"])
    }

    func testHandlesRowsWithoutOuterPipes() {
        // 감싸는 파이프가 없어도 셀을 그대로 가른다.
        let rows = TableMarkdown.rows("a | b | c")
        XCTAssertEqual(rows, [["a", "b", "c"]])
    }
}
