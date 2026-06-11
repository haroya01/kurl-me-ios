//
//  LibraryViews.swift
//  kurl
//

import SwiftUI

/// 북마크한 글 — 행 탭 = 글로.
struct BookmarksView: View {
    @State private var items: [BookmarkItem] = []
    @State private var loading = true

    var body: some View {
        ReadingColumn(spacing: 0) {
            if loading {
                ProgressView().tint(Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if items.isEmpty {
                ContentUnavailableView("북마크한 글이 없습니다", systemImage: "bookmark")
                    .padding(.top, 60)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    NavigationLink(value: Route.post(username: item.username, slug: item.slug)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(item.username)
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowButtonStyle())
                    if index < items.count - 1 { Hairline() }
                }
            }
        }
        .navigationTitle("북마크")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            items = (try? await LibraryAPI.bookmarks()) ?? []
            loading = false
        }
        .refreshable { items = (try? await LibraryAPI.bookmarks()) ?? items }
    }
}

/// 좋아요한 글 — 피드와 같은 행 문법.
struct LikedPostsView: View {
    @State private var items: [FeedItem] = []
    @State private var loading = true

    var body: some View {
        ReadingColumn(spacing: 0) {
            if loading {
                ProgressView().tint(Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if items.isEmpty {
                ContentUnavailableView("좋아요한 글이 없습니다", systemImage: "heart")
                    .padding(.top, 60)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    NavigationLink(value: Route.post(username: item.author.username, slug: item.slug)) {
                        FeedRow(item: item)
                    }
                    .buttonStyle(RowButtonStyle())
                    if index < items.count - 1 { Hairline() }
                }
            }
        }
        .navigationTitle("좋아요한 글")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            items = (try? await LibraryAPI.likedPosts()) ?? []
            loading = false
        }
        .refreshable { items = (try? await LibraryAPI.likedPosts()) ?? items }
    }
}

/// 구독한 시리즈 — 시리즈 행 문법(제목 · n편 · 마지막 발행).
struct SubscribedSeriesView: View {
    @State private var items: [PublicSeriesCard] = []
    @State private var loading = true

    var body: some View {
        ReadingColumn(spacing: 0) {
            if loading {
                ProgressView().tint(Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if items.isEmpty {
                ContentUnavailableView("구독한 시리즈가 없습니다", systemImage: "square.stack.3d.up")
                    .padding(.top, 60)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, card in
                    NavigationLink(value: Route.series(
                        username: card.author?.username ?? "", slug: card.slug)) {
                        HStack(spacing: 10) {
                            Image(systemName: "square.stack.3d.up")
                                .font(.system(size: 14))
                                .foregroundStyle(Palette.accentMarker)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(card.title)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    if let author = card.author?.username {
                                        Text(author)
                                    }
                                    Text("\(card.postCount)편")
                                }
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowButtonStyle())
                    if index < items.count - 1 { Hairline() }
                }
            }
        }
        .navigationTitle("구독한 시리즈")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            items = (try? await LibraryAPI.subscribedSeries()) ?? []
            loading = false
        }
        .refreshable { items = (try? await LibraryAPI.subscribedSeries()) ?? items }
    }
}
