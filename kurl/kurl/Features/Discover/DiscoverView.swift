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
    /// page 0 이 전역 폴백으로 내려왔는가 — 흐름별로 따로 둔다(연결·하이라이트는 다른 엔드포인트).
    /// 활성이면 조용한 맥락 한 줄을 세그먼트 콘텐츠 위에 올리고, 이후 요청에 scope=global 을 고정한다.
    @State private var connectionsSource: DiscoverScope = .following
    @State private var highlightsSource: DiscoverScope = .following
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    // 세 흐름을 떠 있는 유리 세그먼트로 — FeedView 의 최신·인기·팔로잉과 같은 문법.
                    // 스위처는 화면 정중앙에 — 스튜디오 헤더와 같은 Spacer 보정(왼쪽에 기대던 것 교정).
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        GlassSegmentSwitcher(items: DiscoverTab.allCases, selection: $tab) { $0.label }
                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 14)
                    // 전역 폴백이 활성인 흐름에서만 조용한 맥락 한 줄(§10) — 왜 이게 보이는지 + 큐레이터 찾기.
                    if activeSourceIsGlobal {
                        globalFallbackCaption
                    }
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
                CollectionDetailView(collectionId: $0.id)
            }
            .navigationDestination(for: Route.self) {
                RouteView(route: $0)
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
        // events 는 최신순 — 첫 등장이 그 길에 가장 최근 붙은 연결이라, 그 "왜" 한 줄을 입구 미리보기로 싣는다.
        for e in events where seen.insert(e.collectionId).inserted {
            out.append(
                DiscoverPath(
                    id: e.collectionId, title: e.collectionTitle,
                    kind: e.collectionKind, curatorUsername: e.curator.username,
                    latestWhy: e.why))
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

    /// 지금 보고 있는 흐름이 전역 폴백으로 내려왔는가 — 입구·최근은 연결 소스, 하이라이트는 제 소스.
    private var activeSourceIsGlobal: Bool {
        switch tab {
        case .entrances, .connections: connectionsSource == .global
        case .highlights: highlightsSource == .global
        }
    }

    /// 전역 폴백 맥락 한 줄(§10) — 왜 개인화가 아니라 전역이 보이는지 조용히 알리고, 큐레이터를
    /// 팔로우하면 개인화된다는 다음 행동으로 잇는다. 배너 아님 — eyebrow 급 한 줄 + 인라인 링크.
    private var globalFallbackCaption: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("아직 팔로우한 큐레이터의 소식이 없어, 지금 전역에서 이어지는 것들을 보여드려요.")
                .typeScale(.footnote)
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // 큐레이터 찾기 = 입구 탭의 "취향이 겹치는 큐레이터" 레일로 데려간다(팔로우하면 개인화된다).
            Button {
                tab = .entrances
            } label: {
                Text("큐레이터 찾기")
                    .typeScale(.footnote)
                    .foregroundStyle(Palette.link)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 14)
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
            ErrorState(retry: { Task { await loadHighlights(force: true) } })
                .padding(.top, 60)
        } else if highlights.isEmpty {
            // 막다른 길 금지 — 팔로우한 큐레이터가 밑줄 치면 흐른다. 연결 흐름으로 이어준다.
            ContentUnavailableView {
                Label("아직 하이라이트가 없어요", systemImage: "highlighter")
            } description: {
                Text("팔로우한 큐레이터가 글에서 밑줄 친 문장이 여기에 모여요.")
            } actions: {
                // 콜드스타트(팔로우 0)면 연결 흐름도 비어 "빈 화면 → 빈 화면" 루프였다 —
                // 그땐 피드(작가 찾기)로 바로 보낸다. 흐름이 있으면 원래 안내 유지.
                if events.isEmpty {
                    Button("읽을 글 찾기") { TabRouter.shared.switchTo(0, reduceMotion: reduceMotion) }
                        .foregroundStyle(Palette.link)
                } else {
                    Button("연결 흐름 보기") { tab = .connections }
                        .foregroundStyle(Palette.link)
                }
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
            // 폴백이 활성이던 흐름은 scope=global 을 고정해 개인화 페이지와 안 섞이게 한다.
            let response = try await CollectionsAPI.discoverFeed(scope: connectionsSource)
            events = response.items
            connectionsSource = response.source
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
            // 폴백이 활성이던 흐름은 scope=global 을 고정한다(연결 흐름과 같은 문법).
            let page = try await HighlightsAPI.feed(scope: highlightsSource)
            highlights = page.items
            highlightsSource = page.source
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
            action: { TabRouter.shared.switchTo(0, reduceMotion: reduceMotion) }
        )
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var failedState: some View {
        ErrorState(retry: { Task { await load() } })
            .padding(.top, 80)
    }
}

/// 큐레이터 연결 한 장 — 일반 글 카드 문법으로 수렴한 미니멀 카드(≤3층, 장식 아이콘 0, 웹 #891 미러).
/// 연결된 것(글 제목·하이라이트 구절·노트 본문)이 주인공으로 본문에 직접(중첩 박스·아이콘 없음),
/// why 조용한 한 줄, 맥락은 메타 한 줄(아바타 + "@큐레이터가 [컬렉션]에 연결 · 날짜", 컬렉션=그린 링크).
/// 발견 표면(팔로우 큐레이터 흐름)과 비로그인 첫 피드의 공개 연결 인터리브가 이 하나를 공유한다.
struct ConnectionEventCard: View {
    let event: ConnectionEvent
    /// 비로그인 첫 피드에서도 이 카드가 흐른다 — 이때 컬렉션 링크는 인증 전용 상세(401)로
    /// 데려가면 막다른 길이라, 정식 로그인 시트로 돌린다(발견 표면은 이미 로그인 뒤라 안 뜬다).
    @State private var showLoginPrompt = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 주인공 — 연결된 것(일반 카드 제목과 같은 급). 중첩 박스·아이콘 없이 본문에 직접.
            // 하이라이트만 세로 그린 스파인 유지(칠한 구절은 콘텐츠라). 노트는 종이 위 그대로.
            MinimalConnectionHero(block: event.block)

            // why — 큐레이터의 한 줄(콘텐츠라 유지). 일반 카드 소개글 자리, 스파인 없이 조용히.
            if let why = event.why {
                Text(why)
                    .typeScale(.lede)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 맥락 한 줄 — 일반 카드 작가 행과 같은 결. 아바타 + "@큐레이터가 [컬렉션]에 연결 · 날짜".
            // 장식 아이콘 0, 컬렉션은 그린 텍스트(알약 아님). 로케일 어순은 xcstrings 위치 인자로 지킨다.
            // 행 전체 탭 = 컬렉션(연결의 주 문); 로그인 뒤에만 상세로, 비로그인이면 로그인 시트로.
            metaLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .loginPrompt(isPresented: $showLoginPrompt, message: "큐레이터가 엮은 컬렉션 이어 보기")
    }

    @ViewBuilder
    private var metaLine: some View {
        if AuthStore.shared.isSignedIn {
            NavigationLink(value: CollectionRef(id: event.collectionId)) { metaRow }
                .buttonStyle(.plain)
        } else {
            Button { showLoginPrompt = true } label: { metaRow }
                .buttonStyle(.plain)
        }
    }

    private var metaRow: some View {
        HStack(spacing: 7) {
            AvatarView(author: event.curator, size: 20)
            // 큐레이터·컬렉션 이름을 서식 있는 Text 조각으로 끼워 로케일 어순을 지킨다(웹 t.rich 대응):
            // 컬렉션=그린, 나머지=secondary. 날짜는 · 뒤 faint.
            metaText
                .typeScale(.meta)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .expandTapTarget(6)
    }

    /// "@큐레이터가 [컬렉션]에 연결 · 날짜" — 컬렉션만 그린으로 강조한 단일 Text. 길/컬렉션 어투 분리.
    private var metaText: Text {
        let curator = Text(event.curator.username).foregroundStyle(Palette.secondary)
        let collection = Text(event.collectionTitle).foregroundStyle(Palette.link)
        // xcstrings 위치 인자(%1$@ 큐레이터 · %2$@ 컬렉션)로 로케일별 어순 유지.
        let phrase: Text = event.collectionKind == .path
            ? Text("\(curator)가 \(collection) 길에 엮음")
            : Text("\(curator)가 \(collection)에 연결")
        var line = phrase.foregroundStyle(Palette.secondary)
        if let at = event.connectedAt {
            line = line
                + Text("  ·  ").foregroundStyle(Palette.faint)
                + Text(at.relativeShort).foregroundStyle(Palette.faint)
        }
        return line
    }
}

/// 연결 이벤트의 주인공 — 웹 #891 미러. 글=제목만(박스·아이콘 없이 본문에 직접), 하이라이트=그린
/// 스파인+칠한 구절, 노트=본문 그대로. 전부 일반 카드 제목 급이 주인공이고 장식 꼬리표는 없다.
private struct MinimalConnectionHero: View {
    let block: ConnectionBlock

    var body: some View {
        switch block {
        case let .post(title, _, username, slug, _):
            NavigationLink(value: Route.post(username: username, slug: slug)) {
                Text(title)
                    .typeScale(.title)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

        case let .highlight(quote, _, username, slug):
            // 하이라이트 = 칠한 구절이 주인공. 세로 그린 스파인만 남기고(콘텐츠라), 탭은 그 문장으로 딥링크.
            NavigationLink(value: Route.postFocusQuote(username: username, slug: slug, quote: quote)) {
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Palette.accent)
                        .frame(width: 3)
                    Text(quote)
                        .typeScale(.title)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

        case let .note(body):
            // 노트 = 붙잡은 생각. 목적지 없이 종이 위 그대로, 제목 급 본문.
            Text(body)
                .typeScale(.title)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 연결된 블록 — 일반 글 카드 문법으로 수렴한 미니멀 렌더(웹 #894 미러). 글·상세 "이어진 것"·
/// 컬렉션 상세·하이라이트 스레드가 이 하나를 공유하므로, 장식 꼬리표(타입 태그·문서/인용/노트
/// 아이콘)와 중첩 박스를 걷어 연결된 것 자체가 종이 위 주인공이 되게 한다. 종류 구분은 실루엣만:
/// 글=제목이 카드 제목 급 · 하이라이트=그린 좌측 스파인 + 구절(칠한 구절이 콘텐츠) · 노트=본문 그대로.
struct BlockPreview: View {
    let block: ConnectionBlock

    var body: some View {
        switch block {
        case let .post(title, excerpt, username, slug, _):
            // 글 = 제목이 주인공. 중첩 박스·보더·문서 아이콘·"글" 태그 제거하고 종이에 직접,
            // 소개글은 조용한 한 줄. (연결의 주인공은 연결된 글이지 카드 장식이 아니다.)
            NavigationLink(value: Route.post(username: username, slug: slug)) {
                VStack(alignment: .leading, spacing: 4) {
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

        case let .highlight(quote, postTitle, username, slug):
            // 하이라이트 = 칠한 구절이 주인공. 그린 좌측 스파인만 남기고(구절이 콘텐츠) 인용 아이콘·
            // "하이라이트" 태그 제거. 탭 = 글의 *그 문장*으로 딥링크. 출처 제목은 조용한 한 줄.
            NavigationLink(value: Route.postFocusQuote(username: username, slug: slug, quote: quote)) {
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Palette.accent)
                        .frame(width: 3)
                    VStack(alignment: .leading, spacing: 6) {
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
            // 노트 = 붙잡은 생각. StickyNote 아이콘·"노트" 태그·래퍼 없이 본문이 맨 종이에 그대로.
            Text(body)
                .typeScale(.body)
                .foregroundStyle(Palette.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    // 답글 수 = 말풍선 아이콘 없이 평문(웹 #894 미러). 장식 대신 사실 한 조각.
                    Text("답글 \(item.replyCount)")
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
    /// 이 길에 가장 최근 붙은 연결의 "왜" 한 줄(있으면) — 입구가 제목만이 아니라 큐레이터의 목소리를
    /// 한 줄 미리 보여 주는 신호. 흐름(events)에 이미 실려 온 값이라 새 콜 없이 붙인다.
    let latestWhy: String?
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
                // 큐레이터의 최근 한 줄 — 입구가 알고리즘이 아니라 사람의 목소리임을 미리 보여 준다(§0).
                if let why = path.latestWhy, !why.isEmpty {
                    Text(why)
                        .typeScale(.lede)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 1)
                }
                Text("@\(path.curatorUsername)")
                    .typeScale(.meta)
                    .foregroundStyle(Palette.faint)
                    .padding(.top, 1)
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

