//
//  SeriesReorderSheet.swift
//  kurl
//
//  시리즈 회차를 짠다 — 글과 노트를 드래그로 한 순서에 놓고(이 순서가 곧 독자의 목차), 빼고,
//  내 노트를 더한다. 네이티브 List `.onMove`/`.onDelete`(컬렉션 PathReorderSheet 와 같은 UX),
//  저장은 항목 전체 교체 한 번. 공개 상세는 발행글만 오므로 주인 상세를 따로 읽어 초안·예약
//  회차까지 다룬다. 서버가 아직 항목을 모르면(옛 서버) 글 순서만 짜는 예전 길로 돌아간다.
//

import SwiftUI

struct SeriesReorderSheet: View {
    let seriesId: Int64
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [SeriesOwnerItem] = []
    @State private var original: [SeriesOwnerItem] = []
    /// 항목을 아는 서버인가 — false 면 글 순서만(노트 추가·빼기 없음).
    @State private var mixed = true
    @State private var loading = true
    @State private var saving = false
    @State private var pickingNote = false
    /// 순번 배지 — 사다리에 딱 맞는 롤이 없어 크기 보존 + Dynamic Type(PathReorderSheet 와 동일).
    @ScaledMetric(relativeTo: .caption) private var indexSize: CGFloat = 12

    // 그대로면 저장은 무의미한 PUT + reload — 막아 둔다.
    private var changed: Bool { items.map(\.id) != original.map(\.id) }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    KurlLoadingMark()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            row(index: index, item: item)
                        }
                        .onMove { from, to in items.move(fromOffsets: from, toOffset: to) }
                        .onDelete(perform: mixed ? { items.remove(atOffsets: $0) } : nil)
                        if mixed {
                            Button {
                                pickingNote = true
                            } label: {
                                Text("내 노트 더하기")
                                    .foregroundStyle(Palette.link)
                            }
                            .accessibilityIdentifier("series.addNote")
                        }
                    }
                    .environment(\.editMode, .constant(.active))
                    .listStyle(.plain)
                    // 시스템 회색 대신 브랜드 종이(§1) — 수정 시트(EditSeriesSheet)와 같은 면.
                    .scrollContentBackground(.hidden)
                    .background(Palette.readingBg)
                }
            }
            .navigationTitle(mixed ? "회차 편집" : "순서 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { Task { await save() } }
                        .disabled(saving || loading || !changed)
                }
            }
            .sheet(isPresented: $pickingNote) {
                SeriesNotePicker(excluding: Set(items.filter(\.isNote).map(\.refId))) { note in
                    items.append(.note(id: note.id, excerpt: note.body.cleanedPreview))
                }
            }
        }
        .task { await load() }
    }

    private func row(index: Int, item: SeriesOwnerItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: indexSize, weight: .bold).monospacedDigit())
                .foregroundStyle(Palette.accent)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .typeScale(item.isNote ? .lede : .body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                if item.isNote {
                    SeriesNoteMark(size: indexSize, current: false)
                } else if !item.isPublished {
                    // 발행 전 회차는 한 줄로 표식 — 목차엔 안 뜨지만 시리즈엔 속한다는 걸 여기선 보여준다.
                    Text(item.status == "SCHEDULED" ? "예약" : "초안")
                        .typeScale(.meta)
                        .foregroundStyle(Palette.faint)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        do {
            if let fresh = try await WriteAPI.seriesItems(seriesId: seriesId) {
                items = fresh
            } else {
                mixed = false
                items = try await WriteAPI.seriesMembers(seriesId: seriesId).map {
                    SeriesOwnerItem(
                        type: "POST", post: .init(id: $0.id, title: $0.title, status: $0.status), note: nil)
                }
            }
            original = items
        } catch {
            ToastCenter.shared.show(String(localized: "회차를 불러오지 못했습니다"))
            dismiss()
        }
        loading = false
    }

    private func save() async {
        saving = true
        do {
            if mixed {
                try await WriteAPI.setSeriesItems(seriesId: seriesId, items: items)
            } else {
                try await WriteAPI.reorderSeries(id: seriesId, postIds: items.map(\.refId))
            }
            onSaved()
            dismiss()
        } catch {
            saving = false
            ToastCenter.shared.show(String(localized: "순서를 저장하지 못했습니다"))
        }
    }
}

/// 시리즈에 더할 내 노트 고르기 — 시리즈 독자가 읽을 수 있는(공개·조용한 공개) 노트만, 이미 든 것은 뺀다.
struct SeriesNotePicker: View {
    let excluding: Set<Int64>
    let onPick: (Note) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var notes: [Note] = []
    @State private var page = 0
    @State private var hasNext = true
    @State private var loading = false
    @State private var failed = false

    private var candidates: [Note] {
        notes.filter { $0.noteVisibility.shareable && !excluding.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(candidates) { note in
                    Button {
                        onPick(note)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.body.cleanedPreview)
                                .typeScale(.lede)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                            if let date = note.createdAt {
                                Text(date.relativeShort)
                                    .typeScale(.meta)
                                    .foregroundStyle(Palette.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("series.pickNote.\(note.id)")
                }
                if hasNext && !loading {
                    Button("더 불러오기") { Task { await loadMore() } }
                        .foregroundStyle(Palette.link)
                }
                if loading {
                    KurlLoadingMark().frame(maxWidth: .infinity).padding(.vertical, 12)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.readingBg)
            .overlay {
                if !loading && candidates.isEmpty {
                    Text(failed ? "노트를 불러오지 못했습니다" : "더할 수 있는 노트가 없어요. 팔로워만·멘션한 사람만 보는 노트는 시리즈에 넣을 수 없어요.")
                        .typeScale(.lede)
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .navigationTitle("노트 고르기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
            }
        }
        .task { await loadMore() }
    }

    private func loadMore() async {
        guard let username = AuthStore.shared.me?.username, hasNext, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let feed = try await NoteAPI.byAuthor(username, page: page)
            notes += feed.items.filter { note in !notes.contains { $0.id == note.id } }
            hasNext = feed.hasNext
            page += 1
            failed = false
        } catch {
            failed = true
        }
    }
}
