//
//  DiscoverView.swift
//  kurl
//
//  발견 = 읽기의 연결 그래프 홈(§0). 발견은 활동 로그가 아니라 *입구 모음* 이다 — "어디로 들어가서
//  어디로 나가나". 기본 표면 = 지금 열려 있는 길(공개 컬렉션 입구) · 취향이 겹치는 큐레이터(사람 입구).
//  시간순 "누가 언제 무엇을 이었나" 흐름은 삭제하지 않고 "최근" 탭으로 보존한다(칭찬받은 표면, 회귀 0).
//  broadcast 아니라 큐레이션을 따라간다(docs/collections-design.md).
//  (릴스형 몰입 덱 DiscoverDeckView 는 `--screen deck` 으로 주차 — 발견 표면에선 내렸다.)
//

import SwiftUI

/// 발견 표면 세 흐름 — 입구(길·큐레이터) · 최근(큐레이터 연결 시간순) · 남들 하이라이트.
/// 입구가 기본: 발견은 "누가 언제"가 아니라 "어디로 들어가나"로 시작한다(§0).
private enum DiscoverTab: String, CaseIterable, Identifiable {
    case entrances
    case connections
    case highlights
    var id: String { rawValue }
    var label: String {
        switch self {
        case .entrances: String(localized: "입구")
        case .connections: String(localized: "최근")
        case .highlights: String(localized: "하이라이트")
        }
    }
}

struct DiscoverView: View {
    @State private var events: [ConnectionEvent] = []
    @State private var loading = true
    @State private var failed = false
    @State private var showLoginSheet = false
    /// 직전 로그인 상태 — 재-appear 재발화와 실제 인증 전환을 구분한다(FeedView 와 같은 문법).
    @State private var wasSignedIn = AuthStore.shared.isSignedIn
    @State private var hasLoaded = false
    /// 발견 표면 세 흐름: 입구(길·큐레이터) / 최근(큐레이터 연결 시간순) / 남들 하이라이트.
    /// 입구가 기본 — 발견은 활동 로그가 아니라 어디로 들어가나로 연다(§0).
    @State private var tab: DiscoverTab = .entrances
    @State private var highlights: [HighlightFeedItemView] = []
    @State private var hlLoading = true
    @State private var hlFailed = false
    @State private var hlLoaded = false

    var body: some View {
        NavigationStack {
            ReadingColumn(spacing: 0) {
                // 콘텐츠가 edge-to-edge로 흐른다 — 피드 탭과 같은 결(고정 "발견" 타이틀 ❌).
                Color.clear.frame(height: 8)
                if !AuthStore.shared.isSignedIn {
                    // 발견 = 팔로우한 큐레이터의 연결/하이라이트 피드(인증 필요). 비로그인은 401 무한
                    // 재시도가 아니라 로그인 게이트로(막다른 길 금지).
                    loggedOutGate
                } else {
                    // 발견 표면 = 큐레이터 연결(누가 무엇을 이었나) · 남들 하이라이트(누가 무엇을 밑줄 쳤나)
                    // 두 흐름을 떠 있는 유리 세그먼트로 — FeedView 의 최신·인기·팔로잉과 같은 문법.
                    GlassSegmentSwitcher(items: DiscoverTab.allCases, selection: $tab) { $0.label }
                        .padding(.bottom, 14)
                    switch tab {
                    case .entrances: entrancesContent
                    case .connections: connectionsContent
                    case .highlights: highlightsContent
                    }
                }
            }
            // 스크롤을 내리면 탭바가 사라지고 올리면 돌아온다(스레드식) — 탭 루트 전용.
            .tracksTabBarVisibility()
            // 고정 스트립 대신 콘텐츠가 유리 크롬 밑으로 흐른다 — 상단 라벨은 탭바 아이콘이 맡는다.
            .toolbar(.hidden, for: .navigationBar)
            // 푸시된 상세는 탭바 숨김을 추적하지 않는다(탭 루트 전용).
            .navigationDestination(for: CollectionRef.self) {
                CollectionDetailView(collectionId: $0.id).environment(\.tabBarVisibility, nil)
            }
            .navigationDestination(for: Route.self) {
                RouteView(route: $0).environment(\.tabBarVisibility, nil)
            }
            // .task 는 재-appear(탭 전환·글에서 pop 복귀)마다 재발화한다 — 첫 진입과 실제
            // 인증 전환에서만 요청(FeedViewModel.loadInitial 의 idle 가드와 같은 문법).
            // 명시적 갱신은 refreshable 이 맡는다.
            .task(id: AuthStore.shared.isSignedIn) {
                let signedIn = AuthStore.shared.isSignedIn
                if hasLoaded, signedIn == wasSignedIn { return }
                wasSignedIn = signedIn
                hasLoaded = true
                await load()
            }
            .task(id: tab) { if tab == .highlights { await loadHighlights() } }
            .refreshable {
                // 입구·최근은 같은 연결 흐름(events)에서 산다 — 둘 다 load() 로 새로고침한다.
                if tab == .highlights { await loadHighlights(force: true) } else { await load() }
            }
        }
    }

