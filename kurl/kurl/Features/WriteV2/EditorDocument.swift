//
//  EditorDocument.swift
//  kurl — WriteV2
//
//  편집 모델. 블록 배열 + 포커스 + 편집 연산(엔터=분할 · 백스페이스=병합 · 삽입/삭제 ·
//  줄머리 마크다운 지름길). 뷰(WysiwygEditorView)는 이 @Observable 하나에만 말을 건다 —
//  per-block UITextView 는 텍스트/캐럿만 위임하고 구조 변경은 전부 여기서 일어난다.
//
//  아키텍처 선택(§4): "블록 = per-block UITextView" 를 택했다.
//   • 이유: 현행 앱이 이미 UITextView(MarkdownTextView) 로 한글 IME·선택·하이라이트를 다룬다.
//     블록별 UITextView 는 그 자산(마커드텍스트 가드·타이핑 속성)을 블록 경계 안에서 재사용한다.
//   • 어려운 부분(명시): (1) 블록 경계에서의 엔터/백스페이스를 shouldChangeText 로 가로채 구조
//     연산으로 승격 (2) 분할/병합 후 캐럿을 옮긴 블록의 정확한 오프셋으로 복원 (3) 새 블록이
//     first responder 를 이어받게 하는 포커스 핸드오프. 이 세 지점이 per-block 아키텍처의 세금이다.
//

import SwiftUI

/// 어느 블록의 어디에 캐럿이 있는지 — 포커스 핸드오프의 좌표.
nonisolated struct EditorFocus: Equatable {
    var blockID: UUID
    /// 블록 text 안 캐럿 위치(UTF-16 오프셋 아님, Swift String 인덱스 거리). 병합/분할 복원에 쓴다.
    var caret: Int
}

@MainActor
@Observable
final class EditorDocument {
    private(set) var blocks: [EditorBlock]
    /// 포커스 — 뷰가 이 값 변화를 보고 해당 블록 UITextView 를 first responder 로 만들고 캐럿을 놓는다.
    var focus: EditorFocus?

    init(blocks: [EditorBlock] = [.paragraph("")]) {
        self.blocks = blocks.isEmpty ? [.paragraph("")] : blocks
    }

    convenience init(markdown: String) {
        self.init(blocks: MarkdownBlockParser.parse(markdown))
    }

    /// 현재 문서를 마크다운으로(저장·왕복 검증 진입점).
    var markdown: String { MarkdownSerializer.markdown(from: blocks) }

    // MARK: 인덱싱

    func index(of id: UUID) -> Int? { blocks.firstIndex { $0.id == id } }

    // MARK: 텍스트 갱신 (구조 변경 없음)

    /// 뷰가 블록 안 타이핑을 반영 — 구조는 그대로, text 만 바꾼다.
    func updateText(_ id: UUID, _ newText: String) {
        guard let i = index(of: id) else { return }
        blocks[i].text = newText
    }

    // MARK: 엔터 = 분할

    /// 블록 `id` 의 caret 위치에서 엔터. 코드 블록 안 엔터는 분할이 아니라 개행(뷰가 처리) —
    /// 여기 오는 엔터는 "블록을 가르는" 엔터다. caret 앞은 현재 블록, 뒤는 새 블록으로.
    /// 반환: 새로 포커스를 받아야 하는 (blockID, caret=0).
    @discardableResult
    func splitBlock(_ id: UUID, at caret: Int) -> EditorFocus? {
        guard let i = index(of: id) else { return nil }
        let block = blocks[i]
        let clamped = max(0, min(caret, block.text.count))
        let cut = block.text.index(block.text.startIndex, offsetBy: clamped)
        let head = String(block.text[..<cut])
        let tail = String(block.text[cut...])

        blocks[i].text = head

        // 제목/인용 뒤로 엔터를 치면 새 줄은 문단으로 떨어진다(에디터 관습) — 단 내용이 남은
        // 뒷부분이 있으면 같은 종류를 유지(제목 중간에서 가른 경우).
        let newKind: EditorBlockKind = {
            switch block.kind {
            case .heading, .quote:
                return tail.isEmpty ? .paragraph : block.kind
            case .paragraph:
                return .paragraph
            case .code:
                return .paragraph  // 코드 분할은 뷰가 개행으로 흡수하므로 여기 안 옴(안전 기본).
            }
        }()

        let newBlock = EditorBlock(kind: newKind, text: tail)
        blocks.insert(newBlock, at: i + 1)
        let f = EditorFocus(blockID: newBlock.id, caret: 0)
        focus = f
        return f
    }

    // MARK: 백스페이스 = 병합

    /// 블록 `id` 의 맨 앞(caret==0)에서 백스페이스 → 앞 블록과 병합. 앞 블록 끝에 캐럿을 남긴다.
    /// 첫 블록이면 종류만 문단으로 강등(제목/인용 → 문단; 이미 문단이면 무시).
    /// 반환: 병합 후 포커스(앞 블록, caret=앞 블록 원래 길이).
    @discardableResult
    func mergeBackward(_ id: UUID) -> EditorFocus? {
        guard let i = index(of: id) else { return nil }
        guard i > 0 else {
            // 첫 블록에서 앞이 없으면: 제목/인용을 문단으로 내린다(마커 제거 UX).
            if case .paragraph = blocks[i].kind {
                return nil
            }
            blocks[i].kind = .paragraph
            let f = EditorFocus(blockID: blocks[i].id, caret: 0)
            focus = f
            return f
        }
        let prev = blocks[i - 1]
        // 코드 블록과의 병합은 종류가 섞이므로 막는다(빈 현재 블록만 삭제하고 앞으로 포커스).
        if case .code = prev.kind {
            let caret = prev.text.count
            if blocks[i].text.isEmpty { blocks.remove(at: i) }
            let f = EditorFocus(blockID: prev.id, caret: caret)
            focus = f
            return f
        }

        let joinCaret = prev.text.count
        blocks[i - 1].text = prev.text + blocks[i].text
        // 병합 시 앞 블록의 종류를 따른다(문단으로 붙는 게 관습 — 제목에 문단을 이어붙이면 제목 유지).
        blocks.remove(at: i)
        let f = EditorFocus(blockID: blocks[i - 1].id, caret: joinCaret)
        focus = f
        return f
    }

    // MARK: 블록 종류 전환 (줄머리 마크다운 지름길)

    /// 줄머리 지름길을 블록 종류 전환으로 승격 — 뷰가 `> `·`# `·```` 를 감지해 부른다.
    /// text 는 마커를 뗀 나머지. 전환 후 caret 을 새 text 기준으로 되돌린다.
    func transform(_ id: UUID, to kind: EditorBlockKind, strippedText: String, caret: Int) {
        guard let i = index(of: id) else { return }
        blocks[i].kind = kind
        blocks[i].text = strippedText
        focus = EditorFocus(blockID: id, caret: max(0, min(caret, strippedText.count)))
    }

    // MARK: 삽입 · 삭제

    func insertBlock(_ block: EditorBlock, after id: UUID) {
        guard let i = index(of: id) else { blocks.append(block); return }
        blocks.insert(block, at: i + 1)
        focus = EditorFocus(blockID: block.id, caret: 0)
    }

    func deleteBlock(_ id: UUID) {
        guard blocks.count > 1, let i = index(of: id) else { return }
        blocks.remove(at: i)
        let target = blocks[max(0, i - 1)]
        focus = EditorFocus(blockID: target.id, caret: target.text.count)
    }
}
