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
//   • 구분선 = 단독 줄 `---`(3 하이픈) — MarkdownTextView.insertDivider L753. `***`/`___` 안 씀.
//   • 글머리 리스트 = `- `(정본; `* ` 도 허용) — MarkdownSyntaxHighlighter L360. 중첩=2칸/레벨(L358·리더 lead/2).
//   • 번호 리스트 = `N. `(숫자+점+공백) — 같은 파일 L124. 발행 시 1,2,3 재번호되지만 왕복은 원문 번호 보존.
//   • 이미지 = `![alt](url)` (+ 선택 `"title"`) — Regex L477. 단독 줄일 때만 IMAGE 블록.
//   • 표 = GFM `| a | b |` + 정렬 구분선(`:---`·`:---:`·`---:`) — applyTables L280 / TableMarkdown L560.
//   • 블록 경계 = 빈 줄(`\n\n`). 단, 리스트 항목들·표의 각 행은 인접 줄(`\n`) — 하이라이터의 번호 런
//     추적과 GFM 표 인접성 규칙이 빈 줄에 끊기므로, 같은 리스트/표 그룹은 한 덩이로 붙여 쓴다.
//

import Foundation

// MARK: - 직렬화 (블록 → 마크다운)

nonisolated enum MarkdownSerializer {
    /// 블록 배열을 하나의 마크다운 문자열로.
    /// 대부분의 블록 사이는 빈 줄 하나(백엔드 블록 경계). 하지만 **연속 리스트 항목**은 인접 줄로 붙인다
    /// (`\n` 하나) — 그래야 하이라이터의 번호 런 추적이 이어지고 서버가 한 리스트 블록으로 묶는다.
    /// 표는 자체가 여러 줄(헤더\n구분선\n본문)이라 블록 하나가 곧 여러 줄이다(사이는 `\n\n`).
    static func markdown(from blocks: [EditorBlock]) -> String {
        var out = ""
        var i = 0
        while i < blocks.count {
            let block = blocks[i]
            if !out.isEmpty { out += "\n\n" }
            // 연속 리스트 항목을 한 그룹으로 — 사이는 단일 개행.
            if block.listInfo != nil {
                var group: [EditorBlock] = [block]
                var j = i + 1
                while j < blocks.count, blocks[j].listInfo != nil {
                    group.append(blocks[j])
                    j += 1
                }
                out += serializeList(group)
                i = j
                continue
            }
            out += serialize(block)
            i += 1
        }
        return out
    }

    /// 연속 리스트 항목 그룹 → 항목당 한 줄. 번호 리스트의 순번은 **원문 보존**을 위해 항목 순서대로
    /// 매긴다 — 같은 indent 의 연속 번호 항목은 1,2,3…(다른 indent 나 글머리 항목이 끼면 리셋).
    /// (발행 렌더는 어차피 재번호하므로 이 규칙은 왕복 안정성만 책임진다.)
    static func serializeList(_ items: [EditorBlock]) -> String {
        var lines: [String] = []
        var runIndent: Int?
        var runN = 0
        for item in items {
            guard let (ordered, indent) = item.listInfo else { continue }
            let pad = String(repeating: " ", count: indent * 2)
            if ordered {
                if runIndent == indent { runN += 1 } else { runIndent = indent; runN = 1 }
                lines.append("\(pad)\(runN). \(item.text)")
            } else {
                runIndent = nil
                lines.append("\(pad)- \(item.text)")
            }
        }
        return lines.joined(separator: "\n")
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
        case .divider:
            return "---"
        case .listItem:
            // 단독 리스트 항목(그룹 밖 진입 시) — 그룹 직렬화와 같은 방언.
            return serializeList([block])
        case .image(let url):
            // alt 는 text 에. 캡션/타이틀은 Phase 2 스코프 밖(왕복은 alt·url 만).
            return "![\(block.text)](\(url))"
        case .table(let table):
            return serializeTable(table)
        }
    }

    /// 표 → GFM. 헤더\n구분선(정렬 토큰)\n본문. 셀 안 파이프는 `\|` 로 이스케이프(TableMarkdown.cells 규칙).
    static func serializeTable(_ table: EditorTable) -> String {
        let cols = table.columnCount
        guard cols > 0, !table.rows.isEmpty else { return "" }
        func row(_ cells: [String]) -> String {
            var padded = cells
            if padded.count < cols { padded += Array(repeating: "", count: cols - padded.count) }
            let escaped = padded.prefix(cols).map { $0.replacingOccurrences(of: "|", with: "\\|") }
            return "| " + escaped.joined(separator: " | ") + " |"
        }
        func sep(_ a: EditorTable.Alignment) -> String {
            switch a {
            case .leading: return "---"
            case .center: return ":---:"
            case .trailing: return "---:"
            }
        }
        let aligns: [EditorTable.Alignment] =
            (0..<cols).map { $0 < table.alignments.count ? table.alignments[$0] : .leading }
        var lines: [String] = []
        lines.append(row(table.rows[0]))
        lines.append("| " + aligns.map(sep).joined(separator: " | ") + " |")
        for r in table.rows.dropFirst() { lines.append(row(r)) }
        return lines.joined(separator: "\n")
    }
}