    // MARK: 입구 모음 — 지금 열려 있는 길 · 취향이 겹치는 큐레이터

    /// 지금 열려 있는 길 — 흐름에 나타난 공개 컬렉션을 collectionId 로 중복 제거(첫 등장 순 = 최신순).
    /// 새 콜 없이 이미 받은 events 에서 입구를 뽑는다(신규 백엔드 0). 발견은 "누가 언제"가 아니라
    /// 어느 길로 들어가나로 시작한다.
    private var openPaths: [DiscoverPath] {
        var seen = Set<Int64>()
        var out: [DiscoverPath] = []
        for e in events where seen.insert(e.collectionId).inserted {
            out.append(
                DiscoverPath(
                    id: e.collectionId, title: e.collectionTitle,
                    kind: e.collectionKind, curatorUsername: e.curator.username))
        }
        return out
    }

    /// 취향이 겹치는 큐레이터 — 흐름에 나타난 큐레이터를 username 으로 중복 제거(첫 등장 순).
    /// 팔로우한 큐레이터의 연결이 events 에 흐르므로, 이들이 곧 취향 겹치는 사람 입구다(같은 흐름 재사용).
    private var flowCurators: [Author] {
        var seen = Set<String>()
        var out: [Author] = []
        for e in events where seen.insert(e.curator.username).inserted {
            out.append(e.curator)
        }
        return out
    }

