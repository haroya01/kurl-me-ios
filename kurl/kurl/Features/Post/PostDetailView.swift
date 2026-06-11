//
//  PostDetailView.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

struct PostDetailView: View {
    @State private var model: PostDetailViewModel

    init(username: String, slug: String) {
        _model = State(initialValue: PostDetailViewModel(username: username, slug: slug))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                switch model.phase {
                case .idle, .loading:
                    ProgressView().tint(Palette.accent)
                        .frame(maxWidth: .infinity, minHeight: 320)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("불러오지 못했습니다", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("다시 시도") { Task { await model.load() } }
                            .foregroundStyle(Palette.accent)
                    }
                    .padding(.top, 80)
                case .loaded(let detail):
                    content(detail)
                }
            }
            .frame(maxWidth: Metrics.readingColumn)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Metrics.gutter)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }

    @ViewBuilder
    private func content(_ detail: PublicPostDetail) -> some View {
        header(detail)
        EngagementBar(postId: detail.post.id, initialLikeCount: detail.post.likeCount)
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(detail.blocks.enumerated()), id: \.offset) { _, block in
                BlockView(block: block)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 8)
        if let nav = detail.series { seriesNav(nav, username: detail.author.username) }
        if !model.comments.isEmpty { comments }
        Color.clear.frame(height: 40)
    }

    private func header(_ detail: PublicPostDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let tag = detail.post.tags.first {
                Text(tag)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.faint)
            }
            Text(detail.post.title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            NavigationLink(value: Route.author(username: detail.author.username)) {
                HStack(spacing: 10) {
                    AvatarView(author: detail.author, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(detail.author.username)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                        if let date = detail.post.publishedAt {
                            Text(date.mediumDate)
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            if detail.post.tags.count > 1 {
                FlowTags(tags: detail.post.tags)
            }
            Hairline().padding(.top, 4)
        }
        .padding(.top, 8)
    }

    private func seriesNav(_ nav: PostSeriesNav, username: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Hairline()
            NavigationLink(value: Route.series(username: username, slug: nav.slug)) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1).fill(Palette.accentMarker).frame(width: 3, height: 12)
                    Text(nav.title).font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.heading)
                    Spacer()
                    Text("\(nav.position) / \(nav.total)")
                        .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                }
            }
            .buttonStyle(.plain)

            HStack(alignment: .top, spacing: 16) {
                if let prev = nav.prev {
                    navLink(username: username, slug: prev.slug, title: prev.title,
                            caption: "이전 글", systemImage: "chevron.left", trailing: false)
                }
                Spacer(minLength: 0)
                if let next = nav.next {
                    navLink(username: username, slug: next.slug, title: next.title,
                            caption: "다음 글", systemImage: "chevron.right", trailing: true)
                }
            }
        }
        .padding(.vertical, 16)
    }

    private func navLink(username: String, slug: String, title: String,
                         caption: LocalizedStringKey, systemImage: String, trailing: Bool) -> some View {
        NavigationLink(value: Route.post(username: username, slug: slug)) {
            VStack(alignment: trailing ? .trailing : .leading, spacing: 4) {
                Label(caption, systemImage: systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.faint)
                    .labelStyle(.titleAndIcon)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.body)
                    .lineLimit(2)
                    .multilineTextAlignment(trailing ? .trailing : .leading)
            }
            .frame(maxWidth: 180, alignment: trailing ? .trailing : .leading)
        }
        .buttonStyle(.plain)
    }

    private var comments: some View {
        VStack(alignment: .leading, spacing: 16) {
            Hairline()
            RailHeading("댓글 \(model.comments.count)")
            ForEach(model.comments) { comment in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        AvatarView(author: comment.author, size: 24)
                        Text(comment.author.username)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                        if let date = comment.createdAt {
                            Text(date.relativeShort)
                                .font(.system(size: 12)).foregroundStyle(Palette.faint)
                        }
                    }
                    Text(comment.body)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.body)
                        .padding(.leading, 32)
                }
            }
        }
        .padding(.vertical, 16)
    }
}

/// 태그 줄바꿈 래핑 — muted 칩.
struct FlowTags: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    NavigationLink(value: Route.tag(tag)) { MutedChip(text: tag) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}
