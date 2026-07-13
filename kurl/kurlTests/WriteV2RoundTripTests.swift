//
//  WriteV2RoundTripTests.swift
//  kurlTests
//
//  블록 ↔ 마크다운 왕복 회귀 — 스왑의 핵심. 마크다운(현행 ComposeView 방언) → 블록 → 마크다운이
//  안정(고정점)이어야 기존 저장/서버 md→blocks 와 무손실 호환된다. Phase 1 스코프:
//  문단 · 제목 h1~3 · 인용 · 코드[lang] + Phase 1 밖 구조의 "문단 보존" 무손실.
//

import XCTest

@testable import kurl

final class WriteV2RoundTripTests: XCTestCase {

    /// parse → serialize 가 원문과 같아야 한다(정규화된 방언 기준).
    private func assertRoundTrip(
        _ markdown: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let blocks = MarkdownBlockParser.parse(markdown)
        let out = MarkdownSerializer.markdown(from: blocks)
        XCTAssertEqual(out, markdown, "왕복 불일치", file: file, line: line)
    }

    // MARK: 블록 종류별 왕복

    func testParagraph() {
        assertRoundTrip("그냥 한 문단.")
    }

    func testParagraphWithInline() {
        assertRoundTrip("이건 **볼드**와 *이탤릭*, 그리고 `코드` 가 섞인 문단.")
    }

    func testHeadings() {
        assertRoundTrip("# 제목 1")
        assertRoundTrip("## 제목 2")
        assertRoundTrip("### 제목 3")
    }

    func testQuote() {
        assertRoundTrip("> 한 줄 인용.")
    }

    func testMultilineQuote() {
        assertRoundTrip("> 첫 줄\n> 둘째 줄")
    }

    func testCodeWithLanguage() {
        assertRoundTrip("```swift\nlet x = 5\nprint(x)\n```")
    }

    func testCodeWithoutLanguage() {
        assertRoundTrip("```\nplain code\n```")
    }

    // MARK: 여러 블록 문서

    func testMixedDocument() {
        let md = """
        # 제목

        첫 문단은 **볼드** 포함.

        ## 소제목

        > 인용 한 줄.

        ```swift
        func f() {}
        ```

        마지막 문단.
        """
        assertRoundTrip(md)
    }

    // MARK: 블록 개수·종류 파싱 검증

    func testParseBlockCountsAndKinds() {
        let md = """
        # 제목

        문단.

        > 인용.

        ```py
        x = 1
        ```
        """
        let blocks = MarkdownBlockParser.parse(md)
        XCTAssertEqual(blocks.count, 4)
        XCTAssertEqual(blocks[0].kind, .heading(level: 1))
        XCTAssertEqual(blocks[0].text, "제목")
        XCTAssertEqual(blocks[1].kind, .paragraph)
        XCTAssertEqual(blocks[2].kind, .quote)
        XCTAssertEqual(blocks[2].text, "인용.")
        XCTAssertEqual(blocks[3].kind, .code(language: "py"))
        XCTAssertEqual(blocks[3].text, "x = 1")
    }

    // MARK: Phase 2 블록 — 왕복 무손실 (정본 방언)

    func testDivider() {
        assertRoundTrip("---")
    }

    func testDividerBetweenParagraphs() {
        assertRoundTrip("위 문단.\n\n---\n\n아래 문단.")
    }

    func testBulletList() {
        assertRoundTrip("- 항목 하나\n- 항목 둘")
    }

    func testNestedBulletList() {
        assertRoundTrip("- 상위\n  - 하위\n  - 하위 둘\n- 다시 상위")
    }

    func testOrderedList() {
        assertRoundTrip("1. 첫째\n2. 둘째\n3. 셋째")
    }

    func testMixedListThenParagraph() {
        assertRoundTrip("- 항목\n- 항목 둘\n\n리스트 뒤 문단.")
    }

    func testImage() {
        assertRoundTrip("![대체 텍스트](https://kurl.me/a.jpg)")
    }

    func testImageEmptyAlt() {
        assertRoundTrip("![](https://kurl.me/a.jpg)")
    }

