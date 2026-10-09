//
//  PostLimits.swift
//  kurl
//

import Foundation

/// 서버 글 입력 한도 — 길이는 Java String.length(UTF-16) 기준(CreatePostRequest·UpdatePostRequest 의 @Size,
/// PostEntity.MAX_TAGS·MAX_TAG_LENGTH). 넘으면 제목·소개글은 400, 태그는 조용히 잘린다.
nonisolated enum PostLimits {
    static let title = 200
    static let excerpt = 500
    static let tags = 10
    static let tagLength = 40

    static func clamped(_ text: String, to limit: Int) -> String {
        guard text.utf16.count > limit else { return text }
        var used = 0
        var end = text.startIndex
        for character in text {
            used += character.utf16.count
            guard used <= limit else { break }
            end = text.index(after: end)
        }
        return String(text[..<end])
    }

    /// 태그 정규화 — '#' 제거(태그는 해시태그가 아니라 주제어) + 공백 트림 + 최대 길이 캡. 빈 입력이면 빈 문자열.
    static func normalizedTag(_ raw: String) -> String {
        let stripped = raw.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
        return clamped(stripped, to: tagLength).trimmingCharacters(in: .whitespaces)
    }

    /// 쉼표로 나뉜 입력을 정규화해 붙인다 — 대소문자만 다른 중복은 건너뛰고, 한도에 닿으면 나머지는 버린다.
    static func adding(_ draft: String, to existing: [String]) -> [String] {
        var next = existing
        for part in draft.split(separator: ",").map({ normalizedTag(String($0)) }) where !part.isEmpty {
            guard next.count < tags else { break }
            if !next.contains(where: { $0.caseInsensitiveCompare(part) == .orderedSame }) {
                next.append(part)
            }
        }
        return next
    }
}
