//
//  BlockInlineRenderer.swift
//  kurl — WriteV2
//
//  블록 text(인라인 마크다운) → 최종 모습 NSAttributedString. 블록 종류가 크기·색·인용 스타일을
//  정하고, 인라인 `**볼드**`/`*이탤릭*`/`` `코드` `` 은 볼드/이탤릭/모노 칩으로 렌더한다.
//  색·크기는 전부 앱 토큰(Palette / BlockRenderer 읽기 스케일)에서 — raw 헥스·raw .red 금지(§색 규율).
//
//  Phase 1 은 인라인 "마커 은닉"까지는 안 한다(입력 지름길로 종류를 바꾸는 게 핵심 증명).
//  볼드는 마커(`**`)를 흐리게 남기고 안쪽만 볼드로 — MarkdownSyntaxHighlighter 와 같은 관습.
//

import SwiftUI
import UIKit

enum BlockInlineRenderer {
    // 읽기 스케일과 맞춘 블록 폰트(BlockRenderer 의 h1 27 / h2 23 / h3 19 / body 18 을 반영).
    private static func baseFont(for kind: EditorBlockKind) -> UIFont {
        switch kind {
        case .heading(let level):
            let size: CGFloat = level == 1 ? 27 : level == 2 ? 23 : 19
            let weight: UIFont.Weight = level <= 2 ? .bold : .semibold
            return UIFontMetrics(forTextStyle: .title1)
                .scaledFont(for: .systemFont(ofSize: size, weight: weight))
        case .quote:
            let body = UIFont.systemFont(ofSize: 18)
            let italic = body.fontDescriptor.withSymbolicTraits(.traitItalic).map {
                UIFont(descriptor: $0, size: 18)
            } ?? body
            return UIFontMetrics(forTextStyle: .body).scaledFont(for: italic)
        case .code:
            return UIFontMetrics(forTextStyle: .body)
                .scaledFont(for: .monospacedSystemFont(ofSize: 14, weight: .regular))
        case .paragraph, .listItem, .divider, .image, .table:
            // 리스트 항목 본문은 문단과 같은 읽기 스케일(18). 비텍스트 블록은 이 렌더를 안 쓰지만
            // switch 완결을 위해 문단 기본을 준다.
            return UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 18))
        }
    }

    private static func baseColor(for kind: EditorBlockKind) -> UIColor {
        switch kind {
        case .heading: return UIColor(Palette.ink)
        case .quote: return UIColor(Palette.secondary)
        case .code: return UIColor(Palette.codeText)
        case .paragraph, .listItem, .divider, .image, .table: return UIColor(Palette.body)
        }
    }

    /// 새 타이핑이 이어받을 속성(폰트·색) — 종류가 정한다.
    static func typingAttributes(for kind: EditorBlockKind) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: baseFont(for: kind),
            .foregroundColor: baseColor(for: kind),
        ]
        let ps = NSMutableParagraphStyle()
        switch kind {
        case .quote:
            ps.firstLineHeadIndent = 20
            ps.headIndent = 20
            ps.lineSpacing = 6
        case .paragraph, .listItem:
            ps.lineSpacing = 7
        case .heading:
            ps.lineSpacing = 2
        case .code:
            ps.lineSpacing = 3
        case .divider, .image, .table:
            break  // 비텍스트 — 이 경로를 안 탄다(뷰가 전용 렌더).
        }
        attrs[.paragraphStyle] = ps
        return attrs
    }

    /// 블록 → 렌더된 속성 문자열(최종 모습). 인라인 마커는 흐리게(faint), 안쪽만 스타일.
    static func render(_ block: EditorBlock) -> NSAttributedString {
        let base = typingAttributes(for: block.kind)
        let result = NSMutableAttributedString(string: block.text, attributes: base)
        applyInline(result, base: block.kind)
        return result
    }

    // MARK: 인라인 — `**볼드**` · `*이탤릭*` · `` `코드` ``

    private static func applyInline(_ s: NSMutableAttributedString, base kind: EditorBlockKind) {
        let ns = s.string as NSString
        let full = NSRange(location: 0, length: ns.length)
        let faint = UIColor(Palette.faint)

        // 인라인 코드 먼저(안쪽 강조 무시) — 모노 + 옅은 칩.
        enumerate(Self.codeRegex, ns, full) { m in
            let inner = m.range(at: 1)
            s.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular), range: inner)
            s.addAttribute(.foregroundColor, value: UIColor(Palette.inlineCodeText), range: inner)
            s.addAttribute(.backgroundColor, value: UIColor(Palette.inlineCodeBg), range: inner)
            dimMarkers(s, full: m.range, inner: inner, color: faint)
        }
        // **볼드**
        enumerate(Self.boldRegex, ns, full) { m in
            addTrait(s, .traitBold, range: m.range(at: 1))
            dimMarkers(s, full: m.range, inner: m.range(at: 1), color: faint)
        }
        // *이탤릭* (단일 별표)
        enumerate(Self.italicRegex, ns, full) { m in
            addTrait(s, .traitItalic, range: m.range(at: 1))
            dimMarkers(s, full: m.range, inner: m.range(at: 1), color: faint)
        }
    }

    private static func addTrait(
        _ s: NSMutableAttributedString, _ trait: UIFontDescriptor.SymbolicTraits, range: NSRange
    ) {
        guard range.length > 0 else { return }
        s.enumerateAttribute(.font, in: range, options: []) { value, sub, _ in
            let font = (value as? UIFont) ?? UIFont.systemFont(ofSize: 18)
            let traits = font.fontDescriptor.symbolicTraits.union(trait)
            if let d = font.fontDescriptor.withSymbolicTraits(traits) {
                s.addAttribute(.font, value: UIFont(descriptor: d, size: font.pointSize), range: sub)
            }
        }
    }

    private static func dimMarkers(
        _ s: NSMutableAttributedString, full: NSRange, inner: NSRange, color: UIColor
    ) {
        let leftLen = inner.location - full.location
        if leftLen > 0 {
            s.addAttribute(.foregroundColor, value: color, range: NSRange(location: full.location, length: leftLen))
        }
        let innerEnd = inner.location + inner.length
        let rightLen = full.location + full.length - innerEnd
        if rightLen > 0 {
            s.addAttribute(.foregroundColor, value: color, range: NSRange(location: innerEnd, length: rightLen))
        }
    }

    private static func enumerate(
        _ regex: NSRegularExpression, _ ns: NSString, _ range: NSRange,
        _ body: (NSTextCheckingResult) -> Void
    ) {
        regex.enumerateMatches(in: ns as String, options: [], range: range) { m, _, _ in
            if let m { body(m) }
        }
    }

    // 방언과 동일한 인라인 정규식(MarkdownSyntaxHighlighter Regex 미러).
    private static let codeRegex = make("`([^`\\n]+)`")
    private static let boldRegex = make("\\*\\*([^*\\n]+)\\*\\*")
    private static let italicRegex = make("(?<![*\\w])\\*([^*\\n]+)\\*(?![*\\w])")

    private static func make(_ pattern: String) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern)
    }
}
