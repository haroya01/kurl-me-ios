//
//  MarkdownTextView.swift
//  kurl
//

import SwiftUI
import UIKit

/// 붙여넣기를 가로채 단일 URL 이면 원문을 먼저 커서 자리에 넣고(즉시 반응) 그 범위를 훅에 넘긴다 —
/// 호스트가 비동기로 kurl 단축링크로 교체한다. URL 이 아니면(텍스트 덩어리 등) 기본 붙여넣기.
final class MarkdownInputTextView: UITextView {
    var onPasteURL: ((_ url: String, _ range: NSRange) -> Void)?

    override func paste(_ sender: Any?) {
        if markedTextRange == nil,
            let raw = UIPasteboard.general.string,
            let url = Self.singleURL(in: raw) {
            let location = selectedRange.location
            insertText(url)
            onPasteURL?(url, NSRange(location: location, length: (url as NSString).length))
            return
        }
        super.paste(sender)
    }

    /// 공백·줄바꿈 없는 단일 http(s) URL 만. 본문 문단 통째 붙여넣기는 그대로 둔다.
    static func singleURL(in s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count <= 2048, !t.isEmpty, !t.contains(" "), !t.contains("\n"),
            t.hasPrefix("http://") || t.hasPrefix("https://")
        else { return nil }
        return t
    }
}

/// 마크다운 캔버스 — SwiftUI `TextEditor(text:selection:)` 는 한글 같은 조합형(IME)
/// 입력에서 selection 바인딩이 조합을 끊어 글자가 씹히는 고질이 있다. UIKit 직결로
/// 바꾸고, 조합(markedText) 중에는 외부 쓰기·프로그램 삽입을 전면 보류한다.
struct MarkdownTextView: UIViewRepresentable {
    @Binding var text: String
    let controller: MarkdownEditorController
    var onFocusChange: (Bool) -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = MarkdownInputTextView()
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
        textView.typingAttributes = MarkdownSyntaxHighlighter.baseAttributes()
        controller.textView = textView
        // 초기 본문(리비전·기존 글)도 곧장 렌더된 모습으로.
        MarkdownSyntaxHighlighter.apply(to: textView)

