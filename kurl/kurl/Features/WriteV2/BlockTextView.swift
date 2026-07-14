//
//  BlockTextView.swift
//  kurl — WriteV2
//
//  블록 하나를 그리는 UITextView 브리지. "원시 마크다운 안 보이고 최종 모습으로 렌더 + 편집" 의
//  실제 구현. 문단/제목/인용은 인라인 마크다운(`**볼드**`·`*이탤릭*`·`[라벨](url)` 등)을 최종 모습으로
//  렌더하며 마커 글자는 숨긴다 — 캐럿이 그 마크업에 걸칠 때만 마커를 흐리게 반개봉해 손볼 수 있게 한다
//  (BlockInlineRenderer.render(activeRange:)). 블록 종류(제목 크기·인용 바)도 마커 없이 최종 모습이다.
//  코드 블록은 별도(BlockCodeView, SwiftUI).
//
//  세금(§4에서 예고): shouldChangeTextIn 에서 (1) 블록 경계 엔터/백스페이스를 가로채 문서 구조
//  연산으로 승격 (2) 줄머리 지름길(`# `·`> `·```)을 종류 전환으로 승격. 한글 IME 는 markedTextRange
//  가 nil 일 때만 인라인 재렌더(조합 중 안 건드림 — MarkdownSyntaxHighlighter 와 같은 가드).
//

import SwiftUI
import UIKit

/// 캔버스 붙여넣기 훅 — 실제 업로드·재호스팅·단축은 호스트(컴포즈)가 잇는다(현행 V1 캔버스와 같은 계약).
/// 하네스(EditorHarnessView)는 기본값(전부 nil)로 살아 네트워크 없이 돈다.
struct EditorPasteHandlers {
    /// 클립보드 이미지 바이트 — 호스트가 업로드 후 IMAGE 블록으로 넣는다.
    var images: (([UIImage]) -> Void)?
    /// 붙여넣은 외부 이미지 URL — 호스트가 우리 버킷으로 재호스팅 후 IMAGE 블록으로 넣는다(핫링크 방지).
    var imageURL: ((String) -> Void)?
    /// 붙여넣은 일반 URL 의 kurl 단축 — nil 반환(실패 포함)이면 원문을 그대로 둔다.
    var shorten: ((String) async -> String?)?
}

