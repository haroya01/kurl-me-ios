//
//  RootView.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI
import UIKit

/// 탭 전환의 단일 손잡이 — 빈 상태의 "발견에서 찾기" 같은 행동 문이 다른 화면에서
/// 탭을 갈아탈 때 쓴다(빈 상태는 막다른 길이면 안 된다 — DESIGN.md 폴리시).
@MainActor
@Observable
final class TabRouter {
    static let shared = TabRouter()

    var selection: Int

    /// 위젯 딥링크의 대기석 — 탭을 갈아탄 뒤 스튜디오가 스스로 소비한다(StudioSection rawValue).
    var pendingStudioSection: String?
    /// 위젯에서 탭한 저장 글 — RootView 가 시트로 띄운다. 탭 스택에 미는 방식은 path 바인딩이
    /// 필요한데, 그 바인딩이 tabBarMinimizeBehavior 를 죽이는 함정이 있어(§DiscoverDeckView) 시트로.
    var pendingPost: WidgetPostRef?
    /// 푸시 탭의 대기석 — 알림함 시트. pendingPost 와 같은 이유로 시트.
    var pendingNotifications = false
    var pendingPushRoute: Route?
    var notificationsSheetVisible = false

    private init() {
        // `--tab notes|write|search|account` — simctl 은 터치를 못 넣으니 검증용 진입로.
        selection =
            switch Config.launchValue(after: "--tab") {
            case "notes": 1
            case "write": 2
            case "search": 3
            case "account": 4
            default: 0
            }
        // `--open notifications`(단독) — 푸시 탭(didReceive)과 같은 대기석을 지나는 검증 진입로.
        // `--tab account --open notifications` 는 기존대로 AccountView 가 소비한다(이중 발화 방지).
        if Config.launchValue(after: "--tab") == nil,
            Config.launchValue(after: "--open") == "notifications" {
            pendingNotifications = true
        }
        if let json = Config.launchValue(after: "--push"),
            let info = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] {
            pendingPushRoute = NotificationRoute.route(push: info)
            pendingNotifications = true
        }
    }

    /// 빈 상태 CTA 의 탭 갈아타기 — 아무 피드백 없이 화면만 바뀌면 눌렀는지조차 모른다.
    /// 전환을 애니메이트해(탭 크로스페이드가 눈에 보이게) 셀렉션 틱 하나를 얹는다(§1.6 조용하지만
    /// 살아 있게). 직접 selection 대입(런치 진입로)은 이 손맛 없이 즉시 바꾼다.
    private(set) var reselections = 0
    private(set) var reselectedTab = 0

    func reselect(_ index: Int) {
        reselectedTab = index
        reselections += 1
    }

    private(set) var topRequests = 0
    private(set) var topTab = 0

    func scrollToTop(_ index: Int) {
        topTab = index
        topRequests += 1
    }

    func switchTo(_ index: Int, reduceMotion: Bool = false) {
        guard index != selection else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if reduceMotion {
            selection = index
        } else {
            withAnimation(.snappy(duration: 0.28)) { selection = index }
        }
    }
}

/// 위젯이 가리킨 글 하나 — 시트 identity 는 주소(작가/슬러그)로 충분하다.
struct WidgetPostRef: Identifiable, Equatable {
    let username: String
    let slug: String
    var id: String { "\(username)/\(slug)" }
}

/// 위젯 탭 URL(kurlwidget://…) 라우팅 — 위젯은 자기 앱만 열 수 있으니 스킴 등록이 필요 없고,
/// 시스템이 이 URL 을 onOpenURL 로 그대로 건네준다. 목적지는 셋: 분석·서재·저장 글 하나.
enum WidgetDeepLink {
    @MainActor
    static func open(_ url: URL) {
        guard url.scheme == "kurlwidget" else { return }
        switch url.host {
        case "analytics":
            TabRouter.shared.selection = 2
            TabRouter.shared.pendingStudioSection = StudioSection.analytics.rawValue
        case "library":
            TabRouter.shared.selection = 4
        case "post":
            let parts = url.path.split(separator: "/").map(String.init)
            guard parts.count == 2 else { return }
            TabRouter.shared.pendingPost = WidgetPostRef(username: parts[0], slug: parts[1])
        default:
            break
        }
    }
}

