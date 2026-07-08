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
        let active = activeParagraph(ns, selected)
        storage.beginEditing()
        storage.setAttributes(base, range: full)
        styleLines(storage, ns, in: full, activePara: active, startInFence: false, startMarker: nil)
        applyImages(storage, ns, in: full, width: availableWidth(textView))
        applyTables(storage, ns, in: full, activePara: active)
        storage.endEditing()
        // 속성만 바꿔 길이는 그대로지만, 캐럿을 한 번 더 못박아 둔다.
        if selected.location <= ns.length {
            textView.selectedRange = selected
        }
        // 다음 입력은 base 로 시작 → 다음 변경에서 다시 정확히 입혀진다(헤딩 줄 안이라도).
        textView.typingAttributes = base
    }

    /// 매 키 입력마다 전체 문서를 다시 칠하지 않게 — 캐럿이 놓인 문단만 다시 입힌다.
    /// 펜스(코드블록)·구조가 걸린 입력은 안전하게 false 를 돌려 호출측이 전체 패스를 돌게 한다.
    /// 평범한 본문 타이핑(긴 글)에서 매 글자마다의 O(문서) 작업을 없애는 빠른 경로다.
    static func applyEditedParagraph(to textView: UITextView) -> Bool {
        guard textView.markedTextRange == nil else { return false }
        let ns = textView.text as NSString
        guard ns.length > 0 else { return false }
        let caret = min(textView.selectedRange.location, ns.length)
        let para = ns.paragraphRange(for: NSRange(location: caret, length: 0))
        // 백틱·물결이 있으면(펜스 토글·인라인 코드·취소선) 아래 줄 상태나 범위가 흔들릴 수 있어 전체 패스로.
        // 파이프('|')도 전체 패스로 — 빠른 경로는 표(applyTables)를 돌지 않아 셀을 칠 때마다 원시 파이프가
        // 밝게 튀고 구분선이 잠깐 드러났다. 표 줄은 전체 패스로 넘겨 파이프를 흐리게·구분선을 계속 숨긴다.
        let paraStr = ns.substring(with: para)
        if paraStr.contains("`") || paraStr.contains("~") || paraStr.contains("|") { return false }
        // 문단이 코드펜스 안이면 전체 패스로(코드색 유지) — 앞쪽 펜스 마커만 싸게 센다(정규식 없음).
        if fenceOpen(before: para.location, ns: ns) { return false }
        let storage = textView.textStorage
        let selected = textView.selectedRange
        storage.beginEditing()
        storage.setAttributes(baseAttributes(), range: para)
        // 빠른 경로는 캐럿이 놓인 문단만 칠한다 — 그 문단이 곧 활성 문단이므로 마커를 노출(편집 가능).
        styleLines(storage, ns, in: para, activePara: para, startInFence: false, startMarker: nil)
        applyImages(storage, ns, in: para, width: availableWidth(textView))
        storage.endEditing()
        if selected.location <= ns.length { textView.selectedRange = selected }
        textView.typingAttributes = baseAttributes()
        return true
    }

    static func availableWidth(_ textView: UITextView) -> CGFloat {
        let pad = textView.textContainer.lineFragmentPadding
        let cw = textView.textContainer.size.width
        return max(0, (cw.isFinite && cw > 1 ? cw : textView.bounds.width) - pad * 2)
    }

    /// location 앞까지 ```·~~~ 펜스를 세어 그 지점이 코드펜스 안인지(정규식 없이) 판정.
    static func fenceOpen(before location: Int, ns: NSString) -> Bool {
        var marker: Character?
        ns.enumerateSubstrings(in: NSRange(location: 0, length: location), options: [.byLines]) {
            line, _, _, _ in
            let t = (line ?? "").trimmingCharacters(in: .whitespaces)
            let fc: Character? = t.hasPrefix("```") ? "`" : (t.hasPrefix("~~~") ? "~" : nil)
            if let fc {
                if marker == nil { marker = fc } else if marker == fc { marker = nil }
            }
        }
        return marker != nil
    }

    // MARK: 줄 단위 — 헤딩·인용·리스트·코드펜스

    static func styleLines(
        _ storage: NSTextStorage, _ ns: NSString, in range: NSRange, activePara: NSRange,
        startInFence: Bool, startMarker: Character?
    ) {
        var inFence = startInFence
        var fenceMarker = startMarker
        // 번호 목록 순번 추적 — 같은 깊이의 연속 번호 항목을 1,2,3…로 그려 발행본과 일치시킨다
        // (원문이 "1. 1. 1." 이어도 발행본은 1,2,3 으로 재번호하므로 에디터도 그렇게 보여야 한다).
        var orderedRun: (lead: Int, n: Int)?
        ns.enumerateSubstrings(in: range, options: [.byLines]) { line, lineRange, _, _ in
            guard let line else { return }
            // 커서가 놓인 줄(활성)이면 마커를 노출(흐리게)해 편집 가능; 아니면 숨겨 렌더된 모습으로.
            let reveal = NSIntersectionRange(lineRange, activePara).length > 0
                || (activePara.location >= lineRange.location
                    && activePara.location <= lineRange.location + lineRange.length)

            // 이 줄이 번호 항목이면 순번을 잇고, 아니면(코드펜스 안 포함) 연속을 끊는다.
            let lead0 = line.prefix(while: { $0 == " " }).count
            let body0 = line.dropFirst(lead0)
            let digits0 = body0.prefix(while: { $0.isNumber })
            let isOrdered = !inFence && !digits0.isEmpty && body0.dropFirst(digits0.count).hasPrefix(". ")
            var orderedOrdinal: Int?
            if isOrdered {
                if let run = orderedRun, run.lead == lead0 {
                    orderedRun = (lead0, run.n + 1)
                } else {
                    orderedRun = (lead0, Int(digits0) ?? 1)  // 첫 항목의 시작 번호를 존중.
                }
                orderedOrdinal = orderedRun?.n
            } else {
                orderedRun = nil
            }

            // ```·~~~ 코드펜스 — 펜스 줄과 그 안쪽을 어두운 코드 박스로(발행면과 같은 모습). 펜스는
            // 흐린 라벨. 여는 마커(`/~)를 기억해 같은 마커로만 닫는다(백엔드와 같은 규칙). 선행 공백 허용.
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let fenceChar: Character? =
                trimmed.hasPrefix("```") ? "`" : (trimmed.hasPrefix("~~~") ? "~" : nil)
            if let fc = fenceChar, fenceMarker == nil || fenceMarker == fc {
                storage.addAttribute(.backgroundColor, value: UIColor(Palette.codeBg), range: lineRange)
                storage.addAttribute(.foregroundColor, value: UIColor(Palette.codeText).withAlphaComponent(0.5), range: lineRange)
                if fenceMarker == nil {
                    fenceMarker = fc
                    inFence = true
                } else {
                    fenceMarker = nil
                    inFence = false
                }
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
                applyHeading(storage, lineRange, level: hashes, reveal: reveal)
                applyInline(storage, ns, lineRange, reveal: reveal) // 제목 안의 **굵게** 등도 살려둔다(크기 유지).
                return
            }

            // > 인용 → 들여쓰기 + 왼쪽 강조 바 + 인용색, 마커 흐리게. 발행본(BlockRenderer .quote 의
            // 좌측 그린 바 인용구)의 에디터 대응 — 줄 전체를 칠하던 옛 그린 배경은 "인용"이 아니라
            // "형광펜 칠한 줄"로 읽혀 어긋났다. 리더와 같은 문법(왼쪽 바 + 들여쓰기 + 흐린 글자)으로 맞춘다.
            if line == ">" || line.hasPrefix("> ") {
                let quoteStyle = NSMutableParagraphStyle()
                quoteStyle.firstLineHeadIndent = 20  // 리더 padding.leading 20 과 같은 들여쓰기.
                quoteStyle.headIndent = 20
                storage.addAttribute(.paragraphStyle, value: quoteStyle, range: lineRange)
                storage.addAttribute(.foregroundColor, value: UIColor(Palette.secondary), range: lineRange)
                // 왼쪽 강조 바 — 레이아웃 매니저가 이 줄(들) 왼단에 그린다(리더의 accentSoft 바와 동일).
                storage.addAttribute(.kurlQuoteBar, value: true, range: lineRange)
                // 인용 마커("> ")는 활성 줄에서도 숨긴다(reveal 무시) — 리더처럼 인용을 "직접 쓰는" 모습이 되게.
                // 바+들여쓰기가 인용임을 보여주므로 마커는 군더더기. 편집은 그대로: 인용 본문 첫 글자에서
                // 백스페이스 = 통강등(shouldChangeTextIn), 0폭 마커는 캐럿을 본문 앞(lineStart+2)에 자연히 둔다.
                marker(storage, NSRange(location: lineRange.location, length: min(2, lineRange.length)), reveal: false)
                applyInline(storage, ns, lineRange, reveal: reveal)
                return
            }

            // -, * 글머리 / 1. 번호 리스트. 활성 줄이면 마커를 강조색(원시 편집), 아니면 마커를 숨기고
            // 불릿/번호를 그려 본문을 행잉 인덴트로 들인다(레이아웃 매니저가 그림).
            if let markerLen = listMarkerLength(line) {
                let markerRange = NSRange(location: lineRange.location, length: min(markerLen, lineRange.length))
                if reveal {
                    storage.addAttribute(.foregroundColor, value: UIColor(Palette.accentMarker), range: markerRange)
                } else {
                    // 번호 항목이면 순번(1,2,3…), 아니면 불릿(•).
                    let bullet = orderedOrdinal.map { "\($0)." } ?? "•"
                    let textIndent = CGFloat(lead0) * 7 + 20
                    let ps = NSMutableParagraphStyle()
                    ps.firstLineHeadIndent = textIndent
                    ps.headIndent = textIndent
                    storage.addAttribute(.paragraphStyle, value: ps, range: lineRange)
                    storage.addAttribute(.foregroundColor, value: UIColor.clear, range: markerRange)
                    storage.addAttribute(.font, value: UIFont.systemFont(ofSize: 0.01), range: markerRange)
                    storage.addAttribute(.kurlListBullet, value: bullet, range: NSRange(location: lineRange.location, length: 1))
                }
            }

            // 단독 URL 줄 — 발행 시 임베드(동영상·카드)가 된다. 에디터에선 링크색+밑줄로 표시해
            // 평범한 평문 URL 이 아니라 미디어가 될 줄임을 알린다(편집 바도 이 줄에서 뜬다).
            if isStandaloneURL(line) {
                storage.addAttribute(.foregroundColor, value: UIColor(Palette.link), range: lineRange)
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: lineRange)
                return
            }

            applyInline(storage, ns, lineRange, reveal: reveal)
        }
    }

    /// 캐럿(또는 선택)이 놓인 문단 범위 — 그 문단의 마크다운 마커는 노출하고 나머지는 숨긴다.
    private static func activeParagraph(_ ns: NSString, _ selected: NSRange) -> NSRange {
        let loc = min(max(0, selected.location), ns.length)
        let len = min(max(0, selected.length), ns.length - loc)
        return ns.paragraphRange(for: NSRange(location: loc, length: len))
    }

    /// `![alt](url)` — URL 표식(.kurlImageURL)을 붙이고 마크다운 문법은 흐리게, 그 줄 아래에
    /// 썸네일 높이만큼 paragraphSpacing 으로 공간을 확보한다(레이아웃 매니저가 그 자리에 그린다).
    /// 본문 텍스트(`![](url)`)는 그대로 남아 마크다운 원문·자동저장이 깨지지 않는다.
    static func applyImages(
        _ storage: NSTextStorage, _ ns: NSString, in range: NSRange, width: CGFloat
    ) {
        // 한 줄이 오롯이 이미지(들)일 때만 숨기고 썸네일을 그린다 — 백엔드는 그럴 때만 IMAGE 블록을
        // 만들고, 텍스트와 같은 줄에 섞인 이미지는 평문으로 렌더하므로 에디터도 마크다운을 남긴다.
        ns.enumerateSubstrings(in: range, options: [.byLines]) { line, lineRange, _, _ in
            guard let line, line.contains("![") else { return }
            let lineNS = line as NSString
            let stripped = Regex.image.stringByReplacingMatches(
                in: line, options: [], range: NSRange(location: 0, length: lineNS.length),
                withTemplate: "")
            guard stripped.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            Regex.image.enumerateMatches(in: ns as String, range: lineRange) { match, _, _ in
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
    }

    // MARK: 표 — 캐럿이 표 밖일 때 진짜 그리드로(원시 텍스트 0폭 숨김 + 예약공간에 레이아웃 매니저가 그림).

    /// 줄에 이스케이프되지 않은 `|` 가 있는가(표 줄 후보).
    private static func hasUnescapedPipe(_ s: String) -> Bool {
        var esc = false
        for ch in s {
            if esc { esc = false } else if ch == "\\" { esc = true } else if ch == "|" { return true }
        }
        return false
    }

    /// `| --- | :--: |` 같은 GFM 정렬 구분선인가.
    private static func isSeparatorRow(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.contains("-") && t.allSatisfy { "|:- ".contains($0) }
    }

    static func applyTables(_ storage: NSTextStorage, _ ns: NSString, in range: NSRange, activePara: NSRange) {
        var lines: [(text: String, range: NSRange)] = []
        ns.enumerateSubstrings(in: range, options: [.byLines]) { sub, r, _, _ in lines.append((sub ?? "", r)) }
        guard !lines.isEmpty else { return }
        // 코드펜스 안 줄은 표로 보지 않는다.
        var fenced = [Bool](repeating: false, count: lines.count)
        var inFence = false
        for i in lines.indices {
            let t = lines[i].text.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") || t.hasPrefix("~~~") { fenced[i] = true; inFence.toggle() } else { fenced[i] = inFence }
        }
        func isTableLine(_ i: Int) -> Bool {
            !fenced[i] && hasUnescapedPipe(lines[i].text) && !lines[i].text.trimmingCharacters(in: .whitespaces).isEmpty
        }
        var i = 0
        while i < lines.count {
            // GFM 표 = 파이프 줄 + 둘째 줄이 정렬 구분선.
            guard isTableLine(i), i + 1 < lines.count, isTableLine(i + 1), isSeparatorRow(lines[i + 1].text)
            else { i += 1; continue }
            var end = i + 1
            while end + 1 < lines.count, isTableLine(end + 1) { end += 1 }
            let startLoc = lines[i].range.location
            let endLoc = lines[end].range.location + lines[end].range.length
            let region = NSRange(location: startLoc, length: endLoc - startLoc)
            // 캐럿이 표 안이면 원시 마크다운 그대로(편집). 밖이면 숨기고 그리드를 예약·표식.
            let active = NSIntersectionRange(region, activePara).length > 0
                || (activePara.location >= startLoc && activePara.location <= endLoc)
            if !active, let parsed = MarkdownTable.parse(ns.substring(with: region)) {
                storage.addAttribute(.foregroundColor, value: UIColor.clear, range: region)
                storage.addAttribute(.font, value: UIFont.systemFont(ofSize: 0.01), range: region)
                let ps = NSMutableParagraphStyle()
                ps.paragraphSpacing = MarkdownTable.gridHeight(rowCount: parsed.rowCount, font: bodyFont())
                storage.addAttribute(.paragraphStyle, value: ps,
                    range: ns.paragraphRange(for: NSRange(location: startLoc, length: 0)))
                storage.addAttribute(.kurlTableMarkdown, value: ns.substring(with: region),
                    range: NSRange(location: startLoc, length: 1))
            } else if active {
                // 편집 중: 값 없는 구분선(---) 줄은 숨기고(구조 편집은 행/열 바로), 나머지 파이프는 흐리게 —
                // "표가 코드로 변한" 느낌 대신 "칸을 편집한다"로 읽히게.
                let sep = lines[i + 1].range
                storage.addAttribute(.foregroundColor, value: UIColor.clear, range: sep)
                storage.addAttribute(.font, value: UIFont.systemFont(ofSize: 0.01), range: sep)
                var loc = startLoc
                while loc < endLoc {
                    if !NSLocationInRange(loc, sep),
                        ns.substring(with: NSRange(location: loc, length: 1)) == "|" {
                        storage.addAttribute(.foregroundColor, value: UIColor(Palette.faint),
                            range: NSRange(location: loc, length: 1))
                    }
                    loc += 1
                }
            }
            i = end + 1
        }
    }

    private static func applyHeading(_ storage: NSTextStorage, _ lineRange: NSRange, level: Int, reveal: Bool) {
        let size: CGFloat = level == 1 ? 25 : level == 2 ? 21 : 18
        let font = UIFontMetrics(forTextStyle: .body)
            .scaledFont(for: .monospacedSystemFont(ofSize: size, weight: .bold))
        storage.addAttribute(.font, value: font, range: lineRange)
        storage.addAttribute(.foregroundColor, value: UIColor(Palette.ink), range: lineRange)
        // 마커("#... " + 공백)는 활성 줄에선 흐리게(편집), 아니면 숨겨 제목만 보이게.
        let markerLen = min(level + 1, lineRange.length)
        marker(storage, NSRange(location: lineRange.location, length: markerLen), reveal: reveal)
    }

    /// 줄 전체가 단독 http(s) URL(또는 `<url>`)인가 — 백엔드가 EMBED 로 만드는 줄.
    private static func isStandaloneURL(_ line: String) -> Bool {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("<"), t.hasSuffix(">") { t = String(t.dropFirst().dropLast()) }
        guard t.hasPrefix("http://") || t.hasPrefix("https://") else { return false }
        return !t.contains(" ") && t.contains(".")
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

    private static func applyInline(_ storage: NSTextStorage, _ ns: NSString, _ range: NSRange, reveal: Bool) {
        var codeRanges: [NSRange] = []

        // `inline code` — 먼저. 안쪽은 코드색, 백틱은 숨김/노출. 이 범위 안의 강조는 무시한다.
        enumerate(Regex.code, ns, range) { m in
            let inner = m.range(at: 1)
            storage.addAttribute(.foregroundColor, value: UIColor(Palette.inlineCodeText), range: inner)
            storage.addAttribute(.backgroundColor, value: UIColor(Palette.inlineCodeBg), range: inner)
            markersAround(storage, full: m.range, inner: inner, reveal: reveal)
            codeRanges.append(m.range)
        }

        // [라벨](url) — 라벨은 링크색, 괄호·url 은 숨김/노출.
        enumerate(Regex.link, ns, range) { m in
            if intersectsAny(m.range, codeRanges) { return }
            storage.addAttribute(.foregroundColor, value: UIColor(Palette.link), range: m.range(at: 1))
            // 라벨을 뺀 나머지([ ] ( url ))는 숨김/노출.
            marker(storage, NSRange(location: m.range.location, length: m.range(at: 1).location - m.range.location), reveal: reveal)
            let labelEnd = m.range(at: 1).location + m.range(at: 1).length
            marker(storage, NSRange(location: labelEnd, length: m.range.location + m.range.length - labelEnd), reveal: reveal)
        }

        // **굵게**
        enumerate(Regex.bold, ns, range) { m in
            if intersectsAny(m.range, codeRanges) { return }
            addTrait(storage, .traitBold, range: m.range(at: 1))
            markersAround(storage, full: m.range, inner: m.range(at: 1), reveal: reveal)
        }

        // *기울임* (단일 별표만 — ** 는 위에서 처리)
        enumerate(Regex.italic, ns, range) { m in
            if intersectsAny(m.range, codeRanges) { return }
            addTrait(storage, .traitItalic, range: m.range(at: 1))
            markersAround(storage, full: m.range, inner: m.range(at: 1), reveal: reveal)
        }

        // ~~취소선~~
        enumerate(Regex.strike, ns, range) { m in
            if intersectsAny(m.range, codeRanges) { return }
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: m.range(at: 1))
            storage.addAttribute(.foregroundColor, value: UIColor(Palette.secondary), range: m.range(at: 1))
            markersAround(storage, full: m.range, inner: m.range(at: 1), reveal: reveal)
        }
    }

    // MARK: 도우미

    private static func dim(_ storage: NSTextStorage, _ range: NSRange) {
        guard range.length > 0 else { return }
        storage.addAttribute(.foregroundColor, value: UIColor(Palette.faint), range: range)
    }

    /// 마크다운 마커를 활성 줄에선 흐리게(편집), 아니면 거의 0 폭으로 숨긴다(WYSIWYG).
    private static func marker(_ storage: NSTextStorage, _ range: NSRange, reveal: Bool) {
        guard range.length > 0 else { return }
        if reveal {
            dim(storage, range)
        } else {
            storage.addAttribute(.foregroundColor, value: UIColor.clear, range: range)
            storage.addAttribute(.font, value: UIFont.systemFont(ofSize: 0.01), range: range)
        }
    }

    /// full 범위에서 inner 를 뺀 좌우(마커)를 숨김/노출.
    private static func markersAround(_ storage: NSTextStorage, full: NSRange, inner: NSRange, reveal: Bool) {
        marker(storage, NSRange(location: full.location, length: inner.location - full.location), reveal: reveal)
        let innerEnd = inner.location + inner.length
        marker(storage, NSRange(location: innerEnd, length: full.location + full.length - innerEnd), reveal: reveal)
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
        // 캡션 안에 줄바꿈을 금지해(미닫힌 따옴표가 다음 줄들을 통째로 삼켜 본문이 사라지지 않게)
        // 전체 문서를 한 번에 훑어도 한 줄을 넘지 않는다.
        static let image = make("!\\[[^\\]\\n]*\\]\\(([^)\\s]+)(?:[ \\t]+\"[^\"\\n]*\")?\\)")

        static func make(_ pattern: String) -> NSRegularExpression {
            // 패턴은 컴파일타임 상수 — 실패할 수 없다.
            try! NSRegularExpression(pattern: pattern)
        }
    }
}
