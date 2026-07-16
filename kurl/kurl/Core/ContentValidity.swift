//
//  ContentValidity.swift
//  kurl
//

import Foundation

/// 렌더 직전 콘텐츠 위생 — 백엔드/사용자 입력에서 새어 든 부스러기(불완전 자모 태그·
/// 사실상 빈 글)가 카드·태그 칩으로 그려지지 않게 거른다. 순수 함수라 뷰가 값만 통과시키면 된다.
enum ContentValidity {

    // MARK: 태그

    /// 렌더할 만한 태그인가 — 불완전 한글 자모("ㅓ", "ㅏ"), 한 글자 부스러기("ㄴ"),
    /// 한 글자 반복("dddd"), 빈/공백 태그를 거른다. 한 글자라도 뜻이 서는 것(한글 음절 "책",
    /// 한자 "詩", 언어 태그 "C"·"R")은 통과한다 — 완성형 한글·영문·숫자·이모지가 섞인 정상 태그도.
    /// 판정은 표시용일 뿐 — 저장·라우팅 값은 원문 그대로 둔다.
    static func isRenderableTag(_ raw: String) -> Bool {
        let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return false }

        // 자모 하나하나(초성/중성만 있는 조각)는 완성된 글자가 아니다 — 전부 자모면 부스러기.
        if tag.unicodeScalars.allSatisfy(isHangulJamo) { return false }

        // 의미 글자 — 자모·구두점·비이모지 기호·공백을 뺀 '읽히는' 글자. 하나도 없으면 태그가 아니다.
        let meaningful = tag.unicodeScalars.filter(isMeaningfulScalar)
        guard let first = meaningful.first else { return false }

        // 한 글자 반복("dddd", "ㅋㅋ" 는 위 자모 컷)은 뜻이 안 서는 부스러기 — 거른다.
        if meaningful.count > 1, meaningful.allSatisfy({ $0 == first }) { return false }

        // 한 글자여도 뜻이 서면 통과 — 한글 음절("책")·한자("詩")·영문 언어 태그("C"·"R").
        // 그 밖의 한 글자(숫자·이모지 단독)는 태그로 보기 어려워 두 글자 이상을 요구한다.
        if meaningful.count == 1 { return isStandaloneWord(first) }
        return true
    }

    /// 완성형 한글 음절(가~힣)이 아니라 조합용/호환용 자모 단독인지 —
    /// U+1100~11FF(조합 자모)·U+3130~318F(호환 자모)·U+A960~A97F(확장 자모).
    private static func isHangulJamo(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return (0x1100...0x11FF).contains(v)
            || (0x3130...0x318F).contains(v)
            || (0xA960...0xA97F).contains(v)
    }

    /// '읽히는' 글자인가 — 자모·공백·구두점을 뺀다. 기호는 이모지만 남기고(이모지-only 제목·태그를
    /// 살리려), 화살표·수학기호 같은 비이모지 기호는 뺀다.
    private static func isMeaningfulScalar(_ scalar: Unicode.Scalar) -> Bool {
        if isHangulJamo(scalar) { return false }
        if CharacterSet.whitespacesAndNewlines.contains(scalar) { return false }
        if CharacterSet.punctuationCharacters.contains(scalar) { return false }
        if CharacterSet.symbols.contains(scalar) { return isEmojiScalar(scalar) }
        return true
    }

    /// 한 글자로도 뜻이 서는가 — 한글 음절·한자·문자(letter). 언어 태그("C"·"R")와 단어("책"·"詩")를 살린다.
    private static func isStandaloneWord(_ scalar: Unicode.Scalar) -> Bool {
        isHangulSyllable(scalar)
            || isCJKIdeograph(scalar)
            || scalar.properties.isAlphabetic
    }

    /// 완성형 한글 음절(가~힣) — U+AC00~D7A3.
    private static func isHangulSyllable(_ scalar: Unicode.Scalar) -> Bool {
        (0xAC00...0xD7A3).contains(scalar.value)
    }

    /// CJK 한자(기본·확장 A·호환·확장 B) — 한 글자로도 단어가 서는 표의문자.
    private static func isCJKIdeograph(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return (0x3400...0x4DBF).contains(v)   // 확장 A
            || (0x4E00...0x9FFF).contains(v)   // 기본
            || (0xF900...0xFAFF).contains(v)   // 호환
            || (0x20000...0x2FA1F).contains(v) // 확장 B~
    }

    /// 이모지 스칼라인가 — 화살표·수학기호 같은 순수 기호와 가른다. ASCII(#·*·숫자 등 이모지 표현이
    /// 있는 문자)는 이모지로 치지 않는다(단독 기호 잔재를 이모지로 오인하지 않게).
    private static func isEmojiScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value > 0x7F && scalar.properties.isEmoji
    }

    /// 렌더용으로 정리한 태그 목록 — 부스러기를 걸러내되 순서·원문은 보존한다.
    static func renderableTags(_ tags: [String]) -> [String] {
        tags.filter(isRenderableTag)
    }

    /// 태그 칩에 붙일 표시용 라벨 — 뷰가 "#" 를 앞에 그리므로, 원문에 이미 "#" 가 박혀 온
    /// 태그("#디자인")는 이중 해시("##디자인")가 된다. 선행 "#" 하나만 벗겨 표시층에서 방어한다
    /// (판정·라우팅 값은 원문 그대로 — 데이터 원인은 백엔드 몫).
    static func tagDisplay(_ raw: String) -> String {
        var tag = raw
        while tag.hasPrefix("#") { tag.removeFirst() }
        return tag
    }

    // MARK: 빈 콘텐츠

    /// 글자로서 의미 있는 내용이 있는가 — 공백·구두점만 있으면 비어 있다고 본다.
    /// "ㅇㅇ"처럼 자모만 두 글자인 제목도 실질 내용 없음으로 걸러 풀 크롬 카드를 막는다.
    /// 이모지는 내용으로 친다 — 이모지-only 제목("🌙")도 정당한 글이라 피드에서 지우지 않는다.
    static func hasMeaningfulText(_ raw: String?) -> Bool {
        guard let raw else { return false }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // 자모·구두점·비이모지 기호만 남으면(예: "ㅇㅇ", "...") 실질 내용이 없다. 이모지는 남긴다.
        return trimmed.unicodeScalars.contains(where: isMeaningfulScalar)
    }
}

extension FeedItem {
    /// 카드로 그릴 만한 글인가 — 제목이 사실상 비어 있으면(예: "ㅇㅇ") 풀 크롬 카드를 만들지 않는다.
    var isRenderableCard: Bool {
        ContentValidity.hasMeaningfulText(title)
    }

    /// 부스러기를 걸러낸 표시용 태그.
    var renderableTags: [String] {
        ContentValidity.renderableTags(tags)
    }
}
