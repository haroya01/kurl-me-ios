//
//  WriteV2AdversarialTests.swift
//  kurlTests
//
//  글쓰기 엔진의 복합·적대 케이스 — "그럴듯하게 동작"이 아니라 못된 입력과 연산 조합에서도
//  왕복(저장 계약)이 안 흔들리는지 고정한다. 세 층: ① 왕복 고정점(정규화 후 멱등) ② 문서 연산
//  시퀀스(분할·병합·변환·표 편집 조합) ③ 지름길·인라인 렌더 경계.
//

import XCTest

@testable import kurl

@MainActor
final class WriteV2AdversarialTests: XCTestCase {

    /// Xcode 27 베타 시뮬 런타임의 isolated-deinit malloc abort 우회 — WriteV2FocusEngineTests 와 동일.
    private static var retained: [EditorDocument] = []

    private func makeDoc(_ blocks: [EditorBlock]) -> EditorDocument {
        let doc = EditorDocument(blocks: blocks)
        Self.retained.append(doc)
        return doc
    }

    private func makeDoc(markdown: String) -> EditorDocument {
        let doc = EditorDocument(markdown: markdown)
        Self.retained.append(doc)
        return doc
    }

    /// 첫 직렬화(정규화) 이후엔 왕복이 고정점이어야 한다 — 저장할 때마다 본문이 변형되면
    /// 자동저장 서명이 출렁여 더티 루프에 빠진다.
    private func assertFixedPoint(
        _ markdown: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let once = MarkdownSerializer.markdown(from: MarkdownBlockParser.parse(markdown))
        let twice = MarkdownSerializer.markdown(from: MarkdownBlockParser.parse(once))
        XCTAssertEqual(twice, once, "정규화 후 왕복이 고정점이 아님", file: file, line: line)
    }

    // MARK: ① 왕복 고정점 — 못된 입력들

    func testFixedPointOnMalformedInline() {
        assertFixedPoint("**닫히지 않은 볼드")
        assertFixedPoint("별표 * 하나")
        assertFixedPoint("`닫히지 않은 코드")
        assertFixedPoint("[라벨만](")
        assertFixedPoint("![이미지 같지만 아닌 것](url 에 공백)")
        assertFixedPoint("**")
        assertFixedPoint("*_*_*")
    }

    func testFixedPointOnComplexDocument() {
        assertFixedPoint(
            """
            # 제목

            본문 **볼드**와 *이탤릭*, `코드`, [링크](https://example.com/a) 와 맨 https://example.com/b

            - 하나
            - 둘
              - 둘의 하나
            1. 첫
            2. 둘

            > 인용 첫 줄
            > 인용 둘째 줄

            ```swift
            let x = "hello"
            # 이건 제목이 아니라 코드다
            ```

            ---

            ![«wide» «1200x800» 히어로](https://cdn.example/hero.png "커버")

            | 이름 | 값 |
            | --- | ---: |
            | 파이프 \\| 이스케이프 | 42 |

            https://youtu.be/dQw4w9WgXcQ
            """)
    }

    func testFixedPointOnEdgeStructures() {
        assertFixedPoint(">")                        // 빈 인용 줄
        assertFixedPoint("> ")                       // 마커만
        assertFixedPoint("```\n```")                 // 빈 코드
        assertFixedPoint("```swift\n\n```")          // 빈 줄만 든 코드
        assertFixedPoint("---")
        assertFixedPoint("----------")               // 긴 구분선
        assertFixedPoint("| a |\n| --- |")           // 본문 없는 1열 표
        assertFixedPoint("![](https://cdn.example/x.png)")  // alt 없는 이미지
    }

