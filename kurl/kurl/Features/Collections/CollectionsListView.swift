//
//  CollectionsListView.swift
//  kurl
//
//  내 컬렉션 목록 — 라이브러리 위의 주제별 채널(docs/collections-design.md).
//

import SwiftUI

struct CollectionsListView: View {
    @State private var collections = CollectionsMock.mine
    @State private var showConnect = false
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    var body: some View {
        ReadingColumn(spacing: 0) {
            // 헌법 한 줄 — 이 면이 무엇인지(broadcast 아니라 잇기).
            Text("읽고 생각한 것을 주제로 잇는 곳.")
                .font(.system(size: 14 * metaUnit))
                .foregroundStyle(Palette.secondary)
                .padding(.top, 4)
                .padding(.bottom, 18)

            LazyVStack(spacing: 0) {
                ForEach(Array(collections.enumerated()), id: \.element.id) { index, c in
                    NavigationLink(value: c) {
                        row(c)
                    }
                    .buttonStyle(RowButtonStyle())
                    .modifier(QuietAppear(index: index))
                    if index < collections.count - 1 { Hairline() }
                }
            }
        }
        .navigationTitle("컬렉션")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showConnect = true } label: {
                    Image(systemName: "plus")
                }
                .tint(.brand)
                .accessibilityLabel(Text("컬렉션에 연결"))
            }
        }
        .sheet(isPresented: $showConnect) {
            ConnectSheet(targetKind: "글", targetTitle: "헥사고날로 갈아탄 지 석 달")
        }
        .navigationDestination(for: CollectionSummary.self) { CollectionDetailView(collection: $0) }
        .navigationDestination(for: Route.self) { RouteView(route: $0) }
    }

    private func row(_ c: CollectionSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(c.title)
                .typeScale(.titleSmall)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)

            if let blurb = c.blurb {
                Text(blurb)
                    .font(.system(size: 14 * unit))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 메타 = 공개 범위 + 담긴 수. 좋아요·팔로워 수 같은 허영 지표는 없다(§0 바깥 조용).
            HStack(spacing: 6) {
                Image(systemName: c.visibility.icon)
                    .font(.system(size: 11 * metaUnit, weight: .medium))
                Text(c.visibility.label)
                Text("·").foregroundStyle(Palette.faint)
                Text("\(c.count)개")
            }
            .font(.system(size: 12 * metaUnit, weight: .medium))
            .foregroundStyle(Palette.faint)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
