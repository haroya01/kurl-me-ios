//
//  MarkdownRoundTrip.swift
//  kurl — WriteV2
//
//  블록 ↔ 마크다운 왕복. 스왑의 핵심 — 이 방언이 현행 ComposeView 가 보내는 것과 같아야
//  기존 저장/파싱(WriteAPI.replaceMarkdown → 서버 md→blocks)과 무손실로 호환된다.
//
//  방언 근거(kurl-ios 소스에서 확정):
//   • 제목 = ATX `# `/`## `/`### ` (h1~3, 해시 뒤 공백 필수) — MarkdownSyntaxHighlighter L160.
//   • 인용 = 줄머리 `> ` (또는 단독 `>`) — 같은 파일 L169. 여러 줄 인용은 줄마다 `> `.
//   • 코드펜스 = ``` (백틱 3) 여는 줄에 언어 선택 — L138~150. 같은 마커로 닫는다.
//   • 블록 경계 = 빈 줄(`\n\n`) — 백엔드가 블록을 가르는 기준(Explore 확인).
//  Phase 1 스코프 밖(리스트/표/이미지/구분선/임베드)은 파서에서 "문단"으로 보존만 한다
//  (원문 마크다운을 문단 text 로 통째 담아 왕복에서 안 잃는다 — Phase 2 에서 전용 블록으로 승격).
//

import Foundation

// MARK: - 직렬화 (블록 → 마크다운)

nonisolated enum MarkdownSerializer {
    /// 블록 배열을 하나의 마크다운 문자열로. 블록 사이는 빈 줄 하나(백엔드 블록 경계 규칙).
    static func markdown(from blocks: [EditorBlock]) -> String {
        blocks.map(serialize).joined(separator: "\n\n")
    }

    static func serialize(_ block: EditorBlock) -> String {
        switch block.kind {
        case .paragraph:
            return block.text
        case .heading(let level):
            let hashes = String(repeating: "#", count: max(1, min(3, level)))
            return "\(hashes) \(block.text)"
        case .quote:
            // 여러 줄 인용은 줄마다 `> ` — 빈 줄은 단독 `>` (방언 L169 가 둘 다 받는다).
            return block.text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.isEmpty ? ">" : "> \($0)" }
                .joined(separator: "\n")
        case .code(let language):
            let fenceOpen = "```" + (language?.trimmingCharacters(in: .whitespaces) ?? "")
            return "\(fenceOpen)\n\(block.text)\n```"
        }
    }
}

// MARK: - 파싱 (마크다운 → 블록)

nonisolated enum MarkdownBlockParser {
    /// 마크다운 문자열을 블록 배열로. 라인 스캐너 — 방언과 1:1(정규식 없이 줄머리 판정).
    /// Phase 1 밖 구조(리스트/표/이미지/구분선)는 문단 블록으로 보존(원문 그대로) → 왕복 무손실.
    static func parse(_ markdown: String) -> [EditorBlock] {
        let lines = markdown.components(separatedBy: "\n")
        var blocks: [EditorBlock] = []
        var i = 0

        // 연속 문단 라인을 모아 하나의 문단 블록으로(빈 줄이 경계). 인용은 연속 `> ` 를 한 블록으로.
        var paragraphBuffer: [String] = []
        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            let joined = paragraphBuffer.joined(separator: "\n")
            blocks.append(.paragraph(joined))
            paragraphBuffer.removeAll(keepingCapacity: true)
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 빈 줄 = 블록 경계. 버퍼를 비운다(빈 줄 자체는 블록이 아님).
            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            // 코드펜스 ``` (여는 줄 언어 선택) — 같은 백틱 마커로 닫힐 때까지 원문 보존.
            if let lang = fenceLanguage(trimmed) {
                flushParagraph()
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t == "```" { i += 1; break }
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.code(codeLines.joined(separator: "\n"), language: lang.isEmpty ? nil : lang))
                continue
            }

            // 제목 `# `/`## `/`### ` (해시 1~3 + 공백).
            if let (level, content) = heading(line) {
                flushParagraph()
                blocks.append(.heading(level, content))
                i += 1
                continue
            }

            // 인용 `> ` — 연속 인용 줄을 한 블록으로 모은다.
            if isQuoteLine(line) {
                flushParagraph()
                var quoteLines: [String] = []
                while i < lines.count, isQuoteLine(lines[i]) {
                    quoteLines.append(stripQuoteMarker(lines[i]))
                    i += 1
                }
                blocks.append(.quote(quoteLines.joined(separator: "\n")))
                continue
            }

            // 그 외(문단 + Phase 1 밖 구조는 문단으로 보존) — 연속 라인을 모은다.
            paragraphBuffer.append(line)
            i += 1
        }
        flushParagraph()

        return blocks.isEmpty ? [.paragraph("")] : blocks
    }

    // MARK: 줄머리 판정 (방언 그대로)

    /// `# `/`## `/`### ` → (레벨, 뒤 내용). 해시 뒤 공백 필수(MarkdownSyntaxHighlighter L160).
    static func heading(_ line: String) -> (Int, String)? {
        var count = 0
        for ch in line {
            if ch == "#" { count += 1 } else { break }
        }
        guard count >= 1, count <= 3 else { return nil }
        let afterHashes = line.dropFirst(count)
        guard afterHashes.first == " " else { return nil }
        return (count, String(afterHashes.dropFirst()))
    }

    /// 여는 코드펜스면 언어(없으면 "")를, 아니면 nil. ``` 뒤 나머지가 언어(공백 트림).
    static func fenceLanguage(_ trimmed: String) -> String? {
        guard trimmed.hasPrefix("```") else { return nil }
        return String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
    }

    /// 단독 `>` 또는 `> ...` (방언 L169).
    static func isQuoteLine(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t == ">" || t.hasPrefix("> ")
    }

    /// `> ` / `>` 마커를 뗀 인용 본문 한 줄.
    static func stripQuoteMarker(_ line: String) -> String {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t == ">" { return "" }
        if t.hasPrefix("> ") { return String(t.dropFirst(2)) }
        return t
    }
}
