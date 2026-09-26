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


@MainActor
final class WriteV2HistoryTests: XCTestCase {
    private static var retained: [EditorDocument] = []

    private func document(_ blocks: [EditorBlock] = [.paragraph("")]) -> EditorDocument {
        let doc = EditorDocument(blocks: blocks)
        Self.retained.append(doc)
        return doc
    }

    func testContinuousTypingCoalescesAndRestoresUnicode() {
        let doc = document()
        let id = doc.blocks[0].id
        doc.focusBody()
        doc.updateText(id, "한")
        doc.updateText(id, "한글🙂")
        doc.updateText(id, "한글🙂 문장")
        doc.undo()
        XCTAssertEqual(doc.blocks[0].text, "")
        XCTAssertFalse(doc.canUndo)
        doc.redo()
        XCTAssertEqual(doc.blocks[0].text, "한글🙂 문장")
        XCTAssertFalse(doc.canRedo)
    }

    func testSplitAndTypingAreSeparateUndoStepsWithStableBlockIDs() {
        let doc = document([.paragraph("First")])
        let firstID = doc.blocks[0].id
        doc.focusTail()
        let second = doc.splitBlock(firstID, at: 5)!
        doc.updateText(second.blockID, "Second")
        doc.undo()
        XCTAssertEqual(doc.blocks.count, 2)
        XCTAssertEqual(doc.blocks[1].text, "")
        doc.undo()
        XCTAssertEqual(doc.blocks, [.init(id: firstID, kind: .paragraph, text: "First")])
        XCTAssertEqual(doc.focus?.blockID, firstID)
        doc.redo()
        XCTAssertEqual(doc.blocks[1].id, second.blockID)
        doc.redo()
        XCTAssertEqual(doc.blocks[1].text, "Second")
    }

    func testNestedInsertionIsAtomicAndNewBranchClearsRedo() {
        let doc = document([.paragraph("Start")])
        doc.focusTail()
        doc.insertLink(url: "https://example.com", label: "Reference")
        XCTAssertEqual(doc.blocks.count, 3)
        doc.undo()
        XCTAssertEqual(doc.blocks.count, 1)
        XCTAssertEqual(doc.blocks[0].text, "Start")
        XCTAssertTrue(doc.canRedo)
        doc.updateText(doc.blocks[0].id, "Different direction")
        XCTAssertFalse(doc.canRedo)
    }

    func testNativeManagerUsesDocumentHistoryAndIgnoresTextOnlyRegistration() {
        let doc = document([.paragraph("Hello")])
        doc.focusTail()
        doc.toggleFocusedBlockKind(.heading(level: 2))
        var nativeOnlyUndoRan = false
        doc.undoManager.registerUndo(withTarget: self) { _ in nativeOnlyUndoRan = true }
        doc.undoManager.undo()
        XCTAssertFalse(nativeOnlyUndoRan, "UIKit registrations must not create a competing text-only undo step")
        XCTAssertEqual(doc.blocks[0].kind, .paragraph)
        doc.undoManager.redo()
        XCTAssertEqual(doc.blocks[0].kind, .heading(level: 2))
        XCTAssertFalse(doc.undoManager.isUndoRegistrationEnabled)
    }

    func testTableTextAndStructureUndoIndependently() {
        let doc = document([.table(.blank)])
        let id = doc.blocks[0].id
        doc.updateTableCell(id, row: 1, col: 0, text: "value")
        doc.addTableRow(id)
        doc.undo()
        XCTAssertEqual(doc.tableSnapshot(id)?.rows.count, 2)
        XCTAssertEqual(doc.tableSnapshot(id)?.rows[1][0], "value")
        doc.undo()
        XCTAssertEqual(doc.tableSnapshot(id)?.rows[1][0], "")
        doc.redo()
        XCTAssertEqual(doc.tableSnapshot(id)?.rows[1][0], "value")
    }

    func testIMECommitsOneEditAndCancelledCompositionAddsNoHistory() {
        let doc = document()
        let id = doc.blocks[0].id
        doc.setComposition(id, active: true)
        doc.updateText(id, "ㅎ")
        doc.updateText(id, "하")
        XCTAssertFalse(doc.canUndo, "Do not replace an active IME candidate from the toolbar")
        doc.updateText(id, "한")
        doc.setComposition(id, active: false)
        XCTAssertTrue(doc.canUndo)
        doc.setComposition(id, active: true)
        doc.updateText(id, "한ㄱ")
        doc.updateText(id, "한") // Candidate cancelled.
        doc.setComposition(id, active: false)
        doc.undo()
        XCTAssertEqual(doc.blocks[0].text, "", "Cancelled composition must not leave a phantom undo step")
        XCTAssertFalse(doc.canUndo)
        doc.redo()
        XCTAssertEqual(doc.blocks[0].text, "한")
    }

