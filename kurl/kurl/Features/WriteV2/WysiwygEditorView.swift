//
//  WysiwygEditorView.swift
//  kurl — WriteV2 (격리 WYSIWYG 에디터)
//
//  블록별 WYSIWYG 캔버스. 각 블록이 최종 모습(제목=큰 글씨·인용=그린 바·코드=박스)으로 렌더+편집되고
//  원시 마크다운은 안 보인다. 종이 세계(§1) — 순백 캔버스, 유리 없음. 읽기 컬럼 672(Metrics).
//  ComposeView 를 안 건드리고 이 뷰만으로 단독 실행(하네스: EditorHarnessView / --screen editor2).
//

import SwiftUI
import UIKit

struct WysiwygEditorView: View {
    @State private var document: EditorDocument
    /// 붙여넣기 훅 — 호스트(컴포즈)가 업로드·재호스팅·단축을 잇는다. 하네스는 기본값(빈 훅)으로 돈다.
    private let pasteHandlers: EditorPasteHandlers
    @ScaledMetric(relativeTo: .body) private var placeholderSize: CGFloat = 18

    init(document: EditorDocument, pasteHandlers: EditorPasteHandlers = EditorPasteHandlers()) {
        _document = State(initialValue: document)
        self.pasteHandlers = pasteHandlers
    }

    var body: some View {
        // 뷰포트 높이를 알아야 본문 아래 남는 공간 전부가 "이어 쓰기" 탭 활주로가 된다 —
        // 블록 UITextView 밖(빈 캔버스)을 탭하면 아무 일도 없던 것이 이 캔버스의 첫 사망 원인이었다.
        GeometryReader { viewport in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(document.blocks) { block in
                        row(for: block)
                            .padding(.vertical, verticalPadding(for: block.kind))
                    }
                    // 본문 아래 남는 화면 전부 — 탭하면 문서 끝에서 이어 쓴다(빈 문서 = 화면 전체가 입력 진입점).
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 120)
                        .contentShape(.rect)
                        .onTapGesture { document.focusTail() }
                        .accessibilityElement()
                        .accessibilityLabel(Text("본문 이어 쓰기"))
                        .accessibilityAddTraits(.isButton)
                }
                .overlay(alignment: .topLeading) {
                    if isBlankDocument {
                        Text("본문을 입력하세요")
                            .font(.system(size: placeholderSize))
                            .foregroundStyle(Palette.secondary)
                            .padding(.vertical, verticalPadding(for: .paragraph))
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                // 읽기 컬럼(672)을 중앙 정렬하되, 좁은 화면에선 좌우 거터로 안전하게 인셋한다.
                .padding(.horizontal, Metrics.gutter)
                .frame(maxWidth: Metrics.readingColumn, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
                // 콘텐츠가 짧아도 뷰포트를 꽉 채운다 — 위 활주로(Color.clear)가 남는 높이를 전부 흡수.
                .frame(minHeight: viewport.size.height, alignment: .top)
            }
            .background(Palette.readingBg)
            .scrollDismissesKeyboard(.interactively)
            .contentMargins(.horizontal, 0, for: .scrollContent)
        }
    }

    // MARK: 블록 행 — 종류별 최종 모습 장식

