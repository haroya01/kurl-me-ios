//
//  BlockInlineRenderer.swift
//  kurl — WriteV2
//
//  블록 text(인라인 마크다운) → 최종 모습 NSAttributedString. 블록 종류가 크기·색·인용 스타일을
//  정하고, 인라인 `**볼드**`/`*이탤릭*`/`` `코드` ``/`[라벨](url)` 은 볼드/이탤릭/모노 칩/링크색으로
//  렌더한다. 색·크기는 전부 앱 토큰(Palette / BlockRenderer 읽기 스케일)에서 — raw 헥스·raw .red
//  금지(§색 규율).
//
//  라이브 렌더(반개봉): 마커 글자(`**`·`*`·`` ` ``·`[ ]( url )`)는 기본으로 **숨긴다**(clear+0.01pt).
//  캐럿(또는 선택)이 그 마크업 범위에 걸치면 그 범위만 마커를 **흐리게 노출**해 편집할 수 있게 한다
//  — MarkdownSyntaxHighlighter 의 reveal 관습과 같다. 이렇게 이탤릭·링크가 원문이 아니라 최종
//  모습으로 보이되, 커서를 넣으면 마크업이 반쯤 열려 손볼 수 있다.
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

    /// 블록 → 렌더된 속성 문자열(최종 모습). `activeRange` 는 캐럿/선택(블록 text 의 NSString 범위) —
    /// 그 범위에 걸친 마크업만 마커를 흐리게 노출하고, 나머지 마커는 숨긴다(반개봉). nil 이면 전부 숨긴다.
    static func render(_ block: EditorBlock, activeRange: NSRange? = nil) -> NSAttributedString {
        let base = typingAttributes(for: block.kind)
        let result = NSMutableAttributedString(string: block.text, attributes: base)
        applyInline(result, base: block.kind, activeRange: activeRange)
        return result
    }

    /// 캐럿(NSString 오프셋)이 걸친 인라인 마크업 span(`**볼드**`·`*이탤릭*`·`` `코드` ``·`[라벨](url)`),
    /// 없으면 nil. 뷰가 "캐럿 이동이 반개봉 상태를 실제 바꿨나"를 싸게 판단해 불필요한 재렌더를 거르는 데 쓴다.
    /// 인라인 문법은 블록 종류와 무관하므로 text·caret 만 본다.
    static func activeMarkupSpan(in text: String, caret: Int) -> NSRange? {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        func touches(_ span: NSRange) -> Bool {
            caret >= span.location && caret <= span.location + span.length
        }
        for regex in [codeRegex, linkRegex, boldRegex, italicRegex] {
            var found: NSRange?
            enumerate(regex, ns, full) { m in
                if found == nil, touches(m.range) { found = m.range }
            }
            if let found { return found }
        }
        return nil
    }

    // MARK: 인라인 — `**볼드**` · `*이탤릭*` · `` `코드` `` · `[라벨](url)`

    private static func applyInline(
        _ s: NSMutableAttributedString, base kind: EditorBlockKind, activeRange: NSRange?
    ) {
        let ns = s.string as NSString
        let full = NSRange(location: 0, length: ns.length)
        var codeRanges: [NSRange] = []
        // 링크의 url 부분(`](url)`)엔 `*`·`**` 가 들어갈 수 있는데, 그건 링크 문법이지 강조가 아니다.
        // 볼드/이탤릭 패스가 url 안 별표를 강조로 오인해 마커를 지우면 url 이 깨져 보이므로, 링크
        // 매치 전체를 강조 제외 범위로 모은다(코드 범위와 같은 취급).
        var linkRanges: [NSRange] = []

        // 인라인 코드 먼저(안쪽 강조 무시) — 모노 + 옅은 칩.
        enumerate(Self.codeRegex, ns, full) { m in
            let inner = m.range(at: 1)
            s.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular), range: inner)
            s.addAttribute(.foregroundColor, value: UIColor(Palette.inlineCodeText), range: inner)
            s.addAttribute(.backgroundColor, value: UIColor(Palette.inlineCodeBg), range: inner)
            markersAround(s, span: m.range, inner: inner, activeRange: activeRange)
            codeRanges.append(m.range)
        }

        // [라벨](url) — 라벨은 링크색, `[` `](` `url` `)` 은 숨김/노출. 코드 범위와 겹치면 건너뜀.
        enumerate(Self.linkRegex, ns, full) { m in
            if intersectsAny(m.range, codeRanges) { return }
            linkRanges.append(m.range)
            let label = m.range(at: 1)
            s.addAttribute(.foregroundColor, value: UIColor(Palette.link), range: label)
            // 마크업 전체(`[…](…)`)에 캐럿이 걸치면 두 조각을 함께 노출한다(한쪽만 열리면 어색).
            let revealed = reveal(m.range, activeRange: activeRange)
            let leadLen = label.location - m.range.location
            marker(s, NSRange(location: m.range.location, length: leadLen), reveal: revealed)
            let labelEnd = label.location + label.length
            let tailLen = m.range.location + m.range.length - labelEnd
            marker(s, NSRange(location: labelEnd, length: tailLen), reveal: revealed)
        }

        // **볼드** — 코드·링크(url) 범위와 겹치면 건너뜀.
        enumerate(Self.boldRegex, ns, full) { m in
            if intersectsAny(m.range, codeRanges) || intersectsAny(m.range, linkRanges) { return }
            addTrait(s, .traitBold, range: m.range(at: 1))
            markersAround(s, span: m.range, inner: m.range(at: 1), activeRange: activeRange)
        }
        // *이탤릭* (단일 별표) — 코드·링크(url) 범위와 겹치면 건너뜀.
        enumerate(Self.italicRegex, ns, full) { m in
            if intersectsAny(m.range, codeRanges) || intersectsAny(m.range, linkRanges) { return }
            addTrait(s, .traitItalic, range: m.range(at: 1))
            markersAround(s, span: m.range, inner: m.range(at: 1), activeRange: activeRange)
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

    /// 마커 한 조각을 숨기거나(clear + 0.01pt, 거의 0 폭) 흐리게 노출(faint) — 노출 여부는 호출자가
    /// 마크업 전체 기준으로 한 번 정해 넘긴다. MarkdownSyntaxHighlighter.marker(reveal:) 와 동형.
    private static func marker(_ s: NSMutableAttributedString, _ range: NSRange, reveal: Bool) {
        guard range.length > 0 else { return }
        if reveal {
            s.addAttribute(.foregroundColor, value: UIColor(Palette.faint), range: range)
        } else {
            s.addAttribute(.foregroundColor, value: UIColor.clear, range: range)
            s.addAttribute(.font, value: UIFont.systemFont(ofSize: 0.01), range: range)
        }
    }

    /// 마크업 span 에서 inner(내용)를 뺀 좌우(마커)를 숨김/노출. 노출은 span 전체 기준으로 한 번 판정해
    /// 두 마커가 항상 함께 열리고 닫히게 한다(한쪽만 열리면 어색).
    private static func markersAround(
        _ s: NSMutableAttributedString, span: NSRange, inner: NSRange, activeRange: NSRange?
    ) {
        let revealed = reveal(span, activeRange: activeRange)
        let leftLen = inner.location - span.location
        marker(s, NSRange(location: span.location, length: leftLen), reveal: revealed)
        let innerEnd = inner.location + inner.length
        let rightLen = span.location + span.length - innerEnd
        marker(s, NSRange(location: innerEnd, length: rightLen), reveal: revealed)
    }

    /// 캐럿/선택이 이 마크업 span 에 걸치는가. 캐럿(길이 0)이 span 의 어느 경계에 닿기만 해도(양 끝
    /// 포함) 노출한다 — 끝에 캐럿을 두고도 마커를 손볼 수 있게. 선택이면 span 과 겹치면 노출. 밖이면 숨김.
    private static func reveal(_ span: NSRange, activeRange: NSRange?) -> Bool {
        guard let a = activeRange else { return false }
        if a.length == 0 {
            return a.location >= span.location && a.location <= span.location + span.length
        }
        return NSIntersectionRange(span, a).length > 0
    }

    private static func intersectsAny(_ range: NSRange, _ others: [NSRange]) -> Bool {
        others.contains { NSIntersectionRange($0, range).length > 0 }
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
    private static let linkRegex = make("\\[([^\\]\\n]+)\\]\\([^)\\n]+\\)")

    private static func make(_ pattern: String) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern)
    }
}
