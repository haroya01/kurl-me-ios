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
    /// 살아 있는(진짜 상세가 그려진) 장 — 현재 ±1 을 미리 깨우고, 한 번 깨어난 장은 유지한다.
    @State private var aliveIds: Set<Int64> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shuffleCount = 0
    /// 위치 칩의 비텍스트 마커(sparkles)도 footnote 라벨과 함께 커지게 — 산발 고정 크기 종식.
    @ScaledMetric(relativeTo: .caption) private var markerUnit: CGFloat = 1
    /// 툴바 "발견" 알약 라벨 — 사다리에 딱 맞는 롤이 없어 크기를 보존하되 Dynamic Type 는 얹는다.
    @ScaledMetric(relativeTo: .headline) private var principalSize: CGFloat = 14
    /// scrollPosition 의 첫 비-nil 배정(초기 착지)은 스와이프가 아니다 — 진짜 넘김만 힌트를 끈다.
    @State private var hasNavigated = false
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
                            .foregroundStyle(Palette.link)
                    }
                case .loaded:
                    // 인증 피드가 빈 덱을 줄 수 있다 — 빈 페이지형 면 대신 막다른 길 금지(작가 찾기로).
                    if model.deck.isEmpty {
                        emptyDeck
                    } else {
                        deck
                    }
                }
            }
            .task { await model.load() }
            .toolbar {
                // "발견" = 떠 있는 리퀴드 글래스 알약(피드 스위처와 같은 결) — 투명 헤더 위에 얹힌다.
                ToolbarItem(placement: .principal) {
                    Text("발견")
                        .font(.system(size: principalSize, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .glassEffect(.regular, in: .capsule)
                        .accessibilityAddTraits(.isHeader)
                }
                // 임베드된 상세는 내비바를 못 쓰므로 공유는 현재 장 기준으로 호스트가 든다.
                // 공유(현재 장)와 섞기(덱 전체)는 작용 범위가 달라 유리 핀도 분리한다.
                ToolbarItem(placement: .primaryAction) {
                    if let url = currentShareURL {
                        // 제목 + 앱 마크 미리보기로 공유 시트가 빈 카드로 뜨지 않게(상세 공유와 같은 문법).
                        ShareLink(
                            item: url,
                            preview: SharePreview(
                                (currentItem?.title).map(\.cleanedPreview) ?? "",
                                icon: Image("LaunchMark"))
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .tint(.brand)
                        .accessibilityLabel(Text("공유"))
                    }
                }
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        shuffleCount += 1
                        // 셔플로 떨궈진 글을 가리키는 stale currentId 가 공유·위치 칩을 잠깐 지운다 —
                        // nil 로 리셋해 `?? deck.first` 폴백이 즉시 받게 한다.
                        currentId = nil
                        hasNavigated = false
                        aliveIds = []
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
            .navigationBarTitleDisplayMode(.inline)
            // 덱은 엣지-투-엣지 읽기 면 — 내비바 배경(반투명 막)을 걷어 투명 헤더로. 발견 알약·
            // 섞기·공유만 유리로 떠 있고, 커버는 상단까지 꽉 찬다.
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }

    private var emptyDeck: some View {
        // 인증 피드가 빈 덱을 줄 수 있다 — 다른 빈 면과 같은 언어(FeedPlaceholder)로 다시 섞기를 건넨다.
        FeedPlaceholder(
            eyebrow: "발견",
            title: "읽을 글이 없어요",
            message: "작가를 팔로우하면, 그들의 글이 이 덱에 흘러요.",
            actionTitle: "다시 섞기",
            action: { Task { await model.reshuffle() } }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var currentItem: FeedItem? {
        let id = currentId ?? model.deck.first?.id
        return model.deck.first { $0.id == id }
    }

    /// 현재 장과 양옆을 alive 집합에 편입 — 스와이프가 시작되기 전에 옆 장이 이미 그려져 있게.
    private func wakeNeighbors() {
        guard !model.deck.isEmpty else { return }
        let index = model.deck.firstIndex { $0.id == (currentId ?? model.deck.first?.id) } ?? 0
        for i in max(0, index - 1)...min(model.deck.count - 1, index + 1) {
            aliveIds.insert(model.deck[i].id)
        }
    }

    /// 네이티브 공유 시트용 공개 URL — 글 상세와 같은 주소.
    private var currentShareURL: URL? {
        guard let item = currentItem else { return nil }
        return URL(
            string: "\(Config.apiBase)/\(Config.preferredLanguageTag)/p/\(item.author.username)/\(item.slug)")
    }

    private var deck: some View {
        ScrollView(.horizontal) {
            // Lazy 대신 손수 깨우는 HStack — lazy 는 옆 장을 스와이프가 시작된 뒤에야 만들기
            // 때문에, 넘기는 손 밑에서 로딩 중인 장이 보였다. 여기서는 현재 ±1 장을 미리
            // 깨워(alive) 넘기는 순간 이미 완성돼 있고, 한 번 깨어난 장은 계속 살려 둬 되돌아가도
            // 읽던 자리·이미지가 그대로다(lazy 의 유지 특성과 동일 — 회귀 없음).
            HStack(spacing: 0) {
                ForEach(model.deck) { item in
                    Group {
                        if aliveIds.contains(item.id) {
                            PostDetailView(
                                username: item.author.username, slug: item.slug, embedded: true
                            )
                            .task { await model.loadMoreIfNeeded(current: item) }
                        } else {
                            Color.clear
                        }
                    }
                    .containerRelativeFrame(.horizontal)
                    // 덱의 깊이 — 넘기는 동안 옆 장은 한 겹 뒤로 물러났다(축소+가라앉음) 떠오른다.
                    // 읽기 폭은 안 깎는다(착지하면 풀스크린). reduce-motion 이면 정지.
                    .scrollTransition(.interactive, axis: .horizontal) { view, phase in
                        view
                            .scaleEffect(reduceMotion ? 1 : (phase.isIdentity ? 1 : 0.9))
                            .opacity(reduceMotion ? 1 : (phase.isIdentity ? 1 : 0.55))
                            .offset(y: reduceMotion ? 0 : (phase.isIdentity ? 0 : 14))
                    }
                }
            }
            .scrollTargetLayout()
        }
        // 착지할 때마다 현재 ±1 장을 깨운다(첫 렌더 포함). 덱이 늘어나거나(더 불러오기)
        // 섞여도(reshuffle) 같은 경로로 갱신된다.
        .onChange(of: currentId, initial: true) { wakeNeighbors() }
        .onChange(of: model.deck) { wakeNeighbors() }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentId)
        .scrollIndicators(.hidden)
        // 새 글에 착지하는 순간의 촉각 — 덱을 넘기는 의례에 손맛 한 틱.
        .sensoryFeedback(.selection, trigger: currentId)
        // 덱에서의 내 위치 + 이게 "추천"이라는 선언 — 무맥락 슬롯머신이 되지 않게.
        .overlay(alignment: .bottom) {
            if let item = currentItem, let idx = model.deck.firstIndex(of: item) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9 * markerUnit, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                    Text("추천 \(idx + 1) / \(model.deck.count)")
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: idx)
                        .typeScale(.footnote)
                        .monospacedDigit()
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
            // 첫 비-nil 배정은 초기 착지일 뿐 — 두 번째 변화(진짜 넘김)부터 배운 것으로 친다.
            guard hasNavigated else { hasNavigated = true; return }
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
    @ScaledMetric(relativeTo: .footnote) private var chevronUnit: CGFloat = 1
    @State private var phase = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15 * chevronUnit, weight: .semibold))
                        .foregroundStyle(.primary)
                        .opacity(phase ? (index == 0 ? 1 : 0.35) : (index == 2 ? 1 : 0.35))
                }
            }
            Text("넘겨서 다음 글")
                .typeScale(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: Metrics.radiusMini))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                phase = true
            }
        }
    }
}
