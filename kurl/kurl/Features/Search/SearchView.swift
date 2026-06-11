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
    @State private var path = NavigationPath()
    @Namespace private var zoomNS

    var body: some View {
        NavigationStack(path: $path) {
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
                if case .post(let username, let slug) = route, path.count <= 1 {
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
                    ForEach(items) { item in
                        NavigationLink(value: Route.post(username: item.author.username, slug: item.slug)) {
                            BlogCard(item: item)
                        }
                        .buttonStyle(CardButtonStyle())
                        .modifier(ZoomSource(
                            active: true,
                            id: "search-\(item.author.username)-\(item.slug)",
                            ns: zoomNS))
                        .modifier(CardScrollFade())
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
        phase = .loading
        do {
            let items = try await BlogAPI.feed(query: text, page: 0, size: 30).items
            guard !Task.isCancelled else { return }
            phase = .loaded(items)
        } catch {
            phase = .failed((error as? APIError)?.localizedDescription ?? error.localizedDescription)
        }
    }
}