    func testCRLFPasteIsNormalized() {
        // 윈도우/외부 앱 붙여넣기 — \r 이 본문에 남으면 줄머리 판정과 저장 계약이 조용히 오염된다.
        let blocks = MarkdownBlockParser.parse("# 제목\r\n\r\n본문 줄\r\n둘째 줄")
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].kind, .heading(level: 1))
        XCTAssertEqual(blocks[0].text, "제목")
        XCTAssertFalse(blocks[1].text.contains("\r"), "CRLF 의 \\r 가 본문에 샘")
        assertFixedPoint("# 제목\r\n\r\n본문")
    }

    func testCodeFenceSwallowsBlockMarkers() {
        // 펜스 안 `#`·`-`·`>`·`---` 는 구조가 아니라 코드다.
        let md = "```\n# not heading\n- not list\n> not quote\n---\n```"
        let blocks = MarkdownBlockParser.parse(md)
        XCTAssertEqual(blocks.count, 1)
        guard case .code = blocks[0].kind else { return XCTFail("코드 블록이 아님") }
        XCTAssertTrue(blocks[0].text.contains("# not heading"))
        assertFixedPoint(md)
    }

    func testOrderedListRenumbersRunsButStaysFixed() {
        // 원문 번호가 어긋나 있어도(3. 7.) 정규화는 연속 순번으로 — 그 뒤로는 고정.
        let once = MarkdownSerializer.markdown(from: MarkdownBlockParser.parse("3. 셋\n7. 일곱"))
        XCTAssertEqual(once, "1. 셋\n2. 일곱")
        assertFixedPoint("3. 셋\n7. 일곱")
    }

    func testTableUnevenRowsArePaddedToWidestRow() {
        // 파서 계약: 열 수 = 가장 넓은 행(헤더가 좁으면 헤더도 빈 셀로 패딩) — 셀이 잘려나가지 않는다.
        let md = "| a | b | c |\n| --- | --- | --- |\n| 하나 |\n| 하나 | 둘 | 셋 | 넷 |"
        let blocks = MarkdownBlockParser.parse(md)
        guard case .table(let table) = blocks[0].kind else { return XCTFail("표가 아님") }
        XCTAssertEqual(table.columnCount, 4)
        XCTAssertTrue(table.rows.allSatisfy { $0.count == 4 }, "행 폭이 열 수로 정규화 안 됨")
        XCTAssertEqual(table.rows[1], ["하나", "", "", ""], "좁은 행은 빈 셀로 패딩")
        assertFixedPoint(md)
    }

    // MARK: ② 문서 연산 시퀀스

    func testSplitHeadingMiddleKeepsKindOnTail() {
        let doc = makeDoc([.heading(2, "앞뒤")])
        doc.splitBlock(doc.blocks[0].id, at: 1)
        XCTAssertEqual(doc.blocks.count, 2)
        XCTAssertEqual(doc.blocks[0].kind, .heading(level: 2))
        XCTAssertEqual(doc.blocks[0].text, "앞")
        XCTAssertEqual(doc.blocks[1].kind, .heading(level: 2), "내용이 남은 꼬리는 종류 유지")
        XCTAssertEqual(doc.blocks[1].text, "뒤")
    }

    func testSplitHeadingAtEndDropsToParagraph() {
        let doc = makeDoc([.heading(2, "제목")])
        doc.splitBlock(doc.blocks[0].id, at: 2)
        XCTAssertEqual(doc.blocks[1].kind, .paragraph, "제목 끝 엔터는 문단으로")
        XCTAssertEqual(doc.focus?.blockID, doc.blocks[1].id)
    }

    func testMergeParagraphIntoHeadingKeepsHeading() {
        let doc = makeDoc([.heading(2, "제목"), .paragraph("이어붙일 본문")])
        doc.mergeBackward(doc.blocks[1].id)
        XCTAssertEqual(doc.blocks.count, 1)
        XCTAssertEqual(doc.blocks[0].kind, .heading(level: 2))
        XCTAssertEqual(doc.blocks[0].text, "제목이어붙일 본문")
        XCTAssertEqual(doc.focus?.caret, 2, "캐럿은 병합 지점(앞 블록 원래 길이)")
    }

    func testBackspaceLadderOnNestedListItem() {
        // 중첩 항목 맨 앞 백스페이스: indent 2 → 1 → 0 → 문단 (사다리).
        let doc = makeDoc([.listItem("항목", ordered: false, indent: 2)])
        let id = doc.blocks[0].id
        doc.mergeBackward(id)
        XCTAssertEqual(doc.blocks[0].kind, .listItem(ordered: false, indent: 1))
        doc.mergeBackward(id)
        XCTAssertEqual(doc.blocks[0].kind, .listItem(ordered: false, indent: 0))
        doc.mergeBackward(id)
        XCTAssertEqual(doc.blocks[0].kind, .paragraph)
        XCTAssertEqual(doc.blocks[0].text, "항목", "사다리를 내려와도 본문은 그대로")
    }

    func testBackspaceAfterNonTextDeletesIt() {
        let doc = makeDoc([.paragraph("본문"), .divider, .paragraph("뒤 문단")])
        doc.mergeBackward(doc.blocks[2].id)
        XCTAssertEqual(doc.blocks.count, 2, "비텍스트(구분선)는 백스페이스로 지워진다")
        XCTAssertEqual(doc.blocks[1].text, "뒤 문단")
    }

    func testTransformThenSplitThenSerialize() {
        // 지름길 변환 → 타이핑 → 분할 → 직렬화가 방언과 일치.
        let doc = makeDoc([.paragraph("")])
        let id = doc.blocks[0].id
        doc.transform(id, to: .quote, strippedText: "인용본문", caret: 4)
        doc.splitBlock(id, at: 2)
        XCTAssertEqual(doc.blocks[0].text, "인용")
        XCTAssertEqual(doc.blocks[1].kind, .quote, "내용 남은 인용 분할은 인용 유지")
        XCTAssertEqual(doc.markdown, "> 인용\n\n> 본문")
    }

    func testWrapSelectionWithKoreanAndEmojiOffsets() {
        // String 인덱스 거리 기반 감싸기 — 한글·이모지(다중 스칼라)에서 마커 위치가 어긋나면 안 된다.
        let doc = makeDoc([.paragraph("한글🙂뒤")])
        doc.focus = EditorFocus(blockID: doc.blocks[0].id, caret: 2, selectionLength: 1)  // 🙂 선택
        doc.wrapFocusedSelection(with: "**")
        XCTAssertEqual(doc.blocks[0].text, "한글**🙂**뒤")
        XCTAssertEqual(doc.focus?.caret, 4, "안쪽 시작(마커 뒤)으로 선택 복원")
        XCTAssertEqual(doc.focus?.selectionLength, 1)
    }

    func testLinkSelectionClampsStaleTarget() {
        // 알럿이 떠 있는 사이 본문이 짧아졌을 때 — 잡아둔 포커스가 범위 밖이어도 죽지 않고 클램프.
        let doc = makeDoc([.paragraph("짧음")])
        let stale = EditorFocus(blockID: doc.blocks[0].id, caret: 10, selectionLength: 5)
        XCTAssertTrue(doc.linkSelection(at: stale, url: "https://example.com", label: "라벨"))
        XCTAssertEqual(doc.blocks[0].text, "짧음[라벨](https://example.com)")
    }

    func testTableEditsRoundTrip() {
        let doc = makeDoc(markdown: "| a | b |\n| --- | --- |\n| 1 | 2 |")
        let id = doc.blocks[0].id
        doc.addTableRow(id)
        doc.addTableColumn(id)
        doc.updateTableCell(id, row: 2, col: 2, text: "새 값 | 파이프")
        doc.cycleTableColumnAlignment(id, col: 2)  // leading → center
        let out = doc.markdown
        let reparsed = MarkdownBlockParser.parse(out)
        guard case .table(let table) = reparsed[0].kind else { return XCTFail("표 왕복 실패") }
        XCTAssertEqual(table.columnCount, 3)
        XCTAssertEqual(table.rows.count, 3)
        XCTAssertEqual(table.rows[2][2], "새 값 | 파이프", "셀 안 파이프 이스케이프 왕복")
        XCTAssertEqual(table.alignments[2], .center)
    }

    func testInsertNonTextAtDocumentEndGrowsTrailingParagraph() {
        let doc = makeDoc([.paragraph("본문")])
        doc.focus = EditorFocus(blockID: doc.blocks[0].id, caret: 2)
        doc.insertNonText(.table(.blank))
        XCTAssertEqual(doc.blocks.count, 3, "비텍스트 뒤엔 이어 쓸 문단이 생긴다")
        XCTAssertTrue(doc.blocks[2].isEmptyParagraph)
        XCTAssertEqual(doc.focus?.blockID, doc.blocks[2].id)
    }

    func testDeleteBlockNeverEmptiesDocument() {
        let doc = makeDoc([.paragraph("하나")])
        doc.deleteBlock(doc.blocks[0].id)
        XCTAssertEqual(doc.blocks.count, 1, "마지막 블록은 지워지지 않는다(빈 문서 금지)")
    }

    // MARK: 진단 — 지우기·단락변경 감사 매트릭스 미커버 셀(관찰 로그)

    /// 마커 스팬 안에서 Enter 분할 시 짝을 닫고 다시 열어 양쪽 서식을 보존한다(짝 깨짐·리터럴 잔존 방지).
    func testSplitInsideMarkerSpanClosesAndReopensPair() {
        // "앞 **굵게** 뒤" 에서 "굵|게"(caret 5)에서 분할. 앞=0 공백=1 **=2,3 굵=4 게=5 **=6,7.
        let doc = makeDoc([.paragraph("앞 **굵게** 뒤")])
        doc.splitBlock(doc.blocks[0].id, at: 5)
        XCTAssertEqual(doc.blocks.count, 2)
        XCTAssertEqual(doc.blocks[0].text, "앞 **굵**", "head 는 닫는 마커로 닫는다")
        XCTAssertEqual(doc.blocks[1].text, "**게** 뒤", "tail 은 여는 마커로 다시 연다")
        // 캐럿은 tail 의 여는 마커 뒤(내용 시작)에 놓여 이어 쓰기가 서식 안에서 시작된다.
        XCTAssertEqual(doc.focus?.blockID, doc.blocks[1].id)
    }

    func testSplitInsideMarkerSpanVariants() {
        // 이탤릭·취소선·코드도 동일하게 짝 보존.
        let cases: [(String, Int, String, String)] = [
            ("가 *기울* 나", 4, "가 *기*", "*울* 나"),      // 가0 공1 *2 기3 울4 *5 공6 나7 → caret4=기|울
            ("가 ~~취소~~ 나", 5, "가 ~~취~~", "~~소~~ 나"), // ~~2,3 취4 소5 ~~6,7 → caret5=취|소
            ("가 `코드` 나", 4, "가 `코`", "`드` 나"),        // `2 코3 드4 `5 → caret4=코|드
        ]
        for (text, caret, expHead, expTail) in cases {
            let doc = makeDoc([.paragraph(text)])
            doc.splitBlock(doc.blocks[0].id, at: caret)
            XCTAssertEqual(doc.blocks[0].text, expHead, "head for \(text)@\(caret)")
            XCTAssertEqual(doc.blocks[1].text, expTail, "tail for \(text)@\(caret)")
        }
    }

    /// 마커 경계·마커 밖에서의 분할은 짝을 안 건드린다(내용 안일 때만 닫고 연다).
    func testSplitOutsideMarkerSpanUnchanged() {
        // 스팬 경계(caret 2, 여는 `**` 바로 앞)에서 분할 — 마커 추가 없이 순수 텍스트 컷.
        let doc = makeDoc([.paragraph("앞 **굵게** 뒤")])
        doc.splitBlock(doc.blocks[0].id, at: 2)
        XCTAssertEqual(doc.blocks[0].text, "앞 ")
        XCTAssertEqual(doc.blocks[1].text, "**굵게** 뒤")
        // 마크업 밖 순수 문단 분할도 그대로.
        let d2 = makeDoc([.paragraph("그냥 문단입니다")])
        d2.splitBlock(d2.blocks[0].id, at: 3)
        XCTAssertEqual(d2.blocks[0].text, "그냥 ")
        XCTAssertEqual(d2.blocks[1].text, "문단입니다")
    }

    /// 이종 kind 병합 — 문단이 인용/리스트 뒤에서 백스페이스로 병합될 때 텍스트·kind 결과(감사 [정상] 잠금).
    func testHeterogeneousMergesPreserveTextAndKind() {
        // 문단 ← 인용: 앞 인용의 kind 를 따르고 텍스트 이어붙임.
        let d1 = makeDoc([.quote("인용문"), .paragraph("문단")])
        d1.mergeBackward(d1.blocks[1].id)
        XCTAssertEqual(d1.blocks.count, 1)
        XCTAssertEqual(d1.blocks[0].text, "인용문문단")
        if case .quote = d1.blocks[0].kind {} else { XCTFail("앞 인용 kind 채택") }

        // 문단 ← 리스트: 종류 섞임 방지로 병합 안 함(2블록 유지) — 의도된 설계(데이터 손상 아님).
        let d2 = makeDoc([.listItem("항목", ordered: false, indent: 0), .paragraph("문단")])
        d2.mergeBackward(d2.blocks[1].id)
        XCTAssertEqual(d2.blocks.count, 2, "리스트+문단은 섞지 않는다(의도)")
        XCTAssertEqual(d2.blocks[1].text, "문단", "문단 텍스트 보존")

        // 인용 ← 문단: 앞 문단 kind 채택, 텍스트 이어붙임.
        let d3 = makeDoc([.paragraph("문단"), .quote("인용")])
        d3.mergeBackward(d3.blocks[1].id)
        XCTAssertEqual(d3.blocks.count, 1)
        XCTAssertEqual(d3.blocks[0].text, "문단인용")
        if case .paragraph = d3.blocks[0].kind {} else { XCTFail("앞 문단 kind 채택") }
    }

    /// 빈 블록 kind 전환 — 제목/인용/리스트/코드 전환 후 재전환으로 문단 복귀, 블록 안 늘어남(감사 [정상] 잠금).
    func testEmptyBlockKindTransitionsRoundTrip() {
        for kind in [EditorBlockKind.heading(level: 1), .quote, .listItem(ordered: false, indent: 0), .code(language: nil)] {
            let doc = makeDoc([.paragraph("")])
            doc.focus = EditorFocus(blockID: doc.blocks[0].id, caret: 0)
            doc.toggleFocusedBlockKind(kind)
            XCTAssertEqual(doc.blocks.count, 1, "빈 블록 전환이 블록을 늘리면 안 됨: \(kind)")
            doc.toggleFocusedBlockKind(kind) // 재전환 → 문단 복귀
            if case .paragraph = doc.blocks[0].kind {} else { XCTFail("재전환이 문단 복귀 아님: \(kind)") }
            XCTAssertEqual(doc.blocks.count, 1)
        }
    }

    /// 전환 직후 직렬화가 올바른 md 를 내는지(감사 [정상] 잠금).
    func testTransitionSerializationRoundTrip() {
        let doc = makeDoc([.paragraph("본문 텍스트")])
        doc.focus = EditorFocus(blockID: doc.blocks[0].id, caret: 0)
        doc.toggleFocusedBlockKind(.heading(level: 2))
        XCTAssertEqual(doc.markdown, "## 본문 텍스트", "문단→H2 전환 후 직렬화가 올바른 md")
        XCTAssertEqual(MarkdownBlockParser.parse(doc.markdown).first?.text, "본문 텍스트")
    }

    // MARK: 블록 삭제 매트릭스 회귀 — 비텍스트 블록(구분선·표·이미지)의 통째 삭제 경로

    /// 비텍스트 블록은 캐럿을 못 받아 뷰의 명시적 삭제 버튼이 removeBlock 을 부른다(구분선·표·이미지 대칭).
    /// 마지막 블록이어도(뒤 문단 없음) removeBlock 으로 지워지고, 되돌리기(restoreBlock)로 복구된다.
    func testNonTextBlocksRemovableAndRestorable() {
        for (label, blk) in [("구분선", EditorBlock.divider),
                             ("표", .table(.blank)),
                             ("이미지", .image(url: "https://kurl.me/a.png", alt: "그림"))] {
            // 앞 문단 + 대상(마지막 블록, 뒤 문단 없음) — 백스페이스 진입점이 없는 최악 구도.
            let doc = makeDoc([.paragraph("앞"), blk])
            let targetID = doc.blocks[1].id
            guard let removed = doc.removeBlock(targetID) else {
                return XCTFail("\(label): removeBlock 이 nil — 통째 삭제 불가")
            }
            XCTAssertFalse(doc.blocks.contains { $0.id == targetID }, "\(label) 삭제 안 됨")
            XCTAssertEqual(doc.blocks.count, 1, "\(label) 삭제 후 앞 문단만 남아야")
            // 되돌리기 — 원 자리에 복원.
            doc.restoreBlock(removed.block, afterId: removed.afterId)
            XCTAssertEqual(doc.blocks.count, 2, "\(label) 되돌리기 후 복원")
            XCTAssertTrue(doc.blocks[1].isNonText, "\(label) 복원 위치·종류 보존")
        }
    }

    /// 비텍스트 블록이 뒤 문단 앞머리 백스페이스로도 지워지는 종전 경로도 유지된다(회귀 가드).
    func testNonTextBlockDeletedByBackspaceFromTrailing() {
        for blk in [EditorBlock.divider, .table(.blank), .image(url: "https://kurl.me/a.png", alt: "그림")] {
            let doc = makeDoc([.paragraph("앞"), blk, .paragraph("")])
            let targetID = doc.blocks[1].id
            doc.mergeBackward(doc.blocks[2].id) // 뒤 빈 문단 앞머리에서 백스페이스
            XCTAssertFalse(doc.blocks.contains { $0.id == targetID }, "백스페이스로 비텍스트 블록 삭제")
        }
    }

    /// 텍스트 블록(인용·제목·코드·리스트) 토글 오프가 문단으로 되돌리고 마커 잔여가 없는지 — 회귀 가드.
    /// (진단 결과 이 경로들은 정상이었다. 사용자 신고의 "삭제 안 됨"은 비텍스트 어포던스 부재가 근원.)
    func testTextBlockToggleOffCleanToParagraph() {
        func assertTogglesToClean(_ block: EditorBlock, to kind: EditorBlockKind, expectText: String) {
            let doc = makeDoc([block])
            doc.focus = EditorFocus(blockID: doc.blocks[0].id, caret: 0)
            doc.toggleFocusedBlockKind(kind)
            guard case .paragraph = doc.blocks[0].kind else {
                return XCTFail("토글 오프가 문단으로 안 감: \(doc.blocks[0].kind)")
            }
            XCTAssertEqual(doc.blocks[0].text, expectText, "토글 오프 시 마커 잔여 없이 텍스트 보존")
        }
        assertTogglesToClean(.quote("주석"), to: .quote, expectText: "주석")
        assertTogglesToClean(.code("코드", language: "swift"), to: .code(language: nil), expectText: "코드")
        assertTogglesToClean(.listItem("항목", ordered: false, indent: 0),
                             to: .listItem(ordered: false, indent: 0), expectText: "항목")
        assertTogglesToClean(.listItem("항목", ordered: true, indent: 0),
                             to: .listItem(ordered: true, indent: 0), expectText: "항목")
        // 제목 순환: H2 에서 heading(2) 재토글 → 문단.
        assertTogglesToClean(.heading(2, "제목"), to: .heading(level: 2), expectText: "제목")
    }

    // MARK: ③ 지름길 비트리거 — 마커를 리터럴로 남겨야 하는 자리

    func testShortcutNonTriggers() {
        XCTAssertNil(BlockShortcuts.detect(in: "#### 4단은 방언 밖", kind: .paragraph))
        XCTAssertNil(BlockShortcuts.detect(in: "#공백없음", kind: .paragraph))
        XCTAssertNil(BlockShortcuts.detect(in: "1.공백없음", kind: .paragraph))
        XCTAssertNil(BlockShortcuts.detect(in: " - 선행 공백", kind: .paragraph))
        XCTAssertNil(BlockShortcuts.detect(in: "> 인용 안에선 재적용 없음", kind: .quote))
        XCTAssertNil(BlockShortcuts.detect(in: "# 제목 안에서도", kind: .heading(level: 2)))
    }

    func testShortcutTriggersStripExactMarker() {
        let h = BlockShortcuts.detect(in: "### 셋", kind: .paragraph)
        XCTAssertEqual(h?.kind, .heading(level: 3))
        XCTAssertEqual(h?.strippedText, "셋")
        let n = BlockShortcuts.detect(in: "12. 열둘", kind: .paragraph)
        XCTAssertEqual(n?.kind, .listItem(ordered: true, indent: 0))
        XCTAssertEqual(n?.strippedText, "열둘")
        let c = BlockShortcuts.detect(in: "```swift", kind: .paragraph)
        XCTAssertEqual(c?.kind, .code(language: "swift"))
    }

    // MARK: ③ 인라인 렌더 경계

    func testActiveMarkupSpanBoundaries() {
        let text = "앞 **볼드** 뒤"
        let span = BlockInlineRenderer.activeMarkupSpan(in: text, caret: 2)   // `**` 시작 위치
        XCTAssertNotNil(span, "마크업 시작 경계의 캐럿도 반개봉 대상")
        let inside = BlockInlineRenderer.activeMarkupSpan(in: text, caret: 4)
        XCTAssertEqual(inside, span)
        XCTAssertNil(BlockInlineRenderer.activeMarkupSpan(in: text, caret: 0), "마크업 밖은 nil")
    }

    func testItalicRendersAsObliqueForKorean() {
        // 한글 폰트엔 이탤릭 트레이트가 없다 — 합성 오블리크 속성이 실제로 붙는지.
        let rendered = BlockInlineRenderer.render(.paragraph("*기울임*"))
        let ns = rendered.string as NSString
        let inner = ns.range(of: "기울임")
        let oblique = rendered.attribute(.obliqueness, at: inner.location, effectiveRange: nil)
        XCTAssertNotNil(oblique, "이탤릭에 오블리크 미적용")
    }

    func testBoldInsideLinkLabelIsNotEmphasized() {
        // 링크 문법이 소유한 범위의 별표는 강조가 아니다 — url 이 깨져 보이면 안 된다.
        let rendered = BlockInlineRenderer.render(.paragraph("[**라벨**](https://example.com/a*b)"))
        XCTAssertEqual(rendered.string, "[**라벨**](https://example.com/a*b)", "문자 자체는 보존")
    }

    // MARK: ③ 인라인 이미지 추가 형태

    func testInlineImageWithQueryURLAndTightText() {
        let segs = InlineImageMarkdown.segments("앞글자![a](https://cdn.example/x.png?w=1200&q=80)뒷글자")
        XCTAssertEqual(segs.count, 3)
        guard case .image(let img) = segs[1] else { return XCTFail() }
        XCTAssertEqual(img.url, "https://cdn.example/x.png?w=1200&q=80")
    }

    func testInlineImageMarkerOnlyAlt() {
        let segs = InlineImageMarkdown.segments("![«half»](https://cdn.example/x.png)")
        guard case .image(let img) = segs[0] else { return XCTFail() }
        XCTAssertEqual(img.width, "half")
        XCTAssertEqual(img.alt, "")
    }
}

