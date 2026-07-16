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
                    // 빈 UITextView 는 SwiftUI 에 베이스라인을 못 줘 firstTextBaseline 정렬이
                    // 틀어진다 — 마커는 제자리인데 캐럿이 한 줄 아래로 보였다(글머리/번호 토글 직후).
                    // 블록 폰트의 ascender 로 첫 줄 베이스라인을 명시해 빈·비어있지 않은 항목 모두
                    // 마커와 같은 줄에 선다(textContainerInset=0 이라 top+ascender 가 곧 첫 베이스라인).
                    .alignmentGuide(.firstTextBaseline) { _ in Self.listItemFirstBaseline }
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
                onFocused: { document.focus = EditorFocus(blockID: block.id, caret: 0) }
            )
        default:
            textBlock(block)
        }
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
        let isFocused = document.focus?.blockID == block.id
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
            onSplit: { document.splitBlock(block.id, at: $0) },
            onMergeBackward: { document.mergeBackward(block.id) },
            onLineHeadShortcut: { kind, stripped, caret in
                document.transform(block.id, to: kind, strippedText: stripped, caret: caret)
            },
            onFocused: {
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
            pasteHandlers: pasteHandlers
        )
    }

    /// 표 행 삭제 + 되돌리기 토스트 — EditorDocument 엔 undo 스택이 없어 스냅샷 복원으로 되돌린다
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
        guard let removed = document.removeBlock(id) else { return }
        ToastCenter.shared.show(String(localized: "이미지를 지웠어요"), actionLabel: String(localized: "실행취소")) {
            document.restoreBlock(removed.block, afterId: removed.afterId)
        }
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