private struct NotificationsSheet: View {
    @State private var path: [Route]

    init(initial: Route?) {
        _path = State(initialValue: initial.map { [$0] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            NotificationsView()
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        .onChange(of: TabRouter.shared.pendingPushRoute) { _, route in
            if let route { path = [route] }
        }
        .onAppear { TabRouter.shared.notificationsSheetVisible = true }
        .onDisappear { TabRouter.shared.notificationsSheetVisible = false }
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var showDebug = false
    /// 하단 탭바 상태의 단일 손잡이 — 탭 루트들이 스크롤 방향을 여기 보고하고,
    /// 커스텀 FloatingTabBar 가 그 상태로 바를 작게 줄였다 되돌린다(인스타그램식).
    @State private var tabBarVisibility = TabBarVisibility()
    @State private var bottomInset: CGFloat = 0
    @State private var blogFeed = BlogFeedChoice.shared
    @State private var noteFeed = NoteFeedChoice.shared
    /// 한 번이라도 연 탭 — 상주시켜 스크롤 위치·상태를 보존한다(시스템 TabView 대체).
    @State private var visitedTabs: Set<Int> = []
    /// 로그인 직후 1회 웹 안내 — 이 실행이 "로그아웃 상태로 시작"했을 때만 후보(콜드런치
    /// 세션 복원에는 안 뜬다). RootView 생성 시점의 세션 상태를 그대로 박는다.
    @State private var didStartSignedOut = !AuthStore.shared.isSignedIn
    @State private var showWebIntro = false
    /// 기기당 딱 한 번 — 본 뒤엔 로그아웃/재로그인해도 다시 안 뜬다.
    @AppStorage("seenWebIntro") private var seenWebIntro = false

    var body: some View {
        // `--post user/slug`·`--author user`·`--series user/slug` — 검증 진입로(simctl 터치 불가 우회).
        if let target = Config.launchValue(after: "--post"),
           let slash = target.firstIndex(of: "/") {
            NavigationStack {
                PostDetailView(
                    username: String(target[..<slash]),
                    slug: String(target[target.index(after: slash)...])
                )
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
            }
        } else if let author = Config.launchValue(after: "--author") {
            NavigationStack {
                AuthorBlogView(username: author)
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
            }
        } else if let target = Config.launchValue(after: "--series"),
                  let slash = target.firstIndex(of: "/") {
            NavigationStack {
                SeriesDetailView(
                    username: String(target[..<slash]),
                    slug: String(target[target.index(after: slash)...])
                )
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
            }
        } else if let tag = Config.launchValue(after: "--tag") {
            NavigationStack {
                TagFeedView(tag: tag)
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
            }
        } else if Config.launchValue(after: "--screen") == "loginsheet" {
            // 로그인 시트는 인게이지 탭으로만 떠 simctl 로 못 띄운다 — 검증 진입로.
            Color(uiColor: .systemBackground).ignoresSafeArea()
                .sheet(isPresented: .constant(true)) {
                    LoginSheet(message: "좋아한 글은 내 라이브러리에 쌓여요")
                }
        } else if Config.launchValue(after: "--screen") == "webintro" {
            // 로그인 직후 1회 시트는 로그인 전환으로만 떠 simctl 로 못 띄운다 — 검증 진입로.
            // ConnectHarness 처럼 실제 바인딩으로 띄운다(.constant(true)는 닫힘이 무시돼
            // '확인으로 닫힘' 단언이 불가능한 함정).
            WebIntroHarness()
        } else if Config.launchValue(after: "--screen") == "series-analytics" {
            // 시리즈 상세 분석은 분석 탭에서 행 탭으로만 들어가 simctl 로 못 띄운다 — 검증 진입로.
            NavigationStack {
                SeriesAnalyticsDetailView(seriesId: 1, seriesTitle: "헥사고날 전환기")
            }
        } else if Config.launchValue(after: "--screen") == "profile-edit" {
            // 프로필 편집은 계정 탭에서 푸시로만 들어가 simctl 로 못 띄운다 — 검증 진입로.
            NavigationStack {
                ProfileEditView(currentAvatarUrl: AuthStore.shared.me?.avatarUrl)
            }
        } else if Config.launchValue(after: "--screen") == "choose-username" {
            // 핸들 정하기 게이트는 빈 username 일 때만 떠 simctl 로 못 띄운다 — 검증 진입로.
            ChooseUsernameView()
        } else if Config.launchValue(after: "--screen") == "deck" {
            // 릴스형 몰입 덱 — 발견 표면에서 내리고 주차. 되살리기/UI 테스트용 진입로.
            DiscoverDeckView()
        } else if Config.launchValue(after: "--screen") == "collections" {
            // 컬렉션 프로토타입 — 계정 탭 안 푸시라 simctl 로 못 띄운다, 검증 진입로.
            NavigationStack { CollectionsListView() }
        } else if Config.launchValue(after: "--screen") == "collection-detail" {
            // 컬렉션 상세 — 목록 탭으로만 들어가 simctl 로 못 띄운다, 검증 진입로(목 백엔드 id).
            // `--collection <id>` 로 특정 컬렉션(예: PATH 104) 지정, 없으면 101.
            NavigationStack {
                CollectionDetailView(
                    collectionId: Int64(Config.launchValue(after: "--collection") ?? "") ?? 101)
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
            }
        } else if Config.launchValue(after: "--screen") == "connect" {
            // "연결" 시트 — 인게이지에서만 떠 simctl 로 못 띄운다, 검증 진입로. 목 글 9101(헥사고날)로
            // 열어 이미 담긴 컬렉션의 "연결됨"·해제를 함께 확인한다(목 컬렉션 101 에 씨앗 연결).
            ConnectHarness()
        } else if Config.launchValue(after: "--screen") == "businesscard" {
            // 명함(/u) 인앱 웹뷰 — 블로그 헤더에서 푸시로만 들어가 simctl 로 못 띄운다 — 검증 진입로.
            NavigationStack {
                BusinessCardView(username: Config.launchValue(after: "--author") ?? "kurl")
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
            }
        } else if Config.launchValue(after: "--screen") == "highlights" {
            // 내 하이라이트(서재)는 계정 탭 서재 안 푸시라 simctl 로 못 띄운다 — 검증 진입로.
            NavigationStack {
                MyHighlightsView()
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
            }
        } else {
            tabs
        }
    }

    private var tabs: some View {
        @Bindable var router = TabRouter.shared
        return tabView(selection: $router.selection)
            // 위젯이 가리킨 저장 글 — 현재 탭 위 시트로. 읽기가 끝나면 원래 자리로 그대로 돌아온다.
            .sheet(item: $router.pendingPost) { ref in
                NavigationStack {
                    PostDetailView(username: ref.username, slug: ref.slug)
                        .navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
            }
            // 푸시 탭 — 알림함 시트. 인박스 안의 딥링크(글·컬렉션)가 같은 스택에서 이어 밀린다.
            .sheet(
                isPresented: $router.pendingNotifications,
                onDismiss: { TabRouter.shared.pendingPushRoute = nil }
            ) {
                NotificationsSheet(initial: TabRouter.shared.pendingPushRoute)
            }
            // 콜드 런치(종료 상태에서 푸시 탭)는 첫 프레임 전에 선 플래그를 시트가 무시하는 런타임이 있다 —
            // 한 틱 뒤에도 안 떴을 때만 재점화한다. 이미 뜬 시트를 내렸다 올리면 깜빡이고 안쪽 스크롤이 처음으로 돌아간다.
            .task {
                guard TabRouter.shared.pendingNotifications else { return }
                try? await Task.sleep(for: .milliseconds(350))
                guard TabRouter.shared.pendingNotifications, !TabRouter.shared.notificationsSheetVisible else { return }
                let route = TabRouter.shared.pendingPushRoute
                TabRouter.shared.pendingNotifications = false
                try? await Task.sleep(for: .milliseconds(350))
                TabRouter.shared.pendingPushRoute = route
                TabRouter.shared.pendingNotifications = true
            }
            // 위젯 몫의 분석 신선도 — 분석 화면을 열지 않아도 앱이 열릴 때 조용히 당겨 둔다.
            .task { await AnalyticsSnapshot.refreshIfStale() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await AnalyticsSnapshot.refreshIfStale() } }
            }
    }

    private func tabView(selection: Binding<Int>) -> some View {
        // 가입 직후 핸들 정하기 — me 로드 후 username 이 비어 있으면(특히 애플 신규) 풀스크린 게이트.
        let needsUsername = AuthStore.shared.isSignedIn
            && AuthStore.shared.me != nil
            && (AuthStore.shared.me?.username ?? "").isEmpty
        // 웹 안내를 띄울 준비 — 로그인 + 핸들까지 선 상태(핸들 게이트 뒤 박자).
        let webIntroReady = AuthStore.shared.isSignedIn
            && !(AuthStore.shared.me?.username ?? "").isEmpty
        // 인스타그램식 하단바: 시스템 `.tabBarMinimizeBehavior` 는 선택 탭 하나만 남긴 원으로
        // 접히는데, 인스타그램은 5탭을 둔 채 바만 작아진다 — 그 동작을 위해 바를 직접 그린다
        // (decisions/2026-10-08-tab-bar-instagram). 검색에 role: .search 를 주지 않는 것도 한 바에
        // 5탭을 모으기 위해서다. 스크롤 방향은 TabBarVisibility 가 누적한다.
        let tabs: [(icon: String, label: LocalizedStringKey)] = [
            ("doc.text.image", "피드"), ("text.bubble", "노트"), ("square.and.pencil", "글쓰기"),
            ("magnifyingglass", "검색"), ("person.crop.circle", "내 계정"),
        ]
        return ZStack(alignment: .bottom) {
            // 다섯 탭 루트를 상주시키고 선택된 것만 보인다 — 탭을 갈아타도 스크롤 위치·상태가 산다
            // (시스템 TabView 의 상태 보존을 손으로 재현). 방문 전 탭은 만들지 않아 첫 화면이 다섯
            // 탭을 한꺼번에 fetch 하지 않게 한다(각 탭 뷰의 .task 는 보일 때 발화).
            ForEach(0..<tabs.count, id: \.self) { index in
                if index == selection.wrappedValue || visitedTabs.contains(index) {
                    tabRoot(index)
                        .opacity(index == selection.wrappedValue ? 1 : 0)
                        .allowsHitTesting(index == selection.wrappedValue)
                        .accessibilityHidden(index != selection.wrappedValue)
                }
            }
            // 커스텀 바가 시스템 탭바의 콘텐츠 인셋을 대신한다 — 마지막 카드가 바 뒤로 숨지 않게
            // 탭 콘텐츠 하단에 바 높이만큼 안전영역을 넓힌다(바는 이 인셋 밖 오버레이라 안 밀린다).
            .safeAreaPadding(.bottom, Metrics.tabBarReservedHeight)

            FloatingTabBar(
                tabs: tabs, selection: selection, hidden: tabBarVisibility.forceHidden,
                compact: tabBarVisibility.scrollHidden, bottomInset: bottomInset, menuTabs: feedMenuTabs
            ) { index in
                if index == 0 {
                    BlogFeedMenu()
                } else {
                    NoteFeedTabMenu()
                }
            }
                // Rebuild glass controls when returning from a screen that force-hides them.
                // Scroll-driven hiding keeps the same identity and its existing animation.
                .id(tabBarVisibility.forceHidden)
        }
        .ignoresSafeArea(.keyboard) // 키보드가 떠도 커스텀 바가 위로 밀려 올라오지 않게.
        // 바 자신이 재면 옮긴 만큼 안전영역이 달라져 값이 진동한다 — 움직이지 않는 전면 층에서 잰다.
        .background {
            Color.clear
                .ignoresSafeArea()
                .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
        }
        .environment(\.tabBarVisibility, tabBarVisibility)
        // 방문한 탭을 기록해 상주시킨다(첫 진입 이후 상태 보존).
        .onChange(of: selection.wrappedValue, initial: true) { _, new in
            visitedTabs.insert(new)
            // 탭을 갈아타면 항상 보이는 상태로 — 새 탭이 숨은 바로 시작하지 않게.
            tabBarVisibility.reset()
        }
        .tint(.brand)
        // Dynamic Type 은 따르되 상한을 둔다 — 그 위 극단 크기는 카드/덱 레이아웃이 깨진다.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .modifier(ToastHost())
        // 관리자만 — 기기를 흔들면 현재 API·앱·유저·기기 진단 화면이 뜬다.
        .sheet(isPresented: $showDebug) { AdminDebugView() }
        // 관리자 흔들기가 잡혔다는 확인 — 비관리자 흔들기는 showDebug 가 안 서 조용히 무시된다.
        .sensoryFeedback(trigger: showDebug) { _, now in now ? .success : nil }
        .onShake {
            guard AuthStore.shared.me?.isAdmin == true else { return }
            showDebug = true
        }
        .task {
            // 흔들기는 시뮬/UITest 로 못 넣으니 검증 진입로(목·DEBUG 전용, 관리자만).
            if Config.launchValue(after: "--open") == "debug", AuthStore.shared.me?.isAdmin == true {
                showDebug = true
            }
        }
        // 핸들 없는 계정은 핸들을 정하기 전엔 못 닫는다 — username 이 서면 me 갱신으로 자동 해제.
        .fullScreenCover(isPresented: .constant(needsUsername)) {
            ChooseUsernameView()
        }
        // 로그인 직후 1회 — "쓴 글이 웹에도 같은 주소로 산다"를 내 주소로 안내.
        // 핸들 게이트가 걷힌 뒤(webIntroReady) 뜨고, 콜드런치 세션 복원(didStartSignedOut=false)
        // 이나 이미 본 기기(seenWebIntro)에는 안 뜬다.
        .onChange(of: webIntroReady) { was, now in
            guard now, !was, didStartSignedOut, !seenWebIntro else { return }
            seenWebIntro = true
            // 핸들 게이트(fullScreenCover)가 닫히는 전환과 겹치면 시트 프레젠테이션이
            // 드랍될 수 있다 — 전환이 끝난 뒤 한 박자 쉬고 띄운다.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                showWebIntro = true
            }
        }
        .sheet(isPresented: $showWebIntro) { WebIntroSheet() }
    }

    private var feedMenuTabs: Set<Int> {
        var tabs: Set<Int> = []
        if blogFeed.path.isEmpty { tabs.insert(0) }
        if noteFeed.path.isEmpty { tabs.insert(1) }
        return tabs
    }

    /// 인덱스별 탭 루트 화면. 각자 제 NavigationStack 을 든다(시스템 TabView 와 동일 계약).
    @ViewBuilder
    private func tabRoot(_ index: Int) -> some View {
        switch index {
        case 1: NotesTabView()
        case 2: StudioView()
        case 3: SearchView()
        case 4: AccountView()
        default: FeedView()
        }
    }
}

/// 인스타그램식 커스텀 하단바 — 5탭 아이콘-온리 유리 캡슐, 선택 탭 아래 알약.
/// 스크롤을 내리면 바 전체가 작아지고(5탭 유지), 바를 누른 채 끌면 알약이 손가락을 따라간다.
private struct FloatingTabBar<TabMenu: View>: View {
    let tabs: [(icon: String, label: LocalizedStringKey)]
    let selection: Binding<Int>
    let hidden: Bool
    let compact: Bool
    let bottomInset: CGFloat
    let menuTabs: Set<Int>
    @ViewBuilder let menu: (Int) -> TabMenu
    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 25
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rowWidth: CGFloat = 0
    @State private var dragX: CGFloat?

