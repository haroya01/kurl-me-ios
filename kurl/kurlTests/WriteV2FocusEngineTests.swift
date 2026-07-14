//
//  WriteV2FocusEngineTests.swift
//  kurlTests
//
//  이어 쓰기 포커스(focusTail)와 무포커스 서식 폴백 회귀 — "캔버스를 탭해도 아무 일 없음 /
//  포커스 전에 누른 서식 버튼이 조용히 죽음" 이 V2 첫 출고의 사망 원인이었다.
//  문서 연산은 순수 모델(EditorDocument)이라 UIKit 없이 검증한다.
//

import XCTest

@testable import kurl

@MainActor
final class WriteV2FocusEngineTests: XCTestCase {

    /// Xcode 27 베타 시뮬 런타임에서 @MainActor @Observable 객체가 XCTest 태스크 스코프 안에서
    /// 해제되면 isolated-deinit 경로가 malloc abort 로 죽는다(앱 프로세스에선 재현 없음 — 컴포즈
    /// UITest·실사용 무사고). 테스트가 만든 문서를 프로세스 수명까지 붙들어 그 해제 경로를 우회한다.
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

    // MARK: focusTail — 캔버스 빈 곳 탭의 도착지

    func testFocusTailLandsAtEndOfLastTextBlock() {
        let doc = makeDoc([.paragraph("첫"), .paragraph("둘째 문단")])
        let focus = doc.focusTail()
        XCTAssertEqual(focus.blockID, doc.blocks.last?.id)
        XCTAssertEqual(focus.caret, "둘째 문단".count)
        XCTAssertEqual(doc.blocks.count, 2, "텍스트로 끝나면 블록을 만들지 않는다")
    }

    func testFocusTailAppendsParagraphAfterNonText() {
        let doc = makeDoc([.paragraph("본문"), .divider])
        let focus = doc.focusTail()
        XCTAssertEqual(doc.blocks.count, 3, "구분선으로 끝나면 이어 쓸 문단을 만든다")
        XCTAssertEqual(focus.blockID, doc.blocks.last?.id)
        XCTAssertTrue(doc.blocks.last?.isEmptyParagraph == true)
    }

    func testFocusTailAppendsParagraphAfterCode() {
        let doc = makeDoc([.code("let x = 1", language: "swift")])
        let focus = doc.focusTail()
        XCTAssertEqual(doc.blocks.count, 2, "코드로 끝나면 코드 안이 아니라 다음 문단으로")
        XCTAssertEqual(focus.blockID, doc.blocks.last?.id)
        XCTAssertTrue(doc.blocks.last?.isEmptyParagraph == true)
    }

    // MARK: 무포커스 서식 폴백 — 버튼이 조용히 죽지 않는다

    func testToggleBlockKindWithoutFocusTransformsTail() {
        let doc = makeDoc([.paragraph("제목이 될 문단")])
        XCTAssertNil(doc.focus)
        doc.toggleFocusedBlockKind(.heading(level: 2))
        XCTAssertEqual(doc.blocks[0].kind, .heading(level: 2), "포커스 없이도 문서 끝에 적용된다")
        XCTAssertNotNil(doc.focus, "적용과 함께 포커스(키보드)도 선다")
    }

    func testWrapSelectionWithoutFocusInsertsMarkersAtTail() {
        let doc = makeDoc([.paragraph("문단")])
        XCTAssertNil(doc.focus)
        doc.wrapFocusedSelection(with: "**")
        XCTAssertEqual(doc.blocks[0].text, "문단****", "끝에 마커쌍을 놓는다")
        XCTAssertEqual(doc.focus?.caret, "문단**".count, "캐럿은 마커 사이 — 이어서 치면 볼드")
    }

    func testToggleBlockKindAfterNonTextTailCreatesParagraph() {
        let doc = makeDoc([.paragraph("본문"), .divider])
        doc.toggleFocusedBlockKind(.quote)
        XCTAssertEqual(doc.blocks.count, 3, "구분선 뒤에 새 문단을 만들어 적용한다")
        XCTAssertEqual(doc.blocks.last?.kind, .quote)
    }

    // MARK: 제목 순환 — 버튼 하나가 # → ## → ### → 문단 (구 에디터 cycleHeading 과 같은 순서)