    @ViewBuilder
    private var entrancesContent: some View {
        if loading {
            KurlLoadingMark()
                .frame(maxWidth: .infinity, minHeight: 320)
        } else if failed {
            failedState
        } else if openPaths.isEmpty && flowCurators.isEmpty {
            // 콜드스타트 — 팔로우 0이면 흐를 게 없다. 입구도 최근과 같은 언어로 작가 찾기(막다른 길 금지).
            emptyState
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !openPaths.isEmpty {
                    RailHeading("지금 열려 있는 길")
                        .padding(.bottom, 12)
                    ForEach(Array(openPaths.enumerated()), id: \.element.id) { index, path in
                        NavigationLink(value: CollectionRef(id: path.id)) {
                            PathEntranceRow(path: path)
                        }
                        .buttonStyle(.plain)
                        .modifier(QuietAppear(index: index))
                        if index < openPaths.count - 1 {
                            Hairline().padding(.leading, 47)
                        }
                    }
                }
                if !flowCurators.isEmpty {
                    RailHeading("취향이 겹치는 큐레이터")
                        .padding(.top, openPaths.isEmpty ? 0 : 30)
                        .padding(.bottom, 12)
                    ForEach(Array(flowCurators.enumerated()), id: \.element.id) { index, curator in
                        NavigationLink(value: Route.author(username: curator.username)) {
                            CuratorEntranceRow(curator: curator)
                        }
                        .buttonStyle(.plain)
                        .modifier(QuietAppear(index: openPaths.count + index))
                        if index < flowCurators.count - 1 {
                            Hairline().padding(.leading, 55)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var connectionsContent: some View {
        if loading {
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

    @ViewBuilder
    private var highlightsContent: some View {
        if hlLoading {
            KurlLoadingMark()
                .frame(maxWidth: .infinity, minHeight: 320)
        } else if hlFailed {
            ContentUnavailableView {
                Label("불러오지 못했습니다", systemImage: "wifi.exclamationmark")
            } actions: {
                Button("다시 시도") { Task { await loadHighlights(force: true) } }
                    .foregroundStyle(Palette.link)
            }
            .padding(.top, 60)
        } else if highlights.isEmpty {
            // 막다른 길 금지 — 팔로우한 큐레이터가 밑줄 치면 흐른다. 연결 흐름으로 이어준다.
            ContentUnavailableView {
                Label("아직 하이라이트가 없어요", systemImage: "highlighter")
            } description: {
                Text("팔로우한 큐레이터가 글에서 밑줄 친 문장이 여기에 모여요.")
            } actions: {
                Button("연결 흐름 보기") { tab = .connections }
                    .foregroundStyle(Palette.link)
            }
            .padding(.top, 60)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(highlights.enumerated()), id: \.element.id) { index, item in
                    HighlightFeedCard(item: item)
                        .modifier(QuietAppear(index: index))
                    if index < highlights.count - 1 {
                        Hairline().padding(.vertical, 10)
                    }
                }
            }
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
        // 빈 목록에서 시작하는 fetch(첫 진입·로그인 직후)는 로딩으로 — 응답 전에
        // 콜드스타트 빈 상태가 먼저 뜨지 않게. 목록이 있으면 조용히 갱신.
        if events.isEmpty { loading = true }
        do {
            events = try await CollectionsAPI.discoverFeed()
            loading = false
        } catch {
            loading = false
            if events.isEmpty {
                failed = true
            } else {
                ToastCenter.shared.show(String(localized: "새로고침하지 못했습니다"))
            }
        }
    }

    /// "남들 하이라이트" 피드 로드 — 이미 받았으면 탭 재전환 시 재fetch 안 함(refreshable 만 force).
    private func loadHighlights(force: Bool = false) async {
        guard AuthStore.shared.isSignedIn else {
            highlights = []
            hlFailed = false
            hlLoading = false
            return
        }
        if hlLoaded, !force, !highlights.isEmpty { return }
        hlFailed = false
        if highlights.isEmpty { hlLoading = true }
        do {
            highlights = try await HighlightsAPI.feed().items
            hlLoaded = true
            hlLoading = false
        } catch {
            hlLoading = false
            if highlights.isEmpty {
                hlFailed = true
            } else {
                ToastCenter.shared.show(String(localized: "새로고침하지 못했습니다"))
            }
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

    // 콜드스타트 — 팔로우가 없으면 백엔드가 빈 피드를 준다. 막다른 길이 아니라 작가 찾기로
    // (다른 빈 면과 같은 언어 = FeedPlaceholder).
    private var emptyState: some View {
        FeedPlaceholder(
            eyebrow: "발견",
            title: "아직 흐를 게 없어요",
            message: "작가를 팔로우하면, 그들이 컬렉션에 이은 글이 여기에 흘러요.",
            actionTitle: "읽을 글 찾기",
            action: { TabRouter.shared.selection = 0 }
        )
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var failedState: some View {
        ContentUnavailableView {
            Label("불러오지 못했습니다", systemImage: "wifi.exclamationmark")
        } actions: {
            Button("다시 시도") { Task { await load() } }
                .foregroundStyle(Palette.link)
        }
        .padding(.top, 80)
    }
}

/// 큐레이터 연결 한 장 — 누가(아바타+이름) → 어느 컬렉션에 → [왜 한 줄] → 블록.
/// 발견 표면(팔로우 큐레이터 흐름)과 비로그인 첫 피드의 공개 연결 인터리브가 이 하나를 공유한다.
struct ConnectionEventCard: View {
    let event: ConnectionEvent
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1
    /// 비로그인 첫 피드에서도 이 카드가 흐른다 — 이때 컬렉션 칩은 인증 전용 상세(401)로
    /// 데려가면 막다른 길이라, 정식 로그인 시트로 돌린다(발견 표면은 이미 로그인 뒤라 안 뜬다).
    @State private var showLoginPrompt = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 귀속 = 조용히. 누가·언제만(broadcast 아니라 connect 라는 건 아래 eyebrow 가 말한다).
            HStack(spacing: 7) {
                // 큐레이터(아바타+이름) → 그 사람 프로필. 컬렉션 eyebrow 와 같은 결의 형제 링크.
                NavigationLink(value: Route.author(username: event.curator.username)) {
                    HStack(spacing: 7) {
                        AvatarView(author: event.curator, size: 22)
                        Text(event.curator.username)
                            .typeScale(.meta)
                            .foregroundStyle(Palette.secondary)
                    }
                }
                .buttonStyle(.plain)
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
            // 로그인 뒤에만 인증 전용 상세로 가고, 비로그인이면 그 자리에서 로그인 시트로 돌린다.
            if AuthStore.shared.isSignedIn {
                NavigationLink(value: CollectionRef(id: event.collectionId)) {
                    collectionChip
                }
                .buttonStyle(.plain)
            } else {
                Button { showLoginPrompt = true } label: {
                    collectionChip
                }
                .buttonStyle(.plain)
            }

            // 큐레이터의 한 줄 = 히어로. 이 흐름이 알고리즘 피드가 아니라 사람의 큐레이션이라는
            // 가장 또렷한 신호. 없으면(이유 안 단 연결) 블록이 곧장 히어로가 된다.
            if let why = event.why {
                Text(why)
                    .typeScale(.body)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            BlockPreview(block: event.block, showsEngagement: true)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .loginPrompt(isPresented: $showLoginPrompt, message: "큐레이터가 엮은 컬렉션 이어 보기")
    }

    /// 컬렉션 칩의 겉모습 — 로그인 여부에 따라 링크로도, 로그인 트리거로도 감싼다(모양은 하나).
    private var collectionChip: some View {
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
}

/// 연결된 블록 — 종류마다 *다른 실루엣*으로 한눈에 구분된다(같은 리듬 반복 = 단조의 원인).
/// 글 = 흰 보더 카드(읽을 아티팩트) · 하이라이트 = 그린 좌측 룰 인용(뽑은 구절) ·
/// 노트 = 부드러운 틴트 패널(붙잡은 생각). 발견 흐름·컬렉션 상세가 이 하나를 공유한다.
struct BlockPreview: View {
    let block: ConnectionBlock
    /// 발견 흐름의 글 미리보기에만 켠다 — 내 좋아요 표식 + 그 자리 북마크 토글. 컬렉션 상세·
    /// 하이라이트 스레드가 쓰는 같은 컴포넌트는 기본 꺼짐(표식 없이 조용히).
    var showsEngagement = false
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
            // 종이 카드 위 조용한 인게이지 표식 — 카드 우상단(BlogCard 북마크 표식과 같은 자리).
            // 유리 없이 종이 문법(§1.5): 좋아요 여부는 표식, 북마크는 그 자리 토글. 버튼이 제 탭을
            // 삼켜 카드 열기와 겹치지 않는다.
            .overlay(alignment: .topTrailing) {
                if showsEngagement {
                    PostPreviewEngagement(username: username, slug: slug)
                }
            }

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

/// 미리보기 카드의 조용한 인게이지 — 좋아요 여부(하트 표식)와 북마크(그 자리 토글).
/// 카드는 종이 세계(§1.5)라 유리 없이 종이 문법: 채워짐/빔 심볼 한둘. 행당 그린 액센트 ≤1 —
/// 그린은 행동 가능한 북마크(켜짐)만 가져가고, 좋아요 표식은 채워진 모양으로만 말한다.
/// 연결 응답엔 postId 가 없어 스토어로 여부를 대조하고, 북마크를 켤 때만 상세로 id 를 푼다.
/// 북마크 = 낙관 토글(즉시 반영 → 실패 시 원상복구 + 토스트) + 가벼운 햅틱, 비로그인이면 그 자리 로그인.
private struct PostPreviewEngagement: View {
    let username: String
    let slug: String

    @State private var showLoginPrompt = false
    @State private var toggleTick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var liked: Bool { LikeStore.shared.contains(username: username, slug: slug) }
    private var bookmarked: Bool { BookmarkStore.shared.contains(username: username, slug: slug) }

    var body: some View {
        HStack(spacing: 12) {
            if liked {
                // 좋아요 여부 = 조용한 표식(끄기/켜기는 상세의 독이 든다). 그린은 북마크가 가져가므로
                // 여기선 무채색(secondary) — 채워진 하트 모양만으로 "좋아요함"을 말한다.
                Image(systemName: "heart.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                    .accessibilityLabel(Text("좋아요한 글"))
            }
            Button {
                toggleBookmark()
            } label: {
                Image(systemName: bookmarked ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 13, weight: .semibold))
                    .symbolEffect(.bounce, value: reduceMotion ? false : bookmarked)
                    .foregroundStyle(bookmarked ? Palette.accent : Palette.faint)
                    // 44pt 터치 타깃(§2) — 보이는 글리프는 작아도 누를 곳은 넉넉히.
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(bookmarked ? "북마크됨" : "북마크"))
            .accessibilityAddTraits(bookmarked ? [.isSelected] : [])
        }
        .padding(.trailing, 4)
        .padding(.top, 2)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: liked)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: bookmarked)
        .sensoryFeedback(.impact(weight: .light), trigger: toggleTick)
        .task(id: AuthStore.shared.isSignedIn) {
            await BookmarkStore.shared.hydrateIfNeeded()
            await LikeStore.shared.hydrateIfNeeded()
        }
        .loginPrompt(isPresented: $showLoginPrompt, message: "북마크한 글은 내 서재에 모여요")
    }

    private func toggleBookmark() {
        guard AuthStore.shared.isSignedIn else {
            showLoginPrompt = true
            return
        }
        toggleTick += 1
        let knownId = BookmarkStore.shared.postId(username: username, slug: slug)
        let target = !bookmarked
        // 낙관 — 응답 전에 표식부터 뒤집는다(id 는 아직 모를 수 있어 nil 로 여부만 표시).
        BookmarkStore.shared.set(username: username, slug: slug, id: knownId, on: target)
        Task {
            do {
                let id: Int64
                if let knownId {
                    id = knownId
                } else {
                    // 연결 미리보기엔 postId 가 없다 — 켤 때 한 번만 상세로 id 를 푼다(탭 1회당 1콜).
                    id = try await BlogAPI.postDetail(username: username, slug: slug).post.id
                }
                let status = try await InteractionsAPI.setBookmark(postId: id, on: target)
                BookmarkStore.shared.set(username: username, slug: slug, id: id, on: status.bookmarked)
                // 북마크 = 오프라인 보장 — 켜지면 기기 사본 확보(서재 위젯 스냅샷까지), 꺼지면 정리.
                // 기존 북마크 플로우와 같은 경로라 OfflineStore·위젯이 자동으로 맞는다.
                if status.bookmarked {
                    await OfflineStore.shared.download(username: username, slug: slug)
                } else {
                    OfflineStore.shared.remove(username: username, slug: slug)
                }
            } catch {
                BookmarkStore.shared.set(username: username, slug: slug, id: knownId, on: !target)
                ToastCenter.shared.show(String(localized: "북마크를 반영하지 못했습니다"))
            }
        }
    }
}

/// "남들 하이라이트" 한 장 — 큐레이터(아바타+이름)가 그은 구절 + 원문 참조. 구절 탭 = 원문의 그 문장으로.
private struct HighlightFeedCard: View {
    let item: HighlightFeedItemView
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 누가 칠했나 = 조용히(아바타+이름 → 프로필, 형제 링크). 우측에 답글 수(있으면).
            HStack(spacing: 7) {
                if let curator = item.curator {
                    NavigationLink(value: Route.author(username: curator.username)) {
                        HStack(spacing: 7) {
                            AvatarView(author: curator, size: 22)
                            Text(curator.username)
                                .typeScale(.meta)
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if let at = item.createdAt {
                    Text("·").foregroundStyle(Palette.faint)
                    Text(at.relativeShort)
                        .typeScale(.meta)
                        .foregroundStyle(Palette.faint)
                }
                Spacer(minLength: 0)
                if item.replyCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 10 * metaUnit))
                        Text("\(item.replyCount)")
                    }
                    .typeScale(.meta)
                    .foregroundStyle(Palette.faint)
                }
            }

            // 구절 + 글 참조 → 원문의 그 구절로(postFocusQuote). 큐레이터 링크와 형제(중첩 아님).
            if let author = item.postAuthorUsername {
                NavigationLink(
                    value: Route.postFocusQuote(username: author, slug: item.postSlug, quote: item.quote)
                ) {
                    quoteBody(author: author)
                }
                .buttonStyle(.plain)
            } else {
                quoteBody(author: nil)
            }
        }
    }

    private func quoteBody(author: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 그은 구절 — 본문에서 칠한 그린 워시를 그대로(내 하이라이트 서재와 같은 문법).
            Text(item.quote)
                .typeScale(.lede)
                .foregroundStyle(Palette.body)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Palette.accent.opacity(0.16),
                    in: RoundedRectangle(cornerRadius: Metrics.radiusThumb))
            // 큐레이터의 여백 메모(있으면).
            if let note = item.note, !note.isEmpty {
                Text(note)
                    .typeScale(.body)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 어느 글에서 — 제목 · @작가.
            HStack(spacing: 4) {
                Text(item.postTitle)
                    .typeScale(.meta)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if let author {
                    Text("·").foregroundStyle(Palette.faint)
                    Text("@\(author)")
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: 입구 — 길 · 큐레이터

/// 발견 입구용 길 한 줄의 값 — 흐름(events)에서 뽑은 공개 컬렉션(collectionId 로 중복 제거).
/// 백엔드 모델이 아니라 events 를 접어 만든 표시용 값이라 여기 산다.
private struct DiscoverPath: Identifiable, Hashable {
    let id: Int64
    let title: String
    let kind: CollectionKind
    let curatorUsername: String
}

/// 길 입구 한 줄 — 그린 글리프(길=↳ / 컬렉션=그리드) + 제목, 그 아래 @큐레이터. PostEdges 의
/// pathChip 과 같은 문법(§1 종이·§10.3 비텍스트만 초록). 허영 지표(편수·분) 없이 조용히(§0).
private struct PathEntranceRow: View {
    let path: DiscoverPath
    @ScaledMetric(relativeTo: .caption) private var glyph: CGFloat = 13

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: path.kind == .path ? "arrow.turn.down.right" : "square.grid.2x2")
                .font(.system(size: glyph, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 24, alignment: .leading)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(path.title)
                    .typeScale(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("@\(path.curatorUsername)")
                    .typeScale(.meta)
                    .foregroundStyle(Palette.faint)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.faint)
                .padding(.top, 4)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// 큐레이터 입구 한 줄 — 아바타 + @이름·소개. PostEdges·컬렉션 상세의 kindred 행과 같은 문법.
/// 흐름에 나타난 큐레이터가 곧 취향 겹치는 사람 입구 — 겹침 수는 특정 블록 그래프에만 있어 여기선 조용히 뺀다.
private struct CuratorEntranceRow: View {
    let curator: Author

    var body: some View {
        HStack(spacing: 11) {
            AvatarView(author: curator, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(curator.username)")
                    .typeScale(.titleSmall)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if let bio = curator.bio, !bio.isEmpty {
                    Text(bio)
                        .typeScale(.lede)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.faint)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

