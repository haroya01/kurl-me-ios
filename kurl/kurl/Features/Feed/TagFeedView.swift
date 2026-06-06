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

    var body: some View {
        StateView(state: phase, retry: { Task { await load() } }) { items in
            List {
                if items.isEmpty {
                    ContentUnavailableView("글이 없습니다", systemImage: "tray")
                        .listRowSeparator(.hidden)
                }
                ForEach(items) { item in
                    NavigationLink(value: Route.post(username: item.author.username, slug: item.slug)) {
                        FeedCard(item: item)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("#\(tag)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        if case .loaded = phase { return }
        phase = .loading
        do {
            phase = .loaded(try await BlogAPI.feed(tag: tag, page: 0, size: 30).items)
        } catch {
            phase = .failed((error as? APIError)?.localizedDescription ?? error.localizedDescription)
        }
    }
}
