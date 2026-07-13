//
//  BlockTextView.swift
//  kurl — WriteV2
//
//  블록 하나를 그리는 UITextView 브리지. "원시 마크다운 안 보이고 최종 모습으로 렌더 + 편집" 의
//  실제 구현. 문단/제목/인용은 인라인 마크다운(`**볼드**` 등)을 볼드/이탤릭으로 *렌더*하되 마커
//  글자는 안 보이게 하지 않고(Phase 1) 인라인 스타일만 입힌다 — 대신 블록 종류(제목 크기·인용 바)는
//  마커 없이 최종 모습이다. 코드 블록은 별도(BlockCodeView, SwiftUI).
//
//  세금(§4에서 예고): shouldChangeTextIn 에서 (1) 블록 경계 엔터/백스페이스를 가로채 문서 구조
//  연산으로 승격 (2) 줄머리 지름길(`# `·`> `·```)을 종류 전환으로 승격. 한글 IME 는 markedTextRange
//  가 nil 일 때만 인라인 재렌더(조합 중 안 건드림 — MarkdownSyntaxHighlighter 와 같은 가드).
//

import SwiftUI
import UIKit

/// 문단·제목·인용 블록용 UITextView. 코드 블록은 이걸 안 쓴다.
struct BlockTextView: UIViewRepresentable {
    let block: EditorBlock
    let isFocused: Bool
    let caretOnFocus: Int
    /// 텍스트 변경 콜백(구조 변경 없음).
    let onTextChange: (String) -> Void
    /// 엔터로 블록 분할 요청 — caret 위치 전달.
    let onSplit: (Int) -> Void
    /// 맨 앞 백스페이스로 앞 블록과 병합 요청.
    let onMergeBackward: () -> Void
    /// 줄머리 지름길 감지 — 종류·마커 뗀 텍스트·caret 을 문서에 승격 요청.
    let onLineHeadShortcut: (EditorBlockKind, String, Int) -> Void
    /// 포커스 획득 통지(문서 focus 동기화).
    let onFocused: () -> Void

    func makeUIView(context: Context) -> BlockUITextView {
        let tv = BlockUITextView()
        tv.delegate = context.coordinator
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.smartInsertDeleteType = .no
        tv.autocorrectionType = .default
        // SwiftUI 가 제안한 폭에 맞춰 줄바꿈하도록 — 안 하면 UITextView 가 본문 폭으로 부풀어 화면 밖으로 샌다.
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        context.coordinator.textView = tv
        context.coordinator.onEmptyBackspace = onMergeBackward
        apply(block, to: tv, coordinator: context.coordinator)
        return tv
    }

