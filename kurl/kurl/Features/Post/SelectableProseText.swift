//
//  SelectableProseText.swift
//  kurl
//

import SwiftUI
import UIKit

/// 선택 가능한 본문 문단 — UITextView 로 감싸 (1) 길게 눌러 텍스트를 선택하고, (2) 선택 메뉴에
/// "하이라이트"를 더해 미디엄식 소셜 하이라이트를 만든다. SwiftUI `Text` 는 커스텀 선택 액션을
/// 달 수 없어 이 한 곳만 UIKit 으로 내려간다. 인라인 서식(볼드·이탤릭·인라인 코드·링크)은
/// `BlockRenderer.inline()` 과 같은 충실도로 NSAttributedString 으로 옮겨 본문과 결이 같다.
/// 기존 하이라이트는 인용-검색으로 그린 워시를 입힌다.
///
/// 기기 검증 필요 — 선택 제스처/편집 메뉴/페인트/높이 측정은 헤드리스로 확인 불가.
struct SelectableProseText: UIViewRepresentable {
    let raw: String
    let fontSize: CGFloat
    let textColor: Color
    let lineSpacing: CGFloat
    /// 이 문단에 칠할 인용들(블록 한정 인용-검색).
    let highlightQuotes: [String]
    /// 선택→하이라이트 콜백. nil 이면 메뉴에 항목을 넣지 않는다(게이트 없는 면).
    let onHighlight: ((_ startOffset: Int, _ endOffset: Int, _ quote: String) -> Void)?

    func makeUIView(context: Context) -> ProseTextView {
        let tv = ProseTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        // SwiftUI Text 와 엣지를 맞춘다 — UITextView 기본 인셋/패딩을 0 으로.
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.adjustsFontForContentSizeCategory = false
        tv.dataDetectorTypes = []
        tv.linkTextAttributes = [.foregroundColor: UIColor(Palette.link)]
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        tv.setContentHuggingPriority(.required, for: .vertical)
        tv.delegate = context.coordinator
        return tv
    }

    func updateUIView(_ tv: ProseTextView, context: Context) {
        tv.onHighlight = onHighlight
        let base = Self.attributed(
            raw, fontSize: fontSize, color: UIColor(textColor), lineSpacing: lineSpacing)
        let painted = NSMutableAttributedString(attributedString: base)
        let hay = painted.string as NSString
        let wash = UIColor(Palette.accent).withAlphaComponent(0.18)
        for quote in highlightQuotes where !quote.isEmpty {
            let range = hay.range(of: quote)
            if range.location != NSNotFound {
                painted.addAttribute(.backgroundColor, value: wash, range: range)
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

    final class Coordinator: NSObject, UITextViewDelegate {
        /// 선택 편집 메뉴에 "하이라이트"를 맨 앞에 더한다(복사 등 기본 항목은 그대로 둔다).
        func textView(
            _ textView: UITextView, editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard range.length > 0,
                  let tv = textView as? ProseTextView,
                  let onHighlight = tv.onHighlight
            else { return UIMenu(children: suggestedActions) }
            let quote = (textView.text as NSString).substring(with: range)
            let action = UIAction(
                title: String(localized: "하이라이트"),
                image: UIImage(systemName: "highlighter")
            ) { _ in
                onHighlight(range.location, range.location + range.length, quote)
                textView.selectedRange = NSRange(location: range.location + range.length, length: 0)
                textView.resignFirstResponder()
            }
            return UIMenu(children: [action] + suggestedActions)
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

/// onHighlight 를 담아 두는 UITextView — 코디네이터가 선택 메뉴에서 꺼내 쓴다.
final class ProseTextView: UITextView {
    var onHighlight: ((_ startOffset: Int, _ endOffset: Int, _ quote: String) -> Void)?
}
