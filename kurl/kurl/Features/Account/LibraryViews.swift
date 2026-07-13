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
    /// 서버 목록 실패 → 기기 사본 목록으로 대신 세운 상태 — 성공 로드가 오면 풀린다.
    @State private var offlineFallback = false

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
                        .foregroundStyle(Palette.link)
                }
                .padding(.top, 60)
            } else {
                if offlineFallback {
                    // 기기 사본 목록 렌더 중 — 상세의 오프라인 배너와 같은 조용한 한 줄.
                    HStack(spacing: 6) {
                        Image(systemName: "wifi.slash")
                        Text("오프라인 — 기기에 저장된 사본만 보여요")
                    }
                    .typeScale(.footnote)
                    .foregroundStyle(Palette.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Palette.hairline, in: Capsule())
                    .padding(.top, 14)
                }
                // 북마크 = 카탈로그(오프라인 책장) — 카드가 아니라 깔끔한 글 행(3원칙 표준).
                // 화면 제목이 이미 "북마크"라 행마다 북마크 글리프는 중복 — 오프라인 저장분만 메타에 ⤓ 배지로.
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        // 클로저형 링크로 민다 — 계정 스택은 클로저형(서재 행)과 값형이 섞여 값 기반
                        // Route 링크가 항해하지 않는다(SwiftUI 혼용 함정). RouteView 로 감싸 목적지는 그대로.
                        NavigationLink {
                            RouteView(route: .post(username: item.username, slug: item.slug))
                        } label: {
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
            offlineFallback = false
            loading = false
            await offline.reconcile(bookmarks: items.map { ($0.username, $0.slug) })
        } catch {
            loading = false
            guard items.isEmpty else { return }
            // 서버 목록 실패여도 기기 사본이 있으면 데드엔드 대신 사본 목록 —
            // "북마크 = 오프라인 보장"이 목록 진입로에서도 지켜진다(행 탭 = 기존 사본 렌더 폴백).
            let cached = offlineItems()
            if cached.isEmpty {
                failed = true
            } else {
                items = cached
                offlineFallback = true
            }
        }
    }

    /// 기기 사본만으로 세우는 대체 목록 — 사본 JSON 에서 행에 필요한 것만 최소 디코딩.
    private func offlineItems() -> [BookmarkItem] {
        offline.cachedKeys.compactMap { key -> BookmarkItem? in
            let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let data = offline.data(username: parts[0], slug: parts[1]),
                  let probe = try? JSONDecoder().decode(OfflineCopyProbe.self, from: data)
            else { return nil }
            return BookmarkItem(
                id: probe.post.id, username: probe.author.username,
                title: probe.post.title, slug: probe.post.slug)
        }
        // 사본 집합엔 서버의 북마크 순서가 없다 — 새로고침마다 안 흔들리게 제목순으로 고정.
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

/// 기기 사본에서 목록 행에 필요한 것만 꺼내는 최소 디코딩(블록·날짜 무시).
private struct OfflineCopyProbe: Decodable {
    struct Author: Decodable { let username: String }
    struct Post: Decodable { let id: Int64; let title: String; let slug: String }
    let author: Author
    let post: Post
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
                        .foregroundStyle(Palette.link)
                }
                    .padding(.top, 60)
            } else {
                // 좋아요한 글 = 내 컬렉션(카탈로그) — 카드가 아니라 피드와 같은 글 행(3원칙 표준).
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        // 클로저형 링크 — 계정 스택 혼용 함정 회피(값 기반은 이 깊이서 항해 안 함).
                        NavigationLink {
                            RouteView(route: .post(username: item.author.username, slug: item.slug))
                        } label: {
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
                        .foregroundStyle(Palette.link)
                }
                .padding(.top, 60)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, card in
                    // 클로저형 링크 — 계정 스택 혼용 함정 회피(값 기반은 이 깊이서 항해 안 함).
                    NavigationLink {
                        RouteView(route: .series(
                            username: card.author?.username ?? "", slug: card.slug))
                    } label: {
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

/// 구독한 태그 — 구독한 시리즈가 서재에 보이듯, 구독(팔로우)한 주제도 한자리에 모아 본다.
/// 주제는 목록 행이 아니라 흐르는 그린 테두리 칩 그리드로 — 태그는 본디 칩이라(§10 "칩처럼 보이면
/// 칩처럼 눌린다") 한 줄 한 개보다 한눈에 훑긴다. 칩 탭 = 그 태그 피드, 길게 눌러 = 구독 해제.
struct SubscribedTagsView: View {
    @State private var tags: [String] = []
    @State private var loading = true
    @State private var failed = false
    /// 구독 해제 낙관 반영 중인 태그 — 응답 전 즉시 걷어내고, 실패하면 되돌린다.
    @State private var unsubscribing: Set<String> = []
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1

    var body: some View {
        ReadingColumn(spacing: 0) {
            if loading {
                KurlLoadingMark()
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if failed {
                LibraryFailedState { Task { loading = true; await load() } }
            } else if tags.isEmpty {
                ContentUnavailableView {
                    Label("구독한 태그가 없습니다", systemImage: "number")
                } description: {
                    Text("글에서 태그를 구독하면 그 주제의 새 글이 구독함에 모여요.")
                } actions: {
                    Button("발견에서 읽을 글 찾기") { TabRouter.shared.selection = 1 }
                        .foregroundStyle(Palette.link)
                }
                .padding(.top, 60)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    // 흐르는 칩 그리드 — 좁은 폭에서 자동 줄바꿈(발행 시트 태그 필드와 같은 FlowLayout).
                    TagFlowLayout(spacing: 10) {
                        ForEach(tags, id: \.self) { tag in
                            subscribedChip(tag)
                        }
                    }
                    // 조용한 안내 한 줄 — 해제가 길게 누르기 뒤에 숨어 있음을 알린다(발견성).
                    Text("칩을 탭하면 그 주제의 글로, 길게 누르면 구독을 해제해요.")
                        .typeScale(.meta)
                        .foregroundStyle(Palette.faint)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
            }
        }
        .navigationTitle("구독한 태그")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    /// 구독 태그 한 칩 — 그린 테두리·잉크 라벨(§10 색 규율, 채움 없이). 탭 = 그 태그 피드로 항해(클로저형
    /// 링크 — 계정 스택 혼용 함정 회피). 길게 누르면 구독 해제 컨텍스트 메뉴(파괴적 롤).
    private func subscribedChip(_ tag: String) -> some View {
        NavigationLink {
            RouteView(route: .tag(tag))
        } label: {
            Text("#\(tag)")
                .font(.system(size: 15 * unit, weight: .medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
                .background(Palette.accent.opacity(0.06), in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.accent.opacity(0.35), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                unsubscribe(tag)
            } label: {
                Label("구독 해제", systemImage: "number.circle.fill")
            }
        }
        .accessibilityLabel(Text("#\(tag) 구독됨"))
        .accessibilityHint(Text("두 번 탭하면 그 태그 글로, 길게 누르면 구독 해제"))
    }

    private func load() async {
        failed = false
        do {
            tags = try await InteractionsAPI.tagPrefs().followed
            loading = false
        } catch {
            loading = false
            if tags.isEmpty { failed = true }
        }
    }

    /// 구독 해제 — 낙관 제거(즉시 칩을 걷고) + 가벼운 햅틱, 실패하면 제자리로 되돌리고 토스트.
    private func unsubscribe(_ tag: String) {
        guard !unsubscribing.contains(tag) else { return }
        unsubscribing.insert(tag)
        let index = tags.firstIndex(of: tag)
        withAnimation(.snappy(duration: 0.2)) { tags.removeAll { $0 == tag } }
        Task {
            defer { unsubscribing.remove(tag) }
            do {
                let prefs = try await InteractionsAPI.setTagFollow(tag: tag, on: false)
                // 서버 확정 목록으로 맞춘다 — 다른 기기 변경까지 반영(멱등).
                withAnimation(.snappy(duration: 0.2)) { tags = prefs.followed }
                ToastCenter.shared.show(String(localized: "‘#\(tag)’ 구독을 해제했어요"))
            } catch {
                // 되돌리기 — 원래 자리에 다시 꽂는다(순서 보존).
                withAnimation(.snappy(duration: 0.2)) {
                    if !tags.contains(tag) {
                        tags.insert(tag, at: min(index ?? tags.count, tags.count))
                    }
                }
                ToastCenter.shared.show(String(localized: "구독 해제를 반영하지 못했습니다"))
            }
        }
    }
}

/// 흐르는 칩 레이아웃 — 줄이 꽉 차면 다음 줄로. 발행 시트의 태그 FlowLayout 과 같은 규칙을
/// 서재 쪽에서도 쓰기 위한 로컬 사본(ComposeView 의 private 판과 결이 같다).
private struct TagFlowLayout: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            sub.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                      anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
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
                .foregroundStyle(Palette.link)
        }
        .padding(.top, 60)
    }
}
