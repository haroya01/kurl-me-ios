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
    /// 붙여넣은 단일 URL 이 이미지 파일을 가리킬 때 — 단축 대신 호스트가 재호스팅 후 `![](url)` 로 넣는다.
    var onPasteImageURL: ((_ url: String) -> Void)?
    /// 클립보드에 이미지 바이트가 실려 있을 때(스크린샷·노션 이미지 복사 등) — 호스트가 업로드 후 `![](url)` 로 넣는다.
    var onPasteImages: ((_ images: [UIImage]) -> Void)?

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
        // 그려진 표(그리드)는 실제 글자가 없는 예약 공간이라 기본 탭이 엉뚱한 곳(헤더 끝·표 뒤 빈 줄)에
        // 커서를 떨군다. 이 탭 인식기가 그리드 안 탭을 잡아 해당 행으로 커서를 넣어 편집 모드로 들어가게 한다.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleGridTap(_:)))
        tap.delegate = self
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    /// 그려진 표 그리드 안을 탭하면 해당 행으로 커서를 넣어(원시 마크다운이 드러나며 편집) 준다.
    @objc private func handleGridTap(_ g: UITapGestureRecognizer) {
        let storage = textStorage
        guard storage.length > 0 else { return }
        let loc = g.location(in: self)
        let p = CGPoint(x: loc.x - textContainerInset.left, y: loc.y - textContainerInset.top)
        let pad = textContainer.lineFragmentPadding
        let availWidth = max(0, textContainer.size.width - pad * 2)
        let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedSystemFont(ofSize: 16, weight: .regular))
        let rowH = MarkdownTable.rowHeight(font)
        var targetCaret: Int?
        storage.enumerateAttribute(.kurlTableMarkdown, in: NSRange(location: 0, length: storage.length), options: []) { value, range, stop in
            guard let md = value as? String, let parsed = MarkdownTable.parse(md) else { return }
            let gr = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let used = layoutManager.boundingRect(forGlyphRange: gr, in: textContainer)
            let gridTop = used.maxY + MarkdownTable.topPad
            let gridRect = CGRect(x: pad, y: gridTop, width: availWidth, height: CGFloat(parsed.rowCount) * rowH)
            guard gridRect.contains(p) else { return }
            // 탭한 y → 시각 행. 0=헤더(원문 0줄), 1+=본문(원문에선 구분선 1줄을 건너뛰므로 +1).
            let row = min(parsed.rowCount - 1, max(0, Int((p.y - gridTop) / rowH)))
            let mdLine = row == 0 ? 0 : row + 1
            let regionStr = (self.text as NSString).substring(with: NSRange(location: range.location, length: (md as NSString).length))
            let mdLines = regionStr.components(separatedBy: "\n")
            var off = 0
            for k in 0..<min(mdLine, mdLines.count) { off += (mdLines[k] as NSString).length + 1 }
            targetCaret = range.location + off
            stop.pointee = true
        }
        // 그려진 이미지 썸네일을 탭하면 그 이미지 줄로 커서를 넣는다 — 폭·캡션·삭제 편집 바가 뜨게(표와 대칭).
        // 마크다운(`![](…)`)이 0폭으로 숨겨져 있어 사진을 탭해도 커서가 안 걸리던 사각을 없앤다.
        if targetCaret == nil {
            storage.enumerateAttribute(.kurlImageURL, in: NSRange(location: 0, length: storage.length), options: []) { value, range, stop in
                guard let str = value as? String, let url = URL(string: str) else { return }
                let gr = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let used = layoutManager.boundingRect(forGlyphRange: gr, in: textContainer)
                let imgTop = used.maxY + MarkdownImage.topPad
                let imgRect = CGRect(x: pad, y: imgTop, width: availWidth, height: MarkdownImage.imageHeight(for: url, width: availWidth))
                guard imgRect.contains(p) else { return }
                targetCaret = range.location
                stop.pointee = true
            }
        }
        guard let caret = targetCaret else { return }
        // 기본 탭 처리(엉뚱한 커서 배치) 다음에 덮어쓰도록 다음 루프에서 적용 → 해당 행이 활성화돼 드러난다.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.isFirstResponder { self.becomeFirstResponder() }
            let limit = (self.text as NSString).length
            self.selectedRange = NSRange(location: min(caret, limit), length: 0)
        }
    }

    override func paste(_ sender: Any?) {
        // 이미지 바이트가 실려 있으면 텍스트 표현보다 이미지를 우선한다 — 기본 붙여넣기는 이미지를
        // 버리고 빈 텍스트/객체 치환문자만 남긴다.
        if markedTextRange == nil, let onPasteImages, UIPasteboard.general.hasImages {
            let images = UIPasteboard.general.images ?? []
            if !images.isEmpty {
                onPasteImages(images)
                return
            }
        }
        if markedTextRange == nil,
            let raw = UIPasteboard.general.string,
            let url = Self.singleURL(in: raw) {
            // 이미지 URL 은 단축하지 않는다 — 호스트가 우리 버킷으로 재호스팅 후 이미지로 넣는다(링크카드 X).
            if Self.isImageURL(url), let onPasteImageURL {
                onPasteImageURL(url)
                return
            }
            let location = selectedRange.location
            insertText(url)
            onPasteURL?(url, NSRange(location: location, length: (url as NSString).length))
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

    /// 공백·줄바꿈 없는 단일 http(s) URL 만. 본문 문단 통째 붙여넣기는 그대로 둔다.
    static func singleURL(in s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count <= 2048, !t.isEmpty, !t.contains(" "), !t.contains("\n"),
            t.hasPrefix("http://") || t.hasPrefix("https://")
        else { return nil }
        return t
    }

    /// 단일 URL 의 경로가 이미지 확장자로 끝나는가(쿼리·프래그먼트 무시) — 서버 import 가 재호스팅할 수
    /// 있는 형식(jpeg/png/gif/webp)만. 그러면 링크 단축 대신 이미지로 넣는다.
    static func isImageURL(_ s: String) -> Bool {
        guard let comps = URLComponents(string: s),
            let scheme = comps.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return false }
        let path = comps.path.lowercased()
        return [".jpg", ".jpeg", ".png", ".gif", ".webp"].contains { path.hasSuffix($0) }
    }
}

extension MarkdownInputTextView: UIGestureRecognizerDelegate {
    // 표 그리드 탭 인식기가 UITextView 기본 탭과 함께 동작하게(둘 다 발화, 그리드 안에서만 우리가 덮어씀).
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
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
    /// 붙여넣은 이미지 URL — 컴포즈가 재호스팅(필요 시 초안 생성) 후 `![](url)` 로 본문에 넣는다.
    var onPasteImageURL: (String) -> Void = { _ in }
    /// 클립보드 이미지 바이트 붙여넣기 — 컴포즈가 업로드 후 `![](url)` 로 본문에 넣는다.
    var onPasteImages: ([UIImage]) -> Void = { _ in }