        // 붙여넣은 URL → kurl 단축링크. 원문을 먼저 넣어 즉시 반응하고, 단축되면 그 자리만 교체한다
        // (그 사이 사용자가 더 입력해 범위가 바뀌었으면 건너뛴다 — 손실 없이 원문 유지).
        let coordinator = context.coordinator
        textView.onPasteURL = { [weak textView] original, range in
            guard let textView else { return }
            Task { @MainActor in
                guard let short = try? await WriteAPI.shorten(original) else { return }
                let ns = textView.text as NSString
                guard range.location + range.length <= ns.length,
                    ns.substring(with: range) == original,
                    let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
                    let end = textView.position(from: start, offset: range.length),
                    let textRange = textView.textRange(from: start, to: end)
                else { return }
                textView.replace(textRange, withText: short)
                textView.selectedRange = NSRange(
                    location: range.location + (short as NSString).length, length: 0)
                coordinator.textViewDidChange(textView)
            }
        }
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        // 외부(리비전 복원·기존 글 로드)에서 온 변경만 반영한다. 조합 중 덮어쓰기 = 조합 파괴.
        // text == 코디네이터가 마지막으로 내보낸 값(lastEditorText)이면 무시 — 한글 IME 조합이
        // 커밋되는 순간 바인딩이 textViewDidChange 직전까지 잠깐 옛 값으로 뒤처지는데, 그 창에
        // (매 입력마다 도는) @State 재렌더가 끼어들면 옛(짧은) 값으로 textView 를 덮어써 본문이
        // 통째로 사라졌다. 에디터가 만든 값의 메아리는 건너뛰고, 진짜 외부 변경만 적용한다.
        guard textView.text != text, textView.markedTextRange == nil,
            text != context.coordinator.lastEditorText
        else { return }
        let caret = textView.selectedRange
        textView.text = text
        context.coordinator.lastEditorText = text
        let limit = (text as NSString).length
        textView.selectedRange = NSRange(location: min(caret.location, limit), length: 0)
        MarkdownSyntaxHighlighter.apply(to: textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: MarkdownTextView
        /// 에디터가 마지막으로 바인딩에 내보낸 본문 — updateUIView 가 이 값(자기 메아리/조합 커밋
        /// 직전 뒤처진 값)으로 textView 를 되덮는 걸 막는다(데이터 손실 레이스 가드).
        var lastEditorText: String

        init(_ parent: MarkdownTextView) {
            self.parent = parent
            self.lastEditorText = parent.text
        }

        func textViewDidChange(_ textView: UITextView) {
            // 조합 중간값은 바인딩에 흘리지 않는다 — 자동저장 시그니처가 조합 글자로 출렁이지 않게.
            guard textView.markedTextRange == nil else { return }
            parent.text = textView.text
            lastEditorText = textView.text
            // 치는 즉시 렌더 — 조합이 끝난 글자부터 제목·굵게 등으로 입혀진다.
            MarkdownSyntaxHighlighter.apply(to: textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocusChange(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            // 끝나는 시점에 마지막 조합분을 확정 반영.
            parent.text = textView.text
            lastEditorText = textView.text
            parent.onFocusChange(false)
        }
    }
}

/// 스니펫 바 → 캔버스 다리. 커서/선택 기준 삽입을 UIKit 의 진짜 커서로 수행한다.
/// 모든 동작은 undo 스택을 보존하고(`replace(_:withText:)`), 조합 중에는 거부한다.
@MainActor
final class MarkdownEditorController {
    weak var textView: UITextView?
    /// 링크 다이얼로그가 뜨는 동안 보관하는 삽입 위치(시트가 뜨며 selection 이 흐려져도 제자리에 넣는다).
    private var pendingLinkRange: NSRange?

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
        MarkdownSyntaxHighlighter.apply(to: textView)
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
        MarkdownSyntaxHighlighter.apply(to: textView)
    }

    func insertFence() {
        insertBlock("\n```\n\n```\n", caretOffsetFromStart: 5)
    }

    /// 코드블록 토글 — 블록 밖이면 빈 펜스를 넣고(커서는 안), 블록 안이면 닫는 ``` 다음 줄로 빠져나온다.
    /// 모바일에서 커서가 코드블록에 갇혀 못 빠져나오던 문제를 한 번 탭으로 푼다.
    func toggleCodeBlock() {
        guard let textView, textView.markedTextRange == nil else { return }
        let ns = textView.text as NSString
        let caret = min(textView.selectedRange.location, ns.length)
        var fences: [NSRange] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines]) {
            sub, _, enclosing, _ in
            if (sub ?? "").hasPrefix("```") { fences.append(enclosing) }
        }
        var i = 0
        while i + 1 < fences.count {
            let blockStart = fences[i].location
            let blockEnd = fences[i + 1].location + fences[i + 1].length
            if caret >= blockStart, caret < blockEnd {
                if blockEnd >= ns.length {
                    // 닫는 펜스가 마지막 줄(뒤에 줄바꿈 없음) → 한 줄 만들어 그리로.
                    textView.selectedRange = NSRange(location: ns.length, length: 0)
                    textView.insertText("\n")
                } else {
                    textView.selectedRange = NSRange(location: blockEnd, length: 0)
                }
                MarkdownSyntaxHighlighter.apply(to: textView)
                return
            }
            i += 2
        }
        insertFence()
    }

    /// 링크 삽입 1단계 — 지금 선택을 라벨 후보로 들고, 그 자리를 보관한 뒤 다이얼로그에 넘긴다.
    /// `(url)` 같은 리터럴을 본문에 떨구지 않는다(주소는 다이얼로그에서 받는다).
    func beginLinkInsertion() -> String {
        guard let textView, textView.markedTextRange == nil else {
            pendingLinkRange = nil
            return ""
        }
        let range = textView.selectedRange
        pendingLinkRange = range
        return (textView.text as NSString).substring(with: range)
    }

    /// 링크 삽입 2단계 — 다이얼로그가 받은 주소로 보관해둔 자리에 `[라벨](주소)` 를 넣는다.
    /// 라벨이 비면 주소를 라벨로(보이는 글자=주소). 주소가 비면 아무것도 하지 않는다.
    func commitLink(label: String, url: String) {
        defer { pendingLinkRange = nil }
        guard let textView, let range = pendingLinkRange else { return }
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let shownLabel = label.isEmpty ? trimmed : label
        let snippet = "[\(shownLabel)](\(trimmed))"
        guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
              let end = textView.position(from: start, offset: range.length),
              let textRange = textView.textRange(from: start, to: end)
        else { return }
        textView.replace(textRange, withText: snippet)
        textView.selectedRange = NSRange(location: range.location + (snippet as NSString).length, length: 0)
        MarkdownSyntaxHighlighter.apply(to: textView)
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
        MarkdownSyntaxHighlighter.apply(to: textView)
    }
}
