//
//  SelectableProseText.swift
//  kurl
//

import SwiftUI
import UIKit

/// 선택 가능한 본문 문단 — UITextView 로 감싸 (1) 길게 눌러 텍스트를 선택하고, (2) 선택 메뉴에
/// "하이라이트"·"메모"를 더해 미디엄/Are.na식 소셜 하이라이트를 만든다. (3) 이미 칠해진
/// 하이라이트를 탭하면 그 답글 스레드를 연다. SwiftUI `Text` 는 커스텀 선택 액션을 달 수 없어
/// 이 한 곳만 UIKit 으로 내려간다. 인라인 서식은 `BlockRenderer.inline()` 과 같은 충실도.
///
/// 기기 검증 필요 — 선택 제스처/편집 메뉴/페인트/탭 히트테스트는 헤드리스로 확인 불가.
struct SelectableProseText: UIViewRepresentable {
    let raw: String
    let fontSize: CGFloat
    let textColor: Color
    let lineSpacing: CGFloat
    /// 이 문단에 칠할 하이라이트 — 저장된 오프셋으로 정밀하게, 어긋나면 인용 폴백.
    let highlights: [Mark]
    /// 선택→하이라이트(메모 없음). nil 이면 메뉴에 항목을 넣지 않는다(게이트 없는 면).
    let onHighlight: ((_ startOffset: Int, _ endOffset: Int, _ quote: String) -> Void)?
    /// 선택→메모 함께(여백 노트). nil 이면 "메모" 항목을 넣지 않는다.
    let onHighlightNote: ((_ startOffset: Int, _ endOffset: Int, _ quote: String) -> Void)?
    /// 칠해진 하이라이트 탭 → 그 답글 스레드 열기(highlight id).
    let onOpenThread: ((_ highlightId: Int64) -> Void)?

    /// 칠할 한 span — 렌더된 본문 텍스트 기준 문자 오프셋 [start, end) + 폴백용 인용. id 로 탭→스레드,
    /// hasThread 면 메모/답글이 있어 강조 밑줄을 더한다.
    struct Mark: Equatable {
        enum Segment: Equatable { case single, start, middle, end }
        let id: Int64
        let start: Int
        let end: Int
        let quote: String
        let hasThread: Bool
        var segment: Segment = .single
    }

    struct ResolvedMark: Equatable {
        let id: Int64
        let range: NSRange
        let hasThread: Bool
    }

    /// Locate the whole quoted passage, including inline formatting and paragraph boundaries.
    /// A repeated quote has no safe destination without its ID/offsets, so don't jump to the first.
    static func sourceBlockID(for quote: String, blocks: [(id: Int, raw: String)]) -> Int? {
        let needle = normalized(quote)
        guard !needle.isEmpty else { return nil }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var text = ""
        var ranges: [(id: Int, range: NSRange)] = []
        for block in blocks {
            let parsed = (try? AttributedString(markdown: block.raw, options: options)) ?? AttributedString(block.raw)
            let plain = normalized(String(parsed.characters))
            guard !plain.isEmpty else { continue }
            if !text.isEmpty { text += " " }
            let start = (text as NSString).length
            text += plain
            ranges.append((block.id, NSRange(location: start, length: (plain as NSString).length)))
        }
        guard let match = uniqueRange(of: needle, in: text as NSString) else { return nil }
        return ranges.first(where: { NSLocationInRange(match.location, $0.range) })?.id
    }