    func makeUIView(context: Context) -> UITextView {
        let textView = MarkdownInputTextView()
        textView.font = UIFontMetrics(forTextStyle: .body)
            .scaledFont(for: .monospacedSystemFont(ofSize: 16, weight: .regular))
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.textColor = UIColor(Palette.body)
        // 캐럿·선택 강조를 브랜드 그린으로 — 종이 위에서 캐럿이 또렷하고, 선택도 브랜드 색을 입는다.
        textView.tintColor = UIColor(Palette.accent)
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

        // 붙여넣은 이미지 URL → 호스트(컴포즈)가 재호스팅 후 본문에 이미지로 넣는다.
        textView.onPasteImageURL = onPasteImageURL
        // 클립보드 이미지 바이트 → 호스트(컴포즈)가 업로드 후 본문에 이미지로 넣는다.
        textView.onPasteImages = onPasteImages

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
                // 조용히 바꾸지 않는다 — 단축됐음을 알리고 원래 주소로 되돌릴 길을 준다.
                ToastCenter.shared.show(
                    String(localized: "kurl 링크로 단축했어요"),
                    actionLabel: String(localized: "되돌리기")
                ) { [weak textView] in
                    guard let textView, let undo = textView.undoManager, undo.canUndo else { return }
                    undo.undo()
                    coordinator.textViewDidChange(textView)
                }
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
        /// 마지막으로 마커를 노출했던 활성 문단의 시작 위치 — 캐럿이 다른 문단으로 옮겨갈 때만
        /// 다시 칠해(떠난 줄은 마커 숨김, 새 줄은 노출) 매 커서 이동마다의 재렌더를 피한다.
        private var lastActiveParaStart = -1

        init(_ parent: MarkdownTextView) {
            self.parent = parent
            self.lastEditorText = parent.text
        }

        /// 캐럿이 놓인 문단의 시작 위치.
        private func activeParaStart(_ textView: UITextView) -> Int {
            let ns = textView.text as NSString
            return ns.paragraphRange(for: NSRange(location: min(textView.selectedRange.location, ns.length), length: 0)).location
        }

        func textViewDidChange(_ textView: UITextView) {
            // 조합 중간값은 바인딩에 흘리지 않는다 — 자동저장 시그니처가 조합 글자로 출렁이지 않게.
            guard textView.markedTextRange == nil else { return }
            // 본문이 바뀌었으니 컨텍스트 캐시를 버린다 — 같은 길이·같은 줄 시작의 편집에서도 정확하게.
            parent.controller.invalidateContextCache()
            // 변경 크기 — 작은 in-place 편집이면 캐럿 문단만 다시 칠해 긴 글 타이핑 지연을 없앤다.
            let delta = abs((textView.text as NSString).length - (lastEditorText as NSString).length)
            parent.text = textView.text
            lastEditorText = textView.text
            // 치는 즉시 렌더 — 조합이 끝난 글자부터 제목·굵게 등으로 입혀진다. 큰 변경(붙여넣기 등)이나
            // 빠른 경로가 거부(펜스·구조)하면 전체 패스로 떨어진다.
            if delta > 2 || !MarkdownSyntaxHighlighter.applyEditedParagraph(to: textView) {
                MarkdownSyntaxHighlighter.apply(to: textView)
            }
            // 방금 친 줄이 활성 문단 — 다음 커서 이동 비교 기준을 여기에 맞춰 둔다(중복 재렌더 방지).
            lastActiveParaStart = activeParaStart(textView)
            parent.onContextChange(parent.controller.caretContext())
            // 입력이 다시 시작되면 '실행취소' 토스트는 거둔다(엉뚱한 대상 undo 방지).
            ToastCenter.shared.dismissActionToast()
        }

        // 커서가 움직일 때마다 캐럿 위치의 성격(표/이미지)을 컴포즈에 알린다(컨텍스트 바 토글).
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard textView.markedTextRange == nil else { return }
            parent.onContextChange(parent.controller.caretContext())
            // 캐럿이 다른 문단으로 옮겨가면 다시 칠한다 — 떠난 줄은 마커를 숨기고, 새 줄은 노출(편집).
            let start = activeParaStart(textView)
            if start != lastActiveParaStart {
                lastActiveParaStart = start
                MarkdownSyntaxHighlighter.apply(to: textView)
            }
        }

        /// 프로그램 편집 중 재진입 가드(아래 replace 가 이 델리게이트를 다시 부를 가능성 차단).
        private var editingProgrammatically = false

        /// Enter = 목록 이어가기(빈 항목이면 목록 종료), Backspace = 줄머리 마커 통째 삭제(한 번에 강등).
        /// 마크다운을 몰라도 목록을 자연스럽게 만들고, 숨은 마커를 한 글자씩 갉아 블록이 슬그머니 바뀌는 걸 막는다.
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard !editingProgrammatically, textView.markedTextRange == nil,
                range.location <= (textView.text as NSString).length
            else { return true }
            let ns = textView.text as NSString
            let lineRange = ns.lineRange(for: NSRange(location: range.location, length: 0))
            let lineStart = lineRange.location
            var content = ns.substring(with: lineRange)
            while content.hasSuffix("\n") || content.hasSuffix("\r") { content.removeLast() }

            // 엔터: 현재 줄이 목록이면 이어가거나(본문 있음) 종료(빈 항목).
            if text == "\n", range.length == 0, let m = Self.listMarker(content) {
                let body = content.dropFirst(min(m.length, content.count))
                if body.trimmingCharacters(in: .whitespaces).isEmpty {
                    // 빈 항목에서 엔터 = 목록 종료(마커 제거).
                    replaceProgrammatically(textView, NSRange(location: lineStart, length: m.length), with: "", caret: lineStart)
                } else {
                    // 다음 항목 마커를 만들어 이어간다(번호는 +1, 들여쓰기 유지).
                    let nextMarker = m.isOrdered ? "\(m.num + 1). " : m.marker
                    let insert = "\n" + String(repeating: " ", count: m.lead) + nextMarker
                    replaceProgrammatically(textView, NSRange(location: range.location, length: 0), with: insert,
                        caret: range.location + (insert as NSString).length)
                }
                return false
            }

