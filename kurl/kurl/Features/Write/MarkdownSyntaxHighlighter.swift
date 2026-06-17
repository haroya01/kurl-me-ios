//
//  MarkdownSyntaxHighlighter.swift
//  kurl
//

import SwiftUI
import UIKit

/// 작성 화면 라이브 렌더 — 치는 즉시 마크다운이 보이는 모습으로 입혀진다(iA Writer/Bear 식).
/// 제목 줄은 크게·굵게, `**굵게**`는 굵게, `*기울임*`은 기울임, `` `코드` ``·코드펜스는 코드색,
/// `>` 인용·`-`/`1.` 리스트 마커는 강조색으로, 문법 마커(#, **, > …)는 흐리게 남는다.
/// 텍스트는 건드리지 않고 `textStorage` 의 속성만 바꾼다 — 그래서 발행 본문(서버 md→blocks)과
/// 1:1 로 유지되고, 한글 IME 조합(markedText)을 깨지 않는다(조합 중에는 적용을 보류).
@MainActor
enum MarkdownSyntaxHighlighter {
    /// 캔버스 본문 폰트(모노) — 기존 MarkdownTextView 와 동일 기준.
    static func bodyFont() -> UIFont {
        UIFontMetrics(forTextStyle: .body)
            .scaledFont(for: .monospacedSystemFont(ofSize: 16, weight: .regular))
    }

    static func baseAttributes() -> [NSAttributedString.Key: Any] {
        [.font: bodyFont(), .foregroundColor: UIColor(Palette.body)]
    }

    /// 현재 텍스트 전체에 마크다운 스타일을 다시 입힌다. 조합 중엔 손대지 않는다.
    static func apply(to textView: UITextView) {
        guard textView.markedTextRange == nil else { return }
        let ns = textView.text as NSString
        let full = NSRange(location: 0, length: ns.length)
        let base = baseAttributes()
        guard full.length > 0 else {
            textView.typingAttributes = base
            return
        }
        let storage = textView.textStorage
        let selected = textView.selectedRange
        storage.beginEditing()
        storage.setAttributes(base, range: full)
        styleLines(storage, ns)
        let pad = textView.textContainer.lineFragmentPadding
        let cw = textView.textContainer.size.width
        let avail = max(0, (cw.isFinite && cw > 1 ? cw : textView.bounds.width) - pad * 2)
        applyImages(storage, ns, width: avail)
        storage.endEditing()
        // 속성만 바꿔 길이는 그대로지만, 캐럿을 한 번 더 못박아 둔다.
        if selected.location <= ns.length {
            textView.selectedRange = selected
        }
        // 다음 입력은 base 로 시작 → 다음 변경에서 다시 정확히 입혀진다(헤딩 줄 안이라도).
        textView.typingAttributes = base
    }

    // MARK: 줄 단위 — 헤딩·인용·리스트·코드펜스

    private static func styleLines(_ storage: NSTextStorage, _ ns: NSString) {
        var inFence = false
        ns.enumerateSubstrings(
            in: NSRange(location: 0, length: ns.length), options: [.byLines]
        ) { line, lineRange, _, _ in
            guard let line else { return }

            // ``` 코드펜스 — 펜스 줄과 그 안쪽을 어두운 코드 박스로(발행면과 같은 모습). 펜스는 흐린 라벨.
            if line.hasPrefix("```") {
                storage.addAttribute(.backgroundColor, value: UIColor(Palette.codeBg), range: lineRange)
                storage.addAttribute(.foregroundColor, value: UIColor(Palette.codeText).withAlphaComponent(0.5), range: lineRange)
                inFence.toggle()
                return
            }
            if inFence {
                storage.addAttribute(.backgroundColor, value: UIColor(Palette.codeBg), range: lineRange)
                storage.addAttribute(.foregroundColor, value: UIColor(Palette.codeText), range: lineRange)
                return
            }

            // # / ## / ### + 공백 → 제목(크게·굵게). 마커는 흐리게.
            let hashes = line.prefix(while: { $0 == "#" }).count
            if hashes >= 1, hashes <= 3, line.dropFirst(hashes).first == " " {
                applyHeading(storage, lineRange, level: hashes)
                applyInline(storage, ns, lineRange) // 제목 안의 **굵게** 등도 살려둔다(크기 유지).
                return
            }

            // > 인용 → 들여쓰기 + 옅은 그린 패널 + 인용색, 마커 흐리게. 발행본(좌측 그린 바 인용구)의
            // 에디터 대응 — 예전엔 글자색만 secondary 로 바꿔 평문과 구분이 안 갔다(인용 친 게 안 보임).
            // 헤딩(크기)·코드(박스)처럼 인용도 한눈에 블록으로 읽히게 들여쓰기+그린 틴트를 더한다.
            if line == ">" || line.hasPrefix("> ") {
                let quoteStyle = NSMutableParagraphStyle()
                quoteStyle.firstLineHeadIndent = 14
                quoteStyle.headIndent = 14
                storage.addAttribute(.paragraphStyle, value: quoteStyle, range: lineRange)
                storage.addAttribute(.backgroundColor, value: UIColor(Palette.accent).withAlphaComponent(0.10), range: lineRange)
                storage.addAttribute(.foregroundColor, value: UIColor(Palette.secondary), range: lineRange)
                dim(storage, NSRange(location: lineRange.location, length: min(2, lineRange.length)))
                applyInline(storage, ns, lineRange)
                return
            }

            // -, * 글머리 / 1. 번호 리스트 → 마커만 강조색.
            if let markerLen = listMarkerLength(line) {
                let markerRange = NSRange(location: lineRange.location, length: min(markerLen, lineRange.length))
                storage.addAttribute(.foregroundColor, value: UIColor(Palette.accentMarker), range: markerRange)
            }

            applyInline(storage, ns, lineRange)
        }
    }