    func testFocusBodyRetainsInsertionPointAfterKeyboardDismissal() {
        let doc = document([.paragraph("One"), .paragraph("Two")])
        doc.focusBody()
        XCTAssertEqual(doc.focus, EditorFocus(blockID: doc.blocks[0].id, caret: 0))
        doc.focus = EditorFocus(blockID: doc.blocks[1].id, caret: 2)
        doc.endEditing(doc.blocks[1].id)
        XCTAssertFalse(doc.isEditing)
        doc.focusBody()
        XCTAssertTrue(doc.isEditing)
        XCTAssertEqual(doc.focus, EditorFocus(blockID: doc.blocks[1].id, caret: 2))
        XCTAssertFalse(doc.canUndo, "Focusing an existing block is not a document edit")
    }

    func testTitleReturnSplitsCoalescedTypingAndCarriesTheRest() {
        XCTAssertEqual(ComposeView.splitAtReturn(from: "Next targe", to: "Next target\n")?.title, "Next target")
        XCTAssertEqual(ComposeView.splitAtReturn(from: "Next targe", to: "Next target\n")?.carried, "")
        XCTAssertEqual(ComposeView.splitAtReturn(from: "제목", to: "제목\n본문")?.title, "제목")
        XCTAssertEqual(ComposeView.splitAtReturn(from: "제목", to: "제목\n본문")?.carried, "본문")
        XCTAssertEqual(ComposeView.splitAtReturn(from: "제목", to: "제\n목")?.title, "제목")
        XCTAssertEqual(ComposeView.splitAtReturn(from: "", to: "첫 줄\n둘\n셋")?.carried, "둘\n셋")
        XCTAssertNil(ComposeView.splitAtReturn(from: "제목", to: "제목입"))
    }

    func testCarriedTitleTextStartsTheBody() {
        let empty = document()
        empty.focusBody()
        empty.insertCarriedText("본문 시작")
        XCTAssertEqual(empty.markdown, "본문 시작")
        XCTAssertEqual(empty.focus?.caret, "본문 시작".count)
        XCTAssertTrue(empty.isEditing)

        let written = document([.paragraph("이어서")])
        written.focusBody()
        written.insertCarriedText("앞 ")
        XCTAssertEqual(written.markdown, "앞 이어서")
        XCTAssertEqual(written.focus?.caret, 2)

        let pasted = document()
        pasted.focusBody()
        pasted.insertCarriedText("둘\n\n셋")
        XCTAssertEqual(pasted.markdown, "둘\n\n셋")
        XCTAssertEqual(pasted.focus?.blockID, pasted.blocks.last?.id)
    }

    func testNoOpDoesNotPolluteHistoryAndFormattingRestoresSelection() {
        let doc = document([.paragraph("Hello")])
        let id = doc.blocks[0].id
        doc.mergeBackward(id)
        XCTAssertFalse(doc.canUndo)
        let selection = EditorFocus(blockID: id, caret: 0, selectionLength: 5)
        doc.focus = selection
        doc.wrapFocusedSelection(with: "**")
        doc.undo()
        XCTAssertEqual(doc.blocks[0].text, "Hello")
        XCTAssertEqual(doc.focus, selection)
    }

    func testNativeUndoCannotReplaceActiveComposition() {
        let doc = document([.paragraph("Original")])
        let id = doc.blocks[0].id
        doc.updateText(id, "Saved edit")
        doc.setComposition(id, active: true)
        doc.updateText(id, "Saved editㅎ")
        XCTAssertFalse(doc.undoManager.canUndo)
        XCTAssertFalse(doc.undoManager.canRedo)
        doc.undoManager.undo() // Native Cmd+Z/edit menu, bypassing doc.undo().
        XCTAssertEqual(doc.blocks[0].text, "Saved editㅎ")
        doc.updateText(id, "Saved edit한")
        doc.setComposition(id, active: false)
        doc.undoManager.undo()
        XCTAssertEqual(doc.blocks[0].text, "Saved edit")
    }