    func testTableRoundTrip() {
        // 정본 방언: leading=`---`, center=`:---:`, trailing=`---:` / 셀 사이 ` | ` / 양 끝 `| … |`.
        let md = "| 언어 | 용도 |\n| --- | ---: |\n| Swift | iOS |\n| Kotlin | Android |"
        assertRoundTrip(md)
    }

    func testTableCenterAlignment() {
        assertRoundTrip("| a | b | c |\n| --- | :---: | ---: |\n| 1 | 2 | 3 |")
    }

    func testTableEmptyCellsPreserved() {
        assertRoundTrip("| a | b | c |\n| --- | --- | --- |\n| 1 |  | 3 |")
    }

    // MARK: 방언 정규화 — 비정본 입력이 정본으로 수렴(왕복 고정점)

    func testStarBulletNormalizesToDash() {
        let blocks = MarkdownBlockParser.parse("* 항목")
        XCTAssertEqual(MarkdownSerializer.markdown(from: blocks), "- 항목")
    }

    func testLeadingColonAlignmentNormalizes() {
        // `:---`(왼쪽) 은 정본 `---` 로 정규화 — 정렬 의미는 보존, 바이트는 수렴.
        let blocks = MarkdownBlockParser.parse("| a |\n| :--- |\n| 1 |")
        XCTAssertEqual(MarkdownSerializer.markdown(from: blocks), "| a |\n| --- |\n| 1 |")
    }

