//
//  ConnectSheet.swift
//  kurl
//
//  "연결" — §0의 동사. 글/하이라이트/노트를 컬렉션에 잇는다(broadcast 아님).
//  2단계 뎁스: ① 어디에 남길까요(컬렉션 고르기) → ② 추가(왜 한 줄 + 확정).
//  "왜 한 줄"이 단순 북마크와 컬렉션을 가르는 영혼이라, 고른 뒤의 집중된 한 순간으로 둔다.
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
        NavigationStack {
            step1
                .navigationTitle("어디에 남길까요?")
                .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .background(Palette.readingBg)
        .task { await loadCollections() }
    }

    private func loadCollections() async {
        collections = (try? await CollectionsAPI.mine()) ?? []
        loading = false
    }

    // MARK: ① 어디에 남길까요 — 컬렉션 고르기

    private var step1: some View {
        VStack(spacing: 0) {
            if loading {
                ProgressView().tint(Palette.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            nextButton
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 16)
    }

    private var nextButton: some View {
        NavigationLink {
            step2
        } label: {
            Text(selected.isEmpty ? "컬렉션을 골라주세요" : "다음")
                .font(.system(size: 16 * unit, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .glassCapsule(prominent: true)
        }
        .buttonStyle(.plain)
        .disabled(selected.isEmpty)
        .opacity(selected.isEmpty ? 0.5 : 1)
        .padding(.top, 12)
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

    // MARK: ② 추가 — 왜 한 줄 + 확정

    private var step2: some View {
        VStack(alignment: .leading, spacing: 0) {
            targetPreview.padding(.top, 18)

            // "왜"가 자기 화면을 얻는다 — 고른 뒤의 집중된 한 순간(§0 큐레이션 영혼).
            Text("왜 이었나요")
                .font(.system(size: 13 * metaUnit, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(Palette.faint)
                .padding(.top, 24)
                .padding(.bottom, 10)
            whyField

            Text("\(selected.count)개 컬렉션에 추가됩니다.")
                .font(.system(size: 12 * metaUnit))
                .foregroundStyle(Palette.faint)
                .padding(.top, 12)

            Spacer(minLength: 0)
            addButton
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 16)
        .navigationTitle("추가")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var targetPreview: some View {
        HStack(spacing: 8) {
            Text(targetKind)
                .font(.system(size: 11 * metaUnit, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(Palette.faint)
            Text(targetTitle)
                .font(.system(size: 15 * unit, weight: .medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    private var whyField: some View {
        // 회색 채움 박스 대신 밑줄 한 줄 — 입력이되 종이 위에 글자가 그대로 앉는다.
        VStack(alignment: .leading, spacing: 9) {
            TextField("한 줄 (선택)", text: $why, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: 16 * unit))
                .foregroundStyle(Palette.ink)
            Hairline()
        }
    }

    private var addButton: some View {
        Button {
            Task { await connectAll() }
        } label: {
            Group {
                if saving { ProgressView().tint(.white) } else { Text("추가") }
            }
            .font(.system(size: 16 * unit, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .glassCapsule(prominent: true)
        }
        .buttonStyle(.plain)
        .disabled(saving)
        .padding(.top, 12)
    }

    // MARK: 동작

    private func createAndSelect() async {
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
        ToastCenter.shared.show(
            failures > 0
                ? String(localized: "일부 연결에 실패했습니다")
                : String(localized: "추가했어요"))
        dismiss()
    }
}
