//
//  MarkdownTextView.swift
//  kurl
//

import SwiftUI
import UIKit

/// 마크다운 캔버스 — SwiftUI `TextEditor(text:selection:)` 는 한글 같은 조합형(IME)
/// 입력에서 selection 바인딩이 조합을 끊어 글자가 씹히는 고질이 있다. UIKit 직결로
/// 바꾸고, 조합(markedText) 중에는 외부 쓰기·프로그램 삽입을 전면 보류한다.
struct MarkdownTextView: UIViewRepresentable {
    @Binding var text: String
    let controller: MarkdownEditorController
    var onFocusChange: (Bool) -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = UIFontMetrics(forTextStyle: .body)
            .scaledFont(for: .monospacedSystemFont(ofSize: 16, weight: .regular))
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.textColor = UIColor(Palette.body)
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no // 마크다운의 ``` · " 를 IME 가 곡선따옴표로 바꾸지 않게.
        textView.smartDashesType = .no
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 12, right: 0)
        textView.delegate = context.coordinator
        textView.text = text
        controller.textView = textView
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        // 조합 중 덮어쓰기 = 조합 파괴. 외부 변경(리비전 복원·정규화)은 조합이 끝난 뒤에만.
        guard textView.text != text, textView.markedTextRange == nil else { return }
        let caret = textView.selectedRange
        textView.text = text
        let limit = (text as NSString).length
        textView.selectedRange = NSRange(location: min(caret.location, limit), length: 0)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: MarkdownTextView

        init(_ parent: MarkdownTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            // 조합 중간값은 바인딩에 흘리지 않는다 — 자동저장 시그니처가 조합 글자로 출렁이지 않게.
            guard textView.markedTextRange == nil else { return }
            parent.text = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocusChange(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            // 끝나는 시점에 마지막 조합분을 확정 반영.
            parent.text = textView.text
            parent.onFocusChange(false)
        }
    }
}

/// 스니펫 바 → 캔버스 다리. 커서/선택 기준 삽입을 UIKit 의 진짜 커서로 수행한다.
/// 모든 동작은 undo 스택을 보존하고(`replace(_:withText:)`), 조합 중에는 거부한다.
@MainActor
final class MarkdownEditorController {
    weak var textView: UITextView?

    var currentText: String { textView?.text ?? "" }

    func focus() {
        textView?.becomeFirstResponder()
    }

    func dismissKeyboard() {
        textView?.resignFirstResponder()
    }

    /// 커서가 속한 줄 맨 앞에 줄머리(#·>·-)를 붙인다.
    func applyLinePrefix(_ prefix: String) {
        guard let textView, textView.markedTextRange == nil else { return }
        let nsText = textView.text as NSString
        let caret = textView.selectedRange
        let lineStart = nsText.lineRange(for: NSRange(location: caret.location, length: 0)).location
        guard let lineStartPosition = textView.position(
            from: textView.beginningOfDocument, offset: lineStart),
            let range = textView.textRange(from: lineStartPosition, to: lineStartPosition)
        else { return }
        textView.replace(range, withText: prefix)
        textView.selectedRange = NSRange(
            location: caret.location + (prefix as NSString).length, length: 0)
    }

    /// 선택이 있으면 감싸고, 없으면 쌍만 넣고 커서를 그 사이에 둔다.
    func wrapSelection(_ fix: String) {
        guard let textView, textView.markedTextRange == nil,
              let selected = textView.selectedTextRange
        else { return }
        let original = textView.text(in: selected) ?? ""
        let fixLength = (fix as NSString).length
        let start = textView.selectedRange.location
        textView.replace(selected, withText: fix + original + fix)
        if original.isEmpty {
            textView.selectedRange = NSRange(location: start + fixLength, length: 0)
        } else {
            textView.selectedRange = NSRange(
                location: start + fixLength * 2 + (original as NSString).length, length: 0)
        }
    }

    func insertFence() {
        insertBlock("\n```\n\n```\n", caretOffsetFromStart: 5)
    }

    /// 선택을 라벨로 삼아 링크를 넣고, url 자리를 선택해 둔다 — 바로 타이핑하면 덮인다.
    func insertLink() {
        guard let textView, textView.markedTextRange == nil,
              let selected = textView.selectedTextRange
        else { return }
        let label = textView.text(in: selected).flatMap { $0.isEmpty ? nil : $0 }
            ?? String(localized: "제목")
        let start = textView.selectedRange.location
        textView.replace(selected, withText: "[\(label)](url)")
        textView.selectedRange = NSRange(
            location: start + (label as NSString).length + 3, length: 3)
    }

    func insertImageMarkdown(url: String) {
        insertBlock("\n![](\(url))\n", caretOffsetFromStart: nil)
    }

    private func insertBlock(_ snippet: String, caretOffsetFromStart: Int?) {
        guard let textView, textView.markedTextRange == nil,
              let selected = textView.selectedTextRange
        else { return }
        let start = textView.selectedRange.location
        textView.replace(selected, withText: snippet)
        let offset = caretOffsetFromStart ?? (snippet as NSString).length
        textView.selectedRange = NSRange(location: start + offset, length: 0)
    }
}