    func testTableIMEUsesCellKeyAndCancellationPreservesPriorHistory() {
        let doc = document([.table(.blank)])
        let id = doc.blocks[0].id
        doc.setTableComposition(id, row: 1, col: 0, active: true)
        doc.updateTableCell(id, row: 1, col: 0, text: "ㅎ")
        XCTAssertFalse(doc.canUndo)
        XCTAssertFalse(doc.undoManager.canUndo)
        doc.updateTableCell(id, row: 1, col: 0, text: "한")
        doc.setTableComposition(id, row: 1, col: 0, active: false)
        XCTAssertTrue(doc.canUndo)
        doc.setTableComposition(id, row: 1, col: 1, active: true)
        doc.updateTableCell(id, row: 1, col: 1, text: "ㄱ")
        doc.updateTableCell(id, row: 1, col: 1, text: "")
        doc.setTableComposition(id, row: 1, col: 1, active: false)
        doc.undo()
        XCTAssertEqual(doc.tableSnapshot(id)?.rows[1], ["", ""])
        XCTAssertFalse(doc.canUndo)
        doc.redo()
        XCTAssertEqual(doc.tableSnapshot(id)?.rows[1], ["한", ""])
    }


    func testBackspaceAfterFirstCharacterDeletesTextButAtStartMergesOnce() {
        var merges = 0
        let block = EditorBlock.paragraph("가나다")
        let view = BlockTextView(
            block: block, isFocused: true, caretOnFocus: 1,
            onTextChange: { _ in }, onSplit: { _, _ in nil }, onMergeBackward: { merges += 1 },
            onLineHeadShortcut: { _, _, _ in }, onFocused: {}, onSelectionChange: { _, _ in })
        let coordinator = view.makeCoordinator()
        coordinator.onEmptyBackspace = { merges += 1 }
        let textView = BlockUITextView()
        textView.delegate = coordinator
        textView.text = "가나다"
        textView.currentBlockText = "가나다"
        textView.selectedRange = NSRange(location: 1, length: 0)
        withExtendedLifetime(coordinator) {
            XCTAssertTrue(coordinator.textView(
                textView, shouldChangeTextIn: NSRange(location: 0, length: 1), replacementText: ""))
            textView.deleteBackward()
            XCTAssertEqual(textView.text, "나다")
            XCTAssertEqual(merges, 0)
            textView.selectedRange = NSRange(location: 0, length: 0)
            textView.deleteBackward()
            XCTAssertEqual(textView.text, "나다")
            XCTAssertEqual(merges, 1, "Only a caret at the actual block start requests one merge")
        }
    }

    func testBodyFocusWaitsForWindowAndCancelledRequestDoesNotStealIt() async {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIViewController()
        window.rootViewController = controller
        defer { window.isHidden = true }

        let body = BlockUITextView(frame: CGRect(x: 20, y: 100, width: 300, height: 100))
        body.text = "본문"
        let acquired = expectation(description: "Body gains focus after window attachment")
        body.requestDocumentFocus(true) { textView in
            textView.selectedRange = NSRange(location: 1, length: 0)
            acquired.fulfill()
        }
        XCTAssertFalse(body.isFirstResponder)
        controller.view.addSubview(body)
        window.makeKeyAndVisible()
        await fulfillment(of: [acquired], timeout: 2)
        XCTAssertTrue(body.isFirstResponder)
        XCTAssertEqual(body.selectedRange.location, 1)

        let abandoned = BlockUITextView(frame: CGRect(x: 20, y: 220, width: 300, height: 100))
        abandoned.requestDocumentFocus(true) { _ in XCTFail("Cancelled focus must never be acquired") }
        abandoned.requestDocumentFocus(false)
        controller.view.addSubview(abandoned)
        let nextTurn = expectation(description: "Attachment callback completed")
        DispatchQueue.main.async { nextTurn.fulfill() }
        await fulfillment(of: [nextTurn], timeout: 2)
        XCTAssertFalse(abandoned.isFirstResponder)
        XCTAssertTrue(body.isFirstResponder)
    }

