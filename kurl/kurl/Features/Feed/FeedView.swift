//
//  FeedView.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

/// 피드 상단 4분면 — 글 셋(최신·인기·구독함) + 짧은 글(노트). 노트는 FeedSource(글 정렬)가
/// 아니라 별도 페이지라 여기서만 합쳐 스위처 한 줄로 묶는다.
enum FeedTab: String, CaseIterable, Identifiable {
    case recent
    case trending
    case following
    case notes

    var id: String { rawValue }

    var source: FeedSource? {
        switch self {
        case .recent: return .recent
        case .trending: return .trending
        case .following: return .following
        case .notes: return nil
        }
    }

    var label: String {
        source?.label ?? String(localized: "노트")
    }
}

struct FeedView: View {
    /// `--feed recent|trending|following|notes` — 스크린샷/목 검증 진입로(--tab 과 같은 문법).
    @State private var selection: FeedTab =
        Config.launchValue(after: "--feed").flatMap(FeedTab.init(rawValue:)) ?? .recent
    @Namespace private var zoomNS
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// 알림은 리텐션 루프의 심장인데 계정 탭 안 2뎁스였다 — 첫 화면에 벨을 둔다.
    @State private var unreadCount: Int64 = 0

    /// 좌우 스와이프 인터랙티브 — 손가락을 따라 화면이 슬라이드되어 "넘기는 중"이 느껴진다.
    /// dragX = 현재 끌린 거리(현재 페이지 오프셋), 인접 페이지는 한 폭 옆에서 따라 들어온다.
    @State private var dragX: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    var body: some View {
        // NavigationStack 에 path 를 바인딩하면 iOS 26 의 tabBarMinimizeBehavior 가
        // 그 탭에서 동작하지 않는다(시스템 버그, 기기에서도 재현). 깊은 푸시의 zoom
        // 중복 발화 가드보다 바 최소화가 우선이라 path 없이 간다.
        NavigationStack {
            // 페이지형 TabView(UIPageViewController) 중첩은 Liquid Glass 가 활성 탭의
            // 스크롤뷰를 못 찾게 만들어 하단 바 아래로 콘텐츠가 흐르지 않고(별도 영역처럼
            // 보임) 스크롤 축소도 안 걸렸다. 두 페이지를 ZStack 으로 살려두고(데이터·스크롤
            // 위치 유지) 좌우 스와이프는 제스처로 직접 — ScrollView 가 탭 콘텐츠의 직계가 된다.
            ZStack {
                ForEach(FeedTab.allCases) { tab in
                    page(for: tab)
                        .opacity(pageVisible(tab) ? 1 : 0)
                        // 드래그 중엔 페이지 콘텐츠를 비활성화 — 페이지가 손가락 따라 미끄러지면
                        // 카드가 손가락과 함께 움직여 탭이 안 취소되고 글로 새던 것을 막는다.
                        .disabled(dragX != 0)
                        .allowsHitTesting(tab == selection)
                        .offset(x: pageOffset(tab))
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
            .simultaneousGesture(feedDrag)
            // 고정 스트립 대신 떠 있는 유리 — 카드가 캡슐 양옆·뒤로 그대로 흐른다.
            .safeAreaInset(edge: .top) {
                // ZStack 중첩(중앙 스위처 + 우단 벨)은 375pt 기기에서 겹쳤다 — 압축 가능한
                // HStack 으로. 한 영역의 유리 둘은 컨테이너 하나로 묶는다(§1.4).
                GlassEffectContainer(spacing: GlassTokens.clusterSpacing) {
                    HStack(spacing: 10) {
                        Spacer(minLength: 0)
                        GlassSegmentSwitcher(items: FeedTab.allCases, selection: $selection) {
                            $0.label
                        }
                        Spacer(minLength: 0)
                        if AuthStore.shared.isSignedIn {
                            NavigationLink {
                                NotificationsView()
                            } label: {
                                Image(systemName: "bell")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 40, height: 40)
                                    .overlay(alignment: .topTrailing) {
                                        if unreadCount > 0 {
                                            Circle()
                                                .fill(Palette.accent)
                                                .frame(width: 7, height: 7)
                                                .offset(x: -7, y: 8)
                                                .transition(.scale.combined(with: .opacity))
                                        }
                                    }
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .accessibilityLabel(Text("알림"))
                            .accessibilityValue(
                                unreadCount > 0 ? Text("읽지 않음 \(unreadCount)") : Text(""))
                        }
                    }
                    .padding(.horizontal, Metrics.gutter)
                }
                .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: unreadCount > 0)
                .padding(.top, 2)
                .padding(.bottom, 8)
            }
            .task(id: AuthStore.shared.isSignedIn) { await refreshUnread() }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active { Task { await refreshUnread() } }
            }
            // 유리는 뒤에 흐르는 것이 있을 때만 유리다 — 스위처 뒤 옅은 안개 한 겹.
            // 뷰포트 고정(스크롤 안 함)이라 카드 사이 틈으로도 첫 화면이 은은하게 물든다.
            .background(alignment: .top) {
                BrandMist()
                    .frame(height: 240)
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
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
        }
    }

    @ViewBuilder
    private func page(for tab: FeedTab) -> some View {
        if let source = tab.source {
            FeedPage(source: source, active: tab == selection, zoom: zoomNS)
        } else {
            NotesPage(active: tab == selection)
        }
    }

    private var selectionIndex: Int { FeedTab.allCases.firstIndex(of: selection) ?? 0 }
    private func tabIndex(_ tab: FeedTab) -> Int { FeedTab.allCases.firstIndex(of: tab) ?? 0 }

    /// 선택 기준 한 칸 이내만 그린다 — 인접 페이지가 슬라이드로 들어올 수 있게.
    private func pageVisible(_ tab: FeedTab) -> Bool {
        abs(tabIndex(tab) - selectionIndex) <= 1
    }

    /// 필름스트립 — 각 페이지를 (자기 인덱스 − 선택 인덱스)×폭 + dragX 위치에 둔다. 전환 시
    /// 선택 인덱스와 dragX 를 같은 프레임에 맞바꿔(±폭이 상쇄) 시각이 연속이라 점프·깜빡임이 없다.
    private func pageOffset(_ tab: FeedTab) -> CGFloat {
        CGFloat(tabIndex(tab) - selectionIndex) * containerWidth + dragX
    }

    private var feedDrag: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard !reduceMotion,
                      abs(value.translation.width) > abs(value.translation.height) else { return }
                var dx = value.translation.width
                let all = FeedTab.allCases
                let i = all.firstIndex(of: selection) ?? 0
                // 끝 탭에서 더 끌면 고무줄 저항 — 들어올 페이지가 없다.
                let atEdge = (i == 0 && dx > 0) || (i == all.count - 1 && dx < 0)
                if atEdge { dx *= 0.28 }
                dragX = dx
            }
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                let vx = value.velocity.width
                let all = FeedTab.allCases
                let i = all.firstIndex(of: selection) ?? 0
                // 빠른 플릭(속도) 또는 의도적 끌기(거리+방향비) 둘 다 받는다.
                let horizontal = abs(dx) > abs(dy)
                let flick = abs(vx) > 260 && abs(dx) > 20
                let deliberate = abs(dx) > 48 && abs(dx) > abs(dy) * 1.2
                let canGo = dx < 0 ? i < all.count - 1 : i > 0
                guard horizontal, flick || deliberate, canGo else {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { dragX = 0 }
                    return
                }
                let newTab = all[dx < 0 ? i + 1 : i - 1]
                if reduceMotion {
                    selection = newTab
                    dragX = 0
                    return
                }
                // 선택을 곧바로 바꾸고(→ 햅틱 즉시) dragX 를 ±폭만큼 보정해 한 프레임에 같이
                // 적용 — 인덱스 변화와 상쇄돼 시각은 연속(깜빡임 없음). 그 뒤 dragX 를 0 으로
                // 애니메이트해 새 페이지를 중앙에 안착시킨다.
                selection = newTab
                dragX += dx < 0 ? containerWidth : -containerWidth
                withAnimation(.snappy(duration: 0.28)) { dragX = 0 }
            }
    }

    private func refreshUnread() async {
        guard AuthStore.shared.isSignedIn else {
            unreadCount = 0
            return
        }
        unreadCount = (try? await NotificationsAPI.unreadCount()) ?? unreadCount
    }
}