    /// 제안된 폭에 맞춰 높이를 재는 대신 폭을 강제 — UITextView 가 그 폭 안에서 줄바꿈한다(오버플로 방지).
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: BlockUITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width < .infinity else { return nil }
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fit.height)
    }

    func updateUIView(_ tv: BlockUITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.onEmptyBackspace = onMergeBackward
        // 외부(문서)에서 온 text/kind 변화만 반영 — 사용자가 방금 친 것과 같으면 건너뛴다(캐럿 튐 방지).
        if tv.currentBlockText != block.text || context.coordinator.renderedKind != block.kind {
            apply(block, to: tv, coordinator: context.coordinator)
        }
        if isFocused, !tv.isFirstResponder {
            tv.becomeFirstResponder()
            setCaret(caretOnFocus, in: tv)
        } else if isFocused, tv.isFirstResponder,
                  context.coordinator.pendingCaret != nil {
            setCaret(caretOnFocus, in: tv)
        }
        context.coordinator.pendingCaret = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: 렌더 — 블록을 최종 모습으로

    private func apply(_ block: EditorBlock, to tv: BlockUITextView, coordinator: Coordinator) {
        coordinator.isProgrammaticEdit = true
        tv.currentBlockText = block.text
        coordinator.renderedKind = block.kind
        tv.attributedText = BlockInlineRenderer.render(block)
        tv.typingAttributes = BlockInlineRenderer.typingAttributes(for: block.kind)
        coordinator.isProgrammaticEdit = false
    }

    private func setCaret(_ pos: Int, in tv: UITextView) {
        let clamped = max(0, min(pos, (tv.text as NSString).length))
        if let position = tv.position(from: tv.beginningOfDocument, offset: clamped) {
            tv.selectedTextRange = tv.textRange(from: position, to: position)
        }
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: BlockTextView
        weak var textView: BlockUITextView?
        var renderedKind: EditorBlockKind?
        var isProgrammaticEdit = false
        var pendingCaret: Int?
        var onEmptyBackspace: (() -> Void)?

        init(_ parent: BlockTextView) { self.parent = parent }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocused()
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            guard let tv = textView as? BlockUITextView else { return true }

            // 엔터 = 블록 분할(코드 블록은 이 뷰를 안 쓰므로 여기 엔터는 항상 구조 엔터).
            if text == "\n" {
                let caret = swiftCaret(in: tv, nsLocation: range.location)
                parent.onSplit(caret)
                return false
            }

            // 맨 앞에서 백스페이스(빈 replacement + 길이1 삭제 + range.location==0) = 앞과 병합.
            if text.isEmpty, range.length == 1, range.location == 0 {
                onEmptyBackspace?()
                return false
            }

            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isProgrammaticEdit, let tv = textView as? BlockUITextView else { return }
            let newText = tv.text ?? ""

            // 줄머리 마크다운 지름길 — 조합 중이 아닐 때만(한글 IME 가드).
            if tv.markedTextRange == nil,
               let shortcut = BlockShortcuts.detect(in: newText, kind: parent.block.kind) {
                tv.currentBlockText = shortcut.strippedText
                parent.onLineHeadShortcut(shortcut.kind, shortcut.strippedText, shortcut.caret)
                return
            }

            tv.currentBlockText = newText
            parent.onTextChange(newText)

            // 인라인 재렌더는 조합이 끝난 뒤에만(조합 중 attributedText 교체는 IME 를 깬다).
            if tv.markedTextRange == nil {
                reRenderInline(tv)
            }
        }

        /// 인라인 마크다운(`**볼드**` 등)을 스타일로 다시 입힌다 — 캐럿을 보존한 채.
        private func reRenderInline(_ tv: BlockUITextView) {
            let selected = tv.selectedRange
            let block = EditorBlock(kind: parent.block.kind, text: tv.text ?? "")
            isProgrammaticEdit = true
            tv.attributedText = BlockInlineRenderer.render(block)
            tv.typingAttributes = BlockInlineRenderer.typingAttributes(for: block.kind)
            if selected.location <= (tv.text as NSString).length {
                tv.selectedRange = selected
            }
            isProgrammaticEdit = false
        }

        /// NSString(UTF-16) location → Swift String 캐럿(문서 연산은 String 인덱스 기준).
        private func swiftCaret(in tv: UITextView, nsLocation: Int) -> Int {
            let ns = tv.text as NSString
            let clamped = max(0, min(nsLocation, ns.length))
            let prefix = ns.substring(to: clamped)
            return prefix.count
        }
    }
}

/// 빈 블록에서의 백스페이스를 잡기 위한 서브클래스 — 빈 UITextView 는 shouldChangeText 가
/// 안 불릴 수 있어(삭제할 문자 없음) deleteBackward 를 직접 가로챈다(블록 병합·강등의 핵심).
final class BlockUITextView: UITextView {
    /// 문서가 아는 이 블록의 현재 text — SwiftUI 왕복 시 캐럿 튐/재렌더 루프 방지용 캐시.
    var currentBlockText: String = ""
    var onEmptyBackspaceOverride: (() -> Void)?

    override func deleteBackward() {
        // 캐럿이 맨 앞이고 선택이 없으면(빈 블록 포함) 병합/강등으로 승격.
        if let range = selectedTextRange, range.isEmpty,
           offset(from: beginningOfDocument, to: range.start) == 0 {
            if let coordinator = delegate as? BlockTextView.Coordinator {
                coordinator.onEmptyBackspace?()
                return
            }
        }
        super.deleteBackward()
    }
}
