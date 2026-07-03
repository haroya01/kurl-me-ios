//
//  DiscoverView.swift
//  kurl
//
//  발견 = 읽기의 연결 그래프 홈(§0). 1차 표면 = 큐레이터 연결 흐름("누가 무엇을 어느 컬렉션에
//  이었나 + 왜"). broadcast 아니라 큐레이션을 따라간다(docs/collections-design.md).
//  (릴스형 몰입 덱 DiscoverDeckView 는 `--screen deck` 으로 주차 — 발견 표면에선 내렸다.)
//

import SwiftUI

struct DiscoverView: View {
    @State private var events: [ConnectionEvent] = []
    @State private var loading = true
    @State private var failed = false
    @State private var showLoginSheet = false

    var body: some View {
        NavigationStack {
            ReadingColumn(spacing: 0) {
                // 콘텐츠가 edge-to-edge로 흐른다 — 피드 탭과 같은 결(고정 "발견" 타이틀 ❌).
                Color.clear.frame(height: 8)
                if !AuthStore.shared.isSignedIn {
                    // 발견 = 팔로우한 큐레이터의 연결 피드(인증 필요). 비로그인은 401 무한
                    // 재시도가 아니라 로그인 게이트로(막다른 길 금지).
                    loggedOutGate
                } else if loading {
                    KurlLoadingMark()
                        .frame(maxWidth: .infinity, minHeight: 320)
                } else if failed {
                    failedState
                } else if events.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                            ConnectionEventCard(event: event)
                                .modifier(QuietAppear(index: index))
                            if index < events.count - 1 {
                                Hairline().padding(.vertical, 10)
                            }
                        }
                    }
                }
            }
            // 고정 스트립 대신 콘텐츠가 유리 크롬 밑으로 흐른다 — 상단 라벨은 탭바 아이콘이 맡는다.
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: CollectionRef.self) { CollectionDetailView(collectionId: $0.id) }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
            .task(id: AuthStore.shared.isSignedIn) { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        // 비로그인이면 인증 엔드포인트를 때리지 않는다 — 401→영구 재시도 데드엔드 방지.
        guard AuthStore.shared.isSignedIn else {
            events = []
            failed = false
            loading = false
            return
        }
        failed = false
        do {
            events = try await CollectionsAPI.discoverFeed()
            loading = false
        } catch {
            loading = false
            if events.isEmpty { failed = true }
        }
    }

    // 비로그인 게이트 — 발견은 인증 피드라, 로그인하면 흐른다고 안내(FeedView 로그아웃 결과와 동일 문법).
    private var loggedOutGate: some View {
        FeedPlaceholder(
            eyebrow: "발견",
            title: "연결 발견",
            message: "로그인하면 팔로우한 큐레이터가 컬렉션에 이은 글이 여기에 흘러요.",
            actionTitle: "로그인",
            prominent: true,
            action: { showLoginSheet = true }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
        .loginPrompt(isPresented: $showLoginSheet, message: "팔로우한 큐레이터의 연결 흐름 받기")
    }

    // 콜드스타트 — 팔로우가 없으면 백엔드가 빈 피드를 준다. 막다른 길이 아니라 작가 찾기로.
    private var emptyState: some View {
        ContentUnavailableView {
            Label("아직 흐를 게 없어요", systemImage: "sparkles")
        } description: {
            Text("작가를 팔로우하면, 그들이 컬렉션에 이은 글이 여기에 흘러요.")
        } actions: {
            Button("읽을 글 찾기") { TabRouter.shared.selection = 0 }
                .foregroundStyle(Palette.link)
        }
        .padding(.top, 80)
    }

    private var failedState: some View {
        ContentUnavailableView {
            Label("불러오지 못했습니다", systemImage: "wifi.exclamationmark")
        } actions: {
            Button("다시 시도") { Task { loading = true; await load() } }
                .foregroundStyle(Palette.link)
        }
        .padding(.top, 80)
    }
}

/// 큐레이터 연결 한 장 — 누가(아바타+이름) → 어느 컬렉션에 → [왜 한 줄] → 블록.
private struct ConnectionEventCard: View {
    let event: ConnectionEvent
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 귀속 = 조용히. 누가·언제만(broadcast 아니라 connect 라는 건 아래 eyebrow 가 말한다).
            HStack(spacing: 7) {
                AvatarView(author: event.curator, size: 22)
                Text(event.curator.username)
                    .typeScale(.meta)
                    .foregroundStyle(Palette.secondary)
                if let at = event.connectedAt {
                    Text("·").foregroundStyle(Palette.faint)
                    Text(at.relativeShort)
                        .typeScale(.meta)
                        .foregroundStyle(Palette.faint)
                }
                Spacer(minLength: 0)
            }

