//
//  SeriesReorderSheet.swift
//  kurl
//
//  시리즈 회차 순서를 드래그로 짠다 — 이 순서가 곧 독자가 읽어 내려가는 목차 순서다.
//  네이티브 List `.onMove` 로 끌어 옮기고(컬렉션 PathReorderSheet 와 같은 UX), 저장 시
//  백엔드 setMembers(전체 순서) 한 번. 공개 상세는 발행글만 오므로 여기선 주인 상세를
//  따로 읽어 발행 전 회차까지 포함한 전체를 다룬다(안 그러면 초안·예약 회차가 떨어져 나간다).
//

import SwiftUI

struct SeriesReorderSheet: View {
    let seriesId: Int64
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var members: [SeriesMember] = []
    @State private var original: [Int64] = []
    @State private var loading = true
    @State private var saving = false
    /// 순번 배지 — 사다리에 딱 맞는 롤이 없어 크기 보존 + Dynamic Type(PathReorderSheet 와 동일).
    @ScaledMetric(relativeTo: .caption) private var indexSize: CGFloat = 12

    // 순서가 그대로면 저장은 무의미한 PUT + reload — 막아 둔다.
    private var reordered: Bool { members.map(\.id) != original }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    KurlLoadingMark()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(Array(members.enumerated()), id: \.element.id) { index, item in
                            row(index: index, item: item)
                        }
                        .onMove { from, to in members.move(fromOffsets: from, toOffset: to) }
                    }
                    .environment(\.editMode, .constant(.active))
                    .listStyle(.plain)
                    // 시스템 회색 대신 브랜드 종이(§1) — 수정 시트(EditSeriesSheet)와 같은 면.
                    .scrollContentBackground(.hidden)
                    .background(Palette.readingBg)
                }
            }
            .navigationTitle("순서 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { Task { await save() } }
                        .disabled(saving || loading || !reordered)
                }
            }
        }
        .task { await load() }
    }

    private func row(index: Int, item: SeriesMember) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: indexSize, weight: .bold).monospacedDigit())
                .foregroundStyle(Palette.accent)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .typeScale(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                // 발행 전 회차는 한 줄로 표식 — 목차엔 안 뜨지만 시리즈엔 속한다는 걸 순서 편집에선 보여준다.
                if !item.isPublished {
                    Text(item.status == "SCHEDULED" ? "예약" : "초안")
                        .typeScale(.meta)
                        .foregroundStyle(Palette.faint)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        do {
            let fresh = try await WriteAPI.seriesMembers(seriesId: seriesId)
            members = fresh
            original = fresh.map(\.id)
        } catch {
            ToastCenter.shared.show(String(localized: "회차를 불러오지 못했습니다"))
            dismiss()
        }
        loading = false
    }

    private func save() async {
        saving = true
        do {
            try await WriteAPI.reorderSeries(id: seriesId, postIds: members.map(\.id))
            onSaved()
            dismiss()
        } catch {
            saving = false
            ToastCenter.shared.show(String(localized: "순서를 저장하지 못했습니다"))
        }
    }
}
