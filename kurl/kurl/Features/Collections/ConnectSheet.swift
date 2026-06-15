//
//  ConnectSheet.swift
//  kurl
//
//  "연결" — §0의 동사. 글/하이라이트/노트를 컬렉션에 잇는다(broadcast 아님). 여러 컬렉션에
//  동시에, 그리고 "왜 이었는지" 한 줄(선택). 가볍고 조용하게(docs/collections-design.md).
//

import SwiftUI

struct ConnectSheet: View {
    let targetKind: LocalizedStringKey
    let targetTitle: String

    @State private var why = ""
    @State private var selected: Set<Int64> = []
    @State private var collections = CollectionsMock.mine
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("어디에 이을까요")
                .typeScale(.titleSmall)
                .foregroundStyle(Palette.ink)
                .padding(.top, 26)

            targetPreview
                .padding(.top, 12)

            whyField
                .padding(.top, 14)

            Hairline().padding(.top, 16)

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

            connectButton
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 16)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .background(Palette.readingBg)
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

    // MARK: 왜 이었는지 — 한 줄(선택). 컬렉션의 목소리.

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
                // 선택 = 그린 체크(주액션이라 초록 허용, §10). 미선택 = 빈 원.
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
            let new = CollectionSummary(
                id: Int64(900 + collections.count), title: "새 컬렉션",
                blurb: nil, visibility: .private, curator: CollectionsMock.hong, items: [])
            collections.append(new)
            selected.insert(new.id)
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

    private var connectButton: some View {
        Button {
            dismiss()
        } label: {
            Text(selected.isEmpty ? "컬렉션을 골라주세요" : "연결")
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
}
