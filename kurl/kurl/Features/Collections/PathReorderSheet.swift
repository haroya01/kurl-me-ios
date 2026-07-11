//
//  PathReorderSheet.swift
//  kurl
//
//  길(PATH)의 연결 순서를 드래그로 짠다 — PATH 에선 이 순서가 곧 논증의 흐름이다(A 척추 Stage 3).
//  네이티브 List `.onMove` 로 끌어 옮기고, 저장 시 백엔드 reorder(연결 id 전체 순서) 한 번.
//

import SwiftUI

struct PathReorderSheet: View {
    let detail: CollectionDetail
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [ConnectionItem]
    /// 순번 배지 — 사다리에 딱 맞는 롤이 없어 크기 보존 + Dynamic Type.
    @ScaledMetric(relativeTo: .caption) private var indexSize: CGFloat = 12
    @State private var saving = false

    // 순서가 그대로면 저장은 무의미한 POST + reload — 막아 둔다(미로딩 빈 길도 여기서 걸린다).
    private var reordered: Bool { items.map(\.id) != detail.connections.map(\.id) }

    init(detail: CollectionDetail, onSaved: @escaping () -> Void) {
        self.detail = detail
        self.onSaved = onSaved
        _items = State(initialValue: detail.connections)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    row(index: index, item: item)
                }
                .onMove { from, to in items.move(fromOffsets: from, toOffset: to) }
            }
            .environment(\.editMode, .constant(.active))
            .listStyle(.plain)
            // 시스템 회색 대신 브랜드 종이(§1) — 수정 시트(EditSeriesSheet)와 같은 면.
            .scrollContentBackground(.hidden)
            .background(Palette.readingBg)
            .navigationTitle("순서 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { Task { await save() } }.disabled(saving || !reordered)
                }
            }
        }
    }

    private func row(index: Int, item: ConnectionItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: indexSize, weight: .bold))
                .foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 3) {
                if let why = item.why, !why.isEmpty {
                    Text(why)
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
                Text(label(item))
                    .typeScale(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private func label(_ item: ConnectionItem) -> String {
        switch item.block {
        case let .highlight(quote, _, _, _): return quote
        case let .post(title, _, _, _, _): return title
        case let .note(body): return body
        }
    }

    private func save() async {
        saving = true
        do {
            try await CollectionsAPI.reorder(
                collectionId: detail.id, connectionIds: items.map(\.id))
            onSaved()
            dismiss()
        } catch {
            saving = false
            ToastCenter.shared.show(String(localized: "순서를 저장하지 못했습니다"))
        }
    }
}
