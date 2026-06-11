//
//  SearchView.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var phase: LoadState<[FeedItem]> = .idle
    @State private var searchTask: Task<Void, Never>?
    @Namespace private var zoomNS
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // 페이지네이션 — 결과 30개에서 끊기지 않게. generation 은 새 검색이 시작되면
    // 비행 중인 다음-페이지 응답을 버리는 스테일 가드.
    @State private var activeQuery = ""
    @State private var page = 0
    @State private var hasNext = false
    @State private var loadingMore = false
    @State private var generation = 0

    var body: some View {
        // path 바인딩 금지 — tabBarMinimizeBehavior 가 죽는다(FeedView 참조).
        NavigationStack {
            Group {
                switch phase {
                case .idle:
                    ContentUnavailableView("검색", systemImage: "magnifyingglass",
                                           description: Text("제목·내용으로 글을 찾아보세요"))
                case .loading:
                    ProgressView().tint(Palette.accent)
                        .frame(maxWidth: .infinity, minHeight: 280)
                case .loaded(let items):
                    results(items)
                case .failed(let message):
                    ContentUnavailableView("불러오지 못했습니다", systemImage: "wifi.exclamationmark",
                                           description: Text(message))
                }
            }
            .navigationTitle("검색")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Route.self) { route in
                if case .post(let username, let slug) = route, !reduceMotion {
                    RouteView(route: route)
                        .navigationTransition(.zoom(sourceID: "search-\(username)-\(slug)", in: zoomNS))
                } else {
                    RouteView(route: route)
                }
            }
            // 스택 안쪽에 부착 — 바깥이면 push 된 글 상세에도 검색바가 남는다.
            .searchable(text: $query, prompt: "글 검색")
        }
        .onChange(of: query) { _, newValue in scheduleSearch(newValue) }
        .onSubmit(of: .search) { runSearch(query) }
    }

    @ViewBuilder
    private func results(_ items: [FeedItem]) -> some View {
        if items.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            // 검색도 browse 면 — 피드와 같은 카드 문법(웹 §10.1 예외와 동일 경계).
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: Route.post(username: item.author.username, slug: item.slug)) {
                            BlogCard(item: item)
                        }
                        .buttonStyle(CardButtonStyle())
                        .modifier(ZoomSource(
                            active: true,
                            id: "search-\(item.author.username)-\(item.slug)",
                            ns: zoomNS))
                        .modifier(CardScrollFade())
                        .task {
                            if index >= items.count - 5 { await loadMore() }
                        }
                    }
                    if loadingMore {
                        ProgressView().tint(Palette.accent)
                            .frame(maxWidth: .infinity).padding(.vertical, 18)
                    }
                }
                .padding(.vertical, 16)
                .frame(maxWidth: Metrics.readingColumn)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Metrics.gutter)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { phase = .idle; return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await search(trimmed)
        }
    }

    private func runSearch(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        searchTask?.cancel()
        searchTask = Task { await search(trimmed) }
    }

    private func search(_ text: String) async {
        generation += 1
        let myGen = generation
        phase = .loading
        do {
            let result = try await BlogAPI.feed(query: text, page: 0, size: 30)
            guard !Task.isCancelled, myGen == generation else { return }
            activeQuery = text
            page = 0
            hasNext = result.hasNext
            phase = .loaded(result.items)
        } catch {
            guard myGen == generation else { return }
            phase = .failed((error as? APIError)?.localizedDescription ?? error.localizedDescription)
        }
    }

    private func loadMore() async {
        guard hasNext, !loadingMore, case .loaded(let current) = phase else { return }
        loadingMore = true
        defer { loadingMore = false }
        let myGen = generation
        if let result = try? await BlogAPI.feed(query: activeQuery, page: page + 1, size: 30) {
            // 그 사이 새 검색이 시작됐으면 이 페이지는 옛 질의의 것 — 버린다.
            guard myGen == generation else { return }
            page += 1
            hasNext = result.hasNext
            phase = .loaded(current + result.items)
        }
    }
}