    @ViewBuilder
    private func row(for block: EditorBlock) -> some View {
        switch block.kind {
        case .code:
            BlockCodeView(
                block: block,
                isFocused: document.focus?.blockID == block.id && document.isEditing,
                onTextChange: { document.updateText(block.id, $0) },
                onFocused: { document.focus = EditorFocus(blockID: block.id, caret: block.text.count) },
                onMergeBackward: { document.mergeBackward(block.id) },
                documentUndoManager: document.undoManager,
                onEditingEnded: { document.endEditing(block.id) },
                onSeparateEdit: { document.breakUndoCoalescing() },
                onCompositionChange: { document.setComposition(block.id, active: $0) }
            )
        case .divider:
            BlockDividerView(
                isFocused: document.focus?.blockID == block.id,
                onFocused: { document.focus = EditorFocus(blockID: block.id, caret: 0) },
                onDelete: { deleteNonTextBlock(block.id, undoLabel: String(localized: "구분선을 지웠어요")) }
            )
        case .linkCard(let url):
            BlockLinkCardView(
                url: url,
                isFocused: document.focus?.blockID == block.id,
                onFocused: { document.focus = EditorFocus(blockID: block.id, caret: 0) },
                onDelete: { deleteNonTextBlock(block.id, undoLabel: String(localized: "링크 카드를 지웠어요")) }
            )
        case .image:
            BlockImageView(
                block: block,
                isFocused: document.focus?.blockID == block.id,
                onAltChange: { document.updateText(block.id, $0) },
                onDelete: { deleteImage(block.id) },
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
                onDeleteRow: { deleteTableRow(block.id) },
                onDeleteColumn: { deleteTableColumn(block.id) },
                onDeleteTable: { deleteNonTextBlock(block.id, undoLabel: String(localized: "표를 지웠어요")) },
                onFocused: { document.focus = EditorFocus(blockID: block.id, caret: 0) },
                documentUndoManager: document.undoManager,
                onEditingEnded: { document.endEditing(block.id) },
                onCellCompositionChange: { document.setTableComposition(block.id, row: $0, col: $1, active: $2) }
            )
        default:
            textRow(block)
        }
    }