    /// Paint and tap share one verified range. Never fall back to an arbitrary first occurrence.
    /// A multi-block quote is validated against its relevant edge, rather than comparing each
    /// paragraph slice with the entire quote. Drifted multi-block offsets fail closed: one paragraph
    /// alone cannot safely reconstruct the other blocks' boundaries.
    static func resolve(_ mark: Mark, in text: NSString) -> ResolvedMark? {
        let quote = normalized(mark.quote)
        guard !quote.isEmpty else { return nil }
        if mark.start >= 0, mark.start < text.length {
            let end = min(mark.end, text.length)
            if end > mark.start {
                let range = NSRange(location: mark.start, length: end - mark.start)
                let fragment = normalized(text.substring(with: range))
                let matches: Bool
                switch mark.segment {
                case .single: matches = fragment == quote
                case .start: matches = !fragment.isEmpty && quote.hasPrefix(fragment)
                case .end: matches = !fragment.isEmpty && quote.hasSuffix(fragment)
                case .middle:
                    matches = !fragment.isEmpty && uniqueRange(of: fragment, in: quote as NSString) != nil
                }
                if matches { return ResolvedMark(id: mark.id, range: range, hasThread: mark.hasThread) }
            }
        }
        guard mark.segment == .single, let range = uniqueRange(of: mark.quote, in: text) else { return nil }
        return ResolvedMark(id: mark.id, range: range, hasThread: mark.hasThread)
    }

    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func uniqueRange(of quote: String, in text: NSString) -> NSRange? {
        guard !quote.isEmpty else { return nil }
        let first = text.range(of: quote)
        guard first.location != NSNotFound else { return nil }
        let next = first.location + 1 // also reject overlapping repeats
        if next < text.length,
           text.range(of: quote, range: NSRange(location: next, length: text.length - next)).location != NSNotFound {
            return nil
        }
        return first
    }

    func makeUIView(context: Context) -> ProseTextView {
        // TextKit1 — 탭 히트테스트(layoutManager.characterIndex)를 안정적으로 쓰기 위해.
        let tv = ProseTextView(usingTextLayoutManager: false)
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.adjustsFontForContentSizeCategory = false
        tv.dataDetectorTypes = []
        tv.linkTextAttributes = [.foregroundColor: UIColor(Palette.link)]
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        tv.setContentHuggingPriority(.required, for: .vertical)
        tv.delegate = context.coordinator
        // 칠해진 하이라이트 탭 → 스레드. 링크/선택을 막지 않게 cancelsTouchesInView=false.
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        tv.addGestureRecognizer(tap)
        // 롱프레스 = 문장 스냅(결정 B). 우리 편집 메뉴를 그 자리에 띄운다.
        let menu = UIEditMenuInteraction(delegate: context.coordinator)
        tv.addInteraction(menu)
        tv.highlightMenuInteraction = menu
        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        longPress.delegate = context.coordinator
        tv.addGestureRecognizer(longPress)
        return tv
    }

    func updateUIView(_ tv: ProseTextView, context: Context) {
        tv.onHighlight = onHighlight
        tv.onHighlightNote = onHighlightNote
        tv.onOpenThread = onOpenThread
        // 베이스(파싱된 본문)는 원문·크기·행간·색이 실제로 바뀔 때만 다시 만든다 — 하이라이트 토글·
        // 부모 무효화(다른 문단의 마크 변화 등)마다 마크다운을 재파싱하던 것을 막는다. 페인트 패스는
        // 아래에서 늘 새로 얹으므로(하이라이트만 바뀌어도) 재파싱 없이 span 만 다시 칠해진다.
        // 색은 동적 UIColor(스킴별 재해석)라 스킴이 바뀌어도 베이스는 그대로 유효 — 키에 넣지 않는다.
        let signature = Coordinator.BaseSignature(
            raw: raw, fontSize: fontSize, lineSpacing: lineSpacing, textColor: textColor)
        // 본문도 하이라이트도 그대로면 여기서 끝 — attributedText 를 다시 꽂지 않는다.
        // (재설정 자체가 TextKit 재조판이라, 무변경 update 스톰에서 이 한 줄이 프레임을 살린다.)
        if context.coordinator.lastPaintSignature == signature,
           context.coordinator.lastPaintMarks == highlights {
            Self.refreshAccessibilityActions(tv)
            return
        }
        let base: NSAttributedString
        if let cached = context.coordinator.baseCache, context.coordinator.baseSignature == signature {
            base = cached
        } else {
            base = Self.attributed(
                raw, fontSize: fontSize, color: UIColor(textColor), lineSpacing: lineSpacing)
            context.coordinator.baseCache = base
            context.coordinator.baseSignature = signature
        }
        let painted = NSMutableAttributedString(attributedString: base)
        let hay = painted.string as NSString
        let wash = UIColor(Palette.highlightWash)
        tv.resolvedMarks = highlights.compactMap { Self.resolve($0, in: hay) }
        for mark in tv.resolvedMarks {
            let range = mark.range
            painted.addAttribute(.backgroundColor, value: wash, range: range)
            // 낮춘 채움을 얇은 그린 밑줄로 보완 — 모든 하이라이트에 헤어라인 하나(놓칠 곳에서도 표식 유지).
            // 메모/답글이 달린 건 굵고 진한 밑줄로 올려 "탭하면 대화" 신호를 구분한다.
            painted.addAttribute(
                .underlineStyle,
                value: (mark.hasThread ? NSUnderlineStyle.thick : NSUnderlineStyle.single).rawValue,
                range: range)
            painted.addAttribute(
                .underlineColor,
                value: UIColor(mark.hasThread ? Palette.highlightUnderlineThread : Palette.highlightUnderline),
                range: range)
        }
        tv.attributedText = painted
        Self.refreshAccessibilityActions(tv)
        context.coordinator.lastPaintSignature = signature
        context.coordinator.lastPaintMarks = highlights
    }

