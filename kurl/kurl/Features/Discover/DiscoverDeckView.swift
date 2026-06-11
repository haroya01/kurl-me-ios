//
//  DiscoverDeckView.swift
//  kurl
//

import SwiftUI
import Observation

/// 발견 = 리딩 덱. 한 장 = 열린 글 전체(커버·제목·본문·태그·반응 바) — 카드를 탭해
/// 들어가는 한 단계를 없애고, 릴스처럼 콘텐츠가 즉시 시작된다. 좌우 스와이프 = 다음 글,
/// 세로 스크롤 = 본문 읽기, 댓글만 시트 한 겹 아래. 최신+트렌딩 셔플, 끝 도달 시 append.
@MainActor
@Observable
final class DiscoverDeckModel {
    private(set) var phase: LoadState<Bool> = .idle
    private(set) var deck: [FeedItem] = []
    /// 글 id → 풀 본문. 현재 장 + 다음 두 장을 미리 받아 스와이프 시 본문이 즉시 선다.
    private(set) var details: [Int64: PublicPostDetail] = [:]

    private var detailTasks: [Int64: Task<Void, Never>] = [:]
    /// 체류 비콘을 이미 쏜 글 — 세션당 한 번. 스쳐 지나간 장은 조회수로 세지 않는다.
    private var beaconed: Set<Int64> = []
    private var seenIds: Set<Int64> = []
    private var nextRecentPage = 0
    private var exhausted = false
    private var loadingMore = false
    private var epoch = 0

    func load() async {
        if case .loaded = phase { return }
        phase = .loading
        do {
            async let recent = BlogAPI.feed(sort: .recent, page: 0, size: 20)
            async let trending = BlogAPI.feed(sort: .trending, page: 0, size: 20)
            let mixed = try await recent.items + trending.items
            nextRecentPage = 1
            appendShuffled(mixed)
            phase = .loaded(true)
        } catch {
            phase = .failed((error as? APIError)?.localizedDescription ?? error.localizedDescription)
        }
    }

    /// 덱 끝이 가까우면 최신 피드 다음 페이지를 셔플해 이어 붙인다.
    func loadMoreIfNeeded(current: FeedItem) async {
        guard !exhausted, !loadingMore,
              let idx = deck.firstIndex(of: current), idx >= deck.count - 3
        else { return }
        loadingMore = true
        defer { loadingMore = false }
        let myEpoch = epoch
        if let page = try? await BlogAPI.feed(sort: .recent, page: nextRecentPage, size: 20) {
            // 셔플이 끼어들었으면 옛 페이지 — 새 덱 머리에 붙이지 않는다.
            guard myEpoch == epoch else { return }
            nextRecentPage += 1
            if page.items.isEmpty { exhausted = true }
            appendShuffled(page.items)
        }
    }

    /// 셔플 버튼 — 덱을 새로 섞는다(처음부터 다시). 본문 캐시는 살린다.
    func reshuffle() async {
        epoch += 1
        phase = .idle
        deck = []
        seenIds = []
        nextRecentPage = 0
        exhausted = false
        await load()
    }

    /// 풀 본문 확보 — 중복 요청은 비행 중 태스크로 단일화.
    func ensureDetail(for item: FeedItem) {
        guard details[item.id] == nil, detailTasks[item.id] == nil else { return }
        detailTasks[item.id] = Task {
            defer { detailTasks[item.id] = nil }
            if let detail = try? await BlogAPI.postDetail(
                username: item.author.username, slug: item.slug) {
                details[item.id] = detail
            }
        }
    }

    /// 현재 장 + 다음 두 장 프리페치.
    func prefetchAround(id: Int64) {
        guard let idx = deck.firstIndex(where: { $0.id == id }) else { return }
        for i in idx..<min(idx + 3, deck.count) {
            ensureDetail(for: deck[i])
        }
    }

    /// 체류 비콘 — 한 장에 머문 뒤에만 호출된다(스와이프로 지나가면 발화 전에 취소).
    func recordDwell(id: Int64) async {
        guard let item = deck.first(where: { $0.id == id }),
              !beaconed.contains(id) else { return }
        beaconed.insert(id)
        await BlogAPI.recordView(username: item.author.username, slug: item.slug, source: "ios-deck")
    }

