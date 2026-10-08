//
//  FeedView.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

/// 피드 상단 스위처 — 글 셋(최신·인기·구독함). 짧은 글(노트)은 1급 탭에서 강등,
/// 내 계정 탭의 진입으로 옮겼다(블로그=긴 글 정체성을 흐리지 않게).
enum FeedTab: String, CaseIterable, Identifiable {
    case recent
    case trending
    case forYou
    case following

    var id: String { rawValue }

    var source: FeedSource {
        switch self {
        case .recent: return .recent
        case .trending: return .trending
        case .forYou: return .forYou
        case .following: return .following
        }
    }

    var label: String { source.label }

    var symbol: String {
        switch self {
        case .recent: "clock"
        case .trending: "flame"
        case .forYou: "sparkles"
        case .following: "tray.full"
        }
    }
}

@MainActor
@Observable
final class BlogFeedChoice {
    static let shared = BlogFeedChoice()

    private static let key = "feed.tab"

    var tab: FeedTab {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: Self.key) }
    }
    var path = NavigationPath()

    /// `--feed recent|trending|forYou|following` — 스크린샷/목 검증 진입로(--tab 과 같은 문법).
    private init() {
        let launched = Config.launchValue(after: "--feed").flatMap(FeedTab.init(rawValue:))
        let saved = Config.useMocks ? nil : UserDefaults.standard.string(forKey: Self.key).flatMap(FeedTab.init(rawValue:))
        tab = launched ?? saved ?? .recent
    }
}

struct FeedView: View {
    @State private var choice = BlogFeedChoice.shared
    @Namespace private var zoomNS
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = TabRouter.shared

    var body: some View {
        // 탭바가 커스텀(FloatingTabBar)이라 path 바인딩이 시스템 tabBarMinimizeBehavior 를 죽이던 함정과
        // 무관하다 — 탭 다시 누르기로 루트까지 되돌리려면 path 가 필요하다.
        NavigationStack(path: $choice.path) {
            SwipePager(tabs: FeedTab.allCases, selection: $choice.tab) { tab, active, warm in
                FeedPage(source: tab.source, active: active, warm: warm, zoom: zoomNS)
            }
            .onChange(of: router.reselections) {
                if router.reselectedTab == 0 { choice.path = NavigationPath() }
            }
            // 고정 스트립 대신 떠 있는 유리 — 카드가 캡슐 양옆·뒤로 그대로 흐른다.
            .safeAreaBar(edge: .top) {
                FeedHeaderBar(items: FeedTab.allCases, selection: $choice.tab) { $0.label }
            }
            .task(id: AuthStore.shared.isSignedIn) { await UnreadStore.shared.refresh() }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active { Task { await UnreadStore.shared.refresh() } }
            }
            // 유리는 뒤에 흐르는 것이 있을 때만 유리다 — 스위처 뒤 옅은 안개 한 겹.
            // 뷰포트 고정(스크롤 안 함)이라 카드 사이 틈으로도 첫 화면이 은은하게 물든다.
            .background(alignment: .top) { FeedHeaderMist() }
            .background(Palette.pageBg)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                // 글 푸시만 zoom. 소스 카드가 화면에 없으면(깊은 푸시) 시스템이 표준
                // 푸시로 폴백한다.
                if case .post(let username, let slug) = route, !reduceMotion {
                    RouteView(route: route)
                        .navigationTransition(.zoom(sourceID: "post-\(username)-\(slug)", in: zoomNS))
                } else {
                    RouteView(route: route)
                }
            }
            // 인터리브한 공개 연결 카드의 컬렉션 칩 → 컬렉션 상세(발견 표면과 같은 목적지).
            .navigationDestination(for: CollectionRef.self) {
                CollectionDetailView(collectionId: $0.id)
            }
        }
    }
}

struct BlogFeedMenu: View {
    @State private var choice = BlogFeedChoice.shared

