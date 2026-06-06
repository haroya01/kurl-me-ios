//
//  AuthorBlogView.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

struct AuthorBlogView: View {
    let username: String

    @State private var phase: LoadState<PublicPostListView> = .idle
    @State private var series: [SeriesListItem] = []

    var body: some View {
        StateView(state: phase, retry: { Task { await load() } }) { view in
            List {
                Section {
                    authorHeader(view.author)
                        .listRowSeparator(.hidden)
                }
                if !series.isEmpty {
                    Section("시리즈") {
                        ForEach(series) { s in
                            NavigationLink(value: Route.series(username: username, slug: s.slug)) {
                                HStack {
                                    Image(systemName: "square.stack.3d.up").foregroundStyle(.brand)
                                    Text(s.title)
                                    Spacer()
                                    Text("\(s.postCount)").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Section("글") {
                    ForEach(view.posts) { post in
                        NavigationLink(value: Route.post(username: username, slug: post.slug)) {
                            PostRow(item: post)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle(username)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func authorHeader(_ author: Author) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AvatarView(author: author, size: 56)
            Text(author.username).font(.title2.bold())
            if let bio = author.bio, !bio.isEmpty {
                Text(bio).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private func load() async {
        if case .loaded = phase { return }
        phase = .loading
        do {
            let view = try await BlogAPI.authorPosts(username: username)
            phase = .loaded(view)
            series = (try? await BlogAPI.authorSeries(username: username))?.series ?? []
        } catch {
            phase = .failed((error as? APIError)?.localizedDescription ?? error.localizedDescription)
        }
    }
}