    /// `![alt](url)` — URL 표식(.kurlImageURL)을 붙이고 마크다운 문법은 흐리게, 그 줄 아래에
    /// 썸네일 높이만큼 paragraphSpacing 으로 공간을 확보한다(레이아웃 매니저가 그 자리에 그린다).
    /// 본문 텍스트(`![](url)`)는 그대로 남아 마크다운 원문·자동저장이 깨지지 않는다.
    private static func applyImages(_ storage: NSTextStorage, _ ns: NSString, width: CGFloat) {
        let full = NSRange(location: 0, length: ns.length)
        Regex.image.enumerateMatches(in: ns as String, range: full) { match, _, _ in
            guard let match else { return }
            let urlRange = match.range(at: 1)
            guard urlRange.location != NSNotFound else { return }
            let urlString = ns.substring(with: urlRange)
            storage.addAttribute(.kurlImageURL, value: urlString, range: match.range)
            // 마크다운(`![](url)`)은 숨긴다 — 에디터엔 사진만 보이게(WYSIWYG처럼). 원문 텍스트는
            // 그대로 남아 자동저장·동기화는 불변. 투명색 + 1pt 폰트로 그 줄을 거의 0 높이로 접어,
            // 아래 예약 공간(paragraphSpacing)에 그려지는 이미지만 남는다.
            storage.addAttribute(.foregroundColor, value: UIColor.clear, range: match.range)
            storage.addAttribute(.font, value: UIFont.systemFont(ofSize: 1), range: match.range)
            let para = ns.paragraphRange(for: match.range)
            let ps = NSMutableParagraphStyle()
            // 로드 전엔 placeholder, 로드 후엔 실제 비율 높이(onImageLoad 가 재하이라이트로 갱신).
            ps.paragraphSpacing =
                URL(string: urlString).map { MarkdownImage.reservedHeight(for: $0, width: width) }
                ?? MarkdownImage.placeholderHeight
            storage.addAttribute(.paragraphStyle, value: ps, range: para)
        }
    }

    private static func applyHeading(_ storage: NSTextStorage, _ lineRange: NSRange, level: Int) {
        let size: CGFloat = level == 1 ? 25 : level == 2 ? 21 : 18
        let font = UIFontMetrics(forTextStyle: .body)
            .scaledFont(for: .monospacedSystemFont(ofSize: size, weight: .bold))
        storage.addAttribute(.font, value: font, range: lineRange)
        storage.addAttribute(.foregroundColor, value: UIColor(Palette.ink), range: lineRange)
        // 흐린 마커(#... + 공백 하나)는 색만 죽이고 크기는 유지해 본문 정렬을 안 깬다.
        let markerLen = min(level + 1, lineRange.length)
        dim(storage, NSRange(location: lineRange.location, length: markerLen))
    }

    /// "- " · "* " · "1. " 형태의 줄머리 길이(공백 포함). 아니면 nil.
    private static func listMarkerLength(_ line: String) -> Int? {
        // 선행 공백(중첩 들여쓰기)을 건너뛴 뒤 마커 — 들여쓴 하위 항목도 마커가 강조된다.
        let lead = line.prefix(while: { $0 == " " }).count
        let body = line.dropFirst(lead)
        if body.hasPrefix("- ") || body.hasPrefix("* ") { return lead + 2 }
        // 1. / 12. 처럼 숫자 + 점 + 공백
        let digits = body.prefix(while: { $0.isNumber }).count
        if digits >= 1 {
            let rest = body.dropFirst(digits)
            if rest.first == ".", rest.dropFirst().first == " " { return lead + digits + 2 }
        }
        return nil
    }

    // MARK: 인라인 — `코드` · **굵게** · *기울임* · ~~취소선~~ · [라벨](url)