/// 한 정렬(최신/인기)의 피드 페이지. TabView 가 살려두므로 스와이프해도 상태 유지.
struct FeedPage: View {
    let source: FeedSource
    let active: Bool
    let zoom: Namespace.ID
    @State private var model: FeedViewModel

    init(source: FeedSource, active: Bool, zoom: Namespace.ID) {
        self.source = source
        self.active = active
        self.zoom = zoom
        _model = State(initialValue: FeedViewModel(source: source))
    }

    var body: some View {
        Group {
            // 팔로잉은 인증 피드 — 로그아웃이면 게이트(이때는 fetch 도 하지 않는다).
            if source == .following, !AuthStore.shared.isSignedIn {
                followingGate
            } else {
            switch model.phase {
            case .idle, .loading:
                KurlLoadingMark()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                failed(message)
            case .loaded:
                list
            }
            }
        }
        // 인증 전환을 task id 로 관찰 — 로그아웃 상태의 401 failed 고착과
        // 계정 전환 후 이전 계정 피드 잔존을 모두 해소한다.
        .task(id: AuthStore.shared.isSignedIn) {
            if source == .following {
                guard AuthStore.shared.isSignedIn else {
                    model.resetForAuthChange()
                    return
                }
                model.resetForAuthChange()
            }
            await model.loadInitial()
        }
    }

