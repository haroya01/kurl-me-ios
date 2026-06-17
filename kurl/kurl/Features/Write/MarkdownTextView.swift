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

    /// TextKit 1 스택을 직접 구성 — 커스텀 NSLayoutManager 가 `![](url)` 줄 아래 예약 공간에
    /// 실제 이미지 썸네일을 그린다(본문 텍스트는 마크다운 원문 그대로 유지 → 자동저장·동기화 불변).
    init() {
        let storage = NSTextStorage()
        let layout = MarkdownImageLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        // 이미지가 로드돼 실제 비율을 알게 되면 하이라이트를 다시 돌려 줄 아래 예약 높이를 비율에 맞춘다
        // (로드 전엔 placeholder 높이 → 로드 후 세로/가로 비율대로 재배치).
        layout.onImageLoad = { [weak self] in
            guard let self else { return }
            MarkdownSyntaxHighlighter.apply(to: self)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

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
    /// 캐럿 위치의 성격이 바뀔 때 — 컴포즈가 표/이미지 편집 컨텍스트 바를 켜고 끈다.
    var onContextChange: (EditorCaretContext) -> Void = { _ in }

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
            parent.onContextChange(parent.controller.caretContext())
        }

        // 커서가 움직일 때마다 캐럿 위치의 성격(표/이미지)을 컴포즈에 알린다(컨텍스트 바 토글).
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard textView.markedTextRange == nil else { return }
            parent.onContextChange(parent.controller.caretContext())
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocusChange(true)
            parent.onContextChange(parent.controller.caretContext())
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            // 끝나는 시점에 마지막 조합분을 확정 반영.
            parent.text = textView.text
            lastEditorText = textView.text
            parent.onFocusChange(false)
        }
    }
}