    var body: some View {
        Picker("피드", selection: $choice.tab) {
            ForEach(FeedTab.allCases) { tab in
                Label(tab.label, systemImage: tab.symbol).tag(tab)
            }
        }
        .pickerStyle(.inline)
    }
}

struct FeedHeaderMist: View {
    var body: some View {
        BrandMist()
            .frame(height: 240)
            .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }
}

/// 한 정렬(최신/인기)의 피드 페이지. TabView 가 살려두므로 스와이프해도 상태 유지.
struct FeedPage: View {
    let source: FeedSource
    let active: Bool
    /// 선택 ±1(곧 보일 수 있는 페이지)만 true — 이때만 첫 로드를 발화한다. ZStack 상주라
    /// 숨은 페이지의 .task 도 기동 즉시 돌아 4개 피드가 전부 fetch(구독함은 오프라인
    /// 다운로드까지 연쇄)하며 첫 화면 로딩과 대역폭을 다투던 것.
    let warm: Bool
    let zoom: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: FeedViewModel
    /// 구독함 게이트의 로그인 — 다른 인게이지 면과 같은 정식 로그인 시트로.
    @State private var showLoginSheet = false
    /// 직전 로그인 상태 — 실제 인증 전환에서만 리셋한다(첫 로드 헛 epoch·빈 깜빡임 방지).
    @State private var wasSignedIn = AuthStore.shared.isSignedIn
    /// 스크롤 복원 앵커 — 글로 들어갔다 돌아오면 보던 위치가 사라지던 것(ScrollView 는 push·pop
    /// 을 건너 오프셋을 안 물어 준다). 페이지가 ZStack 에 상주해 이 @State 가 살아남으므로,
    /// 마지막으로 보이던 카드 id 를 붙들어 두면 복귀 시 그 카드로 스크롤이 되돌아간다.
    @State private var scrollAnchor: String?
    @State private var router = TabRouter.shared

    init(source: FeedSource, active: Bool, warm: Bool, zoom: Namespace.ID) {
        self.source = source
        self.active = active
        self.warm = warm
        self.zoom = zoom
        _model = State(initialValue: FeedViewModel(source: source))
    }

    var body: some View {
        Group {
            // 추천·구독함은 인증 피드 — 로그아웃이면 게이트(이때는 fetch 도 하지 않는다).
            if source.requiresAuth, !AuthStore.shared.isSignedIn {
                followingGate
            } else {
            switch model.phase {
            case .idle, .loading:
                // 콜드 로딩은 중앙 마크 대신 카드 그리드 스켈레톤 — 실제 리스트와 같은 레이아웃이라
                // 카드가 착지해도 위치가 안 튄다(중앙→상단 점프 제거). 첫 장은 커버(피처드) 모양.
                FeedSkeleton(leadingCover: source == .recent)
            case .failed(let message):
                failed(message)
            case .loaded:
                list
            }
            }
        }
        // 인증 전환을 task id 로 관찰 — 로그아웃 상태의 401 failed 고착과
        // 계정 전환 후 이전 계정 피드 잔존을 모두 해소한다. 단 실제 전환에서만
        // 리셋한다(첫 발화는 초기값이라 헛 epoch·빈 깜빡임이 된다).
        // warm 도 id 에 묶어 페이지가 선택 ±1 로 들어오는 시점에 재발화 — 리셋은 숨어
        // 있어도 즉시(이전 계정 잔상 방지), fetch 는 warm 일 때만(loadInitial 은 idle
        // 가드라 재발화는 무해).
        .task(id: [warm, AuthStore.shared.isSignedIn]) {
            let signedIn = AuthStore.shared.isSignedIn
            if signedIn != wasSignedIn {
                wasSignedIn = signedIn
                model.resetForAuthChange()
            }
            guard warm, !source.requiresAuth || signedIn else { return }
            await model.loadInitial()
        }
        // 글을 읽다 작가를 차단하고 돌아오면 — 그 작가의 카드를 재조회 없이 그 자리에서 걷어낸다
        // (차단이 피드에도 즉시 반영). 차단 목록이 바뀔 때만 발화한다.
        .onChange(of: BlockStore.shared.blockedUsernames) { _, _ in
            model.pruneBlocked()
        }
    }