// MARK: - 파싱 (마크다운 → 블록)

nonisolated enum MarkdownBlockParser {
    /// 마크다운 문자열을 블록 배열로. 라인 스캐너 — 방언과 1:1(정규식 없이 줄머리 판정).
    /// Phase 1 밖 구조(리스트/표/이미지/구분선)는 문단 블록으로 보존(원문 그대로) → 왕복 무손실.
    static func parse(_ markdown: String) -> [EditorBlock] {
        // 윈도우/외부 앱에서 붙여넣은 CRLF 를 정규화 — 안 하면 \r 이 줄 끝에 남아 줄머리 판정과
        // 직렬화 본문에 조용히 섞인다(타이핑 입력은 \n 뿐이라 영향 없음).
        let markdown = markdown.replacingOccurrences(of: "\r\n", with: "\n")
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

            // 표 = GFM. 파이프 줄 + 바로 다음 줄이 정렬 구분선일 때만(applyTables L297 규칙).
            // 구분선 `---`(파이프 없음)와 헷갈리지 않게 표를 먼저 본다 — 표 구분행은 반드시 `|` 를 포함.
            if isTableRow(line), i + 1 < lines.count, isSeparatorRow(lines[i + 1]) {
                flushParagraph()
                var region: [String] = [line, lines[i + 1]]
                i += 2
                while i < lines.count, isTableRow(lines[i]), !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    region.append(lines[i])
                    i += 1
                }
                blocks.append(.table(parseTable(region)))
                continue
            }

            // 구분선 `---`(단독 줄, 3+ 하이픈) — 파이프 없는 순수 하이픈 줄. `insertDivider` 방언과 왕복.
            if isDividerLine(trimmed) {
                flushParagraph()
                blocks.append(.divider)
                i += 1
                continue
            }

            // 이미지 = 단독 줄 `![alt](url)`(하이라이터는 그럴 때만 IMAGE 로 접는다). 텍스트 섞인 줄은 문단.
            if let img = standaloneImage(trimmed) {
                flushParagraph()
                blocks.append(.image(url: img.url, alt: img.alt))
                i += 1
                continue
            }

            // 리스트 `- `/`* `/`N. `(선행 공백=중첩). 연속 항목을 각각 한 블록으로(그룹은 직렬화가 다시 묶는다).
            if let item = listItem(line) {
                flushParagraph()
                blocks.append(.listItem(item.text, ordered: item.ordered, indent: item.indent))
                i += 1
                continue
            }

            // 그 외 = 문단 — 연속 라인을 모은다.
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

    // MARK: 구분선

    /// 단독 줄 `---`(3+ 하이픈, 하이픈·공백만) — 파이프가 있으면 표 구분행이므로 여기선 배제.
    /// 방언 정본은 `---`(insertDivider). setext 밑줄(`===`)은 안 씀.
    static func isDividerLine(_ trimmed: String) -> Bool {
        guard !trimmed.isEmpty, !trimmed.contains("|") else { return false }
        let hyphens = trimmed.filter { $0 == "-" }.count
        return hyphens >= 3 && trimmed.allSatisfy { $0 == "-" || $0 == " " }
    }

    // MARK: 이미지

    /// 줄 전체가 오롯이 `![alt](url)` 하나일 때만 이미지(하이라이터 applyImages 의 "단독 이미지 줄" 규칙).
    /// title(`"…"`)은 파싱만 하고 버린다(Phase 2 왕복은 alt·url — title 은 스코프 밖).
    static func standaloneImage(_ trimmed: String) -> (alt: String, url: String)? {
        guard trimmed.hasPrefix("!["), trimmed.hasSuffix(")") else { return nil }
        // ![alt](url) — alt=`![` 와 `]` 사이, url=`(` 와 `)` 사이(공백·title 앞까지).
        guard let altOpen = trimmed.range(of: "!["),
              let altClose = trimmed.range(of: "](", range: altOpen.upperBound..<trimmed.endIndex)
        else { return nil }
        let alt = String(trimmed[altOpen.upperBound..<altClose.lowerBound])
        guard !alt.contains("]"), !alt.contains("\n") else { return nil }
        let inner = String(trimmed[altClose.upperBound..<trimmed.index(before: trimmed.endIndex)])
        // url = 첫 공백 전까지(선택 title 배제). url 자체엔 공백·닫는 괄호 없음(Regex L477).
        let url = inner.split(separator: " ", maxSplits: 1).first.map(String.init) ?? inner
        guard !url.isEmpty, !url.contains("("), !url.contains(")") else { return nil }
        // 잔여(title 등)가 있으면 반드시 `"…"` 꼴이어야(아니면 단독 이미지가 아님 → 문단).
        let rest = inner.dropFirst(url.count).trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty, !(rest.hasPrefix("\"") && rest.hasSuffix("\"")) { return nil }
        return (alt, url)
    }

    // MARK: 리스트

    /// `- `/`* `(글머리) 또는 `N. `(번호). 선행 공백 2칸=한 레벨(리더 lead/2, 최대 4).
    static func listItem(_ line: String) -> (ordered: Bool, indent: Int, text: String)? {
        let lead = line.prefix(while: { $0 == " " }).count
        let body = line.dropFirst(lead)
        let indent = min(4, lead / 2)
        if body.hasPrefix("- ") || body.hasPrefix("* ") {
            return (false, indent, String(body.dropFirst(2)))
        }
        let digits = body.prefix(while: { $0.isNumber })
        if !digits.isEmpty {
            let rest = body.dropFirst(digits.count)
            if rest.hasPrefix(". ") { return (true, indent, String(rest.dropFirst(2))) }
        }
        return nil
    }

    // MARK: 표 (GFM)

    /// 이스케이프되지 않은 `|` 가 있는 비어있지 않은 줄(표 행 후보) — hasUnescapedPipe 미러.
    static func isTableRow(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return false }
        var esc = false
        for ch in line {
            if esc { esc = false } else if ch == "\\" { esc = true } else if ch == "|" { return true }
        }
        return false
    }

    /// `| --- | :--: |` 같은 GFM 정렬 구분행인가 — `-` 를 포함하고 `|:- ` 문자만(applyTables L275).
    static func isSeparatorRow(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-"), t.contains("|") else { return false }
        return t.allSatisfy { "|:- ".contains($0) }
    }

    /// 표 영역(헤더\n구분선\n본문…) → EditorTable. 셀 파싱·정렬 읽기는 리더(TableMarkdown)와 같은 규칙.
    static func parseTable(_ region: [String]) -> EditorTable {
        guard region.count >= 2 else { return EditorTable(rows: [], alignments: []) }
        let header = tableCells(region[0])
        let alignments = separatorAlignments(region[1])
        let body = region.dropFirst(2).map(tableCells)
        let cols = max(header.count, max(alignments.count, body.map(\.count).max() ?? 0))
        func pad(_ cells: [String]) -> [String] {
            if cells.count >= cols { return Array(cells.prefix(cols)) }
            return cells + Array(repeating: "", count: cols - cells.count)
        }
        var rows: [[String]] = [pad(header)]
        rows.append(contentsOf: body.map(pad))
        let aligns: [EditorTable.Alignment] =
            (0..<cols).map { $0 < alignments.count ? alignments[$0] : .leading }
        return EditorTable(rows: rows, alignments: aligns)
    }

    /// 한 표 행 → 셀들. `\|` 는 리터럴 `|`. 양 끝 파이프가 만드는 빈 셀은 뗀다(TableMarkdown.cells 미러).
    static func tableCells(_ line: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var esc = false
        for ch in line.trimmingCharacters(in: .whitespaces) {
            if esc { cur.append(ch); esc = false }
            else if ch == "\\" { esc = true }
            else if ch == "|" { out.append(cur.trimmingCharacters(in: .whitespaces)); cur = "" }
            else { cur.append(ch) }
        }
        out.append(cur.trimmingCharacters(in: .whitespaces))
        if out.first == "" { out.removeFirst() }
        if out.last == "" { out.removeLast() }
        return out
    }

    /// 구분행 토큰 → 열 정렬(`:---:`=center · `---:`=trailing · 그 외=leading). TableMarkdown.columnAlignments 미러.
    static func separatorAlignments(_ line: String) -> [EditorTable.Alignment] {
        tableCells(line).map { token in
            let l = token.hasPrefix(":")
            let r = token.hasSuffix(":")
            if l && r { return .center }
            if r { return .trailing }
            return .leading
        }
    }
}
