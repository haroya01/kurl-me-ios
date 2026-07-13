//
//  EditorBlock.swift
//  kurl — WriteV2 (격리 WYSIWYG 에디터, Phase 1 증명 슬라이스)
//
//  블록 모델. 에디터의 편집 단위는 "순서 있는 타입 블록"이고, 저장 계약은 마크다운 문자열이다
//  (백엔드가 md↔blocks 를 소유 — WriteAPI.replaceMarkdown/markdown, 서버가 정규화).
//  그래서 이 모델의 진실은 **왕복**이다: 마크다운 → 블록(파싱) / 블록 → 마크다운(직렬화).
//  현행 ComposeView 가 보내는 것과 같은 마크다운 방언을 목표로 한다(MarkdownSyntaxHighlighter 방언).
//
//  Phase 1 스코프: 문단 · 제목 h1~3 · 인용 · 코드[lang]. 리스트/표/이미지/구분선/임베드는 Phase 2+.
//

import Foundation

/// 한 블록의 종류. 라디오값(rawValue)이 아니라 편집 모델의 case 다 — 마크다운으로의 매핑은
/// `MarkdownSerializer`/`MarkdownBlockParser` 가 소유한다(BlockKind 서버 enum 과는 별개 레이어).
nonisolated enum EditorBlockKind: Equatable {
    case paragraph
    case heading(level: Int)   // 1...3
    case quote
    case code(language: String?)
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

    /// 코드 블록만 여러 줄을 한 블록에 담는다 — 나머지는 개념상 한 줄(문단은 소프트랩).
    var isMultiline: Bool {
        if case .code = kind { return true }
        return false
    }

    var isEmptyParagraph: Bool {
        if case .paragraph = kind { return text.isEmpty }
        return false
    }
}

/// 문서 = 순서 있는 블록 배열. 편집 연산(분할·병합·삽입·삭제)은 `EditorDocument`(별 파일)가 소유.
nonisolated struct EditorBlockList: Equatable {
    var blocks: [EditorBlock]

    init(blocks: [EditorBlock] = [.paragraph("")]) {
        self.blocks = blocks.isEmpty ? [.paragraph("")] : blocks
    }
}
