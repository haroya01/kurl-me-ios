//
//  FeedView.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

enum FeedTab: String, CaseIterable, Identifiable {
    case following
    case recent
    case trending

    var id: String { rawValue }

    var source: FeedSource {
        switch self {
        case .following: return .following
        case .recent: return .recent
        case .trending: return .trending
        }
    }

    var label: String { source.label }

    var symbol: String { source.symbol }

    static func initialTab(launched: String?, saved: String?, signedIn: Bool) -> FeedTab {
        for value in [launched, signedIn ? saved : nil] {
            if let value, let tab = FeedTab(stored: value) { return tab }
        }
        return .recent
    }

    /// 저장값 이전 — 구독함은 같은 원시값("following")으로 팔로잉이 됐고, 추천("forYou")은 더 보기 메뉴로 옮겨 최신으로 연다.
    init?(stored: String) {
        if stored == FeedSource.forYou.rawValue {
            self = .recent
        } else {
            self.init(rawValue: stored)
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
    private(set) var more: FeedSource?
    var path = NavigationPath()
    var pendingLogin: FeedSource?

    /// `--feed following|recent|trending|forYou` — 스크린샷/목 검증 진입로. forYou 는 최신 자리에서 추천으로 바꿔 연다.
    private init() {
        let launched = Config.launchValue(after: "--feed")
        tab = FeedTab.initialTab(
            launched: launched,
            saved: Config.useMocks ? nil : UserDefaults.standard.string(forKey: Self.key),
            signedIn: AuthStore.shared.isSignedIn)
        if launched == FeedSource.forYou.rawValue, AuthStore.shared.isSignedIn {
            more = .forYou
        }
    }

    func select(_ next: FeedTab) {
        more = nil
        tab = next
    }

    func show(_ next: FeedTab) {
        path = NavigationPath()
        select(next)
    }

    func show(_ feed: FeedSource) {
        guard AuthStore.shared.isSignedIn else {
            pendingLogin = feed
            return
        }
        path = NavigationPath()
        more = feed
    }

    func signedOut() {
        if tab.source.requiresAuth { tab = .recent }
        more = nil
    }
}

extension FeedSource {
    var moreChoice: SegmentMoreChoice {
        SegmentMoreChoice(title: label, symbol: symbol)
    }

    var symbol: String {
        switch self {
        case .recent: "clock"
        case .trending: "flame"
        case .forYou: "sparkles"
        case .following: "person.2"
        }
    }

    var loginMessage: LocalizedStringKey {
        switch self {
        case .forYou: "추천을 받으려면 로그인하세요"
        default: "팔로잉을 보려면 로그인하세요"
        }
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
            ZStack {
                SwipePager(
                    tabs: FeedTab.allCases, selection: $choice.tab, loadOnSelect: [.following], suspended: choice.more != nil
                ) { tab, active, warm in
                    FeedPage(source: tab.source, active: active && choice.more == nil, warm: warm, zoom: zoomNS)
                }
                if let more = choice.more {
                    FeedPage(source: more, active: true, warm: true, zoom: zoomNS)
                        .id(more)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: choice.more)
            .onChange(of: router.reselections) {
                if router.reselectedTab == 0 { choice.path = NavigationPath() }
            }
            .safeAreaBar(edge: .top) {
                FeedHeaderBar(
                    items: FeedTab.allCases,
                    selection: Binding(get: { choice.tab }, set: { choice.select($0) }),
                    label: \.label, moreChoice: choice.more?.moreChoice,
                    moreLabel: "블로그 피드 더 보기", moreIdentifier: "feed.more"
                ) {
                    BlogFeedMoreMenu()
                }
            }
            .task(id: AuthStore.shared.isSignedIn) { await UnreadStore.shared.refresh() }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active { Task { await UnreadStore.shared.refresh() } }
            }
            .onChange(of: AuthStore.shared.isSignedIn) { _, signedIn in
                if !signedIn { choice.signedOut() }
            }
            .loginPrompt(
                isPresented: Binding(
                    get: { choice.pendingLogin != nil },
                    set: { if !$0 { choice.pendingLogin = nil } }),
                message: choice.pendingLogin?.loginMessage ?? ""
            ) { [feed = choice.pendingLogin] in
                if let feed { choice.show(feed) }
            }
            .background(alignment: .top) { FeedHeaderMist() }
            .background(Palette.readingBg)
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
            .navigationDestination(for: CollectionRef.self) {
                CollectionDetailView(collectionId: $0.id)
            }
        }
    }
}

struct BlogFeedMenu: View {
    @State private var choice = BlogFeedChoice.shared