            // 백스페이스로 줄머리(#·>·-·1.) 마커의 마지막 칸을 지우려 하면 = 마커 전체를 한 번에 지워 통째 강등.
            if text.isEmpty, range.length == 1, let markerLen = Self.leadingMarkerLength(content),
                range.location == lineStart + markerLen - 1 {
                replaceProgrammatically(textView, NSRange(location: lineStart, length: markerLen), with: "", caret: lineStart)
                return false
            }
            return true
        }

        /// undo 보존 replace + 캐럿 지정 + 바인딩·재렌더 동기화. 재진입 가드로 감싼다.
        private func replaceProgrammatically(_ textView: UITextView, _ nsRange: NSRange, with str: String, caret: Int) {
            guard let s = textView.position(from: textView.beginningOfDocument, offset: nsRange.location),
                let e = textView.position(from: s, offset: nsRange.length),
                let r = textView.textRange(from: s, to: e)
            else { return }
            editingProgrammatically = true
            textView.replace(r, withText: str)
            let limit = (textView.text as NSString).length
            textView.selectedRange = NSRange(location: min(caret, limit), length: 0)
            editingProgrammatically = false
            parent.text = textView.text
            lastEditorText = textView.text
            MarkdownSyntaxHighlighter.apply(to: textView)
            lastActiveParaStart = activeParaStart(textView)
            parent.onContextChange(parent.controller.caretContext())
        }

        /// 줄머리 목록 마커 정보(들여쓰기·길이·번호 여부·다음 마커 번호).
        private static func listMarker(_ content: String) -> (lead: Int, length: Int, isOrdered: Bool, num: Int, marker: String)? {
            let lead = content.prefix(while: { $0 == " " }).count
            let body = content.dropFirst(lead)
            if body.hasPrefix("- ") { return (lead, lead + 2, false, 0, "- ") }
            if body.hasPrefix("* ") { return (lead, lead + 2, false, 0, "* ") }
            let digits = body.prefix(while: { $0.isNumber })
            if !digits.isEmpty, body.dropFirst(digits.count).hasPrefix(". ") {
                let n = Int(digits) ?? 1
                return (lead, lead + digits.count + 2, true, n, "\(n). ")
            }
            return nil
        }

        /// 줄머리 블록 마커(제목·인용·목록) 전체 길이 — 백스페이스 원샷 삭제용.
        private static func leadingMarkerLength(_ content: String) -> Int? {
            let lead = content.prefix(while: { $0 == " " }).count
            let body = content.dropFirst(lead)
            let hashes = body.prefix(while: { $0 == "#" }).count
            if hashes >= 1, hashes <= 3, body.dropFirst(hashes).first == " " { return lead + hashes + 1 }
            if body.hasPrefix("> ") { return lead + 2 }
            return listMarker(content)?.length
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

/// 캐럿이 놓인 곳의 성격 — 컴포즈가 그에 맞는 컨텍스트 편집 바(표/이미지/목록)를 띄운다.
enum EditorCaretContext { case none, table, image, video, list }

/// 스니펫 바 → 캔버스 다리. 커서/선택 기준 삽입을 UIKit 의 진짜 커서로 수행한다.
/// 모든 동작은 undo 스택을 보존하고(`replace(_:withText:)`), 조합 중에는 거부한다.
@MainActor
final class MarkdownEditorController {
    weak var textView: UITextView?
    /// 링크 다이얼로그가 뜨는 동안 보관하는 삽입 위치(시트가 뜨며 selection 이 흐려져도 제자리에 넣는다).
    private var pendingLinkRange: NSRange?

    var currentText: String { textView?.text ?? "" }

    /// 한글 등 조합(IME)이 진행 중인가 — 진행 중이면 프로그램 삽입·바인딩 동기화를 보류한다
    /// (조합 중간 글자가 바인딩으로 새 자동저장 시그니처가 출렁이는 것을 막는다).
    var isComposing: Bool { textView?.markedTextRange != nil }

    func focus() {
        textView?.becomeFirstResponder()
    }

    func dismissKeyboard() {
        textView?.resignFirstResponder()
    }

    /// 커서가 놓인 줄의 제목 단계를 순환한다 — 본문 → H1(#) → H2(##) → H3(###) → 본문.
    /// 기존 줄머리(`# `·`## `·`### `)를 걷어내고 다음 단계로 다시 써, applyLinePrefix 가
    /// 무턱대고 앞에 덧붙여 `# # ` 가 쌓이던(H2·H3 가 끝내 안 만들어지던) 문제를 없앤다.
    func cycleHeading() {
        guard let textView, textView.markedTextRange == nil else { return }
        let ns = textView.text as NSString
        let caret = textView.selectedRange
        let lineRange = ns.lineRange(for: NSRange(location: min(caret.location, ns.length), length: 0))
        // 줄바꿈을 뗀 줄 본문 범위(치환 대상).
        var contentLen = lineRange.length
        while contentLen > 0 {
            let c = ns.substring(with: NSRange(location: lineRange.location + contentLen - 1, length: 1))
            if c == "\n" || c == "\r" { contentLen -= 1 } else { break }
        }
        let contentRange = NSRange(location: lineRange.location, length: contentLen)
        let line = ns.substring(with: contentRange)

        // 현재 단계를 하이라이터와 같은 기준으로 읽는다 — `#`·`##`·`###` 뒤에 공백(또는 줄 끝).
        // 그 ATX 마커(해시들 + 뒤 공백)만 떼고 본문은 보존한다(`#태그`처럼 공백 없는 해시는 본문).
        let hashes = line.prefix(while: { $0 == "#" }).count
        let isHeading = hashes >= 1 && hashes <= 3
            && (line.count == hashes || line.dropFirst(hashes).first == " ")
        var bodyIdx = line.index(line.startIndex, offsetBy: hashes)
        while bodyIdx < line.endIndex, line[bodyIdx] == " " || line[bodyIdx] == "\t" {
            bodyIdx = line.index(after: bodyIdx)
        }
        let body = isHeading ? String(line[bodyIdx...]) : line
        let oldMarkerLen = isHeading ? line.distance(from: line.startIndex, to: bodyIdx) : 0

        let current = isHeading ? hashes : 0
        let next = current >= 3 ? 0 : current + 1
        let marker = next == 0 ? "" : String(repeating: "#", count: next) + " "
        let newLine = marker + body

        guard let s = textView.position(from: textView.beginningOfDocument, offset: contentRange.location),
            let e = textView.position(from: s, offset: contentRange.length),
            let range = textView.textRange(from: s, to: e)
        else { return }
        textView.replace(range, withText: newLine)
        // 본문 안의 상대 캐럿을 보존한다(마커 길이 변화만큼만 보정).
        let caretInBody = max(0, caret.location - contentRange.location - oldMarkerLen)
        let newCaret = contentRange.location + (marker as NSString).length + caretInBody
        let limit = (textView.text as NSString).length
        textView.selectedRange = NSRange(location: min(newCaret, limit), length: 0)
        MarkdownSyntaxHighlighter.apply(to: textView)
    }

    /// 줄머리 블록 마커(인용 `> `·글머리 `- `·번호 `1. `)를 토글한다. 같은 마커면 떼고(끄기),
    /// 다른 블록 마커가 있으면 바꾸고, 없으면 붙인다 — 예전 applyLinePrefix 가 무조건 앞에 덧대
    /// `> > `·`- - ` 가 쌓이고, 끌 수도 바꿀 수도 없던 문제를 없앤다. 여러 줄을 선택했으면
    /// 각 줄에 적용한다(문단 → 목록/인용; 모든 줄에 마커가 있으면 모두에서 뗀다).
    func toggleLinePrefix(_ marker: String) {
        guard let textView, textView.markedTextRange == nil else { return }
        let ns = textView.text as NSString
        let sel = textView.selectedRange
        let blockRange = ns.lineRange(for: sel)
        let blockText = ns.substring(with: blockRange)
        let trailingNewline = blockText.hasSuffix("\n")
        let core = trailingNewline ? String(blockText.dropLast()) : blockText
        let lines = core.components(separatedBy: "\n")

        let known = ["> ", "- ", "* ", "1. "]
        func currentMarker(_ line: String) -> String? { known.first { line.hasPrefix($0) } }
        let nonEmpty = lines.filter { !$0.isEmpty }
        // 단일 줄은 그 줄에 이 마커가 있을 때만 끈다. 여러 줄은 (빈 줄 빼고) 모두 있을 때만 끈다.
        let turnOff = lines.count > 1
            ? (!nonEmpty.isEmpty && nonEmpty.allSatisfy { $0.hasPrefix(marker) })
            : (currentMarker(lines.first ?? "") == marker)

        let newLines = lines.map { line -> String in
            if line.isEmpty, lines.count > 1 { return line }  // 여러 줄 적용 때 빈 줄은 그대로(빈 글머리 방지).
            if let cur = currentMarker(line) {
                let body = String(line.dropFirst(cur.count))
                return turnOff ? body : marker + body  // 끄기 또는 다른 마커로 교체.
            }
            return turnOff ? line : marker + line
        }
        let newText = newLines.joined(separator: "\n") + (trailingNewline ? "\n" : "")

        guard let s = textView.position(from: textView.beginningOfDocument, offset: blockRange.location),
            let e = textView.position(from: s, offset: blockRange.length),
            let range = textView.textRange(from: s, to: e)
        else { return }
        textView.replace(range, withText: newText)

        let limit = (textView.text as NSString).length
        if sel.length == 0 {
            // 단일 캐럿: 그 줄에서의 상대 위치를 보존(마커 길이 변화만 보정).
            let oldMarkerLen = currentMarker(lines.first ?? "").map { ($0 as NSString).length } ?? 0
            let newMarkerLen = turnOff ? 0 : (marker as NSString).length
            let caretInBody = max(0, sel.location - blockRange.location - oldMarkerLen)
            textView.selectedRange = NSRange(location: min(blockRange.location + newMarkerLen + caretInBody, limit), length: 0)
        } else {
            // 선택 적용: 바뀐 블록 전체를 다시 선택해 무엇이 바뀌었는지 보인다.
            textView.selectedRange = NSRange(
                location: blockRange.location, length: min((newText as NSString).length, limit - blockRange.location))
        }
        MarkdownSyntaxHighlighter.apply(to: textView)
    }

    /// 선택(또는 닿은 단어/어절)을 강조 마커로 감싼다. 이미 감싸여 있으면 벗긴다(토글) —
    /// 예전엔 다시 누르면 마커가 겹쳐 `~~~~…~~~~`(취소선 렌더 안 됨)·`*…*`→`**…**`(기울임이
    /// 굵게로 뒤집힘) 같은 깨진 출력이 났다. 선택이 없고 빈 줄이면 자리표시자("텍스트")를 넣고 선택해 둔다.
    func wrapSelection(_ fix: String) {
        guard let textView, textView.markedTextRange == nil else { return }
        let ns = textView.text as NSString
        var range = textView.selectedRange
        // 선택이 없으면 닿은 단어/어절(공백 사이 연속 문자)을 감싼다 — 한글도 띄어쓰기로 갈리므로
        // 어절 단위로 감싼다(예전엔 CJK 를 제외해, 캐럿이 단어 가운데면 `굵**텍스트**게`로 쪼개졌다).
        if range.length == 0, let word = currentWordRange(in: textView, around: range.location) {
            range = word
        }
        let fixLen = (fix as NSString).length

        // 이미 감싸여 있으면 벗긴다(토글). (a) 마커가 범위 바로 바깥, (b) 범위 자체가 `fix…fix` 를 포함.
        if range.length > 0 {
            if range.location >= fixLen, range.location + range.length + fixLen <= ns.length,
                ns.substring(with: NSRange(location: range.location - fixLen, length: fixLen)) == fix,
                ns.substring(with: NSRange(location: range.location + range.length, length: fixLen)) == fix {
                let inner = ns.substring(with: range)
                replaceAndSelect(
                    in: textView,
                    NSRange(location: range.location - fixLen, length: fixLen + range.length + fixLen),
                    with: inner)
                return
            }
            let innerStr = ns.substring(with: range) as NSString
            if innerStr.length >= 2 * fixLen, innerStr.hasPrefix(fix), innerStr.hasSuffix(fix) {
                let stripped = innerStr.substring(with: NSRange(location: fixLen, length: innerStr.length - 2 * fixLen))
                replaceAndSelect(in: textView, range, with: stripped)
                return
            }
        }

        var inner = range.length > 0 ? ns.substring(with: range) : ""
        if inner.isEmpty { inner = String(localized: "텍스트") }

        guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
              let end = textView.position(from: start, offset: range.length),
              let textRange = textView.textRange(from: start, to: end)
        else { return }
        textView.replace(textRange, withText: fix + inner + fix)

        // 감싼 내용(자리표시자 포함)을 선택해 둔다 — 바로 덮어쓰거나 다시 눌러 토글(벗기기)할 수 있게.
        let innerLen = (inner as NSString).length
        if let s = textView.position(from: textView.beginningOfDocument, offset: range.location + fixLen),
           let e = textView.position(from: s, offset: innerLen),
           let sel = textView.textRange(from: s, to: e) {
            textView.selectedTextRange = sel
        } else {
            textView.selectedRange = NSRange(location: range.location + fixLen * 2 + innerLen, length: 0)
        }
        MarkdownSyntaxHighlighter.apply(to: textView)
    }

    /// NSRange 를 텍스트로 치환하고(undo 보존) 그 결과를 선택해 둔다 — wrapSelection 의 벗기기 경로용.
    private func replaceAndSelect(in textView: UITextView, _ nsRange: NSRange, with text: String) {
        guard let s = textView.position(from: textView.beginningOfDocument, offset: nsRange.location),
            let e = textView.position(from: s, offset: nsRange.length),
            let r = textView.textRange(from: s, to: e),
            let selEnd = textView.position(from: s, offset: (text as NSString).length),
            let sel = textView.textRange(from: s, to: selEnd)
        else { return }
        textView.replace(r, withText: text)
        textView.selectedTextRange = sel
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
        // 빈 줄로 위아래를 띄운다 — 안 그러면 바로 다음 줄(산문)이 이미지와 한 문단으로 묶여
        // 독립 이미지 블록이 아니라 인라인 이미지로 렌더될 수 있다.
        insertBlock("\n\n![\(marker)](\(url)\(cap))\n\n", caretOffsetFromStart: nil)
    }

    /// GFM 표 골격 — 백엔드 마크다운→블록이 TABLE 로 변환, 리더(TableBlockView)가 렌더. 첫 셀에 커서.
    func insertTable() {
        // 표 앞뒤를 빈 줄로 띄운다 — 표 바로 다음에 산문이 붙으면 GFM 파서가 그 줄을 표의
        // 유령 행으로 빨아들여(에디터엔 평문, 발행본엔 표 안 행으로) 어긋난다.
        let table = "| 제목 | 제목 |\n| --- | --- |\n| 내용 | 내용 |"
        // 삽입 즉시 "표"로 보이게 — 캐럿을 표 아래 빈 줄에 둔다. 캐럿이 표 안이면 원시 마크다운(파이프)이
        // 드러나 코드처럼 읽히지만, 밖이면 레이아웃 매니저가 곧장 진짜 그리드를 그린다. 셀은 탭해서 채운다
        // (그려진 그리드를 탭하면 그 셀로 커서가 들어가 편집 모드가 된다 — handleGridTap).
        let caretOffset = ("\n\n" + table + "\n").utf16.count
        insertBlock("\n\n" + table + "\n\n", caretOffsetFromStart: caretOffset)
    }

    /// 단독 줄 동영상 URL — 백엔드가 EMBED 블록으로(YouTube/Vimeo), 리더(EmbedBlockView)가 플레이어로.
    func insertVideoEmbed(url: String) {
        // 빈 줄로 띄워 URL 이 제 문단에 홀로 서게 한다 — 안 그러면 앞뒤 산문과 한 문단으로 묶여
        // 임베드(플레이어)가 아니라 평범한 인라인 링크로 렌더된다.
        insertBlock("\n\n\(url)\n\n", caretOffsetFromStart: nil)
    }

    /// 현재 줄(또는 선택에 걸친 모든 줄) 맨 앞에 2칸 들여쓰기 — 리스트 항목을 한 단계 안으로(중첩).
    /// 리더가 깊이대로 렌더. 선택이 여러 줄이면 각 줄에 2칸을 더하고 블록 전체를 다시 선택한다.
    func indentLine() {
        guard let textView, textView.markedTextRange == nil else { return }
        if textView.selectedRange.length > 0 {
            transformSelectedLines(textView) { $0.isEmpty ? $0 : "  " + $0 }
            return
        }
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

    /// 현재 줄(또는 선택에 걸친 모든 줄) 앞 들여쓰기 한 단계(최대 2칸) 제거.
    func outdentLine() {
        guard let textView, textView.markedTextRange == nil else { return }
        if textView.selectedRange.length > 0 {
            transformSelectedLines(textView) { Self.dropLeadingSpaces($0, upTo: 2) }
            return
        }
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

    /// 선행 공백을 최대 n칸 뗀다(내어쓰기 한 단계).
    private static func dropLeadingSpaces(_ line: String, upTo n: Int) -> String {
        var removed = 0
        var s = Substring(line)
        while removed < n, s.first == " " { s = s.dropFirst(); removed += 1 }
        return String(s)
    }

    /// 선택에 걸친 각 줄을 변환하고(들여쓰기/내어쓰기) 바뀐 블록 전체를 다시 선택한다 — 무엇이 바뀌었는지 보이게.
    private func transformSelectedLines(_ textView: UITextView, _ transform: (String) -> String) {
        let ns = textView.text as NSString
        let block = ns.lineRange(for: textView.selectedRange)
        let text = ns.substring(with: block)
        let hadTrailingNewline = text.hasSuffix("\n")
        let core = hadTrailingNewline ? String(text.dropLast()) : text
        let newCore = core.components(separatedBy: "\n").map(transform).joined(separator: "\n")
        let newText = newCore + (hadTrailingNewline ? "\n" : "")
        guard let s = textView.position(from: textView.beginningOfDocument, offset: block.location),
            let e = textView.position(from: s, offset: block.length),
            let r = textView.textRange(from: s, to: e)
        else { return }
        textView.replace(r, withText: newText)
        let limit = (textView.text as NSString).length
        textView.selectedRange = NSRange(
            location: block.location, length: min((newText as NSString).length, limit - block.location))
        MarkdownSyntaxHighlighter.apply(to: textView)
    }

    // MARK: 표 편집 — 마크다운을 몰라도 행·열을 늘리고 줄인다.
    // 캐럿이 표 안에 들어오면 컴포즈가 컨텍스트 바를 띄우고, 그 버튼이 이 메서드들을 부른다.
    // 표 전체를 한 번에 다시 그려(셀 정렬 정규화) 손으로 `|` 를 칠 일이 없게 한다.

    /// (문서 길이, 캐럿 줄 시작) 동일하면 컨텍스트 재계산을 건너뛰는 캐시 — 같은 줄 안 커서 이동마다
    /// 전체 문서를 다시 훑지 않게(파이프 든 산문 줄에서 특히). 본문이 바뀌면 무효화해(같은 길이·같은
    /// 줄 시작이라도 내용이 달라질 수 있으므로) 순수 커서 이동에서만 단축되게 한다.
    private var contextCache: (length: Int, lineLocation: Int, context: EditorCaretContext)?

    /// 본문 편집이 일어났을 때 컨텍스트 캐시를 버린다(coordinator 가 매 변경마다 호출).
    func invalidateContextCache() { contextCache = nil }

    /// 캐럿 위치의 성격(표/이미지/동영상/그 외) — 컴포즈가 띄울 컨텍스트 바를 고른다.
    func caretContext() -> EditorCaretContext {
        guard let textView, textView.markedTextRange == nil else { return .none }
        let ns = textView.text as NSString
        guard ns.length > 0 else { return .none }
        let caret = NSRange(location: min(textView.selectedRange.location, ns.length), length: 0)
        let lineRange = ns.lineRange(for: caret)
        if let c = contextCache, c.length == ns.length, c.lineLocation == lineRange.location {
            return c.context
        }
        let line = ns.substring(with: lineRange)
        // 매 커서 이동마다 전체 문서를 훑지 않게 — 캐럿 줄에 '|'·'!'·'://' 가 있을 때만 정밀 판별한다.
        // 목록은 줄머리만 보면 되므로(문서 스캔 없이) 마지막에 싸게 판정한다.
        let result: EditorCaretContext =
            (line.contains("|") && tableBlock(in: textView) != nil) ? .table
            : (line.contains("!") && imageOnCaretLine(in: textView) != nil) ? .image
            : (line.contains("://") && embedLineRange(in: textView) != nil) ? .video
            : Self.isListLine(line) ? .list
            : .none
        contextCache = (ns.length, lineRange.location, result)
        return result
    }

    /// 줄머리가 글머리(`- `·`* `) 또는 번호(`1. `) 목록인가 — 들여쓰기 바를 띄울지 판정.
    static func isListLine(_ line: String) -> Bool {
        let body = line.drop(while: { $0 == " " })
        if body.hasPrefix("- ") || body.hasPrefix("* ") { return true }
        let digits = body.prefix(while: { $0.isNumber })
        return !digits.isEmpty && body.dropFirst(digits.count).hasPrefix(". ")
    }

    /// 캐럿 줄의 선행 공백 칸 수 — 내어쓰기 가능 여부(depth 0 이면 비활성) 판정용.
    func currentLineIndentSpaces() -> Int {
        guard let textView else { return 0 }
        let ns = textView.text as NSString
        let caret = min(textView.selectedRange.location, ns.length)
        let lineStart = ns.lineRange(for: NSRange(location: caret, length: 0)).location
        var n = 0
        while lineStart + n < ns.length,
            ns.substring(with: NSRange(location: lineStart + n, length: 1)) == " " {
            n += 1
        }
        return n
    }

    private struct TableBlock {
        var charRange: NSRange  // 표 전체를 덮는 치환 범위(마지막 줄바꿈 제외)
        var startLocation: Int  // = charRange.location
        var header: [String]
        var separator: [String]  // 정렬 토큰(---·:--·--:·:-:) — op 뒤에도 보존한다.
        var body: [[String]]
        var caretLine: Int  // 블록 내 줄 인덱스(0=헤더, 1=구분선, 2+=본문)
        var caretColumn: Int  // 캐럿이 놓인 셀 인덱스
        // 가장 넓은 행 기준 — 헤더가 본문보다 좁아도 본문 칸을 잃지 않게.
        var columnCount: Int {
            max(1, max(header.count, separator.count), body.map(\.count).max() ?? 0)
        }
    }

    /// '\\|' 로 이스케이프된 파이프는 가르지 않고, 칸 안에서는 리터럴 '|' 로 되돌린다.
    private func splitUnescapedPipes(_ line: String) -> [String] {
        var cells: [String] = []
        var cur = ""
        var escaped = false
        for ch in line {
            if escaped {
                if ch == "|" { cur.append("|") } else { cur.append("\\"); cur.append(ch) }
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else if ch == "|" {
                cells.append(cur)
                cur = ""
            } else {
                cur.append(ch)
            }
        }
        if escaped { cur.append("\\") }
        cells.append(cur)
        return cells
    }

    /// 줄 안에서 이스케이프되지 않은 '|' 개수 — 선두 파이프 보정 판단용.
    private func countUnescapedPipes(_ s: String) -> Int {
        var n = 0
        var escaped = false
        for ch in s {
            if escaped { escaped = false } else if ch == "\\" { escaped = true } else if ch == "|" {
                n += 1
            }
        }
        return n
    }

    /// 표 한 줄을 셀 배열로 — 선두·말미 파이프가 만드는 빈 칸은 떨군다.
    private func tableCells(_ line: String) -> [String] {
        var parts = splitUnescapedPipes(line).map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.first == "" { parts.removeFirst() }
        if parts.last == "" { parts.removeLast() }
        return parts
    }

    /// 부족한 칸은 채우고 넘치는 칸은 자른다 — op 전 모든 행을 같은 폭으로 정규화.
    private func padded(_ cells: [String], to n: Int, fill: String = "") -> [String] {
        var c = cells
        while c.count < n { c.append(fill) }
        return Array(c.prefix(n))
    }

    /// `| --- | :--: |` 같은 정렬 구분선인가.
    private func isSeparatorRow(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-") else { return false }
        return t.allSatisfy { "|:- ".contains($0) }
    }

    /// 캐럿이 속한 표 블록을 찾아 헤더·본문·캐럿 위치를 파싱한다. 표가 아니면 nil.
    /// 코드 펜스(```) 안의 파이프 줄은 표로 보지 않는다(하이라이터 styleLines 와 같은 규칙).
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
        // 코드 펜스 안 줄(펜스 마커 포함)은 표 후보에서 제외한다.
        var fenced = [Bool](repeating: false, count: subs.count)
        var inFence = false
        for i in subs.indices {
            if subs[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                fenced[i] = true
                inFence.toggle()
            } else {
                fenced[i] = inFence
            }
        }
        let caretIdx = ranges.firstIndex { caret <= $0.location + $0.length } ?? (ranges.count - 1)
        func isTableLine(_ i: Int) -> Bool {
            !fenced[i] && subs[i].contains("|")
                && !subs[i].trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard isTableLine(caretIdx) else { return nil }
        var start = caretIdx
        var end = caretIdx
        while start > 0, isTableLine(start - 1) { start -= 1 }
        while end < subs.count - 1, isTableLine(end + 1) { end += 1 }
        // GFM 표 = 최소 2줄 + 둘째 줄이 정렬 구분선.
        guard end - start >= 1, isSeparatorRow(subs[start + 1]) else { return nil }
        let loc = ranges[start].location
        let endLoc = ranges[end].location + ranges[end].length
        let header = tableCells(subs[start])
        let separator = tableCells(subs[start + 1])
        let body = (start + 2 <= end) ? (start + 2...end).map { tableCells(subs[$0]) } : []
        // 캐럿 셀 인덱스 — 줄에 선두 파이프가 있으면 한 칸 보정, 없으면(파이프리스 표) 보정하지 않는다.
        let lineStart = ranges[caretIdx].location
        let inLine = max(0, caret - lineStart)
        let line = subs[caretIdx] as NSString
        let prefix = line.substring(to: min(inLine, line.length))
        let pipes = countUnescapedPipes(prefix)
        let hasLeadingPipe = subs[caretIdx].trimmingCharacters(in: .whitespaces).hasPrefix("|")
        return TableBlock(
            charRange: NSRange(location: loc, length: endLoc - loc),
            startLocation: loc,
            header: header,
            separator: separator,
            body: body,
            caretLine: caretIdx - start,
            caretColumn: hasLeadingPipe ? max(0, pipes - 1) : pipes)
    }

    /// 헤더·본문을 정규화된 GFM 표 줄 배열로 — 칸을 ` | ` 로 가지런히, 정렬 토큰은 보존,
    /// 셀 안 리터럴 '|' 는 '\\|' 로 다시 이스케이프한다. 폭은 가장 넓은 행 기준.
    private func renderTable(header: [String], separator: [String], body: [[String]]) -> [String] {
        let n = max(1, max(header.count, separator.count), body.map(\.count).max() ?? 0)
        func row(_ cells: [String]) -> String {
            let c = padded(cells, to: n).map { $0.replacingOccurrences(of: "|", with: "\\|") }
            return "| " + c.joined(separator: " | ") + " |"
        }
        let sep = padded(separator, to: n, fill: "---").map { $0.isEmpty ? "---" : $0 }
        var lines = [row(header)]
        lines.append("| " + sep.joined(separator: " | ") + " |")
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
        // 별도 undo 그룹으로 — '실행취소' 토스트가 직전 타이핑까지 한꺼번에 되돌리지 않게.
        textView.undoManager?.beginUndoGrouping()
        textView.replace(range, withText: serialized)
        textView.undoManager?.endUndoGrouping()
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
            block,
            lines: renderTable(header: block.header, separator: block.separator, body: body),
            caretLine: 2 + idx, caretColumn: 0)
    }

    /// 맨 끝에 빈 열을 더하고, 그 새 열로 커서를 옮긴다. 모든 행을 같은 폭으로 맞춘 뒤 더한다.
    func addTableColumn() {
        guard let textView, textView.markedTextRange == nil,
            let block = tableBlock(in: textView)
        else { return }
        let n = block.columnCount
        let header = padded(block.header, to: n) + [""]
        let separator = padded(block.separator, to: n, fill: "---") + ["---"]
        let body = block.body.map { padded($0, to: n) + [""] }
        applyTable(
            block, lines: renderTable(header: header, separator: separator, body: body),
            caretLine: block.caretLine == 1 ? (block.body.isEmpty ? 0 : 2) : block.caretLine, caretColumn: n)
    }

    /// 캐럿이 놓인 본문 행을 지운다(헤더·구분선은 보호 — 그 자리에선 무동작). 지웠으면 true.
    @discardableResult
    func deleteTableRow() -> Bool {
        guard let textView, textView.markedTextRange == nil,
            let block = tableBlock(in: textView), block.caretLine >= 2, !block.body.isEmpty
        else { return false }
        var body = block.body
        let removeAt = block.caretLine - 2
        guard removeAt < body.count else { return false }
        body.remove(at: removeAt)
        let caretLine: Int
        if body.isEmpty {
            // 본문이 비면 빈 행 하나를 남겨 캐럿이 구분선(---)에 갇히지 않게.
            body.append(Array(repeating: "", count: block.columnCount))
            caretLine = 2
        } else {
            caretLine = 2 + min(removeAt, body.count - 1)
        }
        applyTable(
            block,
            lines: renderTable(header: block.header, separator: block.separator, body: body),
            caretLine: caretLine, caretColumn: 0)
        return true
    }

    /// 캐럿이 놓인 열을 모든 행에서 지운다(마지막 한 열은 보호). 지웠으면 true.
    @discardableResult
    func deleteTableColumn() -> Bool {
        guard let textView, textView.markedTextRange == nil,
            let block = tableBlock(in: textView), block.columnCount >= 2
        else { return false }
        let n = block.columnCount
        let col = min(block.caretColumn, n - 1)
        var header = padded(block.header, to: n)
        header.remove(at: col)
        var separator = padded(block.separator, to: n, fill: "---")
        separator.remove(at: col)
        let body = block.body.map { row -> [String] in
            var r = padded(row, to: n)
            r.remove(at: col)
            return r
        }
        applyTable(
            block, lines: renderTable(header: header, separator: separator, body: body),
            caretLine: block.caretLine == 1 ? (block.body.isEmpty ? 0 : 2) : block.caretLine,
            caretColumn: min(col, max(0, header.count - 1)))
        return true
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

    /// 캐럿이 놓인 이미지 줄을 통째로 지운다. 지웠으면 true.
    @discardableResult
    func removeImage() -> Bool {
        guard let textView, textView.markedTextRange == nil,
            let img = imageOnCaretLine(in: textView)
        else { return false }
        guard let s = textView.position(from: textView.beginningOfDocument, offset: img.lineRange.location),
            let e = textView.position(from: s, offset: img.lineRange.length),
            let range = textView.textRange(from: s, to: e)
        else { return false }
        // 별도 undo 그룹으로 — '실행취소' 토스트가 직전 타이핑까지 한꺼번에 되돌리지 않게.
        textView.undoManager?.beginUndoGrouping()
        textView.replace(range, withText: "")
        textView.undoManager?.endUndoGrouping()
        let limit = (textView.text as NSString).length
        textView.selectedRange = NSRange(location: min(img.lineRange.location, limit), length: 0)
        MarkdownSyntaxHighlighter.apply(to: textView)
        return true
    }

    /// 마지막 편집을 시스템 undo 스택으로 되돌린다(삭제 토스트의 '실행취소'). 되돌렸으면 true.
    @discardableResult
    func undoLastEdit() -> Bool {
        guard let textView, let undo = textView.undoManager, undo.canUndo else { return false }
        undo.undo()
        MarkdownSyntaxHighlighter.apply(to: textView)
        return true
    }

    /// 방금 되돌린 편집을 다시 적용한다(에디터 크롬의 '다시실행'). 다시 했으면 true.
    @discardableResult
    func redoLastEdit() -> Bool {
        guard let textView, let undo = textView.undoManager, undo.canRedo else { return false }
        undo.redo()
        MarkdownSyntaxHighlighter.apply(to: textView)
        return true
    }

    /// 실행취소/다시실행 가능 여부 — 스니펫 바의 버튼 비활성 상태를 라이브로 반영한다.
    var canUndo: Bool { textView?.undoManager?.canUndo ?? false }
    var canRedo: Bool { textView?.undoManager?.canRedo ?? false }

    // MARK: 동영상/임베드 줄 — 단독 URL 줄(백엔드가 EMBED 로 렌더). 편집 바로 지우거나 바꾼다.

    /// 캐럿 줄이 단독 http(s) URL(임베드)이면 그 줄 범위를 돌려준다.
    private func embedLineRange(in textView: UITextView) -> NSRange? {
        let ns = textView.text as NSString
        guard ns.length > 0 else { return nil }
        let caret = min(textView.selectedRange.location, ns.length)
        let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
        let content = ns.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
        let t = content.hasPrefix("<") && content.hasSuffix(">")
            ? String(content.dropFirst().dropLast()) : content
        guard (t.hasPrefix("http://") || t.hasPrefix("https://")),
            !t.contains(" "), !t.contains("\n"), t.contains(".")
        else { return nil }
        return lineRange
    }

    /// 캐럿이 놓인 임베드 줄을 통째로 지운다. 지웠으면 true.
    @discardableResult
    func removeEmbedLine() -> Bool {
        guard let textView, textView.markedTextRange == nil,
            let lineRange = embedLineRange(in: textView)
        else { return false }
        guard let s = textView.position(from: textView.beginningOfDocument, offset: lineRange.location),
            let e = textView.position(from: s, offset: lineRange.length),
            let range = textView.textRange(from: s, to: e)
        else { return false }
        textView.undoManager?.beginUndoGrouping()
        textView.replace(range, withText: "")
        textView.undoManager?.endUndoGrouping()
        let limit = (textView.text as NSString).length
        textView.selectedRange = NSRange(location: min(lineRange.location, limit), length: 0)
        MarkdownSyntaxHighlighter.apply(to: textView)
        return true
    }

    private func replaceImage(in textView: UITextView, content: NSRange, with md: String) {
        guard let s = textView.position(from: textView.beginningOfDocument, offset: content.location),
            let e = textView.position(from: s, offset: content.length),
            let range = textView.textRange(from: s, to: e)
        else { return }
        textView.replace(range, withText: md)
        // 줄 끝(숨겨진 마크다운 바깥)에 커서를 둔다 — 줄 머리에 두면 이어 친 글자가 `!` 앞에 박혀
        // 이미지가 깨졌다. 캐럿은 여전히 이 이미지 줄이라 편집 바도 계속 이 이미지를 가리킨다.
        let caret = content.location + (md as NSString).length
        let limit = (textView.text as NSString).length
        textView.selectedRange = NSRange(location: min(caret, limit), length: 0)
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
    /// 표 영역 첫 글자에 붙는 표식 — 값은 그 표의 원시 마크다운. 캐럿이 표 밖일 때 레이아웃 매니저가
    /// 이 자리에 진짜 그리드를 그린다(원시 텍스트는 0폭으로 숨김). 캐럿이 표 안이면 표식을 안 붙여 원시 편집.
    static let kurlTableMarkdown = NSAttributedString.Key("kurlTableMarkdown")
    /// 목록 줄 첫 글자에 붙는 표식 — 값은 그릴 불릿/번호("•"·"1."). 캐럿이 그 줄 밖일 때 원시 마커("- ")는
    /// 0폭으로 숨기고 행잉 인덴트로 본문을 들이며, 레이아웃 매니저가 이 자리에 불릿/번호를 그린다.
    static let kurlListBullet = NSAttributedString.Key("kurlListBullet")
    /// 인용(`> `) 줄에 붙는 표식 — 레이아웃 매니저가 그 줄(들) 왼단에 강조 바를 그린다(리더 .quote 와 같은 문법).
    static let kurlQuoteBar = NSAttributedString.Key("kurlQuoteBar")
}

/// 본문에 진짜 그리드로 그리는 표(WYSIWYG) — 캐럿이 표 밖일 때만. 원시 `| … |`·`---` 는 0폭으로 숨기고
/// 예약된 paragraphSpacing 공간에 레이아웃 매니저가 셀 테두리+내용을 그린다(이미지 썸네일과 같은 방식).
enum MarkdownTable {
    static let cellPadH: CGFloat = 10
    static let cellPadV: CGFloat = 7
    static let topPad: CGFloat = 6
    static let bottomGap: CGFloat = 12

    struct Parsed {
        var header: [String]
        var rows: [[String]]
        var cols: Int
        var rowCount: Int { 1 + rows.count }  // 헤더 + 본문
    }

    /// 표 영역 마크다운(헤더\n구분선\n본문…) → 셀. 구분선(`---`) 줄은 건너뛴다.
    static func parse(_ md: String) -> Parsed? {
        let lines = md.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 2 else { return nil }
        let header = cells(lines[0])
        let rows = lines.count > 2 ? lines[2...].map(cells) : []
        let cols = max(header.count, rows.map(\.count).max() ?? 0)
        guard cols > 0 else { return nil }
        return Parsed(header: header, rows: rows, cols: cols)
    }

    /// 한 줄 → 셀들. 선두·말미 파이프가 만드는 빈 칸은 떨군다. `\|` 이스케이프는 리터럴 `|`.
    static func cells(_ line: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var esc = false
        for ch in line {
            if esc { cur.append(ch == "|" ? "|" : ch); esc = false }
            else if ch == "\\" { esc = true }
            else if ch == "|" { out.append(cur.trimmingCharacters(in: .whitespaces)); cur = "" }
            else { cur.append(ch) }
        }
        out.append(cur.trimmingCharacters(in: .whitespaces))
        if out.first == "" { out.removeFirst() }
        if out.last == "" { out.removeLast() }
        return out
    }

    static func rowHeight(_ font: UIFont) -> CGFloat { font.lineHeight + cellPadV * 2 }

    /// 표 밖 줄들 아래에 예약할 그리드 총 높이(위·아래 여백 포함).
    static func gridHeight(rowCount: Int, font: UIFont) -> CGFloat {
        topPad + CGFloat(max(1, rowCount)) * rowHeight(font) + bottomGap
    }
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
    // 디코드된 원본을 무제한 쌓지 않게 한도를 둔다 — 이미지 많은 글에서 메모리가 폭주하지 않게.
    private let cache: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.countLimit = 40
        c.totalCostLimit = 64 * 1024 * 1024
        return c
    }()
    private var loading = Set<NSURL>()
    /// URL 별 시도 횟수 — 실패해도 곧바로 영구 블랙리스트하지 않고 백오프로 몇 번 더 받아본다.
    /// 갓 업로드한 이미지는 S3/CDN 전파가 늦어 첫 GET 이 404·오류일 수 있는데(그새 본문엔 이미 넣음),
    /// 예전엔 그 한 번의 비-2xx 로 URL 을 영구 블랙리스트해 썸네일이 끝내 안 뜨던(첨부해도 안 보이던) 버그가 있었다.
    private var attempts: [NSURL: Int] = [:]
    private static let maxAttempts = 5
    /// 재시도 백오프(초) — 전파 지연을 흡수한다. 시도가 늘수록 간격을 벌려 요청 폭주를 막는다.
    private static let backoff: [TimeInterval] = [0.5, 1.2, 2.5, 5.0]

    /// 캐시에 있으면 즉시 반환, 없으면 비동기로 받아 캐시 후 onLoad 호출(메인 스레드).
    /// 실패(전송오류·비-2xx·디코드 실패)면 백오프 뒤 onLoad 로 리드로우를 유도해(→ 재호출) 최대 maxAttempts 회 재시도.
    func image(for url: URL, onLoad: @escaping () -> Void) -> UIImage? {
        let key = url as NSURL
        if let img = cache.object(forKey: key) { return img }
        // 로딩 중이거나 재시도 한도를 소진했으면 새 요청을 걸지 않는다(리드로우마다의 폭주 차단).
        guard !loading.contains(key), (attempts[key] ?? 0) < Self.maxAttempts else { return nil }
        loading.insert(key)
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading.remove(key)
                let statusOK =
                    (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? true
                if error == nil, statusOK, let data, let img = UIImage(data: data) {
                    let cost = Int(img.size.width * img.size.height * img.scale * img.scale * 4)
                    self.cache.setObject(img, forKey: key, cost: cost)
                    self.attempts[key] = nil
                    onLoad()
                } else {
                    // 실패 — 한 번 더 세고, 한도 안이면 백오프 뒤 리드로우를 부른다(→ image(for:) 재호출 → 다음 시도).
                    let n = (self.attempts[key] ?? 0) + 1
                    self.attempts[key] = n
                    if n < Self.maxAttempts {
                        let delay = Self.backoff[min(n - 1, Self.backoff.count - 1)]
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: onLoad)
                    }
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

        // 인용 — 왼단에 강조 바를 그린다(리더 BlockRenderer .quote 의 accentSoft 바와 같은 문법).
        // 줄 전체 범위에 표식이 붙어 있어 boundingRect 이 줄바꿈 포함 여러 시각 줄의 높이를 덮는다.
        storage.enumerateAttribute(.kurlQuoteBar, in: charRange, options: []) { value, range, _ in
            guard value != nil, let ctx = UIGraphicsGetCurrentContext() else { return }
            let gr = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let used = boundingRect(forGlyphRange: gr, in: container)
            let bar = CGRect(
                x: origin.x + pad + 4, y: origin.y + used.minY + 1,
                width: 3, height: max(0, used.height - 2))
            guard bar.height > 1 else { return }
            ctx.saveGState()
            UIColor(Palette.accentSoft).setFill()
            UIBezierPath(roundedRect: bar, cornerRadius: 1.5).fill()
            ctx.restoreGState()
        }

        // 목록 — 원시 마커("- ")가 숨겨진 자리에 불릿/번호를 그린다(본문은 행잉 인덴트로 들어가 있음).
        storage.enumerateAttribute(.kurlListBullet, in: charRange, options: []) { value, range, _ in
            guard let bullet = value as? String else { return }
            let gr = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let line = lineFragmentUsedRect(forGlyphAt: gr.location, effectiveRange: nil)
            let indent = (storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil)
                as? NSParagraphStyle)?.headIndent ?? 20
            let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedSystemFont(ofSize: 16, weight: .regular))
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(Palette.accentMarker)]
            let size = (bullet as NSString).size(withAttributes: attrs)
            let x = origin.x + pad + max(0, indent - size.width - 6)
            let y = origin.y + line.minY + (line.height - size.height) / 2
            (bullet as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
        }

        // 표 — 캐럿이 밖일 때(표식이 붙어 있을 때) 진짜 그리드로 그린다(원시 텍스트는 0폭으로 숨겨짐).
        storage.enumerateAttribute(.kurlTableMarkdown, in: charRange, options: []) { value, range, _ in
            guard let md = value as? String, let parsed = MarkdownTable.parse(md) else { return }
            let gr = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let used = boundingRect(forGlyphRange: gr, in: container)
            drawTable(parsed, at: CGPoint(x: origin.x + pad, y: origin.y + used.maxY + MarkdownTable.topPad), width: availWidth)
        }

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
                // 로딩 중(또는 재시도 대기) — 빈 회색 칸이 "안 떴다"로 읽히지 않게 사진 아이콘을 얹어 자리를 잡는다.
                UIColor.secondarySystemFill.setFill()
                UIBezierPath(roundedRect: box, cornerRadius: 12).fill()
                if let icon = UIImage(systemName: "photo")?
                    .withConfiguration(UIImage.SymbolConfiguration(pointSize: 30, weight: .regular))
                    .withTintColor(UIColor(Palette.secondary), renderingMode: .alwaysOriginal) {
                    icon.draw(at: CGPoint(x: box.midX - icon.size.width / 2, y: box.midY - icon.size.height / 2))
                }
            }
            ctx.restoreGState()
        }
    }

    /// 예약된 공간에 표 그리드(테두리 + 셀 내용)를 그린다 — 발행본 TableBlockView 와 같은 모습.
    private func drawTable(_ t: MarkdownTable.Parsed, at top: CGPoint, width: CGFloat) {
        guard width > 1, t.cols > 0, let ctx = UIGraphicsGetCurrentContext() else { return }
        let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedSystemFont(ofSize: 16, weight: .regular))
        let headFont = UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedSystemFont(ofSize: 16, weight: .semibold))
        let rowH = MarkdownTable.rowHeight(font)
        let colW = width / CGFloat(t.cols)
        let totalH = CGFloat(t.rowCount) * rowH

        ctx.saveGState()
        // 헤더 배경(옅게) — 발행본처럼 헤더를 구분.
        UIColor(Palette.chipBg).setFill()
        UIBezierPath(rect: CGRect(x: top.x, y: top.y, width: width, height: rowH)).fill()

        func drawRow(_ cells: [String], y: CGFloat, head: Bool) {
            for c in 0..<t.cols {
                let text = c < cells.count ? cells[c] : ""
                guard !text.isEmpty else { continue }
                let para = NSMutableParagraphStyle()
                para.lineBreakMode = .byTruncatingTail
                (text as NSString).draw(
                    in: CGRect(
                        x: top.x + CGFloat(c) * colW + MarkdownTable.cellPadH,
                        y: y + MarkdownTable.cellPadV,
                        width: max(0, colW - MarkdownTable.cellPadH * 2),
                        height: rowH - MarkdownTable.cellPadV * 2),
                    withAttributes: [
                        .font: head ? headFont : font,
                        .foregroundColor: UIColor(head ? Palette.heading : Palette.body),
                        .paragraphStyle: para,
                    ])
            }
        }
        drawRow(t.header, y: top.y, head: true)
        for (i, row) in t.rows.enumerated() {
            drawRow(row, y: top.y + CGFloat(i + 1) * rowH, head: false)
        }

        // 그리드 선(하어라인).
        UIColor(Palette.hairline).setStroke()
        let grid = UIBezierPath()
        grid.lineWidth = 1
        for r in 0...t.rowCount {
            let y = top.y + CGFloat(r) * rowH
            grid.move(to: CGPoint(x: top.x, y: y))
            grid.addLine(to: CGPoint(x: top.x + width, y: y))
        }
        for c in 0...t.cols {
            let x = top.x + CGFloat(c) * colW
            grid.move(to: CGPoint(x: x, y: top.y))
            grid.addLine(to: CGPoint(x: x, y: top.y + totalH))
        }
        grid.stroke()

        // 편집 가능 단서 — 우상단에 연필. 정적인 이미지가 아니라 "탭하면 고친다"로 읽히게.
        if let pencil = UIImage(systemName: "square.and.pencil")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 12, weight: .regular))
            .withTintColor(UIColor(Palette.secondary), renderingMode: .alwaysOriginal) {
            pencil.draw(at: CGPoint(x: top.x + width - pencil.size.width - 6, y: top.y + 5))
        }
        ctx.restoreGState()
    }
}
