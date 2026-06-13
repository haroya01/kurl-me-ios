//
//  LibraryViews.swift
//  kurl
//

import SwiftUI

/// 북마크한 글 — 행 탭 = 글로. 북마크 = 오프라인 보장이라 목록을 볼 때마다 서버
/// 목록과 기기 사본을 맞춘다(웹에서 북마크한 글도 여기서 기기로 따라온다).
struct BookmarksView: View {
    @State private var items: [BookmarkItem] = []
    @State private var loading = true
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1

    private var offline: OfflineStore { .shared }

    var body: some View {
        ReadingColumn(spacing: 0) {
            if loading {
                ProgressView().tint(Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if items.isEmpty {
                ContentUnavailableView {
                    Label("북마크한 글이 없습니다", systemImage: "bookmark")
                } description: {
                    Text("북마크한 글은 오프라인에서도 읽을 수 있어요.")
                } actions: {
                    Button("발견에서 읽을 글 찾기") { TabRouter.shared.selection = 1 }
                        .foregroundStyle(Palette.accent)
                }
                .padding(.top, 60)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    NavigationLink(value: Route.post(username: item.username, slug: item.slug)) {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.system(size: 16 * unit, weight: .semibold))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Text(item.username)
                                    .font(.system(size: 13 * unit))
                                    .foregroundStyle(Palette.secondary)
                            }
                            Spacer(minLength: 0)
                            if offline.contains(username: item.username, slug: item.slug) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Palette.accentMarker)
                                    .padding(.top, 4)
                                    .accessibilityLabel("오프라인 저장됨")
                            }
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
            await offline.reconcile(bookmarks: items.map { ($0.username, $0.slug) })
        }
        .refreshable {
            items = (try? await LibraryAPI.bookmarks()) ?? items
            await offline.reconcile(bookmarks: items.map { ($0.username, $0.slug) })
        }
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
                ContentUnavailableView {
                    Label("좋아요한 글이 없습니다", systemImage: "heart")
                } actions: {
                    Button("발견에서 읽을 글 찾기") { TabRouter.shared.selection = 1 }
                        .foregroundStyle(Palette.accent)
                }
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
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1

    var body: some View {
        ReadingColumn(spacing: 0) {
            if loading {
                ProgressView().tint(Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if items.isEmpty {
                ContentUnavailableView {
                    Label("구독한 시리즈가 없습니다", systemImage: "square.stack.3d.up")
                } actions: {
                    Button("검색에서 시리즈 찾기") { TabRouter.shared.selection = 3 }
                        .foregroundStyle(Palette.accent)
                }
                .padding(.top, 60)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, card in
                    // author 없는 카드는 라우팅 불가 — 행은 그리되 링크를 걸지 않는다.
                    NavigationLink(value: Route.series(
                        username: card.author?.username ?? "", slug: card.slug)) {
                        HStack(spacing: 10) {
                            KurlMark(drawn: [true, true, true])
                                .frame(width: 18, height: 11)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(card.title)
                                    .font(.system(size: 16 * unit, weight: .semibold))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    if let author = card.author?.username {
                                        Text(author)
                                    }
                                    Text("\(card.postCount)편")
                                }
                                .font(.system(size: 13 * unit))
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