/// 캐럿이 놓인 곳의 성격 — 컴포즈가 그에 맞는 컨텍스트 편집 바(표/이미지)를 띄운다.
enum EditorCaretContext { case none, table, image }

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

    /// 선택이 있으면 감싼다. 선택이 없으면 커서가 닿은 단어를 감싸고, 닿은 단어도 없으면
    /// 자리표시자("텍스트")를 넣고 선택 상태로 둔다 — 빈 마커(예: ****)만 본문에 남아 렌더가
    /// 안 되고 평문 위에 기호가 떠 "고장난 것처럼" 보이던 마찰을 없앤다.
    func wrapSelection(_ fix: String) {
        guard let textView, textView.markedTextRange == nil else { return }
        var range = textView.selectedRange
        if range.length == 0, let word = currentWordRange(in: textView, around: range.location) {
            range = word
        }
        let ns = textView.text as NSString
        var inner = range.length > 0 ? ns.substring(with: range) : ""
        let placeholder = inner.isEmpty
        if placeholder { inner = String(localized: "텍스트") }

        guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
              let end = textView.position(from: start, offset: range.length),
              let textRange = textView.textRange(from: start, to: end)
        else { return }
        let fixLen = (fix as NSString).length
        let innerLen = (inner as NSString).length
        textView.replace(textRange, withText: fix + inner + fix)

        // 자리표시자는 선택해 둬서 바로 쳐서 덮어쓰게, 단어를 감쌌으면 닫는 마커 뒤로 커서를 둔다.
        if placeholder,
           let s = textView.position(from: textView.beginningOfDocument, offset: range.location + fixLen),
           let e = textView.position(from: s, offset: innerLen),
           let sel = textView.textRange(from: s, to: e) {
            textView.selectedTextRange = sel
        } else {
            textView.selectedRange = NSRange(location: range.location + fixLen * 2 + innerLen, length: 0)
        }
        MarkdownSyntaxHighlighter.apply(to: textView)
    }

    /// 커서가 닿은(또는 직전) 단어 범위 — 공백·줄바꿈 사이의 연속 문자. 없으면 nil.
    private func currentWordRange(in textView: UITextView, around loc: Int) -> NSRange? {
        let ns = textView.text as NSString
        guard ns.length > 0 else { return nil }
        let seps = CharacterSet.whitespacesAndNewlines
        func isSep(_ i: Int) -> Bool {
            ns.substring(with: NSRange(location: i, length: 1)).rangeOfCharacter(from: seps) != nil
        }
        var lo = min(loc, ns.length)
        var hi = lo
        while lo > 0, !isSep(lo - 1) { lo -= 1 }
        while hi < ns.length, !isSep(hi) { hi += 1 }
        return hi > lo ? NSRange(location: lo, length: hi - lo) : nil
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
        insertImage(url: url, width: nil, caption: nil)
    }

    /// 폭(«wide»/«half» 마커, alt 위치)·캡션(표준 image title)을 담아 이미지 삽입. 백엔드가
    /// width·caption 으로 파싱, 리더가 그대로 렌더.
    func insertImage(url: String, width: String?, caption: String?) {
        let marker = width.map { "«\($0)» " } ?? ""
        let cap =
            (caption?.isEmpty == false)
            ? " \"\(caption!.replacingOccurrences(of: "\"", with: "'"))\"" : ""
        insertBlock("\n![\(marker)](\(url)\(cap))\n", caretOffsetFromStart: nil)
    }

    /// GFM 표 골격 — 백엔드 마크다운→블록이 TABLE 로 변환, 리더(TableBlockView)가 렌더. 첫 셀에 커서.
    func insertTable() {
        insertBlock("\n| 제목 | 제목 |\n| --- | --- |\n| 내용 | 내용 |\n", caretOffsetFromStart: 3)
    }

    /// 단독 줄 동영상 URL — 백엔드가 EMBED 블록으로(YouTube/Vimeo), 리더(EmbedBlockView)가 플레이어로.
    func insertVideoEmbed(url: String) {
        insertBlock("\n\(url)\n", caretOffsetFromStart: nil)
    }

    /// 현재 줄 맨 앞에 2칸 들여쓰기 — 리스트 항목을 한 단계 안으로(중첩). 리더가 깊이대로 렌더.
    func indentLine() {
        guard let textView, textView.markedTextRange == nil else { return }
        let ns = textView.text as NSString
        let caret = textView.selectedRange
        let lineStart = ns.lineRange(for: NSRange(location: min(caret.location, ns.length), length: 0)).location
        guard let pos = textView.position(from: textView.beginningOfDocument, offset: lineStart),
            let range = textView.textRange(from: pos, to: pos)
        else { return }
        textView.replace(range, withText: "  ")
        textView.selectedRange = NSRange(location: caret.location + 2, length: 0)
        MarkdownSyntaxHighlighter.apply(to: textView)
    }

    /// 현재 줄 앞 들여쓰기 한 단계(최대 2칸) 제거.
    func outdentLine() {
        guard let textView, textView.markedTextRange == nil else { return }
        let ns = textView.text as NSString
        let caret = textView.selectedRange
        let lineStart = ns.lineRange(for: NSRange(location: min(caret.location, ns.length), length: 0)).location
        var remove = 0
        while remove < 2, lineStart + remove < ns.length,
            ns.substring(with: NSRange(location: lineStart + remove, length: 1)) == " " {
            remove += 1
        }
        guard remove > 0,
            let start = textView.position(from: textView.beginningOfDocument, offset: lineStart),
            let end = textView.position(from: start, offset: remove),
            let range = textView.textRange(from: start, to: end)
        else { return }
        textView.replace(range, withText: "")
        textView.selectedRange = NSRange(location: max(lineStart, caret.location - remove), length: 0)
        MarkdownSyntaxHighlighter.apply(to: textView)
    }

    // MARK: 표 편집 — 마크다운을 몰라도 행·열을 늘리고 줄인다.
    // 캐럿이 표 안에 들어오면 컴포즈가 컨텍스트 바를 띄우고, 그 버튼이 이 메서드들을 부른다.
    // 표 전체를 한 번에 다시 그려(셀 정렬 정규화) 손으로 `|` 를 칠 일이 없게 한다.

    /// 캐럿이 GFM 표 안에 있는가 — 컨텍스트 표 편집 바의 노출 조건.
    func isCaretInTable() -> Bool {
        guard let textView, textView.markedTextRange == nil else { return false }
        return tableBlock(in: textView) != nil
    }

    /// 캐럿 위치의 성격(표/이미지/그 외) — 컴포즈가 띄울 컨텍스트 바를 고른다.
    func caretContext() -> EditorCaretContext {
        guard let textView, textView.markedTextRange == nil else { return .none }
        if tableBlock(in: textView) != nil { return .table }
        if imageOnCaretLine(in: textView) != nil { return .image }
        return .none
    }

    private struct TableBlock {
        var charRange: NSRange  // 표 전체를 덮는 치환 범위(마지막 줄바꿈 제외)
        var startLocation: Int  // = charRange.location
        var header: [String]
        var body: [[String]]
        var caretLine: Int  // 블록 내 줄 인덱스(0=헤더, 1=구분선, 2+=본문)
        var caretColumn: Int  // 캐럿이 놓인 셀 인덱스
        var columnCount: Int { max(1, header.count) }
    }

    /// 표 한 줄을 셀 배열로 — 선두·말미 파이프가 만드는 빈 칸은 떨군다.
    private func tableCells(_ line: String) -> [String] {
        var parts = line.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if parts.first == "" { parts.removeFirst() }
        if parts.last == "" { parts.removeLast() }
        return parts
    }

    /// `| --- | :--: |` 같은 정렬 구분선인가.
    private func isSeparatorRow(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-") else { return false }
        return t.allSatisfy { "|:- ".contains($0) }
    }

    /// 캐럿이 속한 표 블록을 찾아 헤더·본문·캐럿 위치를 파싱한다. 표가 아니면 nil.
    private func tableBlock(in textView: UITextView) -> TableBlock? {
        let ns = textView.text as NSString
        guard ns.length > 0 else { return nil }
        let caret = min(textView.selectedRange.location, ns.length)
        var subs: [String] = []
        var ranges: [NSRange] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) {
            sub, range, _, _ in
            subs.append(sub ?? "")
            ranges.append(range)
        }
        guard !subs.isEmpty else { return nil }
        let caretIdx = ranges.firstIndex { caret <= $0.location + $0.length } ?? (ranges.count - 1)
        func isTableLine(_ s: String) -> Bool {
            s.contains("|") && !s.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard isTableLine(subs[caretIdx]) else { return nil }
        var start = caretIdx
        var end = caretIdx
        while start > 0, isTableLine(subs[start - 1]) { start -= 1 }
        while end < subs.count - 1, isTableLine(subs[end + 1]) { end += 1 }
        // GFM 표 = 최소 2줄 + 둘째 줄이 정렬 구분선.
        guard end - start >= 1, isSeparatorRow(subs[start + 1]) else { return nil }
        let loc = ranges[start].location
        let endLoc = ranges[end].location + ranges[end].length
        let header = tableCells(subs[start])
        let body = (start + 2 <= end) ? (start + 2...end).map { tableCells(subs[$0]) } : []
        // 캐럿 셀 인덱스 = 줄 안 캐럿 앞 '|' 개수 - 1(선두 파이프 보정).
        let lineStart = ranges[caretIdx].location
        let inLine = max(0, caret - lineStart)
        let line = subs[caretIdx] as NSString
        let prefix = line.substring(to: min(inLine, line.length))
        let pipes = prefix.reduce(0) { $1 == "|" ? $0 + 1 : $0 }
        return TableBlock(
            charRange: NSRange(location: loc, length: endLoc - loc),
            startLocation: loc,
            header: header,
            body: body,
            caretLine: caretIdx - start,
            caretColumn: max(0, pipes - 1))
    }

    /// 헤더·본문을 정규화된 GFM 표 줄 배열로 — 모든 셀을 ` | ` 로 가지런히, 빈 셀은 공칸.
    private func renderTable(header: [String], body: [[String]]) -> [String] {
        let n = max(1, header.count)
        func row(_ cells: [String]) -> String {
            var c = cells
            while c.count < n { c.append("") }
            return "| " + c.prefix(n).joined(separator: " | ") + " |"
        }
        var lines = [row(header)]
        lines.append("| " + Array(repeating: "---", count: n).joined(separator: " | ") + " |")
        lines += body.map(row)
        return lines
    }

    /// 렌더된 줄 배열에서 (줄·셀) 위치의 셀 본문 시작 오프셋 — 캐럿을 그 셀 머리에 놓기 위함.
    private func cellOffset(lines: [String], line: Int, column: Int) -> Int {
        var off = 0
        for i in 0..<min(max(0, line), lines.count) { off += (lines[i] as NSString).length + 1 }
        guard line >= 0, line < lines.count else { return off }
        let ns = lines[line] as NSString
        var found = 0
        var search = NSRange(location: 0, length: ns.length)
        var cellStart = ns.length
        while true {
            let r = ns.range(of: "| ", options: [], range: search)
            if r.location == NSNotFound { break }
            if found == column {
                cellStart = r.location + 2
                break
            }
            found += 1
            let next = r.location + r.length
            search = NSRange(location: next, length: ns.length - next)
        }
        return off + min(cellStart, ns.length)
    }

    private func applyTable(
        _ block: TableBlock, lines: [String], caretLine: Int, caretColumn: Int
    ) {
        guard let textView else { return }
        let serialized = lines.joined(separator: "\n")
        guard
            let s = textView.position(
                from: textView.beginningOfDocument, offset: block.charRange.location),
            let e = textView.position(from: s, offset: block.charRange.length),
            let range = textView.textRange(from: s, to: e)
        else { return }
        textView.replace(range, withText: serialized)
        let caret = block.startLocation + cellOffset(lines: lines, line: caretLine, column: caretColumn)
        let limit = (textView.text as NSString).length
        textView.selectedRange = NSRange(location: min(caret, limit), length: 0)
        MarkdownSyntaxHighlighter.apply(to: textView)
    }

    /// 캐럿이 놓인 행 바로 아래에 빈 행을 끼우고, 새 행 첫 칸으로 커서를 옮긴다.
    func addTableRow() {
        guard let textView, textView.markedTextRange == nil,
            let block = tableBlock(in: textView)
        else { return }
        var body = block.body
        let idx = min(block.caretLine < 2 ? 0 : block.caretLine - 1, body.count)
        body.insert(Array(repeating: "", count: block.columnCount), at: idx)
        applyTable(
            block, lines: renderTable(header: block.header, body: body),
            caretLine: 2 + idx, caretColumn: 0)
    }

    /// 맨 끝에 빈 열을 더하고, 그 새 열로 커서를 옮긴다.
    func addTableColumn() {
        guard let textView, textView.markedTextRange == nil,
            let block = tableBlock(in: textView)
        else { return }
        let header = block.header + [""]
        let body = block.body.map { $0 + [""] }
        applyTable(
            block, lines: renderTable(header: header, body: body),
            caretLine: block.caretLine == 1 ? 0 : block.caretLine, caretColumn: header.count - 1)
    }

    /// 캐럿이 놓인 본문 행을 지운다(헤더·구분선은 보호 — 그 자리에선 무동작).
    func deleteTableRow() {
        guard let textView, textView.markedTextRange == nil,
            let block = tableBlock(in: textView), block.caretLine >= 2, !block.body.isEmpty
        else { return }
        var body = block.body
        let removeAt = block.caretLine - 2
        guard removeAt < body.count else { return }
        body.remove(at: removeAt)
        let caretLine = body.isEmpty ? 1 : 2 + min(removeAt, body.count - 1)
        applyTable(
            block, lines: renderTable(header: block.header, body: body),
            caretLine: caretLine, caretColumn: 0)
    }

    /// 캐럿이 놓인 열을 모든 행에서 지운다(마지막 한 열은 보호).
    func deleteTableColumn() {
        guard let textView, textView.markedTextRange == nil,
            let block = tableBlock(in: textView), block.columnCount >= 2
        else { return }
        let col = min(block.caretColumn, block.columnCount - 1)
        var header = block.header
        header.remove(at: col)
        let body = block.body.map { row -> [String] in
            var r = row
            if col < r.count { r.remove(at: col) }
            return r
        }
        applyTable(
            block, lines: renderTable(header: header, body: body),
            caretLine: block.caretLine == 1 ? 0 : block.caretLine,
            caretColumn: min(col, max(0, header.count - 1)))
    }

    // MARK: 이미지 편집 — 넣은 뒤에도 마크다운을 건드리지 않고 폭·캡션을 바꾸고 지운다.
    // 캐럿이 이미지 줄에 있으면 컴포즈가 이미지 편집 바(기본/와이드/하프·캡션·삭제)를 띄운다.

    private struct ImageOnLine {
        var lineRange: NSRange  // 줄 전체(줄바꿈 포함) — 삭제용
        var contentRange: NSRange  // 줄바꿈 제외 — 치환용
        var width: String?  // nil·wide·full·half
        var alt: String
        var url: String
        var caption: String
    }

    /// 표준 image + 선택적 폭 마커(«…»)·캡션(title)을 한 줄에서 통째로 파싱.
    private static let imageLineRegex = try! NSRegularExpression(
        pattern: "^\\s*!\\[(?:«(wide|full|half)»\\s*)?([^\\]\\n]*)\\]\\(([^)\\s]+)(?:\\s+\"([^\"]*)\")?\\)\\s*$")

    private func imageOnCaretLine(in textView: UITextView) -> ImageOnLine? {
        let ns = textView.text as NSString
        guard ns.length > 0 else { return nil }
        let caret = min(textView.selectedRange.location, ns.length)
        let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
        // 줄바꿈을 떼어 치환 범위(content)를 만든다.
        var contentLen = lineRange.length
        while contentLen > 0 {
            let c = ns.substring(with: NSRange(location: lineRange.location + contentLen - 1, length: 1))
            if c == "\n" || c == "\r" { contentLen -= 1 } else { break }
        }
        let contentRange = NSRange(location: lineRange.location, length: contentLen)
        let content = ns.substring(with: contentRange) as NSString
        guard
            let m = Self.imageLineRegex.firstMatch(
                in: content as String, range: NSRange(location: 0, length: content.length))
        else { return nil }
        func group(_ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : content.substring(with: r)
        }
        guard let url = group(3) else { return nil }
        return ImageOnLine(
            lineRange: lineRange, contentRange: contentRange,
            width: group(1), alt: group(2) ?? "", url: url, caption: group(4) ?? "")
    }

    private func buildImageMarkdown(width: String?, alt: String, url: String, caption: String) -> String {
        let marker = width.map { "«\($0)» " } ?? ""
        let cap =
            caption.isEmpty ? "" : " \"\(caption.replacingOccurrences(of: "\"", with: "'"))\""
        return "![\(marker)\(alt)](\(url)\(cap))"
    }

    func currentImageWidth() -> String? {
        guard let textView else { return nil }
        return imageOnCaretLine(in: textView)?.width
    }

    func currentImageCaption() -> String {
        guard let textView else { return "" }
        return imageOnCaretLine(in: textView)?.caption ?? ""
    }

    /// 캐럿이 놓인 이미지의 폭을 바꾼다(nil=기본). 폭만 바꾸고 캡션·대체텍스트는 보존.
    func setImageWidth(_ width: String?) {
        guard let textView, textView.markedTextRange == nil,
            let img = imageOnCaretLine(in: textView)
        else { return }
        let md = buildImageMarkdown(width: width, alt: img.alt, url: img.url, caption: img.caption)
        replaceImage(in: textView, content: img.contentRange, with: md)
    }

    /// 캐럿이 놓인 이미지의 캡션을 바꾼다(빈 문자열=캡션 제거).
    func setImageCaption(_ caption: String) {
        guard let textView, textView.markedTextRange == nil,
            let img = imageOnCaretLine(in: textView)
        else { return }
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let md = buildImageMarkdown(width: img.width, alt: img.alt, url: img.url, caption: trimmed)
        replaceImage(in: textView, content: img.contentRange, with: md)
    }

    /// 캐럿이 놓인 이미지 줄을 통째로 지운다.
    func removeImage() {
        guard let textView, textView.markedTextRange == nil,
            let img = imageOnCaretLine(in: textView)
        else { return }
        guard let s = textView.position(from: textView.beginningOfDocument, offset: img.lineRange.location),
            let e = textView.position(from: s, offset: img.lineRange.length),
            let range = textView.textRange(from: s, to: e)
        else { return }
        textView.replace(range, withText: "")
        let limit = (textView.text as NSString).length
        textView.selectedRange = NSRange(location: min(img.lineRange.location, limit), length: 0)
        MarkdownSyntaxHighlighter.apply(to: textView)
    }

    private func replaceImage(in textView: UITextView, content: NSRange, with md: String) {
        guard let s = textView.position(from: textView.beginningOfDocument, offset: content.location),
            let e = textView.position(from: s, offset: content.length),
            let range = textView.textRange(from: s, to: e)
        else { return }
        textView.replace(range, withText: md)
        // 마크다운은 숨겨져 보이지 않으므로 커서는 줄 머리에 둔다(편집 바가 계속 이 이미지를 가리키게).
        textView.selectedRange = NSRange(location: content.location, length: 0)
        MarkdownSyntaxHighlighter.apply(to: textView)
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

// MARK: 인라인 이미지 썸네일 — `![](url)` 아래 실제 이미지를 그린다(원문 텍스트는 그대로).

extension NSAttributedString.Key {
    /// 이미지 마크다운 범위에 붙는 표식 — 값은 이미지 URL 문자열. 레이아웃 매니저가 이 줄 아래에 썸네일을 그린다.
    static let kurlImageURL = NSAttributedString.Key("kurlImageURL")
}

enum MarkdownImage {
    static let topPad: CGFloat = 6      // 마크다운 텍스트 줄과 이미지 사이
    static let bottomGap: CGFloat = 12  // 이미지와 다음 문단 사이
    static let maxHeight: CGFloat = 420 // 아주 긴 세로 이미지가 화면을 다 먹지 않게 상한
    static let placeholderHeight: CGFloat = 200 // 로드 전(비율 모름) 임시 높이

    /// 로드된 이미지의 실제 비율로 표시 높이 — 세로·가로 모두 잘림 없이 전체가 보이게(상한만 적용).
    static func imageHeight(for url: URL, width: CGFloat) -> CGFloat {
        guard width > 1, let size = ImageThumbCache.shared.cachedSize(for: url),
            size.width > 1, size.height > 1
        else { return placeholderHeight }
        return min(maxHeight, max(80, width * size.height / size.width))
    }

    /// paragraphSpacing 으로 예약할 총 높이(위·아래 여백 포함).
    static func reservedHeight(for url: URL, width: CGFloat) -> CGFloat {
        topPad + imageHeight(for: url, width: width) + bottomGap
    }
}

/// URL → UIImage 메모리 캐시 + 비동기 로더. 로드되면 onLoad 로 해당 줄만 다시 그리게 한다.
final class ImageThumbCache {
    static let shared = ImageThumbCache()
    private let cache = NSCache<NSURL, UIImage>()
    private var loading = Set<NSURL>()

    /// 캐시에 있으면 즉시 반환, 없으면 비동기로 받아 캐시 후 onLoad 호출(메인 스레드).
    func image(for url: URL, onLoad: @escaping () -> Void) -> UIImage? {
        let key = url as NSURL
        if let img = cache.object(forKey: key) { return img }
        guard !loading.contains(key) else { return nil }
        loading.insert(key)
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading.remove(key)
                if let data, let img = UIImage(data: data) {
                    self.cache.setObject(img, forKey: key)
                    onLoad()
                }
            }
        }.resume()
        return nil
    }

    /// 로드돼 캐시된 이미지의 원본 크기(비율 계산용). 없으면 nil.
    func cachedSize(for url: URL) -> CGSize? {
        cache.object(forKey: url as NSURL)?.size
    }
}