    private static func refreshAccessibilityActions(_ tv: ProseTextView) {
        guard tv.onOpenThread != nil else {
            tv.accessibilityCustomActions = nil
            return
        }
        let hay = (tv.attributedText?.string ?? "") as NSString
        var seen: [String: Int] = [:]
        tv.accessibilityCustomActions = tv.resolvedMarks.map { mark in
            var snippet = String(hay.substring(with: mark.range).prefix(30))
            seen[snippet, default: 0] += 1
            if let n = seen[snippet], n > 1 { snippet += " (\(n))" }
            let name = mark.hasThread
                ? String(localized: "메모 열기: \(snippet)")
                : String(localized: "하이라이트 열기: \(snippet)")
            return UIAccessibilityCustomAction(name: name) { [weak tv] _ in
                guard let open = tv?.onOpenThread else { return false }
                open(mark.id)
                return true
            }
        }
    }

    /// 제안 폭에 맞춘 높이 — isScrollEnabled=false 라 본문 높이를 직접 재서 돌려준다.
    func sizeThatFits(
        _ proposal: ProposedViewSize, uiView: ProseTextView, context: Context
    ) -> CGSize? {
        let width: CGFloat
        if let w = proposal.width, w.isFinite, w > 0 {
            width = w
        } else {
            width = uiView.bounds.width > 0 ? uiView.bounds.width : 320
        }
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fit.height))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate,
        UIEditMenuInteractionDelegate {
        /// 마지막으로 파싱한 베이스 본문과 그 입력 — 입력이 그대로면 재파싱을 건너뛴다.
        var baseCache: NSAttributedString?
        var baseSignature: BaseSignature?

        /// 마지막으로 tv.attributedText 에 실제 반영한 입력(베이스+하이라이트). 이 둘이 그대로면
        /// 페인트·재설정을 통째로 건너뛴다 — attributedText 재설정은 TextKit 전체 재레이아웃이라,
        /// 부모 body 무효화(스크롤 중 탭바 신호·크롬 토글 등)마다 보이는 모든 문단이 다시
        /// 조판되며 긴 글이 프레임 단위로 버벅였다(실기기 "글 길면 렉"의 핵심 비용).
        var lastPaintSignature: BaseSignature?
        var lastPaintMarks: [Mark]?

        /// 베이스 본문을 결정하는 입력. 이 넷이 같으면 파싱 결과도 같다(색은 동적이라 제외).
        struct BaseSignature: Equatable {
            let raw: String
            let fontSize: CGFloat
            let lineSpacing: CGFloat
            let textColor: Color
        }

        /// 선택 편집 메뉴에 "하이라이트"·"메모"를 맨 앞에 더한다(복사 등 기본 항목은 그대로).
        /// 더블탭/드래그(기본 편집 메뉴) 경로.
        func textView(
            _ textView: UITextView, editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard range.length > 0, let tv = textView as? ProseTextView else {
                return UIMenu(children: suggestedActions)
            }
            return UIMenu(children: highlightActions(tv: tv, range: range) + suggestedActions)
        }

        /// 선택 구간의 "하이라이트"·"메모" 액션 — 더블탭(기본 메뉴)과 롱프레스(문장 스냅, 우리
        /// UIEditMenuInteraction)가 공유한다. quote 는 호출 시점에 굳혀 둔다(선택이 바뀌어도 일관).
        private func highlightActions(tv: ProseTextView, range: NSRange) -> [UIMenuElement] {
            let text = tv.text as NSString
            guard range.location >= 0, range.location <= text.length,
                  range.length > 0, range.length <= text.length - range.location else { return [] }
            guard range.length <= HighlightsAPI.maxQuoteLength else {
                return [UIAction(title: String(localized: "1,000자 이내로 선택해 주세요."), attributes: .disabled) { _ in }]
            }
            let quote = text.substring(with: range)
            let after = NSRange(location: range.location + range.length, length: 0)
            var actions: [UIMenuElement] = []
            if let onHighlight = tv.onHighlight {
                actions.append(UIAction(title: String(localized: "하이라이트"), image: UIImage(systemName: "highlighter")) { _ in
                    onHighlight(range.location, range.location + range.length, quote)
                    tv.selectedRange = after
                    tv.resignFirstResponder()
                })
            }
            if let onNote = tv.onHighlightNote {
                actions.append(UIAction(title: String(localized: "메모"), image: UIImage(systemName: "text.bubble")) { _ in
                    onNote(range.location, range.location + range.length, quote)
                    tv.selectedRange = after
                    tv.resignFirstResponder()
                })
            }
            return actions
        }

        // MARK: 롱프레스 = 문장 스냅 (결정 B)

        /// 길게 누르면 그 지점이 속한 문장 전체를 선택하고, 우리 편집 메뉴를 그 자리에 띄운다.
        /// 더블탭(단어)·드래그(임의 범위)는 UITextView 기본 동작 그대로.
        @objc func handleLongPress(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let tv = g.view as? ProseTextView,
                  tv.onHighlight != nil || tv.onHighlightNote != nil else { return }
            let ns = tv.text as NSString
            guard ns.length > 0 else { return }
            let lm = tv.layoutManager
            var point = g.location(in: tv)
            point.x -= tv.textContainerInset.left
            point.y -= tv.textContainerInset.top
            let glyph = lm.glyphIndex(for: point, in: tv.textContainer)
            guard glyph < lm.numberOfGlyphs else { return }
            let charIndex = min(lm.characterIndexForGlyph(at: glyph), ns.length - 1)
            let range = Self.sentenceRange(in: ns, around: charIndex)
            guard range.length > 0 else { return }
            tv.becomeFirstResponder()
            tv.selectedRange = range
            let cfg = UIEditMenuConfiguration(identifier: nil, sourcePoint: g.location(in: tv))
            tv.highlightMenuInteraction?.presentEditMenu(with: cfg)
        }

        /// 인덱스가 속한 문장 범위 — 끝의 공백·줄바꿈은 떼어 선택이 다음 문장으로 새지 않게.
        static func sentenceRange(in text: NSString, around index: Int) -> NSRange {
            var result = NSRange(location: index, length: 0)
            text.enumerateSubstrings(
                in: NSRange(location: 0, length: text.length), options: .bySentences
            ) { _, sub, _, stop in
                if index >= sub.location, index < sub.location + sub.length {
                    result = sub
                    stop.pointee = true
                }
            }
            while result.length > 0 {
                let c = text.character(at: result.location + result.length - 1)
                if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D { result.length -= 1 } else { break }
            }
            return result
        }

        /// 롱프레스로 띄운 우리 메뉴 — 현재(문장) 선택에 하이라이트/메모 + 기본 항목.
        func editMenuInteraction(
            _ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard let tv = interaction.view as? ProseTextView, tv.selectedRange.length > 0 else {
                return UIMenu(children: suggestedActions)
            }
            return UIMenu(children: highlightActions(tv: tv, range: tv.selectedRange) + suggestedActions)
        }

        /// 우리 롱프레스가 UITextView 기본 제스처와 함께 인식되게(기본 selection 과 경쟁 안 함).
        func gestureRecognizer(
            _ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        /// 칠해진 하이라이트를 탭 → 그 스레드 열기. 글자 위가 아닌 탭(빈 줄·여백)은 무시.
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let tv = gesture.view as? ProseTextView, let onOpen = tv.onOpenThread, !tv.resolvedMarks.isEmpty else { return }
            let lm = tv.layoutManager
            var point = gesture.location(in: tv)
            point.x -= tv.textContainerInset.left
            point.y -= tv.textContainerInset.top
            let glyph = lm.glyphIndex(for: point, in: tv.textContainer)
            guard glyph < lm.numberOfGlyphs else { return }
            let rect = lm.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: tv.textContainer)
            guard rect.contains(point) else { return }
            let charIndex = lm.characterIndexForGlyph(at: glyph)
            if let mark = tv.resolvedMarks.first(where: { NSLocationInRange(charIndex, $0.range) }) {
                onOpen(mark.id)
            }
        }
    }

    /// raw(인라인 마크다운) → NSAttributedString. `BlockRenderer.inline()` 과 같은 처리:
    /// 볼드·이탤릭·인라인 코드(모노+칩 배경)·링크 색. 본문 폰트/색/행간을 베이스로 깐다.
    static func attributed(
        _ raw: String, fontSize: CGFloat, color: UIColor, lineSpacing: CGFloat
    ) -> NSAttributedString {
        let baseFont = UIFont.systemFont(ofSize: fontSize)
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let parsed = (try? AttributedString(markdown: raw, options: options))
            ?? AttributedString(raw)
        let out = NSMutableAttributedString()
        for run in parsed.runs {
            let piece = String(parsed[run.range].characters)
            var attrs: [NSAttributedString.Key: Any] = [.font: baseFont, .foregroundColor: color]
            var traits: UIFontDescriptor.SymbolicTraits = []
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
                if intent.contains(.emphasized) { traits.insert(.traitItalic) }
                if intent.contains(.code) {
                    attrs[.font] = UIFont.monospacedSystemFont(
                        ofSize: fontSize * 0.92, weight: .regular)
                    attrs[.foregroundColor] = UIColor(Palette.ink)
                    attrs[.backgroundColor] = UIColor(Palette.chipBg)
                }
            }
            if !traits.isEmpty,
               let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) {
                attrs[.font] = UIFont(descriptor: descriptor, size: fontSize)
            }
            if let link = run.link {
                attrs[.link] = link
            }
            out.append(NSAttributedString(string: piece, attributes: attrs))
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        out.addAttribute(
            .paragraphStyle, value: paragraph, range: NSRange(location: 0, length: out.length))
        return out
    }
}

/// 코디네이터가 선택 메뉴·탭에서 꺼내 쓰는 콜백·마크를 담아 두는 UITextView.
final class ProseTextView: UITextView {
    var onHighlight: ((_ startOffset: Int, _ endOffset: Int, _ quote: String) -> Void)?
    var onHighlightNote: ((_ startOffset: Int, _ endOffset: Int, _ quote: String) -> Void)?
    var onOpenThread: ((_ highlightId: Int64) -> Void)?
    var resolvedMarks: [SelectableProseText.ResolvedMark] = []
    /// 롱프레스(문장 스냅)가 띄우는 편집 메뉴 인터랙션.
    var highlightMenuInteraction: UIEditMenuInteraction?
}
