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
        let id: Int64
        let start: Int
        let end: Int
        let quote: String
        let hasThread: Bool
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
        tv.marks = highlights
        let base = Self.attributed(
            raw, fontSize: fontSize, color: UIColor(textColor), lineSpacing: lineSpacing)
        let painted = NSMutableAttributedString(attributedString: base)
        let hay = painted.string as NSString
        let total = painted.length
        let wash = UIColor(Palette.accent).withAlphaComponent(0.18)
        for mark in highlights {
            var painted_range: NSRange?
            // 정밀: 저장된 오프셋이 이 렌더 텍스트에 들어맞으면 그 span 을 칠한다(서식 교차 포함).
            // end 는 본문 길이로 clamp — 다중 블록의 "이 블록 끝까지"(Int.max)를 처리한다.
            if mark.start >= 0, mark.start < total {
                let end = min(mark.end, total)
                if mark.start < end {
                    painted_range = NSRange(location: mark.start, length: end - mark.start)
                }
            }
            if painted_range == nil, !mark.quote.isEmpty {
                // 폴백: 오프셋이 본문 수정으로 어긋났을 때 인용 텍스트로.
                let range = hay.range(of: mark.quote)
                if range.location != NSNotFound { painted_range = range }
            }
            guard let range = painted_range else { continue }
            painted.addAttribute(.backgroundColor, value: wash, range: range)
            // 메모/답글이 있는 하이라이트엔 강조 밑줄 — "탭하면 대화" 신호.
            if mark.hasThread {
                painted.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                painted.addAttribute(.underlineColor, value: UIColor(Palette.accent), range: range)
            }
        }
        tv.attributedText = painted
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
            let quote = (tv.text as NSString).substring(with: range)
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
            guard let tv = gesture.view as? ProseTextView, let onOpen = tv.onOpenThread, !tv.marks.isEmpty else { return }
            let lm = tv.layoutManager
            var point = gesture.location(in: tv)
            point.x -= tv.textContainerInset.left
            point.y -= tv.textContainerInset.top
            let glyph = lm.glyphIndex(for: point, in: tv.textContainer)
            let rect = lm.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: tv.textContainer)
            guard rect.contains(point) else { return }
            let charIndex = lm.characterIndexForGlyph(at: glyph)
            if let mark = tv.marks.first(where: { $0.start >= 0 && $0.start <= charIndex && charIndex < $0.end }) {
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
    var marks: [SelectableProseText.Mark] = []
    /// 롱프레스(문장 스냅)가 띄우는 편집 메뉴 인터랙션.
    var highlightMenuInteraction: UIEditMenuInteraction?
}