/// `.kurlImageURL` 표식이 붙은 줄 아래(예약된 paragraphSpacing 공간)에 이미지를 그린다(aspect-fit).
final class MarkdownImageLayoutManager: NSLayoutManager {
    /// 이미지가 로드돼 실제 비율을 알게 되면 호출 — 호스트가 하이라이트를 다시 돌려 높이를 비율에 맞춘다.
    var onImageLoad: (() -> Void)?

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let pad = container.lineFragmentPadding
        let availWidth = max(0, container.size.width - pad * 2)
        storage.enumerateAttribute(.kurlImageURL, in: charRange, options: []) { value, range, _ in
            guard let str = value as? String, let url = URL(string: str) else { return }
            let gr = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let used = boundingRect(forGlyphRange: gr, in: container)
            let h = MarkdownImage.imageHeight(for: url, width: availWidth)
            let box = CGRect(
                x: origin.x + pad,
                y: origin.y + used.maxY + MarkdownImage.topPad,
                width: availWidth,
                height: h)
            guard box.width > 1, let ctx = UIGraphicsGetCurrentContext() else { return }
            let img = ImageThumbCache.shared.image(for: url) { [weak self] in
                self?.invalidateDisplay(forCharacterRange: range)
                self?.onImageLoad?() // 실제 비율 반영해 높이 재계산
            }
            ctx.saveGState()
            UIBezierPath(roundedRect: box, cornerRadius: 12).addClip()
            if let img {
                // aspect-fit — 세로/가로 모두 잘리지 않고 전체가 보이게.
                let scale = min(box.width / img.size.width, box.height / img.size.height)
                let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
                img.draw(
                    in: CGRect(
                        x: box.midX - size.width / 2, y: box.midY - size.height / 2,
                        width: size.width, height: size.height))
            } else {
                UIColor.secondarySystemFill.setFill()
                UIBezierPath(roundedRect: box, cornerRadius: 12).fill()
            }
            ctx.restoreGState()
        }
    }
}
