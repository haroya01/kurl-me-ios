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
    @State private var failed = false

    private var offline: OfflineStore { .shared }

    var body: some View {
        ReadingColumn(spacing: 0) {
            if loading {
                KurlLoadingMark()
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if failed {
                LibraryFailedState { Task { loading = true; await load() } }
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
                // 북마크 = 카탈로그(오프라인 책장) — 카드가 아니라 깔끔한 글 행(3원칙 표준).
                // 오프라인 저장분은 메타에 ⤓ 배지로, 끝에 북마크 글리프.
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: Route.post(username: item.username, slug: item.slug)) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.title)
                                        .typeScale(.title)
                                        .foregroundStyle(Palette.ink)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                    HStack(spacing: 6) {
                                        Text(item.username)
                                            .foregroundStyle(Palette.secondary)
                                        if offline.contains(username: item.username, slug: item.slug) {
                                            Text("·").foregroundStyle(Palette.faint)
                                            HStack(spacing: 3) {
                                                Image(systemName: "arrow.down.circle.fill")
                                                Text("오프라인")
                                            }
                                            .foregroundStyle(Palette.accentMarker)
                                            .accessibilityElement(children: .combine)
                                            .accessibilityLabel("오프라인 저장됨")
                                        }
                                    }
                                    .typeScale(.meta)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "bookmark.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Palette.accentMarker.opacity(0.85))
                                    .accessibilityHidden(true)
                            }
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowButtonStyle())
                        .modifier(QuietAppear(index: index))
                        if index < items.count - 1 { Hairline() }
                    }
                }
            }
        }
        .navigationTitle("북마크")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        failed = false
        do {
            items = try await LibraryAPI.bookmarks()
            loading = false
            await offline.reconcile(bookmarks: items.map { ($0.username, $0.slug) })
        } catch {
            loading = false
            if items.isEmpty { failed = true }
        }
    }
}

/// 좋아요한 글 — 피드와 같은 행 문법.
struct LikedPostsView: View {
    @State private var items: [FeedItem] = []
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        ReadingColumn(spacing: 0) {
            if loading {
                KurlLoadingMark()
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if failed {
                LibraryFailedState { Task { loading = true; await load() } }
            } else if items.isEmpty {
                ContentUnavailableView {
                    Label("좋아요한 글이 없습니다", systemImage: "heart")
                } actions: {
                    Button("발견에서 읽을 글 찾기") { TabRouter.shared.selection = 1 }
                        .foregroundStyle(Palette.accent)
                }
                    .padding(.top, 60)
            } else {
                // 좋아요한 글 = 내 컬렉션(카탈로그) — 카드가 아니라 피드와 같은 글 행(3원칙 표준).
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: Route.post(username: item.author.username, slug: item.slug)) {
                            FeedRow(item: item)
                        }
                        .buttonStyle(RowButtonStyle())
                        .modifier(QuietAppear(index: index))
                        if index < items.count - 1 { Hairline() }
                    }
                }
            }
        }
        .navigationTitle("좋아요한 글")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        failed = false
        do {
            items = try await LibraryAPI.likedPosts()
            loading = false
        } catch {
            loading = false
            if items.isEmpty { failed = true }
        }
    }
}

/// 구독한 시리즈 — 시리즈 행 문법(제목 · n편 · 마지막 발행).
struct SubscribedSeriesView: View {
    @State private var items: [PublicSeriesCard] = []
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        ReadingColumn(spacing: 0) {
            if loading {
                KurlLoadingMark()
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if failed {
                LibraryFailedState { Task { loading = true; await load() } }
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
                                    .typeScale(.titleSmall)
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    if let author = card.author?.username {
                                        Text(author)
                                    }
                                    Text("\(card.postCount)편")
                                }
                                .typeScale(.meta)
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
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        failed = false
        do {
            items = try await LibraryAPI.subscribedSeries()
            loading = false
        } catch {
            loading = false
            if items.isEmpty { failed = true }
        }
    }
}

/// 세 라이브러리 목록이 공유하는 실패 상태 — 빈 200 과 구분되는 네트워크 오류 표시.
private struct LibraryFailedState: View {
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("불러오지 못했습니다", systemImage: "wifi.exclamationmark")
        } actions: {
            Button("다시 시도", action: retry)
                .foregroundStyle(Palette.accent)
        }
        .padding(.top, 60)
    }
}