    private static func applyInline(_ storage: NSTextStorage, _ ns: NSString, _ range: NSRange) {
        var codeRanges: [NSRange] = []

        // `inline code` — 먼저. 안쪽은 코드색, 백틱은 흐리게. 이 범위 안의 강조는 무시한다.
        enumerate(Regex.code, ns, range) { m in
            let inner = m.range(at: 1)
            storage.addAttribute(.foregroundColor, value: UIColor(Palette.inlineCodeText), range: inner)
            storage.addAttribute(.backgroundColor, value: UIColor(Palette.inlineCodeBg), range: inner)
            dimMarkersAround(storage, full: m.range, inner: inner)
            codeRanges.append(m.range)
        }

        // [라벨](url) — 라벨은 링크색, 괄호·url 은 흐리게.
        enumerate(Regex.link, ns, range) { m in
            if intersectsAny(m.range, codeRanges) { return }
            storage.addAttribute(.foregroundColor, value: UIColor(Palette.link), range: m.range(at: 1))
            // 라벨을 뺀 나머지([ ] ( url ))는 흐리게.
            dim(storage, NSRange(location: m.range.location, length: m.range(at: 1).location - m.range.location))
            let labelEnd = m.range(at: 1).location + m.range(at: 1).length
            dim(storage, NSRange(location: labelEnd, length: m.range.location + m.range.length - labelEnd))
        }

        // **굵게**
        enumerate(Regex.bold, ns, range) { m in
            if intersectsAny(m.range, codeRanges) { return }
            addTrait(storage, .traitBold, range: m.range(at: 1))
            dimMarkersAround(storage, full: m.range, inner: m.range(at: 1))
        }

        // *기울임* (단일 별표만 — ** 는 위에서 처리)
        enumerate(Regex.italic, ns, range) { m in
            if intersectsAny(m.range, codeRanges) { return }
            addTrait(storage, .traitItalic, range: m.range(at: 1))
            dimMarkersAround(storage, full: m.range, inner: m.range(at: 1))
        }

        // ~~취소선~~
        enumerate(Regex.strike, ns, range) { m in
            if intersectsAny(m.range, codeRanges) { return }
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: m.range(at: 1))
            storage.addAttribute(.foregroundColor, value: UIColor(Palette.secondary), range: m.range(at: 1))
            dimMarkersAround(storage, full: m.range, inner: m.range(at: 1))
        }
    }

    // MARK: 도우미

    private static func dim(_ storage: NSTextStorage, _ range: NSRange) {
        guard range.length > 0 else { return }
        storage.addAttribute(.foregroundColor, value: UIColor(Palette.faint), range: range)
    }

    /// full 범위에서 inner 를 뺀 좌우(마커)를 흐리게.
    private static func dimMarkersAround(_ storage: NSTextStorage, full: NSRange, inner: NSRange) {
        dim(storage, NSRange(location: full.location, length: inner.location - full.location))
        let innerEnd = inner.location + inner.length
        dim(storage, NSRange(location: innerEnd, length: full.location + full.length - innerEnd))
    }

    /// 기존 폰트(헤딩이면 헤딩 폰트)를 보존한 채 굵게/기울임 트레잇만 더한다.
    private static func addTrait(_ storage: NSTextStorage, _ trait: UIFontDescriptor.SymbolicTraits, range: NSRange) {
        guard range.length > 0 else { return }
        storage.enumerateAttribute(.font, in: range, options: []) { value, sub, _ in
            let font = (value as? UIFont) ?? bodyFont()
            let traits = font.fontDescriptor.symbolicTraits.union(trait)
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                storage.addAttribute(.font, value: UIFont(descriptor: descriptor, size: font.pointSize), range: sub)
            }
        }
    }

    private static func intersectsAny(_ range: NSRange, _ others: [NSRange]) -> Bool {
        others.contains { NSIntersectionRange($0, range).length > 0 }
    }

    private static func enumerate(
        _ regex: NSRegularExpression, _ ns: NSString, _ range: NSRange,
        _ body: (NSTextCheckingResult) -> Void
    ) {
        regex.enumerateMatches(in: ns as String, options: [], range: range) { match, _, _ in
            if let match { body(match) }
        }
    }

    private enum Regex {
        static let code = make("`([^`\\n]+)`")
        static let bold = make("\\*\\*([^*\\n]+)\\*\\*")
        static let italic = make("(?<![*\\w])\\*([^*\\n]+)\\*(?![*\\w])")
        static let strike = make("~~([^~\\n]+)~~")
        static let link = make("\\[([^\\]\\n]+)\\]\\([^)\\n]+\\)")
        // 선택적 캡션(표준 image title `"…"`)까지 한 매치로 — 캡션 있는 이미지도 본문에서
        // 마크다운을 숨기고 썸네일만 보이게(없으면 마크다운 원문이 그대로 노출되던 버그).
        static let image = make("!\\[[^\\]\\n]*\\]\\(([^)\\s]+)(?:\\s+\"[^\"]*\")?\\)")

        static func make(_ pattern: String) -> NSRegularExpression {
            // 패턴은 컴파일타임 상수 — 실패할 수 없다.
            try! NSRegularExpression(pattern: pattern)
        }
    }
}
