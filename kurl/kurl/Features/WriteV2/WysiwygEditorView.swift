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
        case .listItem(let ordered, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(marker(for: block, ordered: ordered))
                    .font(.system(size: 18))
                    .foregroundStyle(Palette.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 18, alignment: .trailing)
                textBlock(block)
            }
            .padding(.leading, CGFloat(indent) * 18)
        case .divider:
            BlockDividerView(
                isFocused: document.focus?.blockID == block.id,
                onFocused: { document.focus = EditorFocus(blockID: block.id, caret: 0) }
            )
        case .image:
            BlockImageView(
                block: block,
                isFocused: document.focus?.blockID == block.id,
                onAltChange: { document.updateText(block.id, $0) },
                onFocused: { document.focus = EditorFocus(blockID: block.id, caret: 0) }
            )
        case .table:
            BlockTableView(
                block: block,
                isFocused: document.focus?.blockID == block.id,
                onCellChange: { document.updateTableCell(block.id, row: $0, col: $1, text: $2) },
                onAddRow: { document.addTableRow(block.id) },
                onAddColumn: { document.addTableColumn(block.id) },
                onAlignColumn: { document.cycleTableColumnAlignment(block.id, col: $0) },
                onFocused: { document.focus = EditorFocus(blockID: block.id, caret: 0) }
            )
        default:
            textBlock(block)
        }
    }

    /// 리스트 항목 마커 — 글머리는 `•`, 번호는 같은 indent 의 연속 항목 순번(1,2,3…).
    /// 발행 렌더가 재번호하므로 여기 순번은 화면 표시용(왕복 번호는 직렬화가 책임).
    private func marker(for block: EditorBlock, ordered: Bool) -> String {
        guard ordered, let (_, indent) = block.listInfo else { return "•" }
        guard let idx = document.blocks.firstIndex(where: { $0.id == block.id }) else { return "1." }
        var n = 1
        var i = idx - 1
        while i >= 0, let info = document.blocks[i].listInfo, info.ordered, info.indent == indent {
            n += 1
            i -= 1
        }
        // 사이에 다른 indent 항목이 있으면 위 루프가 끊긴다 — 같은 indent 연속만 센다.
        return "\(n)."
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
        case .listItem: return 3
        case .divider: return 4
        case .image: return 10
        case .table: return 8
        }
    }
}