/// 문단·제목·인용 블록용 UITextView. 코드 블록은 이걸 안 쓴다.
struct BlockTextView: UIViewRepresentable {
    let block: EditorBlock
    let isFocused: Bool
    /// 문서 focus 의 캐럿(String 인덱스 거리). 포커스 획득/서식 적용 후 이 위치로 캐럿·선택을 되돌린다.
    let caretOnFocus: Int
    /// 문서 focus 의 선택 길이(String 인덱스). >0 이면 [caret, caret+length) 를 선택 상태로 복원(서식 감싸기 후).
    var selectionLengthOnFocus: Int = 0
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
    /// 선택/캐럿 변화 통지 — (caret, selectionLength) String 인덱스. 서식 툴바가 이 선택을 마커로 감싼다.
    let onSelectionChange: (Int, Int) -> Void
    /// 붙여넣기 훅 — 이미지·URL 붙여넣기를 기본 텍스트 붙여넣기보다 먼저 가로챈다(V1 캔버스 계약 미러).
    var pasteHandlers: EditorPasteHandlers = EditorPasteHandlers()

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
        wirePaste(tv, coordinator: context.coordinator)
        apply(block, to: tv, coordinator: context.coordinator)
        return tv
    }

    /// 붙여넣기 경로 배선 — 이미지/이미지 URL 은 호스트로 넘기고, 일반 URL 은 원문을 먼저 넣어
    /// 즉시 반응한 뒤(맨 URL 도 링크색으로 라이브 렌더된다) 단축이 오면 그 자리만 치환한다.
    private func wirePaste(_ tv: BlockUITextView, coordinator: Coordinator) {
        tv.onPasteImages = pasteHandlers.images
        tv.onPasteImageURL = pasteHandlers.imageURL
        tv.onPastedURL = { [weak tv, weak coordinator] url, range in
            guard let tv, let coordinator else { return }
            coordinator.shortenPastedURL(url, at: range, in: tv)
        }
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
        wirePaste(tv, coordinator: context.coordinator)
        // 외부(문서)에서 온 text/kind 변화만 반영 — 사용자가 방금 친 것과 같으면 건너뛴다(캐럿 튐 방지).
        let textChanged = tv.currentBlockText != block.text
            || context.coordinator.renderedKind != block.kind
        if textChanged {
            apply(block, to: tv, coordinator: context.coordinator)
        }
        if isFocused, !tv.isFirstResponder {
            tv.becomeFirstResponder()
            setSelection(caret: caretOnFocus, length: selectionLengthOnFocus, in: tv)
        } else if isFocused, tv.isFirstResponder, textChanged {
            // 외부(문서)에서 온 텍스트 변화 = 서식 툴바 감싸기·블록 토글·구조 연산 — 문서가 준 새 선택/
            // 캐럿을 복원한다. 사용자 타이핑은 textViewDidChange 가 currentBlockText 를 먼저 맞춰 여기
            // textChanged=false 이므로 이 경로를 안 타(타이핑 캐럿을 안 건드린다).
            // 동기 지름길 전환 직후엔 한 번 건너뛴다 — 전환과 이 복원 사이에 이미 새 글자가 들어와
            // 있을 수 있어(속사 타이핑), 캐럿 0 복원이 이후 입력을 앞으로 끼워 넣는다.
            if context.coordinator.suppressSelectionRestoreOnce {
                context.coordinator.suppressSelectionRestoreOnce = false
            } else {
                setSelection(caret: caretOnFocus, length: selectionLengthOnFocus, in: tv)
            }
        }
        context.coordinator.pendingCaret = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: 렌더 — 블록을 최종 모습으로

    private func apply(_ block: EditorBlock, to tv: BlockUITextView, coordinator: Coordinator) {
        coordinator.isProgrammaticEdit = true
        tv.currentBlockText = block.text
        coordinator.renderedKind = block.kind
        // 포커스 중이면 현재 캐럿을 반개봉 기준으로 넘긴다 — 안 그러면 외부 갱신마다 활성 마커까지 숨는다.
        // attributedText 교체는 selection 을 끝으로 리셋하므로, 포커스 중이면 캐럿을 복원한다(외부 동기화
        // 중 캐럿이 맨 앞으로 튀지 않게 — reRenderInline 과 같은 규율).
        let active = tv.isFirstResponder ? tv.selectedRange : nil
        tv.attributedText = BlockInlineRenderer.render(block, activeRange: active)
        tv.typingAttributes = BlockInlineRenderer.typingAttributes(for: block.kind)
        if let active, active.location + active.length <= (tv.text as NSString).length {
            tv.selectedRange = active
        }
        coordinator.isProgrammaticEdit = false
    }

    /// 문서 focus 의 (caret, length) — 둘 다 String 인덱스 거리 — 를 UITextView 선택으로 복원한다.
    /// String↔UTF-16 변환을 거쳐(한글 등 다바이트 안전) length>0 이면 범위 선택, 0 이면 캐럿.
    private func setSelection(caret: Int, length: Int, in tv: UITextView) {
        let text = tv.text ?? ""
        let startStr = max(0, min(caret, text.count))
        let endStr = max(startStr, min(caret + max(0, length), text.count))
        let utf16Start = text.index(text.startIndex, offsetBy: startStr).utf16Offset(in: text)
        let utf16End = text.index(text.startIndex, offsetBy: endStr).utf16Offset(in: text)
        guard let from = tv.position(from: tv.beginningOfDocument, offset: utf16Start),
              let to = tv.position(from: tv.beginningOfDocument, offset: utf16End) else { return }
        tv.selectedTextRange = tv.textRange(from: from, to: to)
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
        /// 동기 지름길 전환 직후 한 번, updateUIView 의 문서 focus 선택 복원을 건너뛴다 —
        /// 전환 뒤에도 키 입력이 이어지는 중이라(속사 타이핑) 캐럿을 0 으로 되돌리면 글자가 뒤섞인다.
        /// 툴바 감싸기/토글 경로는 이 플래그를 안 세우므로 종전대로 복원한다.
        var suppressSelectionRestoreOnce = false

        init(_ parent: BlockTextView) { self.parent = parent }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocused()
            // 막 포커스를 얻었으면 캐럿이 걸친 마크업을 반개봉한다(숨어 있던 마커를 그 자리만 노출).
            if let tv = textView as? BlockUITextView, tv.markedTextRange == nil {
                reRenderInline(tv)
            }
        }

        /// 캐럿/선택이 바뀌면 (1) 문서에 선택 좌표를 알려 서식 툴바가 감쌀 수 있게 하고 (2) 캐럿이
        /// 들어온 `**볼드**`·`[라벨](url)` 은 마커를 흐리게 열고 벗어난 것은 다시 숨긴다(반개봉의 왕복).
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isProgrammaticEdit, let tv = textView as? BlockUITextView,
                  tv.markedTextRange == nil else { return }
            // 선택 좌표를 String 인덱스로 문서에 보고(선택 유무 무관) — 툴바가 이 선택을 감싼다.
            let range = tv.selectedRange
            let caret = swiftCaret(in: tv, nsLocation: range.location)
            let end = swiftCaret(in: tv, nsLocation: range.location + range.length)
            parent.onSelectionChange(caret, max(0, end - caret))

            // 드래그 선택 중(길이>0)엔 재렌더하지 않는다 — attributedText 교체가 확대경/드래그를 끊고,
            // 선택 중엔 반개봉이 굳이 필요 없다(선택을 놓으면 캐럿이 되고 그때 열린다).
            guard range.length == 0 else { return }
            // 인라인 마커가 아예 없는 블록은 반개봉할 게 없으니 건너뛴다(캐럿 이동마다 재렌더 낭비 방지).
            let text = tv.text ?? ""
            guard text.contains("*") || text.contains("`") || text.contains("[") else { return }
            // 반개봉 상태(어느 마크업이 열렸나)가 캐럿 이동으로 실제 바뀔 때만 다시 칠한다 — 마크업과
            // 무관한 위치들 사이 이동엔 재렌더를 생략(방향키 네비 낭비 방지).
            let active = BlockInlineRenderer.activeMarkupSpan(in: text, caret: range.location)
            guard active != lastRevealedSpan else { return }
            lastRevealedSpan = active
            reRenderInline(tv)
        }

        /// 직전에 반개봉된 마크업 span(없으면 nil) — 캐럿 이동이 반개봉 상태를 바꿀 때만 재렌더하려는 캐시.
        private var lastRevealedSpan: NSRange?

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

            // 줄머리 지름길(`# `·`- `·`> `·`1. `)의 방아쇠 공백을 **동기** 가로채기 — didChange
            // (SwiftUI 왕복 뒤 재렌더)에 맡기면 전환이 한 프레임 늦고, 그 창에 속사 타이핑(하드웨어
            // 키보드·연속 입력)의 다음 글자들이 끼면 문서 focus(캐럿 0) 복원이 타이핑을 뒤섞는다.
            // 여기서 텍스트뷰를 즉시 마커 제거 상태로 바꾸고 문서에 전환을 알리면, 이후 키 입력은
            // 처음부터 올바른(빈) 블록에 떨어진다. 붙여넣기 등 비공백 경로는 아래 didChange 가 그대로 처리.
            if text == " ", range.length == 0, tv.markedTextRange == nil,
               range.location == (tv.text as NSString).length,
               let shortcut = BlockShortcuts.detect(in: (tv.text ?? "") + " ", kind: parent.block.kind) {
                isProgrammaticEdit = true
                tv.text = shortcut.strippedText
                tv.currentBlockText = shortcut.strippedText
                tv.typingAttributes = BlockInlineRenderer.typingAttributes(for: shortcut.kind)
                isProgrammaticEdit = false
                suppressSelectionRestoreOnce = true
                parent.onLineHeadShortcut(shortcut.kind, shortcut.strippedText, shortcut.caret)
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

        /// 인라인 마크다운(`**볼드**`·`[라벨](url)` 등)을 최종 모습으로 다시 입힌다 — 캐럿을 보존한 채,
        /// 그 캐럿이 걸친 마크업만 마커를 반개봉한다(activeRange). attributedText 교체가 selection 을
        /// 리셋하므로 곧바로 되돌린다.
        private func reRenderInline(_ tv: BlockUITextView) {
            let selected = tv.selectedRange
            let block = EditorBlock(kind: parent.block.kind, text: tv.text ?? "")
            isProgrammaticEdit = true
            tv.attributedText = BlockInlineRenderer.render(block, activeRange: selected)
            tv.typingAttributes = BlockInlineRenderer.typingAttributes(for: block.kind)
            if selected.location <= (tv.text as NSString).length {
                tv.selectedRange = selected
            }
            // 방금 반개봉한 span 을 캐시에 기록 — 이어지는 selection 콜백이 같은 상태로 재렌더 반복하지 않게.
            lastRevealedSpan = BlockInlineRenderer.activeMarkupSpan(in: block.text, caret: selected.location)
            isProgrammaticEdit = false
        }

        /// 붙여넣은 일반 URL 을 kurl 단축링크로 치환한다 — V1(MarkdownTextView.onPasteURL) 계약 미러.
        /// 원문은 이미 캐럿 자리에 들어가 있다(즉시 반응). 단축이 돌아오면 그 사이 사용자가 그 범위를
        /// 안 건드렸을 때만 제자리 교체하고, 조용히 바꾸지 않도록 되돌리기 토스트를 띄운다.
        /// 동영상(YouTube·Vimeo) URL 은 단축하지 않는다 — 단독 문단 원문이어야 발행 시 플레이어가 된다.
        func shortenPastedURL(_ original: String, at range: NSRange, in tv: BlockUITextView) {
            guard let shorten = parent.pasteHandlers.shorten,
                  !WriteV2VideoDetect.isVideoURL(original) else { return }
            Task { @MainActor [weak tv, weak self] in
                guard let short = await shorten(original), short != original,
                      let tv, let self, tv.markedTextRange == nil else { return }
                let ns = tv.text as NSString
                guard range.location + range.length <= ns.length,
                      ns.substring(with: range) == original,
                      let start = tv.position(from: tv.beginningOfDocument, offset: range.location),
                      let end = tv.position(from: start, offset: range.length),
                      let textRange = tv.textRange(from: start, to: end)
                else { return }
                tv.replace(textRange, withText: short)
                tv.selectedRange = NSRange(
                    location: range.location + (short as NSString).length, length: 0)
                self.textViewDidChange(tv)
                ToastCenter.shared.show(
                    String(localized: "kurl 링크로 단축했어요"),
                    actionLabel: String(localized: "되돌리기")
                ) { [weak tv, weak self] in
                    guard let tv, let undo = tv.undoManager, undo.canUndo else { return }
                    undo.undo()
                    self?.textViewDidChange(tv)
                }
            }
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
    /// 붙여넣기 가로채기 — 이미지 바이트 / 이미지 URL / 일반 URL(삽입 범위 통지). 없으면 기본 붙여넣기.
    var onPasteImages: (([UIImage]) -> Void)?
    var onPasteImageURL: ((String) -> Void)?
    var onPastedURL: ((String, NSRange) -> Void)?

    override func paste(_ sender: Any?) {
        // 이미지 바이트가 실려 있으면 텍스트 표현보다 이미지를 우선한다 — 기본 붙여넣기는 이미지를
        // 버리고 빈 텍스트/객체 치환문자만 남긴다(V1 캔버스와 같은 규칙).
        if markedTextRange == nil, let onPasteImages, UIPasteboard.general.hasImages {
            let images = UIPasteboard.general.images ?? []
            if !images.isEmpty {
                onPasteImages(images)
                return
            }
        }
        if markedTextRange == nil,
           let raw = UIPasteboard.general.string,
           let url = MarkdownInputTextView.singleURL(in: raw) {
            // 이미지 URL 은 단축하지 않는다 — 호스트가 우리 버킷으로 재호스팅 후 이미지 블록으로 넣는다.
            if MarkdownInputTextView.isImageURL(url), let onPasteImageURL {
                onPasteImageURL(url)
                return
            }
            let location = selectedRange.location
            insertText(url)
            onPastedURL?(url, NSRange(location: location, length: (url as NSString).length))
            return
        }
        super.paste(sender)
    }

    // 클립보드가 이미지뿐이면 기본 UITextView 는 '붙여넣기' 메뉴를 감춘다 — 이미지 훅이 있을 땐 살린다.
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)), onPasteImages != nil, UIPasteboard.general.hasImages {
            return true
        }
        return super.canPerformAction(action, withSender: sender)
    }

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