    func testDividerNotConfusedWithTableSeparator() {
        // 파이프 없는 `---` = 구분선. 파이프 있는 구분행은 표 안에서만.
        let blocks = MarkdownBlockParser.parse("---")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].kind, .divider)
    }

    // MARK: 파싱 검증 — 종류·필드

    func testParseListKinds() {
        let blocks = MarkdownBlockParser.parse("- a\n  - b\n1. c")
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].kind, .listItem(ordered: false, indent: 0))
        XCTAssertEqual(blocks[1].kind, .listItem(ordered: false, indent: 1))
        XCTAssertEqual(blocks[1].text, "b")
        XCTAssertEqual(blocks[2].kind, .listItem(ordered: true, indent: 0))
    }

    func testParseImageFields() {
        let blocks = MarkdownBlockParser.parse("![alt 텍스트](https://kurl.me/x.png)")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].kind, .image(url: "https://kurl.me/x.png"))
        XCTAssertEqual(blocks[0].text, "alt 텍스트")
    }

    func testParseTableFields() {
        let blocks = MarkdownBlockParser.parse("| h1 | h2 |\n| --- | :---: |\n| a | b |")
        XCTAssertEqual(blocks.count, 1)
        guard case .table(let table) = blocks[0].kind else { return XCTFail("표 아님") }
        XCTAssertEqual(table.rows.count, 2)
        XCTAssertEqual(table.rows[0], ["h1", "h2"])
        XCTAssertEqual(table.rows[1], ["a", "b"])
        XCTAssertEqual(table.alignments, [.leading, .center])
    }

    func testImageWithTextIsParagraph() {
        // 텍스트가 섞인 이미지 줄은 단독 이미지가 아니므로 문단으로(하이라이터 규칙).
        let blocks = MarkdownBlockParser.parse("보세요 ![x](u) 이미지")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].kind, .paragraph)
    }

    // MARK: 편집 연산
    // EditorDocument 는 @MainActor @Observable — XCTest 에서 동기 @MainActor 메서드는 이 런타임(Xcode 27
    // 베타 / iOS 26 sim)에서 SIGABRT 로 죽는다. async 메서드로 두고 MainActor.run 안에서 문서를 다뤄 회피.

    func testSplitBlock() async {
        await MainActor.run {
            let doc = EditorDocument(blocks: [.paragraph("안녕세상")])
            let id = doc.blocks[0].id
            doc.splitBlock(id, at: 2)
            XCTAssertEqual(doc.blocks.count, 2)
            XCTAssertEqual(doc.blocks[0].text, "안녕")
            XCTAssertEqual(doc.blocks[1].text, "세상")
            XCTAssertEqual(doc.focus?.blockID, doc.blocks[1].id)
            XCTAssertEqual(doc.focus?.caret, 0)
        }
    }

    func testMergeBackward() async {
        await MainActor.run {
            let doc = EditorDocument(blocks: [.paragraph("안녕"), .paragraph("세상")])
            let second = doc.blocks[1].id
            doc.mergeBackward(second)
            XCTAssertEqual(doc.blocks.count, 1)
            XCTAssertEqual(doc.blocks[0].text, "안녕세상")
            XCTAssertEqual(doc.focus?.caret, 2)  // 앞 블록 원래 길이
        }
    }

    func testSplitThenMergeIsIdentity() async {
        await MainActor.run {
            let doc = EditorDocument(blocks: [.paragraph("한줄문단")])
            let id = doc.blocks[0].id
            doc.splitBlock(id, at: 2)
            let second = doc.blocks[1].id
            doc.mergeBackward(second)
            XCTAssertEqual(doc.blocks.count, 1)
            XCTAssertEqual(doc.blocks[0].text, "한줄문단")
        }
    }

    func testFirstBlockBackspaceDemotesHeadingToParagraph() async {
        await MainActor.run {
            let doc = EditorDocument(blocks: [.heading(2, "제목")])
            let id = doc.blocks[0].id
            doc.mergeBackward(id)
            XCTAssertEqual(doc.blocks[0].kind, .paragraph)
            XCTAssertEqual(doc.blocks[0].text, "제목")
        }
    }

    // MARK: Phase 2 편집 연산 — 리스트

    func testListItemEnterMakesNewItem() async {
        await MainActor.run {
            let doc = EditorDocument(blocks: [.listItem("첫", ordered: false, indent: 0)])
            let id = doc.blocks[0].id
            doc.splitBlock(id, at: 1)  // "첫" 뒤에서 엔터
            XCTAssertEqual(doc.blocks.count, 2)
            XCTAssertEqual(doc.blocks[1].kind, .listItem(ordered: false, indent: 0))
        }
    }

    func testEnterOnEmptyListItemExitsList() async {
        await MainActor.run {
            // 빈 항목에서 엔터 = 리스트 탈출(indent 0 이면 문단).
            let doc = EditorDocument(blocks: [.listItem("", ordered: false, indent: 0)])
            let id = doc.blocks[0].id
            doc.splitBlock(id, at: 0)
            XCTAssertEqual(doc.blocks.count, 1)
            XCTAssertEqual(doc.blocks[0].kind, .paragraph)
        }
    }

    func testEnterOnEmptyNestedItemOutdents() async {
        await MainActor.run {
            let doc = EditorDocument(blocks: [.listItem("", ordered: false, indent: 2)])
            let id = doc.blocks[0].id
            doc.splitBlock(id, at: 0)
            XCTAssertEqual(doc.blocks[0].kind, .listItem(ordered: false, indent: 1))
        }
    }

    func testBackspaceAtListStartOutdentsThenParagraph() async {
        await MainActor.run {
            let doc = EditorDocument(blocks: [.listItem("항목", ordered: true, indent: 1)])
            let id = doc.blocks[0].id
            doc.mergeBackward(id)  // indent 1 → 0
            XCTAssertEqual(doc.blocks[0].kind, .listItem(ordered: true, indent: 0))
            doc.mergeBackward(id)  // 0 → 문단
            XCTAssertEqual(doc.blocks[0].kind, .paragraph)
            XCTAssertEqual(doc.blocks[0].text, "항목")
        }
    }

    func testIndentOutdentListItem() async {
        await MainActor.run {
            let doc = EditorDocument(blocks: [.listItem("x", ordered: false, indent: 0)])
            let id = doc.blocks[0].id
            doc.indentListItem(id)
            XCTAssertEqual(doc.blocks[0].kind, .listItem(ordered: false, indent: 1))
            doc.outdentListItem(id)
            XCTAssertEqual(doc.blocks[0].kind, .listItem(ordered: false, indent: 0))
        }
    }

    // MARK: Phase 2 편집 연산 — 비텍스트 블록

    func testInsertNonTextAddsTrailingParagraph() async {
        await MainActor.run {
            let doc = EditorDocument(blocks: [.paragraph("본문")])
            doc.focus = EditorFocus(blockID: doc.blocks[0].id, caret: 2)
            doc.insertNonText(.divider)
            XCTAssertEqual(doc.blocks.count, 3)  // 문단 · 구분선 · 새 빈 문단
            XCTAssertEqual(doc.blocks[1].kind, .divider)
            XCTAssertEqual(doc.blocks[2].kind, .paragraph)
            XCTAssertEqual(doc.focus?.blockID, doc.blocks[2].id)
        }
    }

    func testBackspaceDeletesPrecedingNonTextBlock() async {
        await MainActor.run {
            let doc = EditorDocument(blocks: [.divider, .paragraph("뒤")])
            let pID = doc.blocks[1].id
            doc.mergeBackward(pID)  // 문단 맨 앞 백스페이스 → 앞 구분선 삭제
            XCTAssertEqual(doc.blocks.count, 1)
            XCTAssertEqual(doc.blocks[0].kind, .paragraph)
            XCTAssertEqual(doc.blocks[0].text, "뒤")
        }
    }

    func testTableCellEditAndRoundTrip() async {
        await MainActor.run {
            let table = EditorTable(rows: [["a", "b"], ["c", "d"]], alignments: [.leading, .leading])
            let doc = EditorDocument(blocks: [.table(table)])
            let id = doc.blocks[0].id
            doc.updateTableCell(id, row: 1, col: 0, text: "변경")
            doc.addTableRow(id)
            doc.cycleTableColumnAlignment(id, col: 1)  // leading → center
            let md = doc.markdown
            // 다시 파싱해도 편집 결과가 살아있다.
            let reparsed = MarkdownBlockParser.parse(md)
            guard case .table(let t) = reparsed[0].kind else { return XCTFail("표 아님") }
            XCTAssertEqual(t.rows[1][0], "변경")
            XCTAssertEqual(t.rows.count, 3)  // 헤더 + 본문 2 (빈 행 추가)
            XCTAssertEqual(t.alignments[1], .center)
        }
    }

    // MARK: 줄머리 지름길 감지

    func testHeadingShortcut() {
        let s = BlockShortcuts.detect(in: "## 소제목", kind: .paragraph)
        XCTAssertEqual(s?.kind, .heading(level: 2))
        XCTAssertEqual(s?.strippedText, "소제목")
    }

    func testBulletListShortcut() {
        let s = BlockShortcuts.detect(in: "- 항목", kind: .paragraph)
        XCTAssertEqual(s?.kind, .listItem(ordered: false, indent: 0))
        XCTAssertEqual(s?.strippedText, "항목")
    }

    func testOrderedListShortcut() {
        let s = BlockShortcuts.detect(in: "1. 항목", kind: .paragraph)
        XCTAssertEqual(s?.kind, .listItem(ordered: true, indent: 0))
        XCTAssertEqual(s?.strippedText, "항목")
    }

    func testQuoteShortcut() {
        let s = BlockShortcuts.detect(in: "> 인용", kind: .paragraph)
        XCTAssertEqual(s?.kind, .quote)
        XCTAssertEqual(s?.strippedText, "인용")
    }

    func testCodeShortcut() {
        let s = BlockShortcuts.detect(in: "```swift", kind: .paragraph)
        XCTAssertEqual(s?.kind, .code(language: "swift"))
    }

    func testNoShortcutInNonParagraph() {
        // 이미 제목이면 `# ` 를 리터럴로 칠 수 있어야(지름길 재적용 없음).
        XCTAssertNil(BlockShortcuts.detect(in: "# 다시", kind: .heading(level: 1)))
    }

    func testHashWithoutSpaceIsNotShortcut() {
        XCTAssertNil(BlockShortcuts.detect(in: "#태그", kind: .paragraph))
    }

    // MARK: 문서 초기화 = 마크다운에서

    func testDocumentFromMarkdownProducesSameMarkdown() async {
        await MainActor.run {
            let md = "# 제목\n\n문단 **볼드**.\n\n> 인용."
            let doc = EditorDocument(markdown: md)
            XCTAssertEqual(doc.markdown, md)
        }
    }
}
