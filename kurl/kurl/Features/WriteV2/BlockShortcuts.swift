//
//  BlockShortcuts.swift
//  kurl — WriteV2
//
//  줄머리 마크다운 지름길 — 마크다운을 "입력 수단"으로만 쓴다. 문단 블록 맨 앞에 `# `/`> `/```` 를
//  치면 블록 종류가 바뀌고 마커 글자는 사라진다(원시 마크다운 안 보임). 인라인 `**볼드**` 는 치는
//  즉시 볼드로 렌더(BlockInlineRenderer) — 이건 종류 전환이 아니라 스타일이라 여기서 안 다룬다.
//

import Foundation

nonisolated struct BlockShortcut {
    let kind: EditorBlockKind
    let strippedText: String
    let caret: Int
}

nonisolated enum BlockShortcuts {
    /// 문단에서만 종류 전환을 켠다(이미 제목/인용/코드면 지름길 재적용 안 함 — 마커를 리터럴로 칠 수 있게).
    /// 트리거는 "줄머리 마커 + 공백"(제목·인용) 또는 "``` "(코드). 마커를 뗀 나머지를 새 text 로.
    static func detect(in text: String, kind: EditorBlockKind) -> BlockShortcut? {
        guard case .paragraph = kind else { return nil }

        // 제목 `# `/`## `/`### `
        if let h = headingShortcut(text) { return h }

        // 인용 `> `
        if text.hasPrefix("> ") {
            let stripped = String(text.dropFirst(2))
            return BlockShortcut(kind: .quote, strippedText: stripped, caret: 0)
        }
        if text == "> " { // 마커만 친 순간
            return BlockShortcut(kind: .quote, strippedText: "", caret: 0)
        }

        // 코드펜스 ``` (언어 선택). 여는 펜스만 친 순간 코드 블록으로.
        if text.hasPrefix("```") {
            let after = String(text.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            return BlockShortcut(kind: .code(language: after.isEmpty ? nil : after), strippedText: "", caret: 0)
        }

        return nil
    }

    /// `# `/`## `/`### ` (해시 1~3 + 공백). 해시만·해시+비공백은 지름길 아님(리터럴 유지).
    private static func headingShortcut(_ text: String) -> BlockShortcut? {
        var count = 0
        for ch in text {
            if ch == "#" { count += 1 } else { break }
        }
        guard count >= 1, count <= 3 else { return nil }
        let after = text.dropFirst(count)
        guard after.first == " " else { return nil }
        let stripped = String(after.dropFirst())
        return BlockShortcut(kind: .heading(level: count), strippedText: stripped, caret: 0)
    }
}
