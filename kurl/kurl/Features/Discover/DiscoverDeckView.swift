//
//  DiscoverDeckView.swift
//  kurl
//

import SwiftUI
import Observation

/// 발견 = 리딩 덱. 한 장 = **글 상세보기 그대로**(PostDetailView 임베드) — 댓글까지
/// 포함된 진짜 그 화면이다. 좌우 스와이프 = 다음 글, 세로 스크롤 = 읽기.
/// 최신+트렌딩을 섞어 셔플하고, 끝에 다다르면 더 가져온다.
@MainActor
@Observable
final class DiscoverDeckModel {
    private(set) var phase: LoadState<Bool> = .idle
    private(set) var deck: [FeedItem] = []

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

    /// 체류 비콘 — 한 장에 머문 뒤에만 호출된다(스와이프로 지나가면 발화 전에 취소).
    /// 임베드된 상세는 자체 비콘을 쏘지 않으므로(recordsView=false) 이중 집계가 없다.
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
                // 임베드된 상세는 내비바를 못 쓰므로 공유는 현재 장 기준으로 호스트가 든다.
                // 공유(현재 장)와 섞기(덱 전체)는 작용 범위가 달라 유리 핀도 분리한다.
                ToolbarItem(placement: .primaryAction) {
                    if let url = currentShareURL {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .tint(.brand)
                    }
                }
                ToolbarSpacer(.fixed, placement: .primaryAction)
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
    }

    private var currentItem: FeedItem? {
        let id = currentId ?? model.deck.first?.id
        return model.deck.first { $0.id == id }
    }

    /// 네이티브 공유 시트용 공개 URL — 글 상세와 같은 주소.
    private var currentShareURL: URL? {
        guard let item = currentItem else { return nil }
        return URL(
            string: "\(Config.apiBase)/\(Config.preferredLanguageTag)/p/\(item.author.username)/\(item.slug)")
    }

    private var deck: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(model.deck) { item in
                    PostDetailView(
                        username: item.author.username, slug: item.slug, embedded: true
                    )
                    .containerRelativeFrame(.horizontal)
                    .modifier(CardScrollFade(axis: .horizontal))
                    .task { await model.loadMoreIfNeeded(current: item) }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentId)
        .scrollIndicators(.hidden)
        // 장이 바뀔 때마다 체류 비콘 무장 — 2.5초 안에 넘기면 sleep 취소 → 미집계.
        .task(id: currentId ?? model.deck.first?.id) {
            guard let id = currentId ?? model.deck.first?.id else { return }
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            await model.recordDwell(id: id)
        }
    }
}
