//
//  DiscoverView.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class DiscoverViewModel {
    private(set) var phase: LoadState<Bool> = .idle
    private(set) var trending: [TrendingTagSection] = []
    private(set) var tags: [TagCount] = []
    private(set) var authors: [SuggestedAuthor] = []
    private(set) var series: [PublicSeriesCard] = []

    func load() async {
        if case .loaded = phase { return }
        phase = .loading
        do {
            async let trending = BlogAPI.trendingByTag(tagLimit: 5, perTag: 4)
            async let tags = BlogAPI.popularTags(limit: 24)
            async let authors = BlogAPI.suggestedAuthors(limit: 6)
            async let series = BlogAPI.discoverSeries(limit: 6)
            self.trending = try await trending
            self.tags = try await tags
            self.authors = try await authors
            self.series = try await series
            phase = .loaded(true)
        } catch {
            phase = .failed((error as? APIError)?.localizedDescription ?? error.localizedDescription)
        }
    }
}

struct DiscoverView: View {
    @State private var model = DiscoverViewModel()

    var body: some View {
        NavigationStack {
            StateView(state: model.phase, retry: { Task { await model.load() } }) { _ in
                ReadingColumn(spacing: 28) {
                    if !model.tags.isEmpty { tagsSection }
                    if !model.authors.isEmpty { authorsSection }
                    if !model.series.isEmpty { seriesSection }
                    ForEach(model.trending) { trendingSection($0) }
                    Color.clear.frame(height: 24)
                }
            }
            .navigationTitle("발견")
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        .task { await model.load() }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            RailHeading("주제")
            FlowTags(tags: model.tags.map(\.tag))
        }
    }

    private var authorsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            RailHeading("추천 작가")
            VStack(spacing: 0) {
                ForEach(Array(model.authors.enumerated()), id: \.element.id) { index, item in
                    NavigationLink(value: Route.author(username: item.author.username)) {
                        HStack(spacing: 12) {
                            AvatarView(author: item.author, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.author.username)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Palette.ink)
                                if let bio = item.author.bio, !bio.isEmpty {
                                    Text(bio).font(.system(size: 13))
                                        .foregroundStyle(Palette.secondary).lineLimit(1)
                                } else {
                                    Text("글 \(item.postCount)")
                                        .font(.system(size: 13)).foregroundStyle(Palette.faint)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12)).foregroundStyle(Palette.faint)
                        }
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    if index < model.authors.count - 1 { Hairline() }
                }
            }
        }
    }

    private var seriesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            RailHeading("시리즈")
            VStack(spacing: 0) {
                ForEach(Array(model.series.enumerated()), id: \.element.id) { index, card in
                    HStack(spacing: 10) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 14)).foregroundStyle(Palette.accentMarker)
                        Text(card.title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Palette.ink).lineLimit(1)
                        Spacer()
                        Text("\(card.postCount)편")
                            .font(.system(size: 13)).foregroundStyle(Palette.faint)
                    }
                    .padding(.vertical, 12)
                    if index < model.series.count - 1 { Hairline() }
                }
            }
        }
    }

    private func trendingSection(_ section: TrendingTagSection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            NavigationLink(value: Route.tag(section.tag)) {
                HStack {
                    RailHeading("\(section.tag)")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11)).foregroundStyle(Palette.faint)
                }
            }
            .buttonStyle(.plain)
            ForEach(Array(section.posts.enumerated()), id: \.element.id) { index, item in
                NavigationLink(value: Route.post(username: item.author.username, slug: item.slug)) {
                    FeedRow(item: item)
                }
                .buttonStyle(RowButtonStyle())
                if index < section.posts.count - 1 { Hairline() }
            }
        }
    }
}
