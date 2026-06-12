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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                switch phase {
                case .idle, .loading:
                    ProgressView().tint(Palette.accent)
                        .frame(maxWidth: .infinity, minHeight: 320)
                case .failed(let message):
                    ContentUnavailableView("불러오지 못했습니다", systemImage: "wifi.exclamationmark",
                                           description: Text(message))
                        .padding(.top, 80)
                case .loaded(let view):
                    content(view)
                }
            }
            .frame(maxWidth: Metrics.readingColumn)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Metrics.gutter)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(username)
        .toolbarRole(.editor)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ view: PublicPostListView) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AvatarView(author: view.author, size: 60)
            Text(view.author.username)
                .font(.system(size: 24, weight: .bold)).foregroundStyle(Palette.ink)
            if let bio = view.author.bio, !bio.isEmpty {
                Text(bio).font(.system(size: 15)).foregroundStyle(Palette.secondary)
            }
            FollowButton(username: view.author.username)
                .padding(.top, 4)
        }
        .padding(.vertical, 16)

        if !series.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                RailHeading("시리즈")
                VStack(spacing: 0) {
                    ForEach(Array(series.enumerated()), id: \.element.id) { index, s in
                        NavigationLink(value: Route.series(username: username, slug: s.slug)) {
                            HStack(spacing: 10) {
                                Image(systemName: "square.stack.3d.up")
                                    .font(.system(size: 14)).foregroundStyle(Palette.accentMarker)
                                Text(s.title).font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                Text("\(s.postCount)편").font(.system(size: 13)).foregroundStyle(Palette.faint)
                            }
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        if index < series.count - 1 { Hairline() }
                    }
                }
            }
            .padding(.bottom, 12)
        }

        RailHeading("글").padding(.bottom, 6)
        Hairline()
        ForEach(Array(view.posts.enumerated()), id: \.element.id) { index, post in
            NavigationLink(value: Route.post(username: username, slug: post.slug)) {
                PostRow(item: post)
            }
            .buttonStyle(RowButtonStyle())
            if index < view.posts.count - 1 { Hairline() }
        }
        Color.clear.frame(height: 40)
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
