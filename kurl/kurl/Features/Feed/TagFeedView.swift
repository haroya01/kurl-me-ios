//
//  TagFeedView.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

struct TagFeedView: View {
    let tag: String

    @State private var phase: LoadState<[FeedItem]> = .idle
    @State private var page = 0
    @State private var hasNext = false
    @State private var loadingMore = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                switch phase {
                case .idle, .loading:
                    ProgressView().tint(Palette.accent)
                        .frame(maxWidth: .infinity, minHeight: 320)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("불러오지 못했습니다", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("다시 시도") { Task { await load() } }
                            .foregroundStyle(Palette.accent)
                    }
                    .padding(.top, 80)
                case .loaded(let items):
                    if items.isEmpty {
                        ContentUnavailableView("글이 없습니다", systemImage: "tray").padding(.top, 80)
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: Route.post(username: item.author.username, slug: item.slug)) {
                            FeedRow(item: item)
                        }
                        .buttonStyle(RowButtonStyle())
                        .task {
                            if index >= items.count - 5 { await loadMore() }
                        }
                        if index < items.count - 1 { Hairline() }
                    }
                    if loadingMore {
                        ProgressView().tint(Palette.accent)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                }
            }
            .frame(maxWidth: Metrics.readingColumn)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Metrics.gutter)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("#\(tag)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        if case .loaded = phase { return }
        phase = .loading
        do {
            let result = try await BlogAPI.feed(tag: tag, page: 0, size: 30)
            page = 0
            hasNext = result.hasNext
            phase = .loaded(result.items)
        } catch {
            phase = .failed((error as? APIError)?.localizedDescription ?? error.localizedDescription)
        }
    }

    private func loadMore() async {
        guard hasNext, !loadingMore, case .loaded(let current) = phase else { return }
        loadingMore = true
        defer { loadingMore = false }
        if let result = try? await BlogAPI.feed(tag: tag, page: page + 1, size: 30) {
            page += 1
            hasNext = result.hasNext
            phase = .loaded(current + result.items)
        }
    }
}
