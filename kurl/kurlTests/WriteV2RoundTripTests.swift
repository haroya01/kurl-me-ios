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

    // MARK: Phase 1 밖 구조 = 문단으로 보존(무손실)

    func testUnscopedListPreservedAsParagraph() {
        // 리스트는 Phase 2 — 파서가 문단으로 보존해 왕복에서 안 잃는다.
        assertRoundTrip("- 항목 하나\n- 항목 둘")
    }

    func testUnscopedTablePreservedAsParagraph() {
        assertRoundTrip("| a | b |\n| --- | --- |\n| 1 | 2 |")
    }

    // MARK: 편집 연산

    @MainActor
    func testSplitBlock() {
        let doc = EditorDocument(blocks: [.paragraph("안녕세상")])
        let id = doc.blocks[0].id
        doc.splitBlock(id, at: 2)
        XCTAssertEqual(doc.blocks.count, 2)
        XCTAssertEqual(doc.blocks[0].text, "안녕")
        XCTAssertEqual(doc.blocks[1].text, "세상")
        XCTAssertEqual(doc.focus?.blockID, doc.blocks[1].id)
        XCTAssertEqual(doc.focus?.caret, 0)
    }

    @MainActor
    func testMergeBackward() {
        let doc = EditorDocument(blocks: [.paragraph("안녕"), .paragraph("세상")])
        let second = doc.blocks[1].id
        doc.mergeBackward(second)
        XCTAssertEqual(doc.blocks.count, 1)
        XCTAssertEqual(doc.blocks[0].text, "안녕세상")
        XCTAssertEqual(doc.focus?.caret, 2)  // 앞 블록 원래 길이
    }

    @MainActor
    func testSplitThenMergeIsIdentity() {
        let doc = EditorDocument(blocks: [.paragraph("한줄문단")])
        let id = doc.blocks[0].id
        doc.splitBlock(id, at: 2)
        let second = doc.blocks[1].id
        doc.mergeBackward(second)
        XCTAssertEqual(doc.blocks.count, 1)
        XCTAssertEqual(doc.blocks[0].text, "한줄문단")
    }

    @MainActor
    func testFirstBlockBackspaceDemotesHeadingToParagraph() {
        let doc = EditorDocument(blocks: [.heading(2, "제목")])
        let id = doc.blocks[0].id
        doc.mergeBackward(id)
        XCTAssertEqual(doc.blocks[0].kind, .paragraph)
        XCTAssertEqual(doc.blocks[0].text, "제목")
    }

    // MARK: 줄머리 지름길 감지

    func testHeadingShortcut() {
        let s = BlockShortcuts.detect(in: "## 소제목", kind: .paragraph)
        XCTAssertEqual(s?.kind, .heading(level: 2))
        XCTAssertEqual(s?.strippedText, "소제목")
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

    @MainActor
    func testDocumentFromMarkdownProducesSameMarkdown() {
        let md = "# 제목\n\n문단 **볼드**.\n\n> 인용."
        let doc = EditorDocument(markdown: md)
        XCTAssertEqual(doc.markdown, md)
    }
}
