//
//  WysiwygEditorView.swift
//  kurl — WriteV2 (격리 WYSIWYG 에디터)
//
//  블록별 WYSIWYG 캔버스. 각 블록이 최종 모습(제목=큰 글씨·인용=그린 바·코드=박스)으로 렌더+편집되고
//  원시 마크다운은 안 보인다. 종이 세계(§1) — 순백 캔버스, 유리 없음. 읽기 컬럼 672(Metrics).
//  ComposeView 를 안 건드리고 이 뷰만으로 단독 실행(하네스: EditorHarnessView / --screen editor2).
//

import SwiftUI

struct WysiwygEditorView: View {
    @State private var document: EditorDocument

    init(document: EditorDocument) {
        _document = State(initialValue: document)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(document.blocks) { block in
                    row(for: block)
                        .padding(.vertical, verticalPadding(for: block.kind))
                }
            }
            // 읽기 컬럼(672)을 중앙 정렬하되, 좁은 화면에선 좌우 거터로 안전하게 인셋한다.
            .padding(.horizontal, Metrics.gutter)
            .frame(maxWidth: Metrics.readingColumn, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
        }
        .background(Palette.readingBg)
        .scrollDismissesKeyboard(.interactively)
        .contentMargins(.horizontal, 0, for: .scrollContent)
    }

    // MARK: 블록 행 — 종류별 최종 모습 장식

    @ViewBuilder
    private func row(for block: EditorBlock) -> some View {
        switch block.kind {
        case .code:
            BlockCodeView(
                block: block,
                isFocused: document.focus?.blockID == block.id,
                onTextChange: { document.updateText(block.id, $0) },
                onFocused: { document.focus = EditorFocus(blockID: block.id, caret: block.text.count) },
                onMergeBackward: { document.mergeBackward(block.id) }
            )
        case .quote:
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Palette.accentSoft)
                    .frame(width: 3)
                    .padding(.trailing, 14)
                textBlock(block)
            }
        default:
            textBlock(block)
        }
    }

    private func textBlock(_ block: EditorBlock) -> some View {
        BlockTextView(
            block: block,
            isFocused: document.focus?.blockID == block.id,
            caretOnFocus: document.focus?.blockID == block.id ? (document.focus?.caret ?? 0) : 0,
            onTextChange: { document.updateText(block.id, $0) },
            onSplit: { document.splitBlock(block.id, at: $0) },
            onMergeBackward: { document.mergeBackward(block.id) },
            onLineHeadShortcut: { kind, stripped, caret in
                document.transform(block.id, to: kind, strippedText: stripped, caret: caret)
            },
            onFocused: {
                if document.focus?.blockID != block.id {
                    document.focus = EditorFocus(blockID: block.id, caret: block.text.count)
                }
            }
        )
    }

    private func verticalPadding(for kind: EditorBlockKind) -> CGFloat {
        switch kind {
        case .heading(let level): return level == 1 ? 12 : level == 2 ? 10 : 8
        case .code: return 8
        case .quote: return 6
        case .paragraph: return 4
        }
    }
}
