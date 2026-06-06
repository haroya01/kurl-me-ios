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

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .idle:
                    ContentUnavailableView("검색", systemImage: "magnifyingglass",
                                           description: Text("제목·내용으로 글을 찾아보세요"))
                case .loading:
                    ProgressView().frame(maxWidth: .infinity, minHeight: 240)
                case .loaded(let items):
                    resultList(items)
                case .failed(let message):
                    ContentUnavailableView("불러오지 못했습니다", systemImage: "wifi.exclamationmark",
                                           description: Text(message))
                }
            }
            .navigationTitle("검색")
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        .searchable(text: $query, prompt: "글 검색")
        .onChange(of: query) { _, newValue in scheduleSearch(newValue) }
        .onSubmit(of: .search) { runSearch(query) }
    }

    private func resultList(_ items: [FeedItem]) -> some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(items) { item in
                    NavigationLink(value: Route.post(username: item.author.username, slug: item.slug)) {
                        FeedCard(item: item)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            }
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