    private var followingGate: some View {
        FeedPlaceholder(
            title: source == .forYou ? "읽을수록 좋아집니다" : "팔로우한 글이 여기 모입니다",
            message: source == .forYou
                ? "로그인하면 읽은 글을 따라 추천이 쌓입니다."
                : "로그인하면 팔로우한 작가의 새 글이 도착합니다.",
            actionTitle: "로그인",
            prominent: true,
            action: { showLoginSheet = true }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .loginPrompt(
            isPresented: $showLoginSheet,
            message: source == .forYou
                ? "읽을수록 정확해지는 추천 받기"
                : "팔로우한 작가의 새 글 모아 보기")
    }

    // 발견(browse) 면 = 1열 카드 그리드(#707 웹과 동일 문법). 구독함도 같은 카드 —
    // 최신·인기와 같은 발견 피드(팔로우한 작가의 새 글)라, 알림 같던 인박스 행 대신 카드로.
    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    NavigationLink(value: Route.post(username: item.author.username, slug: item.slug)) {
                        BlogCard(
                            item: item,
                            featured: false,
                            belonging: model.belonging[item.id] ?? [])
                    }
                    .buttonStyle(CardButtonStyle())
                    .cardQuickActions(item)
                    // 복원 앵커의 좌표 — 카드 id 문자열로 못 박아, 복귀 시 이 id 로 스크롤이 되돌아간다.
                    .id(String(item.id))
                    .modifier(ZoomSource(
                        active: active,
                        id: "post-\(item.author.username)-\(item.slug)",
                        ns: zoom))
                    .modifier(QuietAppear(index: index))
                    .modifier(CardScrollFade())
                    .task { await model.loadMoreIfNeeded(current: item) }

                    // 최신 피드 4번째 글 뒤에 발견 시리즈 한 장(웹 메인 피드와 같은 자리). 글이 적으면 끝에.
                    // 카드가 자체 내비(시리즈)·넘김을 들고 있어 바깥 NavigationLink 로 감싸지 않는다.
                    if source == .recent, let series = model.series,
                        index == min(3, model.items.count - 1),
                        let author = series.author, !author.username.isEmpty {
                        FeedSeriesCard(series: series, author: author)
                            .modifier(QuietAppear(index: index))
                            .modifier(CardScrollFade())
                    }

                    // 공개 연결 흐름을 몇 칸마다 인터리브(웹 #828 미러) — 비로그인 첫 피드에도 흐른다.
                    // 연결 카드는 종이 본문(§1) — 유리 없이 컬렉션·왜·블록 실루엣만. 첫 인서트 위에만
                    // 초록 마커 섹션 라벨을 얹어(§10.3 비텍스트 마커=accent) 한 흐름임을 조용히 알린다.
                    if source == .recent, let slot = connectionSlot(afterIndex: index) {
                        if slot.isFirst {
                            connectionHeading
                                .padding(.top, 2)
                        }
                        ConnectionEventCard(event: slot.event)
                            .modifier(QuietAppear(index: index))
                            .modifier(CardScrollFade())
                    }
                }
                if model.isLoadingMore {
                    KurlLoadingMark()
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                }
                if model.loadMoreFailed {
                    // 아이템별 .task 는 1회성 — 실패로 소진되면 이 버튼이 유일한 재진입로다.
                    Button {
                        Task { await model.retryLoadMore() }
                    } label: {
                        HStack(spacing: 4) {
                            Text("더 불러오지 못했습니다 — 다시 시도")
                                .typeScale(.meta)
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(Palette.link)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if model.items.isEmpty {
                    if source == .following {
                        FeedPlaceholder(
                            title: "구독함이 비어 있어요",
                            message: "작가를 팔로우하면 새 글이 여기 도착해요.",
                            actionTitle: "검색에서 작가 찾기",
                            action: { TabRouter.shared.switchTo(3, reduceMotion: reduceMotion) }
                        )
                        .padding(.top, 64)
                    } else {
                        FeedPlaceholder(
                            title: source == .forYou ? "아직은 고를 거리가 적어요" : "아직 글이 없습니다",
                            message: source == .forYou
                                ? "몇 편 읽고 나면 취향이 잡힙니다."
                                : "첫 글이 올라오면 여기에서 만나요.",
                            actionTitle: "읽을 글 찾기",
                            action: { TabRouter.shared.switchTo(3, reduceMotion: reduceMotion) }
                        )
                        .padding(.top, 64)
                    }
                }
            }
            .padding(.vertical, 16)
            .frame(maxWidth: Metrics.readingColumn)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Metrics.gutter)
            // 카드 행마다 붙인 .id 를 복원 좌표로 노출 — scrollPosition 이 이 레이아웃에서 앵커를 읽는다.
            .scrollTargetLayout()
            // 발견 시리즈는 본 피드 반영 뒤 별도로 도착한다(피드를 막지 않는 설계) — 카드 한 장
            // 높이가 리스트 중간에 순간 끼어들어 아래를 보던 화면이 튀던 것을 애니메이트로 밀어낸다.
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: model.series?.id)
        }
        // 글로 들어갔다 돌아오면 보던 카드로 스크롤을 되돌린다 — 페이지가 상주해 앵커가 살아남는다.
        // .top 앵커라 그 카드가 다시 화면 맨 위에 온다(복귀 지점이 튀지 않게).
        .scrollPosition(id: $scrollAnchor, anchor: .top)
        .onChange(of: router.topRequests) {
            guard active, router.topTab == 0, let first = model.items.first else { return }
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) { scrollAnchor = String(first.id) }
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        // 활성 페이지의 스크롤만 탭바 숨김을 몬다 — ZStack 에 상주하는 숨은 페이지가
        // 방향을 함께 흘리면 서로 어긋난다.
        .tracksTabBarVisibility(active)
        .brandRefreshable { await model.reload() }
    }

    // 공개 연결을 인터리브할 자리 — 시리즈 카드(index 3) 뒤로 충분히 띄워 index 5 부터 5칸마다
    // 한 장씩(5·10·15…), 이벤트가 남아 있는 동안만. "글 뒤에만" 끼우므로 마지막 글 뒤로는 새지
    // 않고 항상 다음 글 행이 따라온다(웹 #828 의 "뒤에 실제 행이 있을 때만"과 같은 규칙).
    private struct ConnectionSlot { let event: ConnectionEvent; let isFirst: Bool }

    private func connectionSlot(afterIndex index: Int) -> ConnectionSlot? {
        let events = model.connectionEvents
        guard !events.isEmpty else { return nil }
        // 시작 5, 간격 5 — (index-5)가 5의 배수이고 시작 이상일 때만 슬롯이 열린다.
        let start = 1, gap = 5
        guard index >= start, (index - start) % gap == 0 else { return nil }
        // 마지막 글 뒤에는 끼우지 않는다 — 연결 카드가 피드 끝에 홀로 매달리지 않게.
        guard index < model.items.count - 1 else { return nil }
        let slotOrdinal = (index - start) / gap
        guard slotOrdinal < events.count else { return nil }
        return ConnectionSlot(event: events[slotOrdinal], isFirst: slotOrdinal == 0)
    }

    // "지금 이어지는 것들" — 공개 연결 흐름의 머릿글. 형제 발견 머릿글과 같은 RailHeading 로
    // 맞춘다 — §10 색 규율로 섹션 마커는 잉크로 가라앉힌 지 오래고, 초록은 아래 카드가 제 몫으로
    // 낸다(연결 칩·하이라이트 룰). 머릿글에까지 초록을 다시 얹으면 그 규율을 되돌리는 셈이다.
    private var connectionHeading: some View {
        RailHeading("지금 이어지는 것들")
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(CardScrollFade())
    }

    private func failed(_ message: String) -> some View {
        ErrorState(message: message, retry: { Task { await model.reload() } })
    }
}