    /// Paragraph, heading, quote and list use one stable UIKit position in the view tree.
    /// Enter can remove the quote/list decoration while the same responder keeps accepting keys.
    private func textRow(_ block: EditorBlock) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if case .listItem(let ordered, _) = block.kind {
                Text(marker(for: block, ordered: ordered))
                    .font(.system(size: 18))
                    .foregroundStyle(Palette.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 18, alignment: .trailing)
            }
            textBlock(block)
                .alignmentGuide(.firstTextBaseline) { dimensions in
                    block.listInfo != nil ? Self.listItemFirstBaseline : dimensions[.firstTextBaseline]
                }
        }
        .padding(.leading, block.kind == .quote ? 17 : 0)
        .overlay(alignment: .leading) {
            if block.kind == .quote {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Palette.accentSoft)
                    .frame(width: 3)
            }
        }
        .padding(.leading, CGFloat(block.listInfo?.indent ?? 0) * 18)
    }

    /// 리스트 항목 블록(18pt 본문 스케일)의 첫 줄 베이스라인 — BlockInlineRenderer.baseFont(.listItem) 와
    /// 같은 폰트의 ascender. 빈 텍스트뷰의 베이스라인 명시(위 alignmentGuide)에 쓴다.
    private static var listItemFirstBaseline: CGFloat {
        UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 18)).ascender
    }

    /// 리스트 항목 마커 — 글머리는 `•`, 번호는 같은 indent 의 연속 항목 순번(1,2,3…).
    /// 발행 렌더가 재번호하므로 여기 순번은 화면 표시용(왕복 번호는 직렬화가 책임).
    private func marker(for block: EditorBlock, ordered: Bool) -> String {
        guard ordered, let (_, indent) = block.listInfo else { return "•" }
        guard let idx = document.blocks.firstIndex(where: { $0.id == block.id }) else { return "1." }
        return "\(Self.ordinal(at: idx, indent: indent, in: document.blocks))."
    }

    static func ordinal(at idx: Int, indent: Int, in blocks: [EditorBlock]) -> Int {
        var n = 1
        var i = idx - 1
        while i >= 0, let info = blocks[i].listInfo, info.indent >= indent {
            if info.indent == indent {
                guard info.ordered else { break }
                n += 1
            }
            i -= 1
        }
        return n
    }

    private func textBlock(_ block: EditorBlock) -> some View {
        let isFocused = document.focus?.blockID == block.id && document.isEditing
        return BlockTextView(
            block: block,
            isFocused: isFocused,
            caretOnFocus: isFocused ? (document.focus?.caret ?? 0) : 0,
            selectionLengthOnFocus: isFocused ? (document.focus?.selectionLength ?? 0) : 0,
            // 툴바 서식 직후 1회 마커 숨김(B1) — 이 블록이 억제 대상이면 렌더가 반개봉을 건너뛴다.
            suppressRevealOnce: document.suppressRevealOnceBlockID == block.id,
            onRevealSuppressConsumed: {
                if document.suppressRevealOnceBlockID == block.id {
                    document.suppressRevealOnceBlockID = nil
                }
            },
            onTextChange: { document.updateText(block.id, $0) },
            onSplit: { caret, length in
                guard let target = document.splitBlock(block.id, at: caret, deleting: length),
                      let continuation = document.blocks.first(where: { $0.id == target.blockID }) else { return nil }
                return EditorSplitContinuation(block: continuation, caret: target.caret)
            },
            onMergeBackward: { document.mergeBackward(block.id) },
            onLineHeadShortcut: { kind, stripped, caret in
                document.transform(block.id, to: kind, strippedText: stripped, caret: caret)
            },
            onFocused: {
                document.isEditing = true
                if document.focus?.blockID != block.id {
                    document.focus = EditorFocus(blockID: block.id, caret: block.text.count)
                }
            },
            onSelectionChange: { caret, length in
                // 라이브 선택을 문서에 반영 — 서식 툴바가 이 선택을 감싼다. 포커스 블록일 때만.
                if document.focus?.blockID == block.id {
                    document.focus = EditorFocus(blockID: block.id, caret: caret, selectionLength: length)
                }
            },
            pasteHandlers: pasteHandlers,
            documentUndoManager: document.undoManager,
            onEditingEnded: { document.endEditing(block.id) },
            onSeparateEdit: { document.breakUndoCoalescing() },
            onCompositionChange: { document.setComposition(block.id, active: $0) }
        )
    }

    /// 표 행 삭제 + 되돌리기 토스트 — 문서 히스토리와 함께 특정 표 스냅샷 복원도 제공한다
    /// (레거시 TableActionBar 의 실행취소 토스트 문법 미러). 지운 게 없으면 조용히 무동작.
    private func deleteTableRow(_ id: UUID) {
        guard let before = document.tableSnapshot(id), document.deleteTableRow(id) else { return }
        ToastCenter.shared.show(String(localized: "행을 지웠어요"), actionLabel: String(localized: "실행취소")) {
            document.restoreTable(id, to: before)
        }
    }

    /// 표 열 삭제 + 되돌리기 토스트 — 위와 동일(스냅샷 복원).
    private func deleteTableColumn(_ id: UUID) {
        guard let before = document.tableSnapshot(id), document.deleteTableColumn(id) else { return }
        ToastCenter.shared.show(String(localized: "열을 지웠어요"), actionLabel: String(localized: "실행취소")) {
            document.restoreTable(id, to: before)
        }
    }

    /// 이미지 블록 삭제 + 되돌리기 토스트 — 지운 블록을 원래 자리에 되돌린다(레거시 removeImage 미러).
    private func deleteImage(_ id: UUID) {
        deleteNonTextBlock(id, undoLabel: String(localized: "이미지를 지웠어요"))
    }

    /// 비텍스트 블록(구분선·이미지·표) 통째 삭제 + 되돌리기 토스트 — 지운 블록을 원래 자리에 되돌린다.
    /// 비텍스트 블록은 캐럿을 못 받아 백스페이스로만 지워지던 걸(뒤 문단 트릭) 명시적 삭제 버튼의 정답 경로로.
    private func deleteNonTextBlock(_ id: UUID, undoLabel: String) {
        guard let removed = document.removeBlock(id) else { return }
        ToastCenter.shared.show(undoLabel, actionLabel: String(localized: "실행취소")) {
            document.restoreBlock(removed.block, afterId: removed.afterId)
        }
    }

    private var isBlankDocument: Bool {
        guard document.blocks.count == 1, let only = document.blocks.first else { return false }
        if case .paragraph = only.kind { return only.text.isEmpty }
        return false
    }

    private func verticalPadding(for kind: EditorBlockKind) -> CGFloat {
        switch kind {
        case .heading(let level): return level == 1 ? 12 : level == 2 ? 10 : 8
        case .code: return 8
        case .quote: return 6
        case .paragraph: return 4
        case .listItem: return 3
        case .divider: return 4
        case .linkCard: return 8
        case .image: return 10
        case .table: return 8
        }
    }
}