    private var slot: CGFloat { rowWidth / CGFloat(max(tabs.count, 1)) }

    private func index(at x: CGFloat) -> Int {
        guard slot > 0 else { return selection.wrappedValue }
        return min(max(Int(x / slot), 0), tabs.count - 1)
    }

    private var slidIndex: Int? { dragX.map(index(at:)) }

    var body: some View {
        GlassEffectContainer(spacing: GlassTokens.clusterSpacing) {
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                    let active = index == selection.wrappedValue
                    let lit = index == (slidIndex ?? selection.wrappedValue)
                    if active, menuTabs.contains(index) {
                        Menu {
                            menu(index)
                        } label: {
                            icon(tab.icon, active: lit)
                        } primaryAction: {
                            TabRouter.shared.scrollToTop(index)
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .accessibilityShowsLargeContentViewer { Label(tab.label, systemImage: tab.icon) }
                        .accessibilityLabel(Text(tab.label))
                        .accessibilityHint(Text("누르면 맨 위로, 길게 누르면 피드 고르기"))
                        .accessibilityAddTraits(.isSelected)
                        .accessibilityIdentifier("tab.menu")
                    } else {
                        Button {
                            if active {
                                TabRouter.shared.reselect(index)
                            } else {
                                selection.wrappedValue = index
                            }
                        } label: {
                            icon(tab.icon, active: lit)
                        }
                        .buttonStyle(.plain)
                        .accessibilityShowsLargeContentViewer { Label(tab.label, systemImage: tab.icon) }
                        .accessibilityLabel(Text(tab.label))
                        .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
                    }
                }
            }
            .background(alignment: .leading) { pill }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
            .simultaneousGesture(slide)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 2)
        .scaleEffect(scale, anchor: .center)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: compact)
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: dragX == nil)
        .offset(y: hidden ? 132 : sink)
        .opacity(hidden ? 0 : 1)
        .allowsHitTesting(!hidden)
        .accessibilityHidden(hidden)
        .sensoryFeedback(.selection, trigger: slidIndex) { old, new in old != nil && new != nil }
    }

    private var sink: CGFloat { max(0, bottomInset - 20) }

    private var scale: CGFloat {
        if reduceMotion { return 1 }
        if dragX != nil { return 1.04 }
        return compact ? Metrics.tabBarCompactScale : 1
    }

    private var pill: some View {
        let width = max(slot + 8, 0)
        let center = dragX.map { min(max($0, slot / 2), rowWidth - slot / 2) }
            ?? (CGFloat(selection.wrappedValue) + 0.5) * slot
        return Capsule()
            .fill(Palette.hairlineStrong)
            .frame(width: width, height: 48)
            .offset(x: center - width / 2)
            .opacity(rowWidth > 0 ? 1 : 0)
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: selection.wrappedValue)
            .animation(reduceMotion ? nil : .interactiveSpring(duration: 0.18), value: dragX)
            .accessibilityHidden(true)
    }

    private var slide: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in dragX = value.location.x }
            .onEnded { value in
                let target = index(at: value.location.x)
                dragX = nil
                if target != selection.wrappedValue { selection.wrappedValue = target }
            }
    }

    private func icon(_ name: String, active: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: min(iconSize, 28), weight: active ? .semibold : .regular))
            .foregroundStyle(active ? AnyShapeStyle(Palette.link) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Rectangle())
    }
}

/// `--screen connect` 검증 진입로 — 시트를 실제 바인딩으로 띄워 dismiss(연결 성공)가
/// 관찰 가능하게 한다(.constant(true)는 닫힘이 무시돼 완료 단언이 불가능했다).
/// `--screen webintro` 검증 진입로 — 실제 바인딩이라 '확인' dismiss 가 관찰 가능하다.
private struct WebIntroHarness: View {
    @State private var open = true

    var body: some View {
        Color(uiColor: .systemBackground).ignoresSafeArea()
            .sheet(isPresented: $open) { WebIntroSheet() }
    }
}

private struct ConnectHarness: View {
    @State private var open = true

    var body: some View {
        Color(uiColor: .systemBackground).ignoresSafeArea()
            .sheet(isPresented: $open) {
                ConnectSheet(
                    targetKind: "글", targetTitle: "헥사고날로 갈아탄 지 석 달, 무엇이 남았나",
                    blockType: .post, refId: 9101)
            }
    }
}

#Preview {
    RootView()
}