// MARK: 구조 가드 1 — 블록 타입 완비성(enum 순회로 삭제 경로 누락을 컴파일/실행에서 강제)

/// 새 EditorBlockKind 를 추가하면서 삭제 경로를 안 만들면 이 가드가 잡는다.
/// 핵심은 아래 exhaustive switch — 케이스가 늘면 컴파일 에러로 "삭제 유형을 선언하라"고 강제한다.
/// (구분선·표에 삭제 어포던스가 없던 버그 #206 계급을 구조적으로 재발 방지.)
@MainActor
final class BlockTypeCompletenessGuardTests: XCTestCase {

    private static var retained: [EditorDocument] = []
    private func makeDoc(_ blocks: [EditorBlock]) -> EditorDocument {
        let doc = EditorDocument(blocks: blocks); Self.retained.append(doc); return doc
    }

    /// 블록의 삭제 계약 유형 — 텍스트 블록은 캐럿 경로(백스페이스/토글)로, 비텍스트는 명시 삭제 컨트롤로.
    private enum DeletionContract { case caretPath, explicitControl }

    /// 각 kind 의 대표 샘플 + 기대 삭제 계약. **exhaustive switch** 라 새 케이스는 컴파일 에러로 강제된다.
    /// 새 블록 타입을 넣으면 여기서 (샘플, 삭제계약)을 선언해야 하고, 그러면 아래 단언이 삭제 경로를 검증한다.
    private func sampleAndContract(for kind: EditorBlockKind) -> (block: EditorBlock, contract: DeletionContract) {
        switch kind {
        case .paragraph:                 return (.paragraph("문단"), .caretPath)
        case .heading:                   return (.heading(2, "제목"), .caretPath)
        case .quote:                     return (.quote("인용"), .caretPath)
        case .code:                      return (.code("코드", language: "swift"), .caretPath)
        case .listItem:                  return (.listItem("항목", ordered: false, indent: 0), .caretPath)
        case .divider:                   return (.divider, .explicitControl)
        case .image:                     return (.image(url: "https://kurl.me/a.png", alt: "그림"), .explicitControl)
        case .table:                     return (.table(.blank), .explicitControl)
        }
    }