    private func appendShuffled(_ items: [FeedItem]) {
        let fresh = items.filter { seenIds.insert($0.id).inserted }
        deck.append(contentsOf: fresh.shuffled())
    }
}

struct DiscoverDeckView: View {
    @State private var model = DiscoverDeckModel()
    @State private var currentId: Int64?
    @State private var commentsTarget: FeedItem?

    var body: some View {
        // path 바인딩 금지 — tabBarMinimizeBehavior 가 죽는다(FeedView 참조).
        NavigationStack {
            Group {
                switch model.phase {
                case .idle, .loading:
                    ProgressView().tint(Palette.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("불러오지 못했습니다", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("다시 시도") { Task { await model.reshuffle() } }
                            .foregroundStyle(Palette.accent)
                    }
                case .loaded:
                    deck
                }
            }
            .task { await model.load() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await model.reshuffle() }
                    } label: {
                        Image(systemName: "shuffle")
                    }
                    .tint(.brand)
                    .accessibilityLabel("덱 섞기")
                }
            }
            .navigationTitle("발견")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        .sheet(item: $commentsTarget) { item in
            CommentsSheet(username: item.author.username, slug: item.slug)
                .presentationDetents([.medium, .large])
        }
    }

    private var deck: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(model.deck) { item in
                    DeckPostPage(item: item, detail: model.details[item.id]) {
                        commentsTarget = item
                    }
                    .containerRelativeFrame(.horizontal)
                    .modifier(CardScrollFade(axis: .horizontal))
                    .task {
                        model.ensureDetail(for: item)
                        await model.loadMoreIfNeeded(current: item)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentId)
        .scrollIndicators(.hidden)
        // 장이 바뀔 때마다 프리페치 + 체류 비콘. 2.5초 안에 넘기면 sleep 취소 →
        // 조회수로 세지 않는다.
        .task(id: currentId ?? model.deck.first?.id) {
            guard let id = currentId ?? model.deck.first?.id else { return }
            model.prefetchAround(id: id)
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            await model.recordDwell(id: id)
        }
    }
}

/// 덱 한 장 = 열린 글. 제목·커버·작가 줄은 피드 데이터로 즉시 서고,
/// 본문(blocks)은 도착하는 대로 아래에 채워진다. 반응 바는 본문 끝 — 글 상세와 같은 결.
private struct DeckPostPage: View {
    let item: FeedItem
    let detail: PublicPostDetail?
    let onComments: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 26

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let urlString = item.ogImageUrl, let url = URL(string: urlString) {
                    Color.clear
                        .aspectRatio(4.0 / 3.0, contentMode: .fit)
                        .overlay {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Rectangle().fill(Palette.hairline)
                            }
                            .saturation(0.85)
                        }
                        .overlay(Palette.coverVeil)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.top, 8)
                        .accessibilityHidden(true)
                }

                Text(item.title)
                    .font(.system(size: titleSize, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, item.ogImageUrl == nil ? 18 : 16)

                NavigationLink(value: Route.author(username: item.author.username)) {
                    HStack(spacing: 9) {
                        AvatarView(author: item.author, size: 26)
                        Text(item.author.username)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                        if let date = item.publishedAt {
                            Text("·").foregroundStyle(Palette.faint)
                            Text(date.mediumDate)
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 12)

                Hairline().padding(.top, 14)

                if let detail {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(detail.blocks.enumerated()), id: \.offset) { _, block in
                            BlockView(block: block)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 18)

                    if !detail.post.tags.isEmpty {
                        FlowTags(tags: detail.post.tags)
                            .padding(.top, 24)
                    }
                    EngagementBar(
                        postId: detail.post.id,
                        initialLikeCount: detail.post.likeCount,
                        onComments: onComments
                    )
                    .padding(.top, 6)
                } else {
                    ProgressView().tint(Palette.accent)
                        .frame(maxWidth: .infinity, minHeight: 180)
                }

                Color.clear.frame(height: 32)
            }
            .frame(maxWidth: Metrics.readingColumn, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Metrics.gutter)
        }
        .scrollIndicators(.hidden)
    }
}