    private var followingGate: some View {
        ContentUnavailableView {
            Label("팔로잉", systemImage: "person.2")
        } description: {
            Text("로그인하면 팔로우한 작가와 구독한 시리즈의 새 글이 여기에 모여요.")
        } actions: {
            Button("로그인") {
                Task { _ = try? await AuthStore.shared.signIn() }
            }
            .foregroundStyle(Palette.accent)
        }
    }

    // 발견(browse) 면 = 1열 카드 그리드(#707 웹과 동일 문법). 행 사이 hairline 대신 카드 간격.
    // 구독함은 카드가 아니라 인박스 문법 — 도착한 글의 행 + 미읽음 점(기기 로컬).
    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: source == .following ? 0 : 16) {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    NavigationLink(value: Route.post(username: item.author.username, slug: item.slug)) {
                        if source == .following {
                            InboxRow(item: item)
                        } else {
                            BlogCard(item: item, featured: index == 0 && source == .recent)
                        }
                    }
                    .buttonStyle(source == .following ? AnyButtonStyle(RowButtonStyle()) : AnyButtonStyle(CardButtonStyle()))
                    .cardQuickActions(item)
                    .modifier(ZoomSource(
                        active: active,
                        id: "post-\(item.author.username)-\(item.slug)",
                        ns: zoom))
                    .modifier(QuietAppear(index: index))
                    .modifier(CardScrollFade())
                    .simultaneousGesture(TapGesture().onEnded {
                        if source == .following { PostReadStore.shared.markRead(item.id) }
                    })
                    .task { await model.loadMoreIfNeeded(current: item) }
                    if source == .following, index < model.items.count - 1 {
                        Hairline()
                    }
                }
                if model.isLoadingMore {
                    ProgressView().tint(Palette.accent)
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                }
                if model.items.isEmpty {
                    if source == .following {
                        ContentUnavailableView {
                            Label("구독함이 비어 있어요", systemImage: "tray")
                        } description: {
                            Text("작가를 팔로우하면 새 글이 여기 도착해요.")
                        } actions: {
                            Button("발견에서 작가 찾기") { TabRouter.shared.selection = 1 }
                                .foregroundStyle(Palette.accent)
                        }
                            .padding(.top, 80)
                    } else {
                        ContentUnavailableView {
                            Label("아직 글이 없습니다", systemImage: "doc.text")
                        } actions: {
                            Button("발견에서 읽을 글 찾기") { TabRouter.shared.selection = 1 }
                                .foregroundStyle(Palette.accent)
                        }
                            .padding(.top, 80)
                    }
                }
            }
            .padding(.vertical, 16)
            .frame(maxWidth: Metrics.readingColumn)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Metrics.gutter)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .refreshable { await model.reload() }
    }

    private func failed(_ message: String) -> some View {
        ContentUnavailableView {
            Label("불러오지 못했습니다", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("다시 시도") { Task { await model.reload() } }
                .foregroundStyle(Palette.accent)
        }
    }
}

/// 행 전체 press 하이라이트 — 본문 정렬 유지(양옆으로 살짝 번짐).
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(configuration.isPressed ? Palette.rowHighlight : .clear)
                    .padding(.horizontal, -10)
            )
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
