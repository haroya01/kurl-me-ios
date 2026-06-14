//
//  MyHighlightsView.swift
//  kurl
//

import SwiftUI

/// 내 하이라이트 — 내가 그은 구절을 모아 본다. 행 탭 = 원문(그 글)으로.
/// 서재의 다른 면(북마크·좋아요·구독)과 같은 글 행 문법.
struct MyHighlightsView: View {
    @State private var items: [MyHighlightView] = []
    @State private var loading = true
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1

    var body: some View {
        ReadingColumn(spacing: 0) {
            if loading {
                ProgressView().tint(Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if items.isEmpty {
                ContentUnavailableView {
                    Label("하이라이트한 구절이 없습니다", systemImage: "highlighter")
                } description: {
                    Text("글을 읽다 마음에 닿는 문장을 길게 눌러 하이라이트해 보세요.")
                } actions: {
                    Button("발견에서 읽을 글 찾기") { TabRouter.shared.selection = 1 }
                        .foregroundStyle(Palette.accent)
                }
                .padding(.top, 60)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: Route.post(
                            username: item.postUsername, slug: item.postSlug)) {
                            VStack(alignment: .leading, spacing: 8) {
                                // 그은 구절 — 본문에서 칠한 그린 워시를 그대로 한 줄로.
                                Text(item.quote)
                                    .font(.system(size: 15 * unit))
                                    .foregroundStyle(Palette.body)
                                    .lineLimit(3)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(
                                        Palette.accent.opacity(0.16),
                                        in: RoundedRectangle(cornerRadius: 6))
                                HStack(spacing: 6) {
                                    Text(item.postTitle)
                                        .foregroundStyle(Palette.ink)
                                        .lineLimit(1)
                                    Text("·").foregroundStyle(Palette.faint)
                                    Text(item.postUsername)
                                        .foregroundStyle(Palette.secondary)
                                        .lineLimit(1)
                                }
                                .font(.system(size: 13 * unit, weight: .medium))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowButtonStyle())
                        .modifier(QuietAppear(index: index))
                        if index < items.count - 1 { Hairline() }
                    }
                }
            }
        }
        .navigationTitle("내 하이라이트")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            items = (try? await HighlightsAPI.mine()) ?? []
            loading = false
        }
        .refreshable { items = (try? await HighlightsAPI.mine()) ?? items }
    }
}
