//
//  InlineImageMarkdown.swift
//  kurl
//
//  문단(PARAGRAPH) 본문 속 인라인 이미지(`![alt](url "caption")`) 분해 — 웹 리더는 문단 안
//  이미지를 <img> 로 그리지만 Apple 마크다운 파서(AttributedString)는 이미지를 못 그려 alt
//  텍스트만 남는다(노션 붙여넣기 글 "앱에서 이미지 안 나옴"의 근본). 문단을 텍스트/이미지
//  세그먼트로 갈라 이미지는 IMAGE 블록과 같은 문법으로 그리게 한다.
//  alt 앞머리의 «wide/full/half»·«left/center/right»·«WxH» 마커(웹 image-width.ts 계약)는
//  여기서 벗겨 폭·비율 힌트로 넘긴다. UI 의존 없음 — 유닛 테스트 가능한 순수 파서.
//

import CoreGraphics
import Foundation

nonisolated enum InlineImageMarkdown {
    struct InlineImage: Equatable {
        var url: String
        /// 마커(«…»)를 벗긴 순수 alt.
        var alt: String
        /// `"…"` title — 웹·발행면과 같은 캡션.
        var caption: String?
        /// «wide»/«full»/«half» — IMAGE 블록 payload.width 와 같은 어휘.
        var width: String?
        /// «가로x세로» 원본 치수 — 로드 전 정확한 높이 예약(본문 밀림 방지)에 쓴다.
        var dimensions: CGSize?
    }

    enum Segment: Equatable {
        case text(String)
        case image(InlineImage)
    }

    /// 백엔드 MarkdownBlocksConverter.IMAGE 미러 — alt 는 `]` 금지, url 은 공백·`)` 금지, title 선택.
    private static let imageRegex = try? NSRegularExpression(
        pattern: "!\\[([^\\]]*)\\]\\(([^)\\s]+)(?:\\s+\"([^\"]*)\")?\\)")

    /// 빠른 판정 — 문단에 인라인 이미지가 하나라도 있는가(분해 렌더 분기용).
    static func containsImage(_ raw: String) -> Bool {
        guard raw.contains("!["), let regex = imageRegex else { return false }
        let ns = raw as NSString
        return regex.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)) != nil
    }

    /// 문단을 텍스트/이미지 세그먼트 순열로. 이미지 사이 하드브레이크 잔재(`\` 만 남은 조각)와
    /// 공백뿐인 텍스트는 버린다 — 노션 붙여넣기가 이미지 뒤에 `\` 를 흘린다.
    static func segments(_ raw: String) -> [Segment] {
        guard let regex = imageRegex else { return [.text(raw)] }
        let ns = raw as NSString
        var out: [Segment] = []
        var cursor = 0
        regex.enumerateMatches(in: raw, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            appendText(ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor)), to: &out)
            let rawAlt = m.range(at: 1).location == NSNotFound ? "" : ns.substring(with: m.range(at: 1))
            let url = ns.substring(with: m.range(at: 2))
            let caption = m.range(at: 3).location == NSNotFound ? nil : ns.substring(with: m.range(at: 3))
            let (alt, width, dims) = stripMarkers(rawAlt)
            out.append(.image(InlineImage(
                url: url, alt: alt,
                caption: (caption?.isEmpty == false) ? caption : nil,
                width: width, dimensions: dims)))
            cursor = m.range.location + m.range.length
        }
        appendText(ns.substring(from: cursor), to: &out)
        return out.isEmpty ? [.text(raw)] : out
    }

    /// 텍스트 조각 정리 — 앞뒤 공백·개행을 걷고, 줄끝 하드브레이크 `\` 잔재를 벗긴 뒤 비면 버린다.
    private static func appendText(_ piece: String, to out: inout [Segment]) {
        var t = piece.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasSuffix("\\") { t = String(t.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) }
        while t.hasPrefix("\\") { t = String(t.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !t.isEmpty else { return }
        out.append(.text(t))
    }

    /// alt 앞머리 마커를 순서대로 벗긴다: 폭(«wide/full/half») → 정렬(«left/center/right», iOS 는
    /// 미지원이라 값은 버림) → 치수(«WxH»). 웹 image-width.ts 와 같은 순서·어휘.
    private static func stripMarkers(_ rawAlt: String) -> (alt: String, width: String?, dims: CGSize?) {
        var alt = rawAlt
        var width: String?
        var dims: CGSize?

        func strip(_ marker: String) -> Bool {
            let token = "«\(marker)»"
            if alt.hasPrefix(token) {
                alt = String(alt.dropFirst(token.count)).trimmingCharacters(in: .whitespaces)
                return true
            }
            return false
        }

        for w in ["wide", "full", "half"] where strip(w) {
            width = w
            break
        }
        for a in ["left", "center", "right"] where strip(a) { break }

        if alt.hasPrefix("«"), let close = alt.firstIndex(of: "»") {
            let inner = alt[alt.index(after: alt.startIndex)..<close]
            let parts = inner.split(separator: "x")
            if parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]), w > 0, h > 0 {
                dims = CGSize(width: w, height: h)
                alt = String(alt[alt.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return (alt, width, dims)
    }
}
