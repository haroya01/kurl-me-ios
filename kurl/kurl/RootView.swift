//
//  RootView.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI
import UIKit

/// 탭 전환의 단일 손잡이 — 빈 상태의 "발견에서 찾기" 같은 행동 문이 다른 화면에서
/// 탭을 갈아탈 때 쓴다(빈 상태는 막다른 길이면 안 된다 — AGENTS 폴리시).
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

    private init() {
        // `--tab write|discover|search|account` — simctl 은 터치를 못 넣으니 검증용 진입로.
        selection =
            switch Config.launchValue(after: "--tab") {
            case "discover": 1
            case "write": 2
            case "search": 3
            case "account": 4
            default: 0
            }
    }

    /// 빈 상태 CTA 의 탭 갈아타기 — 아무 피드백 없이 화면만 바뀌면 눌렀는지조차 모른다.
    /// 전환을 애니메이트해(탭 크로스페이드가 눈에 보이게) 셀렉션 틱 하나를 얹는다(§1.6 조용하지만
    /// 살아 있게). 직접 selection 대입(런치 진입로)은 이 손맛 없이 즉시 바꾼다.
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

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var showDebug = false
    /// 하단 탭바 스크롤 숨김의 단일 손잡이 — 탭 루트들이 스크롤 방향을 여기 보고하고,
    /// 커스텀 FloatingTabBar 가 그 상태로 바를 숨겼다 되살린다(스레드식).
    @State private var tabBarVisibility = TabBarVisibility()
    /// 한 번이라도 연 탭 — 상주시켜 스크롤 위치·상태를 보존한다(시스템 TabView 대체).
    @State private var visitedTabs: Set<Int> = []

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
        // 스레드식 하단바: 라벨 없는 아이콘-온리 탭 + 스크롤 내릴 때 바가 통째로 사라지고
        // 올릴 때 되돌아온다. 검색에 role 을 주지 않는 건 의도 — role: .search 는 Liquid
        // Glass 가 검색을 독립 pill 로 분리하는데, 한 바에 5탭이 모이는 쪽을 택했다.
        //
        // 시스템 TabView 를 안 쓰는 이유: iOS 26 네이티브 `.tabBarMinimizeBehavior(.onScrollDown)`
        // 은 27.0 베타에선 시뮬·실기기 모두 OS 가 안 태우고(2026-06-13 실기기 확정 — 우리 구조
        // 무관), `.toolbar(.hidden, for: .tabBar)` 도 탭 루트에선 시스템 바를 못 숨긴다(27 실측 —
        // 스택이 push 로 소비할 때만 먹는다). 스레드가 그렇듯 스크롤로 바를 통째로 숨기려면 바를
        // 우리가 소유해야 한다. 그래서 콘텐츠 스위칭은 ZStack(탭별 상태 상주)으로, 하단바는
        // 시스템 유리 결의 커스텀 FloatingTabBar 로 직접 그린다(§1 종이 본문·액체 크롬 — 유리·
        // 5탭 아이콘-온리·brand green 은 그대로). 스크롤 방향은 TabBarVisibility 가 누적한다.
        let tabs: [(icon: String, label: LocalizedStringKey)] = [
            ("doc.text.image", "피드"), ("safari", "발견"), ("square.and.pencil", "글쓰기"),
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
            .safeAreaPadding(.bottom, FloatingTabBar.reservedHeight)

            FloatingTabBar(tabs: tabs, selection: selection, hidden: tabBarVisibility.hidden)
        }
        .ignoresSafeArea(.keyboard) // 키보드가 떠도 커스텀 바가 위로 밀려 올라오지 않게.
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
    }

    /// 인덱스별 탭 루트 화면. 각자 제 NavigationStack 을 든다(시스템 TabView 와 동일 계약).
    @ViewBuilder
    private func tabRoot(_ index: Int) -> some View {
        switch index {
        case 1: DiscoverView()
        case 2: StudioView()
        case 3: SearchView()
        case 4: AccountView()
        default: FeedView()
        }
    }
}

/// 스레드식 커스텀 하단바 — 시스템 유리 결(§1 액체 크롬)의 5탭 아이콘-온리. 스크롤을 내리면
/// 아래로 미끄러져 사라지고(hidden) 올리면 되돌아온다. 시스템 TabView 의 바를 스크롤로 못
/// 숨겨(27 실측) 우리가 소유한다 — 대신 스레드처럼 확실히 사라진다.
private struct FloatingTabBar: View {
    /// 탭 콘텐츠가 하단에 비워 둘 높이(바 높이 + 숨 쉴 여백) — 시스템 탭바 콘텐츠 인셋 대체.
    /// 값은 Metrics 에 두고 공유한다 — 바 위에 떠 있는 독(EngagementDock)도 같은 예약 높이를 물어야 한다.
    static let reservedHeight = Metrics.tabBarReservedHeight

    let tabs: [(icon: String, label: LocalizedStringKey)]
    let selection: Binding<Int>
    /// 숨김 여부 — 스크롤다운이면 true. 전환은 위 report 호출부(withAnimation)가 부드럽게 몰고,
    /// reduce-motion 이면 그쪽에서 즉시 토글한다(여기선 상태만 그린다).
    let hidden: Bool
    /// 아이콘 크기는 Dynamic Type 를 따른다(고정 pt 로 접근성 크기를 무시하지 않게).
    /// 네이티브 iOS 26 유리 탭바 심볼 비례(≈25pt)에 맞춘다 — 22pt 는 얇게 읽혔다.
    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 25

    var body: some View {
        GlassEffectContainer(spacing: GlassTokens.clusterSpacing) {
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                    let active = index == selection.wrappedValue
                    Button {
                        // 이미 선택된 탭을 다시 누르면 시각적으로 무해(향후 top-scroll 훅 자리).
                        selection.wrappedValue = index
                    } label: {
                        Image(systemName: tab.icon)
                            .font(.system(size: iconSize, weight: active ? .semibold : .regular))
                            // active = brand green(§10.3 데이터/주액션), 나머지는 잉크로 가라앉힌다.
                            .foregroundStyle(active ? AnyShapeStyle(Color.brand)
                                                    : AnyShapeStyle(Palette.secondary))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(tab.label))
                    .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding(.horizontal, Metrics.gutter)
        // 네이티브 유리 탭바처럼 하단 세이프에어리어에 바짝 앉힌다 — 4pt 는 위로 떠 보였다.
        .padding(.bottom, 2)
        // 스크롤다운 = 바 높이만큼 아래로 미끄러져 완전히 사라진다(스레드식). 페이드도 얹어
        // 세이프에어리어 여백에서도 흔적이 남지 않게. reduce-motion 은 위 report 호출이 즉시 토글.
        .offset(y: hidden ? 132 : 0)
        .opacity(hidden ? 0 : 1)
        // 숨겨졌을 땐 손가락도 안 받는다(투명 바가 하단 탭을 가로채지 않게).
        .allowsHitTesting(!hidden)
        .accessibilityHidden(hidden)
    }
}

/// `--screen connect` 검증 진입로 — 시트를 실제 바인딩으로 띄워 dismiss(연결 성공)가
/// 관찰 가능하게 한다(.constant(true)는 닫힘이 무시돼 완료 단언이 불가능했다).
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
