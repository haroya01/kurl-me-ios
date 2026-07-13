//
//  BlockTableView.swift
//  kurl — WriteV2 (Phase 2)
//
//  표 블록 — 셀별 2차원 편집(셀 하나당 작은 UITextView 서브에디터). 격자로 렌더하고 그 안에서 바로
//  친다(원시 GFM `| … |` 는 안 보인다). 발행면 TableBlockView(BlockRenderer)의 그리드 문법을
//  종이 세계(§1)에서 재현: 헤더 진한 하단 룰 + 행마다 얇은 룰 + 열 정렬. 왕복은 EditorTable↔GFM.
//
//  가장 어려운 지점(§4): (1) 셀 UITextView 서브에디터를 격자에 배치하되 SwiftUI 폭 안에서 줄바꿈
//  (2) 표 편집(행·열 추가, 정렬 순환)이 EditorTable 을 통해 문서로 흘러가게 (3) 셀 포커스는 셀 자체
//  UITextView 에 맡기고 블록 캐럿 규칙과 분리(비텍스트 블록으로 취급). 블록 간 선택·통합은 Phase 2b.
//

import SwiftUI
import UIKit

struct BlockTableView: View {
    let block: EditorBlock
    let isFocused: Bool
    let onCellChange: (Int, Int, String) -> Void
    let onAddRow: () -> Void
    let onAddColumn: () -> Void
    let onAlignColumn: (Int) -> Void
    let onFocused: () -> Void

    private var table: EditorTable? {
        if case .table(let t) = block.kind { return t }
        return nil
    }

    var body: some View {
        if let table {
            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    grid(table)
                }
                controls(table)
            }
            .padding(.vertical, 6)
            .overlay(alignment: .topLeading) {
                if isFocused {
                    RoundedRectangle(cornerRadius: Metrics.radiusControl)
                        .strokeBorder(Palette.accentSoft.opacity(0.5), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(.rect)
            .onTapGesture { onFocused() }
        }
    }

    private func grid(_ table: EditorTable) -> some View {
        let cols = table.columnCount
        return Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(Array(table.rows.enumerated()), id: \.offset) { r, row in
                GridRow {
                    ForEach(0..<cols, id: \.self) { c in
                        TableCellEditor(
                            text: c < row.count ? row[c] : "",
                            isHeader: r == 0,
                            alignment: c < table.alignments.count ? table.alignments[c] : .leading,
                            onChange: { onCellChange(r, c, $0) },
                            onFocused: onFocused
                        )
                        .frame(minWidth: 96, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .overlay(alignment: .trailing) {
                            if c < cols - 1 {
                                Rectangle().fill(Palette.hairline).frame(width: 1)
                            }
                        }
                    }
                }
                Rectangle()
                    .fill(r == 0 ? Palette.hairlineStrong : Palette.hairline)
                    .frame(height: r == 0 ? 2 : 1)
            }
        }
    }

    private func controls(_ table: EditorTable) -> some View {
        HStack(spacing: 14) {
            Button(action: onAddRow) {
                Label("행", systemImage: "plus").labelStyle(.titleAndIcon)
            }
            Button(action: onAddColumn) {
                Label("열", systemImage: "plus").labelStyle(.titleAndIcon)
            }
            // 열 정렬 순환 — 현재 포커스 열을 모르므로 첫 열부터 순환(Phase 2b: 캐럿 열 감지).
            Menu {
                ForEach(0..<table.columnCount, id: \.self) { c in
                    Button("열 \(c + 1) 정렬 (\(alignLabel(table, c)))") { onAlignColumn(c) }
                }
            } label: {
                Label("정렬", systemImage: "text.alignleft")
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Palette.link)
    }

    private func alignLabel(_ table: EditorTable, _ c: Int) -> String {
        switch c < table.alignments.count ? table.alignments[c] : .leading {
        case .leading: return "왼쪽"
        case .center: return "가운데"
        case .trailing: return "오른쪽"
        }
    }
}

/// 셀 하나 — 작은 UITextView. 개행은 금지(표 셀은 한 줄; 개행은 GFM 행을 깨므로 무시).
private struct TableCellEditor: UIViewRepresentable {
    let text: String
    let isHeader: Bool
    let alignment: EditorTable.Alignment
    let onChange: (String) -> Void
    let onFocused: () -> Void

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        apply(tv)
        return tv
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width < .infinity else { return nil }
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fit.height)
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        if tv.text != text { apply(tv) }
    }

    private func apply(_ tv: UITextView) {
        tv.text = text
        tv.font = .systemFont(ofSize: 15, weight: isHeader ? .semibold : .regular)
        tv.textColor = UIColor(isHeader ? Palette.ink : Palette.body)
        tv.textAlignment = {
            switch alignment {
            case .leading: return .left
            case .center: return .center
            case .trailing: return .right
            }
        }()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: TableCellEditor
        init(_ parent: TableCellEditor) { self.parent = parent }

        func textViewDidBeginEditing(_ textView: UITextView) { parent.onFocused() }

        func textView(
            _ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String
        ) -> Bool {
            text != "\n"  // 셀 안 개행 금지 — 한 줄 셀(GFM 행 무결).
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.onChange(textView.text ?? "")
        }
    }
}