    func testImmediateTypingAfterReturnStaysInContinuationBeforeSwiftUIUpdates() {
        for first in [EditorBlock.paragraph("First"), .heading(2, "First"), .quote("First"), .listItem("First")] {
            let doc = document([first])
            let id = first.id
            doc.focusTail()
            let view = BlockTextView(
                block: first, isFocused: true, caretOnFocus: 5,
                onTextChange: { doc.updateText(id, $0) },
                onSplit: { caret, length in
                    guard let target = doc.splitBlock(id, at: caret, deleting: length),
                          let continuation = doc.blocks.first(where: { $0.id == target.blockID }) else { return nil }
                    return EditorSplitContinuation(block: continuation, caret: target.caret)
                },
                onMergeBackward: {}, onLineHeadShortcut: { _, _, _ in },
                onFocused: {}, onSelectionChange: { _, _ in })
            let coordinator = view.makeCoordinator()
            let textView = BlockUITextView()
            textView.delegate = coordinator
            textView.text = first.text
            textView.currentBlockText = first.text
            textView.selectedRange = NSRange(location: 5, length: 0)
            withExtendedLifetime(coordinator) {
                // No run-loop yield or SwiftUI update between Return and any following key.
                for character in "\nSecond\nThird" {
                    let replacement = String(character)
                    if coordinator.textView(textView, shouldChangeTextIn: textView.selectedRange, replacementText: replacement) {
                        textView.insertText(replacement)
                    }
                }
                XCTAssertEqual(doc.blocks.map(\.text), ["First", "Second", "Third"], "\(first.kind)")
                XCTAssertEqual(doc.blocks.last?.id, id, "The continuing input view keeps its identity")
                XCTAssertEqual(textView.text, "Third")
                doc.undo()
                XCTAssertEqual(doc.blocks.map(\.text), ["First", "Second", ""])
                doc.undo()
                XCTAssertEqual(doc.blocks.map(\.text), ["First", "Second"])
            }
        }
    }

    private func splitInputBridge(_ doc: EditorDocument) -> (BlockUITextView, BlockTextView.Coordinator) {
        let first = doc.blocks[0]
        let id = first.id
        let view = BlockTextView(
            block: first, isFocused: true, caretOnFocus: doc.focus?.caret ?? 0,
            onTextChange: { doc.updateText(id, $0) },
            onSplit: { caret, length in
                guard let target = doc.splitBlock(id, at: caret, deleting: length),
                      let continuation = doc.blocks.first(where: { $0.id == target.blockID }) else { return nil }
                return EditorSplitContinuation(block: continuation, caret: target.caret)
            },
            onMergeBackward: {}, onLineHeadShortcut: { _, _, _ in },
            onFocused: {}, onSelectionChange: { _, _ in })
        let coordinator = view.makeCoordinator()
        let textView = BlockUITextView()
        textView.delegate = coordinator
        textView.text = first.text
        textView.currentBlockText = first.text
        return (textView, coordinator)
    }

    func testReturnReplacesUTF16SelectionAndUndoesAsOneEdit() {
        let doc = document([.paragraph("A🙂BC")])
        let original = doc.blocks
        let selection = EditorFocus(blockID: original[0].id, caret: 1, selectionLength: 2)
        doc.focus = selection
        let (textView, coordinator) = splitInputBridge(doc)
        textView.selectedRange = NSRange(location: 1, length: 3) // 🙂 + B occupy three UTF-16 units.
        XCTAssertFalse(coordinator.textView(textView, shouldChangeTextIn: textView.selectedRange, replacementText: "\n"))
        let split = doc.blocks
        XCTAssertEqual(split.map(\.text), ["A", "C"])
        XCTAssertEqual(split[1].id, original[0].id)
        XCTAssertNotEqual(split[0].id, original[0].id)
        XCTAssertEqual(textView.text, "C")
        XCTAssertEqual(textView.selectedRange, NSRange(location: 0, length: 0))
        doc.undo()
        XCTAssertEqual(doc.blocks, original)
        XCTAssertEqual(doc.focus, selection)
        XCTAssertFalse(doc.canUndo, "Selection replacement and Enter are one document edit")
        doc.redo()
        XCTAssertEqual(doc.blocks, split, "Redo restores the same head/tail identities")
    }

    func testReturnKeepsImmediateTypingInsideReopenedFormatting() {
        for marker in ["**", "*", "~~", "`"] {
            let source = marker + "ab" + marker
            let doc = document([.paragraph(source)])
            doc.focus = EditorFocus(blockID: doc.blocks[0].id, caret: marker.count + 1)
            let (textView, coordinator) = splitInputBridge(doc)
            textView.selectedRange = NSRange(location: marker.count + 1, length: 0)
            XCTAssertFalse(coordinator.textView(textView, shouldChangeTextIn: textView.selectedRange, replacementText: "\n"))
            XCTAssertEqual(textView.selectedRange.location, marker.count)
            XCTAssertEqual(doc.focus?.caret, marker.count)
            XCTAssertTrue(coordinator.textView(textView, shouldChangeTextIn: textView.selectedRange, replacementText: "X"))
            textView.insertText("X")
            XCTAssertEqual(doc.blocks.map(\.text), [marker + "a" + marker, marker + "Xb" + marker])
            doc.undo()
            XCTAssertEqual(doc.blocks[1].text, marker + "b" + marker)
            doc.undo()
            XCTAssertEqual(doc.blocks[0].text, source)
        }
    }

}
