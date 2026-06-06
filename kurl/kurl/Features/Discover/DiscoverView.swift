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
            async let trending = BlogAPI.trendingByTag()
            async let tags = BlogAPI.popularTags(limit: 30)
            async let authors = BlogAPI.suggestedAuthors(limit: 8)
            async let series = BlogAPI.discoverSeries(limit: 8)
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
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if !model.tags.isEmpty { tagsSection }
                        if !model.authors.isEmpty { authorsSection }
                        if !model.series.isEmpty { seriesSection }
                        ForEach(model.trending) { section in
                            trendingSection(section)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("발견")
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        .task { await model.load() }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("인기 태그")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.tags) { tag in
                        NavigationLink(value: Route.tag(tag.tag)) { TagChip(tag: tag.tag) }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var authorsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("추천 작가")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(model.authors) { item in
                        NavigationLink(value: Route.author(username: item.author.username)) {
                            VStack(spacing: 6) {
                                AvatarView(author: item.author, size: 56)
                                Text(item.author.username)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                Text("\(item.postCount)편")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 76)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var seriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("시리즈")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(model.series) { card in
                        VStack(alignment: .leading, spacing: 6) {
                            Image(systemName: "square.stack.3d.up.fill")
                                .foregroundStyle(.brand)
                            Text(card.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                            Text("\(card.postCount)편")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 160, height: 110, alignment: .topLeading)
                        .padding(12)
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func trendingSection(_ section: TrendingTagSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: Route.tag(section.tag)) {
                HStack {
                    sectionTitle("#\(section.tag)")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.trailing, 20)
            }
            .buttonStyle(.plain)
            ForEach(section.posts) { item in
                NavigationLink(value: Route.post(username: item.author.username, slug: item.slug)) {
                    FeedCard(item: item)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.title3.bold())
            .padding(.horizontal, 20)
    }
}