            // 컬렉션 eyebrow — "…에 연결" 이라는 동사를 탭 가능한 채널 칩으로. 한 연결에서
            // 그 채널 전체로 이어지는 문(§0 connect). 초록은 데이터 링크라 link 톤 허용.
            NavigationLink(value: CollectionRef(id: event.collectionId)) {
                HStack(spacing: 4) {
                    Image(
                        systemName: event.collectionKind == .path
                            ? "arrow.turn.down.right" : "square.grid.2x2"
                    )
                    .font(.system(size: 10 * metaUnit, weight: .bold))
                    Text(event.collectionTitle)
                        .typeScale(.eyebrow)
                        .tracking(0.3)
                    Text(event.collectionKind == .path ? "길에 엮음" : "에 연결")
                        .typeScale(.meta)
                        .foregroundStyle(Palette.faint)
                }
                .foregroundStyle(Palette.link)
                .expandTapTarget(6)
            }
            .buttonStyle(.plain)

            // 큐레이터의 한 줄 = 히어로. 이 흐름이 알고리즘 피드가 아니라 사람의 큐레이션이라는
            // 가장 또렷한 신호. 없으면(이유 안 단 연결) 블록이 곧장 히어로가 된다.
            if let why = event.why {
                Text(why)
                    .typeScale(.body)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            BlockPreview(block: event.block)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
    }
}

/// 연결된 블록 — 종류마다 *다른 실루엣*으로 한눈에 구분된다(같은 리듬 반복 = 단조의 원인).
/// 글 = 흰 보더 카드(읽을 아티팩트) · 하이라이트 = 그린 좌측 룰 인용(뽑은 구절) ·
/// 노트 = 부드러운 틴트 패널(붙잡은 생각). 발견 흐름·컬렉션 상세가 이 하나를 공유한다.
struct BlockPreview: View {
    let block: ConnectionBlock
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    var body: some View {
        switch block {
        case let .post(title, excerpt, username, slug, tags):
            // 글 = 흰 종이 카드. 셋 중 가장 무거운 아티팩트 — 읽으러 들어가는 곳.
            NavigationLink(value: Route.post(username: username, slug: slug)) {
                VStack(alignment: .leading, spacing: 6) {
                    kindTag("글", icon: "doc.text")
                    Text(title)
                        .typeScale(.titleSmall)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(excerpt)
                        .typeScale(.lede)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let tag = tags.first {
                        Text("#\(tag)")
                            .typeScale(.meta)
                            .foregroundStyle(Palette.secondary)
                            .padding(.top, 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Palette.cardBg, in: RoundedRectangle(cornerRadius: Metrics.radiusMini, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.radiusMini, style: .continuous)
                        .strokeBorder(Palette.cardBorder, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(CardButtonStyle())

        case let .highlight(quote, postTitle, username, slug):
            // 하이라이트 = 인용. 카드 박스가 아니라 그린 좌측 룰 + 큰 구절 — 본문에서 뽑힌 결.
            // 탭 = 글의 *그 문장*으로 딥링크(스크롤+깜빡), 글 맨 위가 아니라.
            NavigationLink(value: Route.postFocusQuote(username: username, slug: slug, quote: quote)) {
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Palette.accent)
                        .frame(width: 3)
                    VStack(alignment: .leading, spacing: 8) {
                        kindTag("하이라이트", icon: "quote.opening")
                        Text(quote)
                            .typeScale(.body)
                            .foregroundStyle(Palette.body)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(postTitle)
                            .typeScale(.meta)
                            .foregroundStyle(Palette.faint)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

        case let .note(body):
            // 노트 = 붙잡은 생각. 회색 박스 없이 바로 본문 — 글(카드)·하이라이트(그린 룰)와
            // 실루엣으로 구분되고, 노트는 가장 조용하게 종이 위에 그대로 앉는다.
            VStack(alignment: .leading, spacing: 8) {
                kindTag("노트", icon: "text.quote")
                Text(body)
                    .typeScale(.body)
                    .foregroundStyle(Palette.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // 종류 꼬리표 — 작고 흐린 한 점. 실루엣이 1차 신호, 이건 확인 사살.
    private func kindTag(_ label: LocalizedStringKey, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9 * metaUnit, weight: .bold))
            Text(label)
                .typeScale(.footnote)
        }
        .foregroundStyle(Palette.faint)
    }
}