/// 비어있음·로그아웃 안내 — 스톡 ContentUnavailableView(큰 SF 심볼 + 가운데 설명문)의
/// 기성품 인상을 걷고, 종이 본문 결의 조용한 면으로 다시 짠다. 브랜드 마크 한 점 +
/// 제목 + 한 줄 + 단일 주액션. 로그인 게이트만 그린 유리 캡슐(§1.4 종이 위
/// 로그인 CTA), 빈 피드 안내는 조용한 그린 텍스트로 — 초록 과용을 피한다(§10 색 규율).
struct FeedPlaceholder: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var prominent: Bool = false
    var action: (() -> Void)?
    /// 주액션 라벨도 시스템 글자 크기를 따른다(제목·설명은 이미 typeScale 로 스케일).
    @ScaledMetric(relativeTo: .headline) private var actionSize: CGFloat = 15

    var body: some View {
        VStack(spacing: 0) {
            // 빈 면에도 남는 브랜드 사인 — 형광 아닌 옅은 잉크(RailHeading 마커와 같은 중립).
            KurlMark(drawn: [true, true, true], tint: Palette.hairlineStrong)
                .frame(width: 46, height: 28)
                .accessibilityHidden(true)
                .padding(.bottom, 24)

            Text(title)
                .typeScale(.featured)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 9)

            Text(message)
                .typeScale(.lede)
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 272)
                .padding(.bottom, 22)

            actionButton
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Metrics.gutter)
    }

    @ViewBuilder private var actionButton: some View {
        if let actionTitle, let action {
            actionButton(actionTitle, action: action)
        }
    }

    @ViewBuilder private func actionButton(_ actionTitle: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        if prominent {
            Button(action: action) {
                Text(actionTitle)
                    .font(.system(size: actionSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassCapsule(prominent: true)
        } else {
            Button(action: action) {
                HStack(spacing: 3) {
                    Text(actionTitle)
                        .typeScale(.meta)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                // 텍스트/인라인 CTA = link(700), accent(600)는 비텍스트 마커 몫(§10.3).
                .foregroundStyle(Palette.link)
                .expandTapTarget(8)
            }
            .buttonStyle(.plain)
        }
    }
}

/// 최신 피드에 끼워 넣는 발견 시리즈 한 장 — 웹 DiscoverySeriesCard 대응. 4:5 "에피소드 페이지":
/// 종이 + 미묘한 그린 그라디언트, 우상단을 비껴 잘리는 거대한 흐린 mono 번호, 위에 마크+시리즈명,
/// 아래에 01/04 + 에피소드 제목 + 작가·날짜. 우측 모서리로 한 장씩 넘긴다. 카드 탭은 시리즈 상세.
private struct FeedSeriesCard: View {
    let series: PublicSeriesCard
    let author: Author
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var idx = 0
    // 방금 떠난 장 — 넘김이 "카드 넘어가듯" 방향성 슬라이드로 보이게, 나가는 장은 왼쪽으로
    // 미세하게 밀려 나가고(페이드 아웃) 새 장은 오른쪽에서 들어온다. 순환이라 항상 전진 방향.
    @State private var prevIdx = 0
    // 모든 장이 ZStack 에 살아 있어(크로스페이드용) 숨은 장의 커버까지 즉시 받게 된다 —
    // 커버 로드는 현재 장 + 다음 장만 켜고, 한 번 켠 장은 유지해 페이드아웃 중
    // 이미지가 placeholder 로 되돌아가지 않게 한다.
    @State private var imagePages: Set<Int> = [0, 1]
    // 슬라이드 이동량 — §10 절제(카드 폭 전체 활주는 과하다). 들고 나는 장이 살짝 미끄러지는 정도.
    private let slideInset: CGFloat = 26
    // 하드코딩 크기가 Dynamic Type 를 무시하던 것 — 텍스트 스타일에 묶어 글자 크기 설정을 따른다.
    // (우상단의 148pt 장식 mono 번호만 고정 — 레이아웃을 이루는 배경 장식이라 스케일 제외.)
    @ScaledMetric(relativeTo: .caption) private var seriesNameSize: CGFloat = 12
    @ScaledMetric(relativeTo: .title) private var epNumSize: CGFloat = 34
    @ScaledMetric(relativeTo: .footnote) private var epTotalSize: CGFloat = 15

    private var posts: [SeriesPostRef] { Array(series.posts.prefix(4)) }

    var body: some View {
        let n = max(posts.count, 1)
        // 새로고침이 series 를 편수 적은 것으로 교체해도 @State idx 는 살아남는다 — 범위 밖이면
        // 모든 장이 opacity 0(빈 카드)이 되므로 표시 인덱스를 클램프해 항상 한 장은 보이게.
        let shown = min(idx, n - 1)
        let prevShown = min(prevIdx, n - 1)
        ZStack(alignment: .topTrailing) {
            // 에피소드 페이지들 — 앞장만 보이고, 넘김은 방향성 슬라이드+크로스페이드.
            // 쉬는 장은 오른쪽(+inset)에서 대기하다 보여질 때 0으로 미끄러져 들어오고,
            // 방금 떠난 장만 왼쪽(-inset)으로 밀려 나간다 — "카드 한 장 넘어가듯". reduce-motion 은
            // 이동량 0 이라 기존 크로스페이드만 남는다.
            ForEach(Array(posts.enumerated()), id: \.offset) { i, ep in
                episodePage(index: i, ep: ep, loadImage: imagePages.contains(i))
                    .opacity(i == shown ? 1 : 0)
                    .offset(x: reduceMotion ? 0 : pageOffset(i, shown: shown, prevShown: prevShown))
            }
            // 카드 전체 탭 → 시리즈 상세(투명 링크가 비주얼 위에 깔린다).
            NavigationLink(value: Route.series(username: author.username, slug: series.slug)) {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // 우측 모서리 한 장 넘김(여러 편일 때만) — 링크 위에 올려 그 영역만 가로챈다.
            if n > 1 {
                Button {
                    // 넘길 대상 장(+그 다음 장) 커버를 미리 켜 크로스페이드가 빈 채로 뜨지 않게.
                    let next = (shown + 1) % n
                    imagePages.insert(next)
                    if next + 1 < n { imagePages.insert(next + 1) }
                    // 떠나는 장을 기억해 그 장만 왼쪽으로 밀어낸다(나머지 쉬는 장은 오른쪽 대기).
                    prevIdx = shown
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.42)) {
                        idx = next
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Palette.secondary)
                        .frame(width: 48)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("다음 편")
            }
        }
        // 1열 피드에서 4:5 는 너무 길었다 — 정사각으로 낮춰 키를 줄인다(디자인은 그대로).
        .aspectRatio(1.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                .strokeBorder(Palette.cardBorder, lineWidth: 1)
        }
        .cardShadow()
        // 회차 넘김에 가벼운 촉감 하나 — 스위처 pill·좋아요와 같은 결(§1.6 조용하지만 살아 있게).
        .sensoryFeedback(.selection, trigger: idx)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("시리즈 \(series.title), \(series.postCount)편"))
    }

    /// 장의 수평 위치 — 보이는 장은 중앙(0), 방금 떠난 장은 왼쪽(-inset)으로 밀려 나가고,
    /// 그 밖의 쉬는 장은 오른쪽(+inset)에 대기해 다음에 보여질 때 오른쪽에서 미끄러져 들어온다.
    private func pageOffset(_ i: Int, shown: Int, prevShown: Int) -> CGFloat {
        if i == shown { return 0 }
        if i == prevShown { return -slideInset }
        return slideInset
    }

    private func episodePage(index i: Int, ep: SeriesPostRef, loadImage: Bool) -> some View {
        let imageURL = ep.ogImageUrl.flatMap { $0.isEmpty ? nil : URL(string: $0) }
        let onImage = imageURL != nil
        return ZStack(alignment: .topLeading) {
            if let url = imageURL {
                // 사진 커버 변형 — 에피소드 사진 + 상하 스크림 위 흰 글씨(웹 이미지 장 대응).
                // 숨은 뒷장은 loadImage 가 켜질 때만 RemoteImage 를 만든다 — 안 보는 커버를 미리 안 받게.
                Color.clear.overlay {
                    if loadImage {
                        RemoteImage(url: url) { phase in
                            if case .success(let img) = phase {
                                // 채움 이미지는 프레임 밖으로 넘친다 — 클립은 그림만 자르고 히트는 못 잘라, 이웃 카드 탭을 먹는다.
                                img.resizable().scaledToFill().allowsHitTesting(false)
                            } else {
                                Palette.accent.opacity(0.12)
                            }
                        }
                    } else {
                        Palette.accent.opacity(0.12)
                    }
                }
                .clipped()
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.32), location: 0),
                        .init(color: .clear, location: 0.34),
                        .init(color: .black.opacity(0.66), location: 1.0),
                    ], startPoint: .top, endPoint: .bottom)
            } else {
                Palette.cardBg
            }

            VStack(alignment: .leading, spacing: 0) {
                // 시리즈 정체 — 마크 + 시리즈명(웹: 12px semibold).
                HStack(spacing: 6) {
                    KurlMark(drawn: [true, true, true], tint: onImage ? .white : Palette.secondary)
                        .frame(width: 16, height: 10)
                    Text(series.title)
                        .font(.system(size: seriesNameSize, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(onImage ? Color.white : Palette.ink)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                // 에피소드 번호 01 / 04 (웹: 34px accent-700 + 15px slate-500).
                (Text(String(format: "%02d", i + 1))
                    .font(.system(size: epNumSize, weight: .bold).monospacedDigit())
                    .foregroundStyle(onImage ? Color.white : Palette.ink)
                    + Text(" / \(String(format: "%02d", series.postCount))")
                    .font(.system(size: epTotalSize, weight: .bold).monospacedDigit())
                    .foregroundStyle(onImage ? Color.white.opacity(0.75) : Palette.secondary))
                    .lineLimit(1)
                // 에피소드 제목(웹: 18px bold, 3줄).
                Text(ep.title)
                    .typeScale(.title)
                    .foregroundStyle(onImage ? Color.white : Palette.ink)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 6)
                HStack(spacing: 6) {
                    AvatarView(author: author, size: 18)
                    Text(author.username)
                        .typeScale(.meta)
                        .foregroundStyle(onImage ? Color.white.opacity(0.9) : Palette.secondary)
                        .lineLimit(1)
                    if let date = series.lastPublishedAt {
                        Text("·").foregroundStyle(onImage ? Color.white.opacity(0.6) : Palette.faint)
                        Text(date.relativeShort)
                            .typeScale(.meta)
                            .foregroundStyle(onImage ? Color.white.opacity(0.9) : Palette.secondary)
                    }
                }
                .padding(.top, 9)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
        }
    }
}

/// 행 전체 press 하이라이트 — 본문 정렬 유지(양옆으로 살짝 번짐).
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: Metrics.radius)
                    .fill(configuration.isPressed ? Palette.rowHighlight : .clear)
                    .padding(.horizontal, -10)
            )
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 콜드 로딩 스켈레톤 — 피드·검색 결과가 뜰 자리에 카드 그리드 모양 자리표시를 그린다.
/// 실제 리스트와 같은 간격·컬럼이라 카드가 착지해도 위치가 안 튄다(중앙 마크→상단 카드 점프 제거).
/// 글/시리즈/작가 단일 로드엔 쓰지 않는다(그쪽은 브랜드 마크 유지).
struct FeedSkeleton: View {
    /// recent 피드는 첫 장이 피처드 커버라 커버 모양으로, 그 외는 전부 종이 카드 모양.
    var leadingCover = false
    var count = 5

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(0..<count, id: \.self) { i in
                    SkeletonCard(cover: leadingCover && i == 0)
                }
            }
            .padding(.vertical, 16)
            .frame(maxWidth: Metrics.readingColumn)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Metrics.gutter)
        }
        .scrollDisabled(true)
        .allowsHitTesting(false)
        .accessibilityLabel(Text("불러오는 중"))
    }
}