    func testCycleHeadingWalksDownSizesThenBackToParagraph() {
        let doc = makeDoc([.paragraph("걷다 보면")])
        _ = doc.focusTail()
        doc.cycleFocusedHeading()
        XCTAssertEqual(doc.blocks[0].kind, .heading(level: 1))
        XCTAssertEqual(trimmed(doc.markdown), "# 걷다 보면", "h1 은 `# ` 로 왕복")
        doc.cycleFocusedHeading()
        XCTAssertEqual(trimmed(doc.markdown), "## 걷다 보면", "h2 는 `## ` 로 왕복")
        doc.cycleFocusedHeading()
        XCTAssertEqual(trimmed(doc.markdown), "### 걷다 보면", "h3 은 `### ` 로 왕복")
        doc.cycleFocusedHeading()
        XCTAssertEqual(doc.blocks[0].kind, .paragraph, "### 다음은 본문으로 복귀")
        XCTAssertEqual(trimmed(doc.markdown), "걷다 보면", "마커 없이 본문만 남는다")
    }

    func testCycleHeadingFromQuoteStartsAtLevelOne() {
        let doc = makeDoc([.quote("인용에서 시작")])
        _ = doc.focusTail()
        doc.cycleFocusedHeading()
        XCTAssertEqual(doc.blocks[0].kind, .heading(level: 1), "다른 텍스트 블록에선 제목 1 부터")
    }

    func testCycleHeadingPreservesTextAndCaret() {
        let doc = makeDoc([.paragraph("본문 유지")])
        doc.focus = EditorFocus(blockID: doc.blocks[0].id, caret: 2)
        doc.cycleFocusedHeading()
        XCTAssertEqual(doc.blocks[0].text, "본문 유지", "종류만 바뀌고 텍스트는 그대로")
        XCTAssertEqual(doc.focus?.caret, 2, "캐럿 보존")
    }

    private func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: 왕복 안정 — 폴백이 저장 계약을 흔들지 않는다

    func testFocusTailDoesNotChangeMarkdownForTextTail() {
        let doc = makeDoc(markdown: "# 제목\n\n본문")
        let before = doc.markdown
        doc.focusTail()
        XCTAssertEqual(doc.markdown, before)
    }

    // MARK: 맨 URL 라이브 렌더 — 붙여넣은/직접 친 주소가 곧장 링크 모습

    func testBareURLRendersInLinkColor() {
        let block = EditorBlock.paragraph("주소 https://example.com/a 를 붙였다")
        let rendered = BlockInlineRenderer.render(block)
        let range = (rendered.string as NSString).range(of: "https://example.com/a")
        let light = UITraitCollection(userInterfaceStyle: .light)
        let at = rendered.attribute(.foregroundColor, at: range.location, effectiveRange: nil)
        let color = (at as? UIColor)?.resolvedColor(with: light)
        XCTAssertEqual(color, UIColor(Palette.link).resolvedColor(with: light), "맨 URL 은 링크색")
        let after = rendered.attribute(.foregroundColor, at: range.location + range.length, effectiveRange: nil)
        let afterColor = (after as? UIColor)?.resolvedColor(with: light)
        XCTAssertEqual(afterColor, UIColor(Palette.body).resolvedColor(with: light), "URL 밖은 본문색 유지")
    }

    func testMarkdownLinkURLNotDoubleRendered() {
        // `[라벨](url)` 안의 주소는 링크 문법이 소유 — 맨 URL 패스가 마커 숨김을 덮으면 안 된다.
        let block = EditorBlock.paragraph("[라벨](https://example.com/b)")
        let rendered = BlockInlineRenderer.render(block)
        let ns = rendered.string as NSString
        let urlStart = ns.range(of: "https://example.com/b").location
        // 링크 렌더는 url 부분을 숨긴다(clear + 0.01pt) — 그 숨김이 유지되어야 한다.
        let font = rendered.attribute(.font, at: urlStart, effectiveRange: nil) as? UIFont
        XCTAssertEqual(font?.pointSize ?? 0, 0.01, accuracy: 0.001, "링크 url 은 숨김 유지")
    }
}
