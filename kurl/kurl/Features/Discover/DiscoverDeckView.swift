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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shuffleCount = 0
    /// 첫 만남 1회 — "이건 추천 덱이고, 넘기면 다음 글"이라는 걸 눈으로 알려준다.
    @AppStorage("deckSwipeHintSeen") private var swipeHintSeen = false

    var body: some View {
        // path 바인딩 금지 — tabBarMinimizeBehavior 가 죽는다(FeedView 참조).
        NavigationStack {
            Group {
                switch model.phase {
                case .idle, .loading:
                    KurlLoadingMark()
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
                        shuffleCount += 1
                        Task { await model.reshuffle() }
                    } label: {
                        Image(systemName: "shuffle")
                            .symbolEffect(.rotate, value: reduceMotion ? 0 : shuffleCount)
                    }
                    .tint(.brand)
                    .sensoryFeedback(.impact(weight: .light), trigger: shuffleCount)
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
        // 덱에서의 내 위치 + 이게 "추천"이라는 선언 — 무맥락 슬롯머신이 되지 않게.
        .overlay(alignment: .bottom) {
            if let item = currentItem, let idx = model.deck.firstIndex(of: item) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                    Text("추천 \(idx + 1) / \(model.deck.count)")
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: idx)
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 6)
                .allowsHitTesting(false)
            }
        }
        // 첫 1회 스와이프 힌트 — 우측 가장자리에서 셰브론이 숨 쉬다 사라진다.
        .overlay(alignment: .trailing) {
            if !swipeHintSeen {
                DeckSwipeHint()
                    .padding(.trailing, 6)
                    .allowsHitTesting(false)
                    .task {
                        try? await Task.sleep(for: .seconds(3.2))
                        swipeHintSeen = true
                    }
            }
        }
        .onChange(of: currentId) {
            // 한 장이라도 넘겼으면 배운 것 — 힌트는 다시 안 나온다.
            swipeHintSeen = true
        }
        // 장이 바뀔 때마다 체류 비콘 무장 — 2.5초 안에 넘기면 sleep 취소 → 미집계.
        .task(id: currentId ?? model.deck.first?.id) {
            guard let id = currentId ?? model.deck.first?.id else { return }
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            await model.recordDwell(id: id)
        }
    }
}

/// 덱 첫 만남의 스와이프 힌트 — 셰브론이 왼쪽으로 숨 쉬며 "넘기면 다음"을 가르친다.
/// 첫 스와이프나 3초 뒤 영원히 사라진다. reduce-motion 이면 정지 상태로만.
private struct DeckSwipeHint: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .opacity(phase ? (index == 0 ? 1 : 0.35) : (index == 2 ? 1 : 0.35))
                }
            }
            Text("넘겨서 다음 글")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                phase = true
            }
        }
    }
}
