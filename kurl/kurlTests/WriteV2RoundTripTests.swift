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

    // MARK: 통합 링크 삽입 — 링크 vs 동영상 임베드 라우팅 (왕복 계약)

    func testInsertPlainLinkProducesMarkdownLink() async {
        await MainActor.run {
            let doc = EditorDocument(blocks: [.paragraph("본문")])
            doc.focus = EditorFocus(blockID: doc.blocks[0].id, caret: 2)
            doc.insertLink(url: "https://example.com", label: "예시")
            // 링크는 자체 문단 `[예시](url)` 로 앉는다(단독 URL 아님 → 인라인 링크로 발행).
            XCTAssertTrue(doc.markdown.contains("[예시](https://example.com)"))
        }
    }

    func testInsertLinkEmptyLabelUsesURL() async {
        await MainActor.run {
            let doc = EditorDocument(blocks: [.paragraph("")])
            doc.focus = EditorFocus(blockID: doc.blocks[0].id, caret: 0)
            doc.insertLink(url: "https://example.com/a", label: "")
            XCTAssertTrue(doc.markdown.contains("[https://example.com/a](https://example.com/a)"))
        }
    }

    func testInsertVideoLinkProducesStandaloneURLForEmbed() async {
        await MainActor.run {
            let doc = EditorDocument(blocks: [.paragraph("본문")])
            doc.focus = EditorFocus(blockID: doc.blocks[0].id, caret: 2)
            doc.insertLink(url: "https://youtu.be/dQw4w9WgXcQ", label: "무시됨")
            // 동영상은 단독 URL 문단으로 — 발행 md→blocks 가 EMBED 로 접는다(대괄호 링크 아님).
            XCTAssertFalse(doc.markdown.contains("["))
            XCTAssertTrue(doc.markdown.contains("https://youtu.be/dQw4w9WgXcQ"))
            // 그 URL 이 제 문단에 홀로 서야 한다(앞뒤 빈 줄).
            XCTAssertTrue(doc.markdown.contains("\n\nhttps://youtu.be/dQw4w9WgXcQ"))
        }
    }

    // MARK: 동영상 URL 판정 — 발행면(BlockRenderer) 규칙 미러

    func testVideoDetectYouTube() {
        XCTAssertTrue(WriteV2VideoDetect.isVideoURL("https://youtu.be/dQw4w9WgXcQ"))
        XCTAssertTrue(WriteV2VideoDetect.isVideoURL("https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
        XCTAssertTrue(WriteV2VideoDetect.isVideoURL("https://youtube.com/shorts/abc123"))
    }

    func testVideoDetectVimeo() {
        XCTAssertTrue(WriteV2VideoDetect.isVideoURL("https://vimeo.com/123456789"))
    }

    func testVideoDetectRejectsPlainLink() {
        XCTAssertFalse(WriteV2VideoDetect.isVideoURL("https://example.com/watch?v=x"))
        XCTAssertFalse(WriteV2VideoDetect.isVideoURL("https://vimeo.com/channels/foo"))  // 숫자 id 아님
        XCTAssertFalse(WriteV2VideoDetect.isVideoURL("https://kurl.me/post/1"))
    }

    // MARK: 인라인 라이브 렌더 — 마커 은닉 / 반개봉

    /// 활성 범위가 없으면(비포커스) `**볼드**` 의 마커(`**`)는 clear 색으로 숨는다(최종 모습).
    func testInlineRenderHidesBoldMarkersWhenInactive() {
        let block = EditorBlock.paragraph("앞 **굵게** 뒤")
        let rendered = BlockInlineRenderer.render(block, activeRange: nil)
        // "앞 " = 0..2, "**" = 3..4 (마커 시작). 마커 첫 글자(index 3)의 색이 clear 여야.
        let markerColor = rendered.attribute(
            .foregroundColor, at: 3, effectiveRange: nil) as? UIColor
        XCTAssertEqual(markerColor, UIColor.clear, "비활성 마커는 숨겨야(clear)")
    }

    /// 캐럿이 그 마크업에 걸치면 양쪽 마커가 함께 faint 로 노출된다(반개봉).
    func testInlineRenderRevealsBoldMarkersWhenActive() {
        let block = EditorBlock.paragraph("앞 **굵게** 뒤")
        // "앞 "=0..1, "**"=2..3, "굵게"=4..5, "**"=6..7. 캐럿을 "굵게" 안(5)에 두면 span(2..7)이 열린다.
        let rendered = BlockInlineRenderer.render(block, activeRange: NSRange(location: 5, length: 0))
        // 여는 마커(index 3)와 닫는 마커(index 6)가 둘 다 faint 여야.
        let openMarker = rendered.attribute(.foregroundColor, at: 3, effectiveRange: nil) as? UIColor
        XCTAssertEqual(openMarker, UIColor(Palette.faint), "활성 마크업 여는 마커는 흐리게 노출")
        let closeMarker = rendered.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? UIColor
        XCTAssertEqual(closeMarker, UIColor(Palette.faint), "활성 마크업 닫는 마커도 함께 노출")
    }

    /// 링크 `[라벨](url)` — 비활성이면 라벨만 링크색으로 남고 `[`·`](url)` 은 숨는다.
    func testInlineRenderLinkShowsLabelHidesURL() {
        let block = EditorBlock.paragraph("[라벨](https://kurl.me)")
        let rendered = BlockInlineRenderer.render(block, activeRange: nil)
        // index 0 = "[" (마커) → clear. index 1 = "라"(라벨) → 링크색.
        let bracket = rendered.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        XCTAssertEqual(bracket, UIColor.clear, "여는 대괄호는 숨김")
        let label = rendered.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? UIColor
        XCTAssertEqual(label, UIColor(Palette.link), "라벨은 링크색")
        // 라벨 뒤 `](url)` 첫 글자(index 3 = "]")는 숨김.
        let tail = rendered.attribute(.foregroundColor, at: 3, effectiveRange: nil) as? UIColor
        XCTAssertEqual(tail, UIColor.clear, "링크 꼬리(url)는 숨김")
    }

    /// 인라인 코드는 안쪽이 모노 + 칩 배경, 백틱은 숨는다.
    func testInlineRenderInlineCodeStyled() {
        let block = EditorBlock.paragraph("`코드`")
        let rendered = BlockInlineRenderer.render(block, activeRange: nil)
        // index 0 = "`" 마커 → clear. index 1 = "코"(코드) → 인라인코드 배경.
        let tick = rendered.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        XCTAssertEqual(tick, UIColor.clear, "백틱은 숨김")
        let bg = rendered.attribute(.backgroundColor, at: 1, effectiveRange: nil) as? UIColor
        XCTAssertEqual(bg, UIColor(Palette.inlineCodeBg), "코드 안쪽은 칩 배경")
    }

    /// 링크 url 안의 `*`·`**` 는 강조가 아니라 링크 문법 — 볼드/이탤릭 패스가 건드려 url 을 깨면 안 된다.
    func testInlineRenderLinkURLWithAsteriskNotMangled() {
        // url 에 별표쌍이 있는 링크. 라벨은 "k", url 은 별표를 포함.
        let block = EditorBlock.paragraph("[k](https://a.com/*b*)")
        // 캐럿을 링크에 넣어 반개봉(url 이 흐리게 드러난다). 이때 url 안 `*` 가 숨겨지면(clear) 버그.
        let rendered = BlockInlineRenderer.render(block, activeRange: NSRange(location: 3, length: 0))
        let ns = block.text as NSString
        let star1 = ns.range(of: "*")
        // 그 `*` 는 링크 꼬리(url)의 일부라 faint(반개봉)여야지, italic 마커로 오인돼 clear 로 숨으면 안 된다.
        let color = rendered.attribute(.foregroundColor, at: star1.location, effectiveRange: nil) as? UIColor
        XCTAssertEqual(color, UIColor(Palette.faint), "url 안 별표는 링크 문법(faint), italic 마커로 숨기지 않음")
    }

    // MARK: activeMarkupSpan — 캐럿이 걸친 마크업 판정(재렌더 게이팅용)

    func testActiveMarkupSpanInsideBold() {
        // "앞 **굵게** 뒤" — "굵게"는 4..5. 캐럿 5는 볼드 span(2..8) 안.
        let span = BlockInlineRenderer.activeMarkupSpan(in: "앞 **굵게** 뒤", caret: 5)
        XCTAssertNotNil(span)
        XCTAssertEqual(span, NSRange(location: 2, length: 6))
    }

    func testActiveMarkupSpanOutsideMarkupIsNil() {
        // 캐럿 0(문단 맨 앞, 마크업 밖) → nil.
        let span = BlockInlineRenderer.activeMarkupSpan(in: "앞 **굵게** 뒤", caret: 0)
        XCTAssertNil(span)
    }

    func testActiveMarkupSpanNoMarkup() {
        let span = BlockInlineRenderer.activeMarkupSpan(in: "그냥 문단", caret: 2)
        XCTAssertNil(span)
    }

    // MARK: 초안 네이티브 미리보기 — 마크다운 → PostBlock 매핑(리더 계약)

    func testDraftPreviewMapsHeadingAndParagraph() {
        let blocks = DraftPreviewBlocks.from(markdown: "# 제목\n\n본문 **볼드**.")
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].kind, .h1)
        XCTAssertEqual(blocks[0].content, "제목")
        XCTAssertEqual(blocks[1].kind, .paragraph)
        XCTAssertEqual(blocks[1].content, "본문 **볼드**.")
    }

    func testDraftPreviewMapsQuoteAndDivider() {
        let blocks = DraftPreviewBlocks.from(markdown: "> 인용.\n\n---")
        XCTAssertEqual(blocks.map(\.kind), [.quote, .divider])
        XCTAssertEqual(blocks[0].content, "인용.")
    }

    func testDraftPreviewMapsCodeAsJSON() {
        let blocks = DraftPreviewBlocks.from(markdown: "```swift\nlet x = 5\n```")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].kind, .code)
        // content 는 CodePayload 가 먹는 {"lang","code"} JSON.
        let data = Data((blocks[0].content ?? "").utf8)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        XCTAssertEqual(json?["lang"] as? String, "swift")
        XCTAssertEqual(json?["code"] as? String, "let x = 5")
    }

    func testDraftPreviewMapsBulletListAsLines() {
        let blocks = DraftPreviewBlocks.from(markdown: "- 하나\n- 둘")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].kind, .listBullet)
        // content 는 줄바꿈으로 이은 항목(리더 parseListItems 의 선행공백=깊이 경로).
        XCTAssertEqual(blocks[0].content, "하나\n둘")
    }

    func testDraftPreviewMapsNumberedList() {
        let blocks = DraftPreviewBlocks.from(markdown: "1. 첫째\n2. 둘째")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].kind, .listNumbered)
    }

    func testDraftPreviewNestedListPreservesIndent() {
        // 중첩 리스트 — 하위 항목은 선행 공백 2칸으로(리더가 depth 로 읽는다).
        let blocks = DraftPreviewBlocks.from(markdown: "- 상위\n  - 하위")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].kind, .listBullet)
        XCTAssertEqual(blocks[0].content, "상위\n  하위")
    }

    func testDraftPreviewMapsImageWithWidthMarker() {
        // 이미지 alt 앞 «half» 폭 마커 → IMAGE payload 의 width.
        let blocks = DraftPreviewBlocks.from(markdown: "![«half» 대체](https://kurl.me/a.jpg)")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].kind, .image)
        let data = Data((blocks[0].content ?? "").utf8)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        XCTAssertEqual(json?["url"] as? String, "https://kurl.me/a.jpg")
        XCTAssertEqual(json?["width"] as? String, "half")
        XCTAssertEqual(json?["alt"] as? String, "대체")
    }

    func testDraftPreviewMapsTableAsGFM() {
        let md = "| a | b |\n| --- | --- |\n| 1 | 2 |"
        let blocks = DraftPreviewBlocks.from(markdown: md)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].kind, .table)
        // TABLE content 는 GFM 원문(리더 TableBlockView(markdown:)가 먹는다).
        XCTAssertEqual(blocks[0].content, md)
    }

    func testDraftPreviewMapsVideoURLAsEmbed() {
        let blocks = DraftPreviewBlocks.from(markdown: "https://youtu.be/dQw4w9WgXcQ")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].kind, .embed)
        let data = Data((blocks[0].content ?? "").utf8)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        XCTAssertEqual(json?["url"] as? String, "https://youtu.be/dQw4w9WgXcQ")
    }

    func testDraftPreviewPlainLinkStaysParagraph() {
        // 동영상 아닌 단독 URL 은 문단(임베드 아님).
        let blocks = DraftPreviewBlocks.from(markdown: "https://kurl.me/post/1")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].kind, .paragraph)
    }

    func testDraftPreviewEmptyIsSingleEmptyParagraph() {
        // 빈 입력 — 파서가 빈 문단 1개를 돌려주고, 뷰는 이걸 빈 상태로 취급.
        let blocks = DraftPreviewBlocks.from(markdown: "")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].kind, .paragraph)
        XCTAssertEqual(blocks[0].content ?? "", "")
    }

    /// 미리보기 매핑은 표시용 — 저장 마크다운 왕복은 그대로여야(프리뷰가 계약을 바꾸지 않는다).
    func testDraftPreviewDoesNotAlterRoundTrip() {
        let md = "# 제목\n\n본문.\n\n> 인용.\n\n```swift\nlet x = 5\n```\n\n- 항목\n- 항목 둘"
        _ = DraftPreviewBlocks.from(markdown: md)  // 매핑을 돌려도
        // 왕복(parse→serialize)은 불변.
        let reserialized = MarkdownSerializer.markdown(from: MarkdownBlockParser.parse(md))
        XCTAssertEqual(reserialized, md)
    }

    // MARK: 서식 툴바 — 인라인 감싸기 / 블록 토글

    func testWrapSelectionBold() async {
        await MainActor.run {
            let doc = EditorDocument(blocks: [.paragraph("안녕세상")])
            let id = doc.blocks[0].id
            // "세상"(2..4) 선택 상태로 focus.
            doc.focus = EditorFocus(blockID: id, caret: 2, selectionLength: 2)
            doc.wrapFocusedSelection(with: "**")
            XCTAssertEqual(doc.blocks[0].text, "안녕**세상**")
            // 안쪽("세상")을 다시 선택 — 마커(2) 뒤부터 2글자.
            XCTAssertEqual(doc.focus?.caret, 4)
            XCTAssertEqual(doc.focus?.selectionLength, 2)
        }
    }

    func testWrapSelectionItalicNoSelectionInsertsMarkersWithCaretBetween() async {
        await MainActor.run {
            let doc = EditorDocument(blocks: [.paragraph("가나")])
            let id = doc.blocks[0].id
            doc.focus = EditorFocus(blockID: id, caret: 1, selectionLength: 0)  // "가|나"
            doc.wrapFocusedSelection(with: "*")
            XCTAssertEqual(doc.blocks[0].text, "가**나")  // `*` + `` + `*` 삽입
            XCTAssertEqual(doc.focus?.caret, 2)  // 두 별표 사이
            XCTAssertEqual(doc.focus?.selectionLength, 0)
        }
    }

    func testWrapSelectionInlineCode() async {
        await MainActor.run {
            let doc = EditorDocument(blocks: [.paragraph("코드블록")])
            let id = doc.blocks[0].id
            doc.focus = EditorFocus(blockID: id, caret: 0, selectionLength: 4)
            doc.wrapFocusedSelection(with: "`")
            XCTAssertEqual(doc.blocks[0].text, "`코드블록`")
        }
    }

    func testLinkSelectionWrapsAsMarkdownLink() async {
        await MainActor.run {
            let doc = EditorDocument(blocks: [.paragraph("여기를 눌러")])
            let id = doc.blocks[0].id
            doc.focus = EditorFocus(blockID: id, caret: 0, selectionLength: 3)  // "여기를"
            doc.linkFocusedSelection(url: "https://kurl.me")
            XCTAssertEqual(doc.blocks[0].text, "[여기를](https://kurl.me) 눌러")
            // 라벨("여기를")을 다시 선택 — `[` 다음부터 3글자.
            XCTAssertEqual(doc.focus?.caret, 1)
            XCTAssertEqual(doc.focus?.selectionLength, 3)
        }
    }

    func testLinkNoSelectionUsesLabel() async {
        await MainActor.run {
            let doc = EditorDocument(blocks: [.paragraph("")])
            let id = doc.blocks[0].id
            doc.focus = EditorFocus(blockID: id, caret: 0, selectionLength: 0)
            doc.linkFocusedSelection(url: "https://kurl.me", label: "링크")
            XCTAssertEqual(doc.blocks[0].text, "[링크](https://kurl.me)")
        }
    }

    /// linkSelection(at:) — 알럿이 선택을 접어도, 잡아둔 포커스로 원래 선택을 감싼다(문서 focus 와 무관).
    func testLinkSelectionAtExplicitTargetSurvivesCollapsedFocus() async {
        await MainActor.run {
            let doc = EditorDocument(blocks: [.paragraph("여기를 눌러")])
            let id = doc.blocks[0].id
            let captured = EditorFocus(blockID: id, caret: 0, selectionLength: 3)  // "여기를"
            // 알럿이 뜬 것처럼 문서 focus 는 접혀 있다(캐럿만).
            doc.focus = EditorFocus(blockID: id, caret: 3, selectionLength: 0)
            let ok = doc.linkSelection(at: captured, url: "https://kurl.me")
            XCTAssertTrue(ok)
            XCTAssertEqual(doc.blocks[0].text, "[여기를](https://kurl.me) 눌러")
        }
    }

    func testLinkSelectionAtNonTextBlockReturnsFalse() async {
        await MainActor.run {
            let doc = EditorDocument(blocks: [.divider])
            let id = doc.blocks[0].id
            let ok = doc.linkSelection(at: EditorFocus(blockID: id, caret: 0), url: "https://kurl.me")
            XCTAssertFalse(ok)  // 비텍스트 → 실패(호출자가 문단 폴백)
        }
    }

    func testToggleBlockKindHeadingOnAndOff() async {
        await MainActor.run {
            let doc = EditorDocument(blocks: [.paragraph("제목감")])
            let id = doc.blocks[0].id
            doc.focus = EditorFocus(blockID: id, caret: 3)
            doc.toggleFocusedBlockKind(.heading(level: 2))
            XCTAssertEqual(doc.blocks[0].kind, .heading(level: 2))
            XCTAssertEqual(doc.blocks[0].text, "제목감")  // 텍스트 보존
            // 같은 버튼 다시 → 문단으로.
            doc.toggleFocusedBlockKind(.heading(level: 2))
            XCTAssertEqual(doc.blocks[0].kind, .paragraph)
        }
    }

    func testToggleBlockKindQuote() async {
        await MainActor.run {
            let doc = EditorDocument(blocks: [.paragraph("인용감")])
            let id = doc.blocks[0].id
            doc.focus = EditorFocus(blockID: id, caret: 0)
            doc.toggleFocusedBlockKind(.quote)
            XCTAssertEqual(doc.blocks[0].kind, .quote)
            doc.toggleFocusedBlockKind(.quote)
            XCTAssertEqual(doc.blocks[0].kind, .paragraph)
        }
    }

    func testToggleBlockKindListPreservesText() async {
        await MainActor.run {
            let doc = EditorDocument(blocks: [.paragraph("항목")])
            let id = doc.blocks[0].id
            doc.focus = EditorFocus(blockID: id, caret: 2)
            doc.toggleFocusedBlockKind(.listItem(ordered: false, indent: 0))
            XCTAssertEqual(doc.blocks[0].kind, .listItem(ordered: false, indent: 0))
            XCTAssertEqual(doc.blocks[0].text, "항목")
        }
    }

    func testToggleBlockKindNonTextNoOp() async {
        await MainActor.run {
            let doc = EditorDocument(blocks: [.divider])
            let id = doc.blocks[0].id
            doc.focus = EditorFocus(blockID: id, caret: 0)
            doc.toggleFocusedBlockKind(.heading(level: 2))
            XCTAssertEqual(doc.blocks[0].kind, .divider)  // 비텍스트는 무동작
        }
    }

    /// 서식 감싸기는 text 에 마크다운 원문을 넣을 뿐 — 왕복(직렬화)이 그 결과를 그대로 지킨다.
    func testWrapThenSerializeRoundTrips() async {
        await MainActor.run {
            let doc = EditorDocument(blocks: [.paragraph("안녕세상")])
            let id = doc.blocks[0].id
            doc.focus = EditorFocus(blockID: id, caret: 2, selectionLength: 2)
            doc.wrapFocusedSelection(with: "**")
            let md = doc.markdown
            XCTAssertEqual(md, "안녕**세상**")
            // 다시 파싱→직렬화해도 고정점.
            XCTAssertEqual(MarkdownSerializer.markdown(from: MarkdownBlockParser.parse(md)), md)
        }
    }

    // MARK: 취소선 (레거시 파리티)

    /// ~~취소선~~ 은 GFM 표준 — 감싸기 후 왕복이 고정점(text=마크다운 원문).
    func testStrikethroughWrapRoundTrips() async {
        await MainActor.run {
            let doc = EditorDocument(blocks: [.paragraph("지운다")])
            let id = doc.blocks[0].id
            doc.focus = EditorFocus(blockID: id, caret: 0, selectionLength: 3)
            doc.wrapFocusedSelection(with: "~~")
            XCTAssertEqual(doc.blocks[0].text, "~~지운다~~")
            let md = doc.markdown
            XCTAssertEqual(MarkdownSerializer.markdown(from: MarkdownBlockParser.parse(md)), md)
        }
    }

    /// 렌더러가 ~~ 을 그은 줄로 처리한다 — 마커는 숨기고 inner 에 strikethroughStyle.
    func testStrikethroughRendersStruckAndHidesMarkers() async {
        await MainActor.run {
            let block = EditorBlock.paragraph("앞 ~~중간~~ 뒤")
            let attributed = BlockInlineRenderer.render(block)
            let ns = attributed.string as NSString
            let innerRange = ns.range(of: "중간")
            XCTAssertNotEqual(innerRange.location, NSNotFound)
            let style = attributed.attribute(.strikethroughStyle, at: innerRange.location, effectiveRange: nil)
            XCTAssertEqual(style as? Int, NSUnderlineStyle.single.rawValue, "취소선 스타일 미적용")
            // 캐럿 없으면(activeRange nil) 마커 `~~` 는 숨김(clear).
            let markerLoc = ns.range(of: "~~").location
            let markerColor = attributed.attribute(.foregroundColor, at: markerLoc, effectiveRange: nil) as? UIColor
            XCTAssertEqual(markerColor, UIColor.clear, "마커가 숨겨지지 않음")
        }
    }

    // MARK: 표 행/열 삭제 (레거시 파리티)

    /// 본문 행 삭제 — 헤더는 보호, 본문 1행은 남긴다. 마지막 본문 행이면 삭제 거부(false).
    func testDeleteTableRowProtectsHeaderAndLastBodyRow() async {
        await MainActor.run {
            // 헤더 + 본문 2행(총 3행).
            let table = EditorTable(
                rows: [["A", "B"], ["1", "2"], ["3", "4"]], alignments: [.leading, .leading])
            let doc = EditorDocument(blocks: [.table(table)])
            let id = doc.blocks[0].id
            XCTAssertTrue(doc.deleteTableRow(id), "본문 2행일 때 삭제 가능해야")
            if case .table(let t) = doc.blocks[0].kind {
                XCTAssertEqual(t.rows.count, 2, "헤더+본문1행 남아야")
                XCTAssertEqual(t.rows[0], ["A", "B"], "헤더 보존")
            } else { XCTFail("표가 아님") }
            // 이제 본문 1행 — 더 못 지운다.
            XCTAssertFalse(doc.deleteTableRow(id), "마지막 본문 행은 보호")
        }
    }

    /// 열 삭제 — 마지막 한 열은 보호. 정렬 배열도 함께 준다.
    func testDeleteTableColumnProtectsLastColumn() async {
        await MainActor.run {
            let table = EditorTable(
                rows: [["A", "B"], ["1", "2"]], alignments: [.leading, .center])
            let doc = EditorDocument(blocks: [.table(table)])
            let id = doc.blocks[0].id
            XCTAssertTrue(doc.deleteTableColumn(id), "2열일 때 삭제 가능해야")
            if case .table(let t) = doc.blocks[0].kind {
                XCTAssertEqual(t.columnCount, 1, "1열 남아야")
                XCTAssertEqual(t.rows[0], ["A"], "마지막 열 제거")
                XCTAssertEqual(t.alignments.count, 1, "정렬도 함께 제거")
            } else { XCTFail("표가 아님") }
            XCTAssertFalse(doc.deleteTableColumn(id), "마지막 열은 보호")
        }
    }

    /// 삭제 스냅샷 복원 — 되돌리기 토스트가 원상복구할 수 있다.
    func testTableSnapshotRestoresAfterDelete() async {
        await MainActor.run {
            let table = EditorTable(
                rows: [["A", "B"], ["1", "2"], ["3", "4"]], alignments: [.leading, .leading])
            let doc = EditorDocument(blocks: [.table(table)])
            let id = doc.blocks[0].id
            let snapshot = doc.tableSnapshot(id)
            XCTAssertNotNil(snapshot)
            _ = doc.deleteTableRow(id)
            doc.restoreTable(id, to: snapshot!)
            if case .table(let t) = doc.blocks[0].kind {
                XCTAssertEqual(t.rows.count, 3, "복원 후 3행")
            } else { XCTFail("표가 아님") }
        }
    }

    // MARK: 이미지 폭 마커 (레거시 파리티)

    /// 폭 마커(`«wide»`)를 alt 앞에 담아 왕복 — `![«wide» alt](url)` 고정점.
    func testImageWidthMarkerRoundTrips() {
        let md = "![«wide» 다이어그램](https://example.com/a.png)"
        let blocks = MarkdownBlockParser.parse(md)
        XCTAssertEqual(blocks.count, 1)
        if case .image(let url) = blocks[0].kind {
            XCTAssertEqual(url, "https://example.com/a.png")
            XCTAssertEqual(blocks[0].text, "«wide» 다이어그램", "폭 마커가 alt 에 보존")
        } else { XCTFail("이미지 블록이 아님") }
        XCTAssertEqual(MarkdownSerializer.markdown(from: blocks), md, "폭 마커 왕복 고정점")
    }

    /// parseImageAlt 이 폭·순수 alt 를 가른다(에디터 UI 가 alt 필드엔 순수 alt 만 보이게).
    func testParseImageAltSplitsWidthAndAlt() {
        let (width, alt) = DraftPreviewBlocks.parseImageAlt("«half» 캡션 텍스트")
        XCTAssertEqual(width, "half")
        XCTAssertEqual(alt, "캡션 텍스트")
        // 마커 없으면 폭 nil.
        let (w2, a2) = DraftPreviewBlocks.parseImageAlt("그냥 설명")
        XCTAssertNil(w2)
        XCTAssertEqual(a2, "그냥 설명")
    }

    // MARK: B1 — 툴바 서식 직후 마커 반개봉 1회 억제

    /// 감싸기는 억제 플래그를 그 블록에 세운다 — 뷰가 다음 렌더에서 마커를 숨기고 소비한다.
    /// (왕복·선택은 불변: text 는 여전히 마크다운 원문, 선택은 inner 로 복원.)
    func testWrapSetsSuppressRevealOnceFlag() async {
        await MainActor.run {
            let doc = EditorDocument(blocks: [.paragraph("굵게할것")])
            let id = doc.blocks[0].id
            XCTAssertNil(doc.suppressRevealOnceBlockID)
            doc.focus = EditorFocus(blockID: id, caret: 0, selectionLength: 4)
            doc.wrapFocusedSelection(with: "**")
            XCTAssertEqual(doc.suppressRevealOnceBlockID, id, "감싼 블록에 1회 억제 플래그가 서야")
            // 왕복·선택 불변 확인.
            XCTAssertEqual(doc.blocks[0].text, "**굵게할것**")
            XCTAssertEqual(doc.focus?.selectionLength, 4)
        }
    }

    /// 렌더러: 선택이 스팬 안(=평소엔 반개봉)이어도, 억제 렌더(activeRange nil)면 마커는 숨는다.
    /// B1 의 핵심 — 뷰가 억제 시 activeRange nil 로 렌더하면 마커가 안 보인다는 계약 확인.
    func testSuppressedRenderHidesMarkersEvenWhenSelectionInside() async {
        await MainActor.run {
            let block = EditorBlock.paragraph("**굵게**")
            let ns = block.text as NSString
            let inside = ns.range(of: "굵게")  // 스팬 안 선택
            // 평소(반개봉): 캐럿이 스팬 안이면 마커가 흐리게 노출(clear 아님).
            let revealed = BlockInlineRenderer.render(block, activeRange: inside)
            let markerLoc = ns.range(of: "**").location
            let revealedColor = revealed.attribute(.foregroundColor, at: markerLoc, effectiveRange: nil) as? UIColor
            XCTAssertNotEqual(revealedColor, UIColor.clear, "반개봉이면 마커가 흐리게라도 보여야")
            // 억제(activeRange nil): 같은 선택이어도 마커는 숨김(clear).
            let suppressed = BlockInlineRenderer.render(block, activeRange: nil)
            let suppressedColor = suppressed.attribute(.foregroundColor, at: markerLoc, effectiveRange: nil) as? UIColor
            XCTAssertEqual(suppressedColor, UIColor.clear, "억제 렌더면 마커가 숨어야(B1)")
        }
    }
}
