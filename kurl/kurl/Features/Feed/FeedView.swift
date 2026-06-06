//
//  FeedView.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

struct FeedView: View {
    @State private var model = FeedViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 상단 고정 탭 스트립 — 스크롤해도 사라지지 않는다.
                UnderlineTabs(items: FeedSort.allCases, selection: $model.sort) { $0.label }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.top, 4)
                    .padding(.bottom, 10)
                Hairline()

                feed
            }
            .background(Color(uiColor: .systemBackground))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        .task { await model.loadInitial() }
    }

    @ViewBuilder
    private var feed: some View {
        switch model.phase {
        case .idle, .loading:
            ProgressView().tint(Palette.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            failed(message)
        case .loaded:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: Route.post(username: item.author.username, slug: item.slug)) {
                            FeedRow(item: item, featured: index == 0 && model.sort == .recent)
                        }
                        .buttonStyle(RowButtonStyle())
                        .task { await model.loadMoreIfNeeded(current: item) }
                        if index < model.items.count - 1 { Hairline() }
                    }
                    if model.isLoadingMore {
                        ProgressView().tint(Palette.accent)
                            .frame(maxWidth: .infinity).padding(.vertical, 18)
                    }
                    if model.items.isEmpty {
                        ContentUnavailableView("아직 글이 없습니다", systemImage: "doc.text")
                            .padding(.top, 80)
                    }
                }
                .frame(maxWidth: Metrics.readingColumn)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Metrics.gutter)
            }
            .scrollIndicators(.hidden)
            .refreshable { await model.reload() }
        }
    }

    private func failed(_ message: String) -> some View {
        ContentUnavailableView {
            Label("불러오지 못했습니다", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("다시 시도") { Task { await model.reload() } }
                .foregroundStyle(Palette.accent)
        }
    }
}

/// 행 전체 press 하이라이트 — 본문 정렬 유지(양옆으로 살짝 번짐).
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(configuration.isPressed ? Palette.rowHighlight : .clear)
                    .padding(.horizontal, -10)
            )
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
