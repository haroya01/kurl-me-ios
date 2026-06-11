//
//  FeedView.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

struct FeedView: View {
    @State private var selection: FeedSort = .recent
    @Namespace private var zoomNS

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 상단 고정 탭 스트립 — 스크롤·스와이프와 동기화.
                UnderlineTabs(items: FeedSort.allCases, selection: $selection) { $0.label }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.top, 4)
                    .padding(.bottom, 10)
                Hairline()

                // 페이지형 TabView(UIPageViewController) 중첩은 Liquid Glass 가 활성 탭의
                // 스크롤뷰를 못 찾게 만들어 하단 바 아래로 콘텐츠가 흐르지 않고(별도 영역처럼
                // 보임) 스크롤 축소도 안 걸렸다. 두 페이지를 ZStack 으로 살려두고(데이터·스크롤
                // 위치 유지) 좌우 스와이프는 제스처로 직접 — ScrollView 가 탭 콘텐츠의 직계가 된다.
                ZStack {
                    ForEach(FeedSort.allCases) { sort in
                        FeedPage(sort: sort, active: sort == selection, zoom: zoomNS)
                            .opacity(sort == selection ? 1 : 0)
                            .allowsHitTesting(sort == selection)
                    }
                }
                .animation(.snappy(duration: 0.28), value: selection)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 30)
                        .onEnded { value in
                            let dx = value.translation.width
                            let dy = value.translation.height
                            guard abs(dx) > 60, abs(dx) > abs(dy) * 1.5 else { return }
                            withAnimation(.snappy(duration: 0.28)) {
                                selection = dx < 0 ? .trending : .recent
                            }
                        }
                )
            }
            .background(Palette.pageBg)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                // 카드에서 출발한 글만 zoom — 탭한 카드가 글로 확대돼 들어간다.
                if case .post(let username, let slug) = route {
                    RouteView(route: route)
                        .navigationTransition(.zoom(sourceID: "post-\(username)-\(slug)", in: zoomNS))
                } else {
                    RouteView(route: route)
                }
            }
        }
    }
}

/// 한 정렬(최신/인기)의 피드 페이지. TabView 가 살려두므로 스와이프해도 상태 유지.
struct FeedPage: View {
    let sort: FeedSort
    let active: Bool
    let zoom: Namespace.ID
    @State private var model: FeedViewModel

    init(sort: FeedSort, active: Bool, zoom: Namespace.ID) {
        self.sort = sort
        self.active = active
        self.zoom = zoom
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
                    .modifier(ZoomSource(
                        active: active,
                        id: "post-\(item.author.username)-\(item.slug)",
                        ns: zoom))
                    .modifier(CardScrollFade())
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
