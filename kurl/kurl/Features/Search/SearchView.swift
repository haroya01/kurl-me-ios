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
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        .searchable(text: $query, prompt: "글 검색")
        .onChange(of: query) { _, newValue in scheduleSearch(newValue) }
        .onSubmit(of: .search) { runSearch(query) }
    }

    @ViewBuilder
    private func results(_ items: [FeedItem]) -> some View {
        if items.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: Route.post(username: item.author.username, slug: item.slug)) {
                            FeedRow(item: item)
                        }
                        .buttonStyle(RowButtonStyle())
                        if index < items.count - 1 { Hairline() }
                    }
                }
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
