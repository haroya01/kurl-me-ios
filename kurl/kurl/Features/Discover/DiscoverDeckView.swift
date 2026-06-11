//
//  DiscoverDeckView.swift
//  kurl
//

import SwiftUI
import Observation

/// 발견 = 리딩 덱. 한 화면에 글 하나(풀스크린 미리보기 카드), 좌우 스와이프로 다음 글.
/// 릴스의 문법을 빌리되 본문 자동재생이 아니라 "표지를 한 장씩 넘기는" 미리보기 —
/// 탭하면 글 상세로 들어간다. 최신+트렌딩을 섞어 셔플하고, 끝에 다다르면 더 가져온다.
@MainActor
@Observable
final class DiscoverDeckModel {
    private(set) var phase: LoadState<Bool> = .idle
    private(set) var deck: [FeedItem] = []

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

    /// 셔플 버튼 — 덱을 새로 섞는다(처음부터 다시).
    func reshuffle() async {
        epoch += 1
        phase = .idle
        deck = []
        seenIds = []
        nextRecentPage = 0
        exhausted = false
        await load()
    }

    private func appendShuffled(_ items: [FeedItem]) {
        let fresh = items.filter { seenIds.insert($0.id).inserted }
        deck.append(contentsOf: fresh.shuffled())
    }
}

struct DiscoverDeckView: View {
    @State private var model = DiscoverDeckModel()
    @State private var path = NavigationPath()
    @Namespace private var zoomNS

    var body: some View {
        NavigationStack(path: $path) {
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
            .navigationDestination(for: Route.self) { route in
                if case .post(let username, let slug) = route, path.count <= 1 {
                    RouteView(route: route)
                        .navigationTransition(.zoom(sourceID: "deck-\(username)-\(slug)", in: zoomNS))
                } else {
                    RouteView(route: route)
                }
            }
        }
    }

    private var deck: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(model.deck) { item in
                    NavigationLink(value: Route.post(username: item.author.username, slug: item.slug)) {
                        DeckCard(item: item)
                            .containerRelativeFrame(.horizontal)
                    }
                    .buttonStyle(.plain)
                    .modifier(ZoomSource(
                        active: true,
                        id: "deck-\(item.author.username)-\(item.slug)",
                        ns: zoomNS))
                    .modifier(CardScrollFade(axis: .horizontal))
                    .task { await model.loadMoreIfNeeded(current: item) }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
    }
}

/// 풀스크린 미리보기 카드 — 표지가 있으면 상단 절반이 사진, 없으면 타이포가 전부.
/// 한 장 = 한 글. 가독은 §10 결: 제목 크게, 발췌 여러 줄, 메타는 조용히.
private struct DeckCard: View {
    let item: FeedItem

    @ScaledMetric(relativeTo: .largeTitle) private var titleUnit: CGFloat = 1

    var body: some View {
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
            } else {
                Spacer(minLength: 28)
            }

            if let tag = item.tags.first {
                Text("#\(tag)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 22)
            }

            Text(item.title)
                .font(.system(size: (item.ogImageUrl == nil ? 30 : 25) * titleUnit, weight: .bold))
                .foregroundStyle(Palette.ink)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            if let excerpt = item.excerpt, !excerpt.isEmpty {
                Text(excerpt)
                    .font(.system(size: 16 * titleUnit))
                    .foregroundStyle(Palette.body)
                    .lineSpacing(5)
                    .lineLimit(item.ogImageUrl == nil ? 10 : 5)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 12)
            }

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                AvatarView(author: item.author, size: 24)
                Text(item.author.username)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.body)
                if let date = item.publishedAt {
                    Text("·").foregroundStyle(Palette.faint)
                    Text(date.formatted(.dateTime.month().day()))
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.secondary)
                }
                if item.likeCount > 0 {
                    Text("·").foregroundStyle(Palette.faint)
                    HStack(spacing: 3) {
                        Image(systemName: "heart")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.accentMarker)
                        Text("\(item.likeCount)")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.secondary)
                    }
                }
                Spacer()
                // 넘김 affordance — 다음 장이 있다는 조용한 신호.
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.faint)
            }
            .padding(.bottom, 18)
        }
        .padding(.horizontal, Metrics.gutter)
        .frame(maxWidth: Metrics.readingColumn)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }
}
