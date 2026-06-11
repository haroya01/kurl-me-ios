//
//  FeedView.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

struct FeedView: View {
    @State private var selection: FeedSort = .recent

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 상단 고정 탭 스트립 — 스크롤·스와이프와 동기화.
                UnderlineTabs(items: FeedSort.allCases, selection: $selection) { $0.label }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.top, 4)
                    .padding(.bottom, 10)
                Hairline()

                // 손가락으로 최신 ↔ 인기 좌우 스와이프. 각 페이지는 자기 데이터·스크롤을 유지.
                TabView(selection: $selection) {
                    ForEach(FeedSort.allCases) { sort in
                        FeedPage(sort: sort)
                            .tag(sort)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.snappy(duration: 0.28), value: selection)
            }
            .background(Color(uiColor: .systemBackground))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }
}

/// 한 정렬(최신/인기)의 피드 페이지. TabView 가 살려두므로 스와이프해도 상태 유지.
struct FeedPage: View {
    let sort: FeedSort
    @State private var model: FeedViewModel

    init(sort: FeedSort) {
        self.sort = sort
        _model = State(initialValue: FeedViewModel(sort: sort))
    }

    var body: some View {
        Group {
            switch model.phase {
            case .idle, .loading:
                ProgressView().tint(Palette.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                failed(message)
            case .loaded:
                list
            }
        }
        .task { await model.loadInitial() }
    }

    // 발견(browse) 면 = 1열 카드 그리드(#707 웹과 동일 문법). 행 사이 hairline 대신 카드 간격.
    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    NavigationLink(value: Route.post(username: item.author.username, slug: item.slug)) {
                        BlogCard(item: item, featured: index == 0 && sort == .recent)
                    }
                    .buttonStyle(CardButtonStyle())
                    .task { await model.loadMoreIfNeeded(current: item) }
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
            .padding(.vertical, 16)
            .frame(maxWidth: Metrics.readingColumn)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Metrics.gutter)
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.reload() }
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