struct NoteSkeleton: View {
    var count = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                HStack(alignment: .top, spacing: 12) {
                    Circle().fill(Palette.hairlineStrong).frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 9) {
                        SkeletonBar(widthFraction: 0.34, height: 13)
                        SkeletonBar(widthFraction: 0.96, height: 14)
                        SkeletonBar(widthFraction: i.isMultiple(of: 2) ? 0.62 : 0.8, height: 14)
                        SkeletonBar(widthFraction: 0.5, height: 12).padding(.top, 4)
                    }
                }
                .padding(.vertical, 14)
                if i < count - 1 { Hairline().padding(.horizontal, -Metrics.noteGutter) }
            }
        }
        .modifier(SkeletonShimmer())
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(Text("불러오는 중"))
    }
}

private struct SkeletonBar: View {
    let widthFraction: CGFloat
    let height: CGFloat

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Palette.hairlineStrong)
                .frame(width: geo.size.width * widthFraction, height: height)
        }
        .frame(height: height)
    }
}

/// 한 장의 카드 자리표시 — 커버(4:3 한 덩어리) 또는 종이(태그·제목·발췌·메타 바). 절제된 shimmer.
private struct SkeletonCard: View {
    let cover: Bool

    var body: some View {
        Group {
            if cover {
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .fill(Palette.hairlineStrong)
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
            } else {
                VStack(alignment: .leading, spacing: 11) {
                    bar(0.4, 13)                         // 태그
                    bar(0.92, 19)                        // 제목 1
                    bar(0.66, 19)                        // 제목 2
                    bar(0.98, 14).padding(.top, 2)       // 발췌 1
                    bar(0.55, 14)                        // 발췌 2
                    HStack(spacing: 8) {                 // 메타
                        Circle().fill(Palette.hairlineStrong).frame(width: 16, height: 16)
                        bar(0.3, 12)
                    }
                    .padding(.top, 2)
                }
                .padding(Metrics.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Palette.cardBg,
                    in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                        .strokeBorder(Palette.cardBorder.opacity(0.6), lineWidth: 1)
                }
            }
        }
        .modifier(SkeletonShimmer())
    }

    private func bar(_ widthFraction: CGFloat, _ height: CGFloat) -> some View {
        GeometryReader { geo in
            Capsule()
                .fill(Palette.hairlineStrong)
                .frame(width: geo.size.width * widthFraction, height: height)
        }
        .frame(height: height)
    }
}

/// 절제된 shimmer — 옅은 빛 띠가 카드를 한 번씩 느리게 쓸고 지나간다. Reduce Motion 이면 정지.
private struct SkeletonShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var travel = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        let w = geo.size.width
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.45), .clear],
                            startPoint: .leading, endPoint: .trailing)
                            .frame(width: w * 0.55)
                            .offset(x: travel ? w * 1.1 : -w * 0.65)
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    travel = true
                }
            }
    }
}
