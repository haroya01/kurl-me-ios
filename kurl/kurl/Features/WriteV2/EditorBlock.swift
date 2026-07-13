//
//  EditorBlock.swift
//  kurl — WriteV2 (격리 WYSIWYG 에디터, Phase 1 증명 슬라이스)
//
//  블록 모델. 에디터의 편집 단위는 "순서 있는 타입 블록"이고, 저장 계약은 마크다운 문자열이다
//  (백엔드가 md↔blocks 를 소유 — WriteAPI.replaceMarkdown/markdown, 서버가 정규화).
//  그래서 이 모델의 진실은 **왕복**이다: 마크다운 → 블록(파싱) / 블록 → 마크다운(직렬화).
//  현행 ComposeView 가 보내는 것과 같은 마크다운 방언을 목표로 한다(MarkdownSyntaxHighlighter 방언).
//
//  Phase 1 스코프: 문단 · 제목 h1~3 · 인용 · 코드[lang].
//  Phase 2 확장: 구분선 · 리스트(글머리/번호, 중첩) · 이미지 · 표. (임베드는 Phase 2+.)
//

import Foundation

/// 표 모델 — 셀 행렬(첫 행=헤더) + 열 정렬. 마크다운(GFM)과의 매핑은 `MarkdownSerializer`가 소유한다.
/// 셀 텍스트는 인라인 마크다운(파이프는 `\|` 이스케이프). 정렬은 구분선 토큰(`:---`·`:---:`·`---:`)으로 왕복.
nonisolated struct EditorTable: Equatable {
    enum Alignment: Equatable { case leading, center, trailing }
    /// 행 배열. `rows[0]` = 헤더. 각 행의 셀 수는 열 수와 같게 유지(파서가 pad/truncate).
    var rows: [[String]]
    /// 열별 정렬 — 열 수와 같은 길이. 기본 `.leading`.
    var alignments: [Alignment]

    var columnCount: Int { max(rows.first?.count ?? 0, alignments.count) }

    init(rows: [[String]], alignments: [Alignment]) {
        self.rows = rows
        self.alignments = alignments
    }

    /// 헤더 1행 + 빈 본문 1행의 2×2 새 표(툴바 삽입 기본).
    static var blank: EditorTable {
        EditorTable(rows: [["", ""], ["", ""]], alignments: [.leading, .leading])
    }
}

/// 한 블록의 종류. 라디오값(rawValue)이 아니라 편집 모델의 case 다 — 마크다운으로의 매핑은
/// `MarkdownSerializer`/`MarkdownBlockParser` 가 소유한다(BlockKind 서버 enum 과는 별개 레이어).
nonisolated enum EditorBlockKind: Equatable {
    case paragraph
    case heading(level: Int)   // 1...3
    case quote
    case code(language: String?)
    // Phase 2 —
    /// 구분선(thematic break). 비텍스트 단일 블록 — `---` 왕복. text 는 항상 빈 문자열.
    case divider
    /// 리스트 항목 한 개. `ordered`=번호, `indent`=중첩 깊이(0 최상위). 마크다운은 항목당 한 줄
    /// (`{indent*2 공백}- {text}` 또는 `{n}. {text}`). 연속 항목이 발행 시 한 리스트 블록으로 묶인다.
    case listItem(ordered: Bool, indent: Int)
    /// 이미지. 비텍스트 블록 — `url`/`alt` 왕복(`![alt](url)`). text 는 alt 를 겸한다(캐럿 규칙 단순화).
    case image(url: String)
    /// 표. 셀은 별도 2차원 편집(text 는 안 쓴다). GFM 왕복은 `EditorTable`이 담는다.
    case table(EditorTable)
}

/// 편집 단위 블록. `id` 는 SwiftUI diffing 안정용(마크다운엔 안 실림). `text` 는 블록의 원본
/// 인라인 마크다운(예: 문단은 `안녕 **볼드**`, 코드는 여러 줄 소스). 렌더는 이 text 를 최종 모습으로 보인다.
nonisolated struct EditorBlock: Identifiable, Equatable {
    let id: UUID
    var kind: EditorBlockKind
    /// 블록 본문. 문단·제목·인용 = 인라인 마크다운 한 덩어리. 코드 = 언어를 뺀 순수 소스(줄바꿈 포함).
    var text: String

    init(id: UUID = UUID(), kind: EditorBlockKind, text: String = "") {
        self.id = id
        self.kind = kind
        self.text = text
    }

    /// 편의 생성자 — 하네스·테스트 가독성.
    static func paragraph(_ text: String = "") -> EditorBlock { .init(kind: .paragraph, text: text) }
    static func heading(_ level: Int, _ text: String) -> EditorBlock {
        .init(kind: .heading(level: max(1, min(3, level))), text: text)
    }
    static func quote(_ text: String) -> EditorBlock { .init(kind: .quote, text: text) }
    static func code(_ text: String, language: String? = nil) -> EditorBlock {
        .init(kind: .code(language: language), text: text)
    }
    static var divider: EditorBlock { .init(kind: .divider, text: "") }
    /// 리스트 항목 — text 는 마커를 뗀 본문(인라인 마크다운).
    static func listItem(_ text: String, ordered: Bool = false, indent: Int = 0) -> EditorBlock {
        .init(kind: .listItem(ordered: ordered, indent: max(0, min(4, indent))), text: text)
    }
    /// 이미지 — url 은 kind 에, alt 는 text 에 담는다(캐럿 규칙은 비텍스트로 취급).
    static func image(url: String, alt: String = "") -> EditorBlock {
        .init(kind: .image(url: url), text: alt)
    }
    static func table(_ table: EditorTable) -> EditorBlock { .init(kind: .table(table), text: "") }

    /// 코드 블록만 여러 줄을 한 블록에 담는다 — 나머지는 개념상 한 줄(문단은 소프트랩).
    var isMultiline: Bool {
        if case .code = kind { return true }
        return false
    }

    var isEmptyParagraph: Bool {
        if case .paragraph = kind { return text.isEmpty }
        return false
    }

    /// 캐럿을 담을 수 없는 블록(구분선·이미지·표) — 엔터/백스페이스/분할·병합 규칙이 텍스트 블록과 다르다.
    var isNonText: Bool {
        switch kind {
        case .divider, .image, .table: return true
        default: return false
        }
    }

    /// 이 블록이 리스트 항목이면 (ordered, indent).
    var listInfo: (ordered: Bool, indent: Int)? {
        if case .listItem(let ordered, let indent) = kind { return (ordered, indent) }
        return nil
    }
}

/// 문서 = 순서 있는 블록 배열. 편집 연산(분할·병합·삽입·삭제)은 `EditorDocument`(별 파일)가 소유.
nonisolated struct EditorBlockList: Equatable {
    var blocks: [EditorBlock]

    init(blocks: [EditorBlock] = [.paragraph("")]) {
        self.blocks = blocks.isEmpty ? [.paragraph("")] : blocks
    }
}
