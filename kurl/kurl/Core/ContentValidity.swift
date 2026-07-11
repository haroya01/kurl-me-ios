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
    /// 빈/공백 태그를 거른다. 완성형 한글·영문·숫자가 섞인 정상 태그는 통과한다.
    /// 판정은 표시용일 뿐 — 저장·라우팅 값은 원문 그대로 둔다.
    static func isRenderableTag(_ raw: String) -> Bool {
        let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return false }

        // 자모 하나하나(초성/중성만 있는 조각)는 완성된 글자가 아니다 — 전부 자모면 부스러기.
        if tag.unicodeScalars.allSatisfy(isHangulJamo) { return false }

        // 의미 글자 수 — 자모·구두점·기호를 뺀 '읽히는' 글자. 하나도 없으면 태그가 아니다.
        let meaningful = tag.unicodeScalars.filter { scalar in
            !isHangulJamo(scalar)
                && !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && !CharacterSet.punctuationCharacters.contains(scalar)
                && !CharacterSet.symbols.contains(scalar)
        }
        guard meaningful.count >= 2 else { return false }
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

    /// 렌더용으로 정리한 태그 목록 — 부스러기를 걸러내되 순서·원문은 보존한다.
    static func renderableTags(_ tags: [String]) -> [String] {
        tags.filter(isRenderableTag)
    }

    // MARK: 빈 콘텐츠

    /// 글자로서 의미 있는 내용이 있는가 — 공백·구두점만 있으면 비어 있다고 본다.
    /// "ㅇㅇ"처럼 자모만 두 글자인 제목도 실질 내용 없음으로 걸러 풀 크롬 카드를 막는다.
    static func hasMeaningfulText(_ raw: String?) -> Bool {
        guard let raw else { return false }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // 자모·구두점·기호만 남으면(예: "ㅇㅇ", "...") 실질 내용이 없다.
        let letters = trimmed.unicodeScalars.filter { scalar in
            !isHangulJamo(scalar)
                && !CharacterSet.punctuationCharacters.contains(scalar)
                && !CharacterSet.symbols.contains(scalar)
                && !CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
        return !letters.isEmpty
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
