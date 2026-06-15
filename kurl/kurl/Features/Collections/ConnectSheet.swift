//
//  ConnectSheet.swift
//  kurl
//
//  "연결" — §0의 동사. 글/하이라이트/노트를 컬렉션에 잇는다(broadcast 아님). 여러 컬렉션에
//  동시에, 그리고 "왜 이었는지" 한 줄(선택). 백엔드 `POST /collections/{id}/connections`.
//

import SwiftUI

struct ConnectSheet: View {
    let targetKind: LocalizedStringKey
    let targetTitle: String
    let blockType: ConnectionBlockKind
    let refId: Int64

    @State private var why = ""
    @State private var selected: Set<Int64> = []
    @State private var collections: [CollectionSummary] = []
    @State private var loading = true
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("어디에 이을까요")
                .typeScale(.titleSmall)
                .foregroundStyle(Palette.ink)
                .padding(.top, 26)

            targetPreview.padding(.top, 12)
            whyField.padding(.top, 14)
            Hairline().padding(.top, 16)

            if loading {
                ProgressView().tint(Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(collections) { c in
                            collectionRow(c)
                            Hairline()
                        }
                        newCollectionRow
                    }
                }
                .scrollIndicators(.hidden)
            }

            connectButton
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 16)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .background(Palette.readingBg)
        .task { await loadCollections() }
    }

    private func loadCollections() async {
        collections = (try? await CollectionsAPI.mine()) ?? []
        loading = false
    }

    // MARK: 무엇을 잇나 — 작은 프리뷰

    private var targetPreview: some View {
        HStack(spacing: 10) {
            Text(targetKind)
                .font(.system(size: 11 * metaUnit, weight: .semibold))
                .foregroundStyle(Palette.chipText)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Palette.chipBg, in: Capsule())
            Text(targetTitle)
                .font(.system(size: 15 * unit, weight: .medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var whyField: some View {
        TextField("왜 잇는지 한 줄 (선택)", text: $why, axis: .vertical)
            .lineLimit(1...3)
            .font(.system(size: 15 * unit))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(Palette.chipBg, in: RoundedRectangle(cornerRadius: 12))
    }

    private func collectionRow(_ c: CollectionSummary) -> some View {
        Button {
            if selected.contains(c.id) { selected.remove(c.id) } else { selected.insert(c.id) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title)
                        .font(.system(size: 15 * unit, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Image(systemName: c.visibility.icon)
                            .font(.system(size: 10 * metaUnit, weight: .medium))
                        Text("\(c.count)개")
                    }
                    .font(.system(size: 12 * metaUnit, weight: .medium))
                    .foregroundStyle(Palette.faint)
                }
                Spacer(minLength: 0)
                Image(systemName: selected.contains(c.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20 * unit))
                    .foregroundStyle(selected.contains(c.id) ? Palette.accent : Palette.faint)
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
    }

    private var newCollectionRow: some View {
        Button {
            Task { await createAndSelect() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 14 * unit, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 22)
                Text("새 컬렉션 만들기")
                    .font(.system(size: 15 * unit, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
    }

    private func createAndSelect() async {
        // 빈 이름의 즉석 컬렉션은 막고, 대상 제목에서 한 단어를 따 기본 이름으로.
        let name = targetTitle.isEmpty ? String(localized: "새 컬렉션") : targetTitle
        guard let created = try? await CollectionsAPI.create(
            title: name, description: nil, visibility: .private)
        else {
            ToastCenter.shared.show(String(localized: "컬렉션을 만들지 못했습니다"))
            return
        }
        collections.insert(created, at: 0)
        selected.insert(created.id)
    }

    private var connectButton: some View {
        Button {
            Task { await connectAll() }
        } label: {
            Group {
                if saving {
                    ProgressView().tint(.white)
                } else {
                    Text(selected.isEmpty ? "컬렉션을 골라주세요" : "연결")
                }
            }
            .font(.system(size: 16 * unit, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .glassCapsule(prominent: true)
        }
        .buttonStyle(.plain)
        .disabled(selected.isEmpty || saving)
        .opacity(selected.isEmpty ? 0.5 : 1)
        .padding(.top, 12)
    }

    private func connectAll() async {
        saving = true
        defer { saving = false }
        let line = why.trimmingCharacters(in: .whitespacesAndNewlines)
        var failures = 0
        for collectionId in selected {
            do {
                try await CollectionsAPI.connect(
                    collectionId: collectionId, blockType: blockType, refId: refId,
                    why: line.isEmpty ? nil : line)
            } catch {
                failures += 1
            }
        }
        if failures > 0 {
            ToastCenter.shared.show(String(localized: "일부 연결에 실패했습니다"))
        } else {
            ToastCenter.shared.show(String(localized: "연결했어요"))
        }
        dismiss()
    }
}