    /// EditorBlockKind 전 케이스의 대표값 — 새 케이스 추가 시 이 배열도 채워야 아래 순회가 그 타입을 덮는다.
    /// (sampleAndContract 의 switch 가 1차 컴파일 게이트, 이 배열이 2차 실행 커버리지.)
    private static let allKinds: [EditorBlockKind] = [
        .paragraph, .heading(level: 2), .quote, .code(language: "swift"),
        .divider, .listItem(ordered: false, indent: 0),
        .image(url: "https://kurl.me/a.png", caption: nil), .table(.blank),
    ]

    func testEveryBlockKindHasCreationAndDeletionPath() {
        for kind in Self.allKinds {
            let (sample, contract) = sampleAndContract(for: kind)
            // (a) 생성 경로 — 샘플이 그 kind 로 만들어진다.
            XCTAssertEqual(sample.kind, kind, "생성 경로가 kind 를 안 맞춤: \(kind)")

            // (b) 삭제 경로 — 계약별로 실제 삭제가 되는지.
            switch contract {
            case .caretPath:
                // 텍스트 블록: 앞 문단 뒤에 놓고 그 블록 맨 앞 백스페이스(mergeBackward)로 병합/해제되어
                // 문서에서 사라지거나(병합) 문단으로 강등된다 — 어느 쪽이든 "갇히지 않음".
                let doc = makeDoc([.paragraph("앞"), sample])
                XCTAssertFalse(sample.isNonText, "텍스트 계약인데 isNonText: \(kind)")
                let before = doc.blocks.count
                doc.mergeBackward(doc.blocks[1].id)
                let merged = doc.blocks.count < before
                let demoted = doc.blocks.count == before &&
                    { if case .paragraph = doc.blocks[1].kind { return true }; return false }()
                XCTAssertTrue(merged || demoted, "텍스트 블록 백스페이스가 병합·강등 어느 것도 안 함: \(kind)")

            case .explicitControl:
                // 비텍스트 블록: 캐럿을 못 받으므로(isNonText) removeBlock(명시 삭제 컨트롤이 부르는 것)으로
                // 반드시 지워져야 한다 — 마지막 블록이어도(뒤 문단 없음) 갇히지 않는다.
                XCTAssertTrue(sample.isNonText, "명시삭제 계약인데 텍스트 블록: \(kind)")
                let doc = makeDoc([.paragraph("앞"), sample])
                let id = doc.blocks[1].id
                XCTAssertNotNil(doc.removeBlock(id), "비텍스트 블록 removeBlock 이 nil(삭제 경로 없음): \(kind)")
                XCTAssertFalse(doc.blocks.contains { $0.id == id }, "비텍스트 블록이 안 지워짐: \(kind)")
            }
        }
    }

    /// isNonText 분류와 삭제 계약이 일관되는지(비텍스트=명시삭제, 텍스트=캐럿경로) — 분류 드리프트 가드.
    func testDeletionContractMatchesIsNonText() {
        for kind in Self.allKinds {
            let (sample, contract) = sampleAndContract(for: kind)
            switch contract {
            case .caretPath:        XCTAssertFalse(sample.isNonText, "\(kind): 캐럿경로인데 비텍스트")
            case .explicitControl:  XCTAssertTrue(sample.isNonText, "\(kind): 명시삭제인데 텍스트")
            }
        }
    }
}