    var body: some View {
        Picker("피드", selection: Binding<FeedTab?>(
            get: { choice.more == nil ? choice.tab : nil },
            set: { if let tab = $0 { choice.show(tab) } }
        )) {
            ForEach(FeedTab.allCases) { tab in
                Label(tab.label, systemImage: tab.symbol).tag(Optional(tab))
            }
        }
        .pickerStyle(.inline)
        BlogFeedMoreMenu()
    }
}

struct BlogFeedMoreMenu: View {
    static let feeds: [FeedSource] = [.forYou]

    @State private var choice = BlogFeedChoice.shared

    var body: some View {
        Picker(selection: Binding<FeedSource?>(
            get: { choice.more },
            set: { if let feed = $0 { choice.show(feed) } }
        )) {
            ForEach(Self.feeds) { feed in
                Label(feed.label, systemImage: feed.symbol).tag(Optional(feed))
            }
        } label: {
            EmptyView()
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
    /// 숨은 페이지의 .task 도 기동 즉시 돌아 피드가 전부 fetch(팔로잉은 오프라인
    /// 다운로드까지 연쇄)하며 첫 화면 로딩과 대역폭을 다투던 것.
    let warm: Bool
    let zoom: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: FeedViewModel
    /// 팔로잉·추천 게이트의 로그인 — 다른 인게이지 면과 같은 정식 로그인 시트로.
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
            // 추천·팔로잉은 인증 피드 — 로그아웃이면 게이트(이때는 fetch 도 하지 않는다).
            if source.requiresAuth, !AuthStore.shared.isSignedIn {
                followingGate
            } else {
            switch model.phase {
            case .idle, .loading:
                FeedSkeleton()
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
                ? "추천을 받으려면 로그인하세요"
                : "팔로잉을 보려면 로그인하세요")
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    // 팔로잉 — 구독한 시리즈에 들어온 노트가 시각 순서대로 이 글 앞에 선다.
                    let notes = model.notesBefore[item.id] ?? []
                    ForEach(Array(notes.enumerated()), id: \.element.id) { offset, note in
                        SeriesNoteRow(note: note)
                            .rowDivider(index > 0 || offset > 0)
                            .modifier(QuietAppear(index: index))
                    }
                    NavigationLink(value: Route.post(username: item.author.username, slug: item.slug)) {
                        FeedRow(item: item, belonging: model.belonging[item.id] ?? [], linked: true)
                    }
                    .buttonStyle(RowButtonStyle())
                    .cardQuickActions(item)
                    .accessibilityIdentifier("feed.row.\(item.id)")
                    // 복원 앵커의 좌표 — 행 id 문자열로 못 박아, 복귀 시 이 id 로 스크롤이 되돌아간다.
                    .id(String(item.id))
                    .modifier(ZoomSource(
                        active: active,
                        id: "post-\(item.author.username)-\(item.slug)",
                        ns: zoom))
                    .rowDivider(index > 0 || !notes.isEmpty)
                    .modifier(QuietAppear(index: index))
                    .task { await model.loadMoreIfNeeded(current: item) }

                    if source == .recent, let series = model.series,
                        index == min(3, model.items.count - 1),
                        let author = series.author, !author.username.isEmpty {
                        FeedSeriesRow(series: series, author: author)
                            .rowDivider(true)
                            .modifier(QuietAppear(index: index))
                    }

                    if source == .recent, let event = connectionEvent(afterIndex: index) {
                        ConnectionEventRow(event: event)
                            .rowDivider(true)
                            .modifier(QuietAppear(index: index))
                    }
                }
                ForEach(Array(model.trailingNotes.enumerated()), id: \.element.id) { offset, note in
                    SeriesNoteRow(note: note)
                        .rowDivider(!model.items.isEmpty || offset > 0)
                        .task {
                            if note.id == model.trailingNotes.last?.id { await model.loadMoreAfterTrailingNote() }
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
                if model.items.isEmpty && model.seriesNotes.isEmpty {
                    if source == .following {
                        FeedPlaceholder(
                            title: "팔로잉 피드가 비어 있어요",
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
            .padding(.bottom, 16)
            .frame(maxWidth: Metrics.readingColumn)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Metrics.gutter)
            // 행마다 붙인 .id 를 복원 좌표로 노출 — scrollPosition 이 이 레이아웃에서 앵커를 읽는다.
            .scrollTargetLayout()
            // 발견 시리즈는 본 피드 반영 뒤 별도로 도착한다(피드를 막지 않는 설계) — 한 행
            // 높이가 리스트 중간에 순간 끼어들어 아래를 보던 화면이 튀던 것을 애니메이트로 밀어낸다.
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: model.series?.id)
        }
        // 글로 들어갔다 돌아오면 보던 행으로 스크롤을 되돌린다 — 페이지가 상주해 앵커가 살아남는다.
        // .top 앵커라 그 행이 다시 화면 맨 위에 온다(복귀 지점이 튀지 않게).
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

    // 공개 연결을 인터리브할 자리 — index 1 부터 5칸마다 한 행씩, 이벤트가 남아 있는 동안만.
    // "글 뒤에만" 끼우므로 마지막 글 뒤로는 새지 않고 항상 다음 글 행이 따라온다(웹 #828 과 같은 규칙).
    private func connectionEvent(afterIndex index: Int) -> ConnectionEvent? {
        let events = model.connectionEvents
        guard !events.isEmpty else { return nil }
        let start = 1, gap = 5
        guard index >= start, (index - start) % gap == 0 else { return nil }
        guard index < model.items.count - 1 else { return nil }
        let slotOrdinal = (index - start) / gap
        guard slotOrdinal < events.count else { return nil }
        return events[slotOrdinal]
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
    var message: LocalizedStringKey?
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

            if let message {
                Text(message)
                    .typeScale(.lede)
                    .foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 272)
                    .padding(.bottom, 22)
            }

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

private struct FeedSeriesRow: View {
    let series: PublicSeriesCard
    let author: Author

    private var episodes: [SeriesItemPreview] {
        series.items ?? series.posts.map {
            SeriesItemPreview(type: "POST", slug: $0.slug, noteId: nil, title: $0.title, ogImageUrl: $0.ogImageUrl)
        }
    }

    private var cover: URL? {
        episodes.lazy.compactMap { $0.ogImageUrl.flatMap { $0.isEmpty ? nil : URL(string: $0) } }.first
    }

    var body: some View {
        NavigationLink(value: Route.series(username: author.username, slug: series.slug)) {
            RowLayout(
                title: series.title,
                excerpt: Text(episodes.prefix(4).map(\.title.cleanedPreview).joined(separator: " · ")),
                cover: cover
            ) {
                HStack(spacing: 6) {
                    Text("시리즈")
                    Text(verbatim: "·").foregroundStyle(Palette.faint)
                    Text("\(series.episodeCount)편")
                }
                .typeScale(.meta)
                .foregroundStyle(Palette.secondary)
            } byline: {
                AuthorByline(author: author, date: series.lastPublishedAt)
            }
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("시리즈 \(series.title), \(series.episodeCount)편"))
        .accessibilityIdentifier("feed.series.\(series.id)")
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

struct FeedSkeleton: View {
    var count = 5

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<count, id: \.self) { i in
                    SkeletonRow(index: i)
                        .rowDivider(i > 0)
                }
            }
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

private struct SkeletonRow: View {
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonBar(widthFraction: 0.3, height: 12)
            SkeletonBar(widthFraction: 0.92, height: 18)
            SkeletonBar(widthFraction: index.isMultiple(of: 2) ? 0.6 : 0.74, height: 18)
            SkeletonBar(widthFraction: 0.96, height: 14).padding(.top, 2)
            HStack(spacing: 6) {
                Circle().fill(Palette.hairlineStrong).frame(width: 16, height: 16)
                SkeletonBar(widthFraction: 0.32, height: 12)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 16)
        .modifier(SkeletonShimmer())
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
