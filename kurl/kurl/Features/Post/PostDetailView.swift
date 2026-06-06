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
        StateView(state: model.phase, retry: { Task { await model.load() } }) { detail in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(detail)
                    blocks(detail.blocks)
                    if let nav = detail.series { seriesNav(nav, username: detail.author.username) }
                    if !model.comments.isEmpty { commentsSection }
                }
                .frame(maxWidth: Metrics.readingMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }

    private func header(_ detail: PublicPostDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(detail.post.title)
                .font(.largeTitle.bold())

            NavigationLink(value: Route.author(username: detail.author.username)) {
                HStack(spacing: 8) {
                    AvatarView(author: detail.author, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(detail.author.username)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if let date = detail.post.publishedAt {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            if !detail.post.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(detail.post.tags, id: \.self) { tag in
                            NavigationLink(value: Route.tag(tag)) { TagChip(tag: tag) }
                        }
                    }
                }
            }
            Divider()
        }
    }

    private func blocks(_ blocks: [PostBlock]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                BlockView(block: block)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func seriesNav(_ nav: PostSeriesNav, username: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            NavigationLink(value: Route.series(username: username, slug: nav.slug)) {
                HStack {
                    Image(systemName: "square.stack.3d.up")
                    Text(nav.title).fontWeight(.semibold)
                    Spacer()
                    Text("\(nav.position)/\(nav.total)").foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
            .buttonStyle(.plain)
            .tint(.brand)

            HStack {
                if let prev = nav.prev {
                    NavigationLink(value: Route.post(username: username, slug: prev.slug)) {
                        Label(prev.title, systemImage: "chevron.left").lineLimit(1)
                    }
                }
                Spacer()
                if let next = nav.next {
                    NavigationLink(value: Route.post(username: username, slug: next.slug)) {
                        Label(next.title, systemImage: "chevron.right")
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                    }
                }
            }
            .font(.footnote)
            .tint(.brand)
        }
        .padding(.top, 8)
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            Text("댓글 \(model.comments.count)").font(.headline)
            ForEach(model.comments) { comment in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        AvatarView(author: comment.author, size: 22)
                        Text(comment.author.username).font(.subheadline.weight(.medium))
                        if let date = comment.createdAt {
                            Text(date.relativeShort).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    Text(comment.body)
                        .font(.subheadline)
                        .padding(.leading, 28)
                }
            }
        }
    }
}
