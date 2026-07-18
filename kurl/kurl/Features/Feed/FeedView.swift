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
}

struct FeedView: View {
    /// `--feed recent|trending|following|notes` — 스크린샷/목 검증 진입로(--tab 과 같은 문법).
    @State private var selection: FeedTab =
        Config.launchValue(after: "--feed").flatMap(FeedTab.init(rawValue:)) ?? .recent
    @Namespace private var zoomNS
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// 알림은 리텐션 루프의 심장인데 계정 탭 안 2뎁스였다 — 첫 화면에 벨을 둔다.
    /// 카운트는 계정 탭 벨과 UnreadStore 공유 — 각자 fetch 해 같은 GET 이 2회 나가지 않게.
    private var unreadCount: Int64 { UnreadStore.shared.count }
    /// 벨 → 알림. isPresented 바인딩이라 pop 시 onChange 가 미읽음을 다시 읽는다(계정 탭과 동일).
    @State private var showNotifications = false

    /// 좌우 스와이프 인터랙티브 — 손가락을 따라 화면이 슬라이드되어 "넘기는 중"이 느껴진다.
    /// dragX = 현재 끌린 거리(현재 페이지 오프셋), 인접 페이지는 한 폭 옆에서 따라 들어온다.
    @State private var dragX: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    /// 스와이프가 방금 selection 을 확정했음을 onChange 에 알린다 — 스와이프 경로는 dragX 를 스스로
    /// 보정해 슬라이드하므로, 뒤이어 발화하는 onChange 가 같은 전환을 한 번 더 슬라이드시키지 않게 한다.
    /// (dragX==0 로 구분하던 방식은 withAnimation 이 dragX 모델값을 그 프레임에 0 으로 써버려
    /// onChange 시점엔 이미 0 이라 스와이프도 통과 → 이중 슬라이드로 튀던 것을 대체.)
    @State private var swipeCommitted = false

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
                        // 슬라이드 중 중앙을 벗어난 분면은 살짝 가라앉는다 — 옆 칸이 "뒤에 있다"는
                        // 얕은 깊이(페이지컨트롤 결). 드래그가 끝나 dragX 가 0 이면 중앙 분면은 1.0 으로
                        // 복원된다(오프셋이 폭의 배수로 스냅). scale 없이 opacity 만(§10 절제).
                        .opacity(pageOpacity(tab))
                        // 드래그 중엔 페이지 콘텐츠를 비활성화 — 페이지가 손가락 따라 미끄러지면
                        // 카드가 손가락과 함께 움직여 탭이 안 취소되고 글로 새던 것을 막는다.
                        .disabled(dragX != 0)
                        .allowsHitTesting(tab == selection)
                        .offset(x: pageOffset(tab))
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
            .simultaneousGesture(feedDrag)
            // 스위처 탭 전환도 스와이프처럼 미끄러진다 — 최신·인기 카드 목록이 즉시 스냅으로 갈리면
            // 생김새가 비슷해 "전환이 일어났나"가 안 느껴졌다. 스와이프 확정은 dragX 보정을 스스로 해
            // 이미 슬라이드했으므로 여기선 건너뛰고(swipeCommitted), 탭 경로만 같은 문법으로 보정한다.
            // 바인딩을 withAnimation 으로 감싸지 않는다 — 스위처 알약 활주와 충돌(메모리 함정).
            .onChange(of: selection) { old, new in
                if swipeCommitted {
                    swipeCommitted = false
                    return
                }
                guard !reduceMotion, containerWidth > 0,
                      let from = FeedTab.allCases.firstIndex(of: old),
                      let to = FeedTab.allCases.firstIndex(of: new), from != to else { return }
                dragX = CGFloat(to - from) * containerWidth
                withAnimation(.snappy(duration: 0.32)) { dragX = 0 }
            }
            // 전환이 손에도 닿게 — 탭이든 스와이프든 선택이 바뀌는 순간 가벼운 셀렉션 틱.
            .sensoryFeedback(.selection, trigger: selection)
            // 고정 스트립 대신 떠 있는 유리 — 카드가 캡슐 양옆·뒤로 그대로 흐른다.
            .safeAreaInset(edge: .top) {
                // ZStack 중첩(중앙 스위처 + 우단 벨)은 375pt 기기에서 겹쳤다 — 압축 가능한
                // HStack 으로. 한 영역의 유리 둘은 컨테이너 하나로 묶는다(§1.4).
                GlassEffectContainer(spacing: GlassTokens.clusterSpacing) {
                    // spacing 0 — 좌우 Spacer 가 중앙 정렬을 맡고, 고정 10pt 간격은 네 탭이
                    // 좁은 기기에서 넘쳐 캡슐을 줄바꿈시키던 폭을 잡아먹었다(되돌려 길쭉하게).
                    HStack(spacing: 0) {
                        // 오른쪽 벨과 같은 폭의 투명 균형추 — 스위처가 화면 정중앙에 오게(벨이
                        // 한쪽으로만 밀던 것 보정). 벨이 흐름 안에 남아 좁은 기기 겹침도 없다.
                        if AuthStore.shared.isSignedIn {
                            Color.clear.frame(width: 40, height: 40)
                        }
                        Spacer(minLength: 0)
                        GlassSegmentSwitcher(items: FeedTab.allCases, selection: $selection) {
                            $0.label
                        }
                        Spacer(minLength: 0)
                        if AuthStore.shared.isSignedIn {
                            Button {
                                showNotifications = true
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
            // 인터리브한 공개 연결 카드의 컬렉션 칩 → 컬렉션 상세(발견 표면과 같은 목적지).
            .navigationDestination(for: CollectionRef.self) {
                CollectionDetailView(collectionId: $0.id)
            }
            .navigationDestination(isPresented: $showNotifications) {
                NotificationsView()
            }
            .onChange(of: showNotifications) { _, open in
                // 알림에서 돌아오면 미읽음 점 갱신 — 모두 읽었는데 점이 남지 않게(계정 탭과 동일).
                if !open { Task { await refreshUnread() } }
            }
        }
    }

    private func page(for tab: FeedTab) -> some View {
        FeedPage(source: tab.source, active: tab == selection, warm: pageVisible(tab), zoom: zoomNS)
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

    /// 슬라이드 중 미세 디밍 — 중앙(오프셋 0)은 1.0, 한 폭 벗어나면 0.85 까지 가라앉는다. 숨은
    /// 분면(선택±1 밖)은 0. reduce-motion 이면 디밍 없이 pageVisible 게이트만(정지 면엔 깊이 연출
    /// 안 함). containerWidth 0(첫 레이아웃)이나 dragX 0(정지)이면 중앙 분면은 자연히 1.0.
    private func pageOpacity(_ tab: FeedTab) -> Double {
        guard pageVisible(tab) else { return 0 }
        guard !reduceMotion, containerWidth > 0 else { return 1 }
        let offCenter = min(1, abs(pageOffset(tab)) / containerWidth)
        return 1 - 0.15 * offCenter
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
                // 이 selection 변경은 스와이프가 이미 슬라이드 중이므로 onChange 가 다시 슬라이드하지 않게 표시.
                swipeCommitted = true
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
        await UnreadStore.shared.refresh()
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
            eyebrow: source == .forYou ? "추천" : "구독함",
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
                            featured: index == 0 && source == .recent,
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
                            eyebrow: "구독함",
                            title: "구독함이 비어 있어요",
                            message: "작가를 팔로우하면 새 글이 여기 도착해요.",
                            actionTitle: "발견에서 작가 찾기",
                            action: { TabRouter.shared.switchTo(1, reduceMotion: reduceMotion) }
                        )
                        .padding(.top, 64)
                    } else {
                        FeedPlaceholder(
                            eyebrow: source == .forYou ? "추천" : "최신",
                            title: source == .forYou ? "아직은 고를 거리가 적어요" : "아직 글이 없습니다",
                            message: source == .forYou
                                ? "몇 편 읽고 나면 취향이 잡힙니다."
                                : "첫 글이 올라오면 여기에서 만나요.",
                            actionTitle: "발견에서 읽을 글 찾기",
                            action: { TabRouter.shared.switchTo(1, reduceMotion: reduceMotion) }
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
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        // 활성 페이지의 스크롤만 탭바 숨김을 몬다 — ZStack 에 상주하는 숨은 페이지가
        // 방향을 함께 흘리면 서로 어긋난다.
        .tracksTabBarVisibility(active)
        .refreshable { await model.reload() }
    }

    // 공개 연결을 인터리브할 자리 — 시리즈 카드(index 3) 뒤로 충분히 띄워 index 5 부터 5칸마다
    // 한 장씩(5·10·15…), 이벤트가 남아 있는 동안만. "글 뒤에만" 끼우므로 마지막 글 뒤로는 새지
    // 않고 항상 다음 글 행이 따라온다(웹 #828 의 "뒤에 실제 행이 있을 때만"과 같은 규칙).
    private struct ConnectionSlot { let event: ConnectionEvent; let isFirst: Bool }

    private func connectionSlot(afterIndex index: Int) -> ConnectionSlot? {
        let events = model.connectionEvents
        guard !events.isEmpty else { return nil }
        // 시작 5, 간격 5 — (index-5)가 5의 배수이고 시작 이상일 때만 슬롯이 열린다.
        let start = 5, gap = 5
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
/// 섹션 라벨 + 제목 + 한 줄 + 단일 주액션. 로그인 게이트만 그린 유리 캡슐(§1.4 종이 위
/// 로그인 CTA), 빈 피드 안내는 조용한 그린 텍스트로 — 초록 과용을 피한다(§10 색 규율).
struct FeedPlaceholder: View {
    let eyebrow: LocalizedStringKey
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let actionTitle: LocalizedStringKey
    var prominent: Bool = false
    let action: () -> Void
    /// 주액션 라벨도 시스템 글자 크기를 따른다(제목·설명은 이미 typeScale 로 스케일).
    @ScaledMetric(relativeTo: .headline) private var actionSize: CGFloat = 15

    var body: some View {
        VStack(spacing: 0) {
            // 빈 면에도 남는 브랜드 사인 — 형광 아닌 옅은 잉크(RailHeading 마커와 같은 중립).
            KurlMark(drawn: [true, true, true], tint: Palette.hairlineStrong)
                .frame(width: 46, height: 28)
                .accessibilityHidden(true)
                .padding(.bottom, 24)

            Text(eyebrow)
                .typeScale(.eyebrow)
                .foregroundStyle(Palette.secondary)
                .padding(.bottom, 10)

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
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous)
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
                // 종이 변형 — 아주 옅은 그린(accent-50→accent-100) 대각 그라디언트(웹 EP_GRADS).
                LinearGradient(
                    colors: [
                        Palette.cardBg, Palette.accent.opacity(0.05), Palette.accent.opacity(0.10),
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)
                // 우상단에서 비껴 잘리는 거대한 흐린 mono 번호(웹: 148px·accent-600/9%).
                Text(String(format: "%02d", i + 1))
                    .font(.system(size: 148, weight: .bold, design: .monospaced))
                    .tracking(-4)
                    .foregroundStyle(Palette.accent.opacity(0.09))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .offset(x: 14, y: -28)
                    .allowsHitTesting(false)
            }

            VStack(alignment: .leading, spacing: 0) {
                // 시리즈 정체 — 마크 + 시리즈명(웹: 12px semibold).
                HStack(spacing: 6) {
                    KurlMark(drawn: [true, true, true], tint: onImage ? .white : Palette.accent)
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
                    .font(.system(size: epNumSize, weight: .bold, design: .monospaced))
                    .foregroundStyle(onImage ? Color.white : Palette.link)
                    + Text(" / \(String(format: "%02d", series.postCount))")
                    .font(.system(size: epTotalSize, weight: .bold, design: .monospaced))
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
                RoundedRectangle(cornerRadius: Metrics.radiusControl)
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

/// 한 장의 카드 자리표시 — 커버(4:3 한 덩어리) 또는 종이(태그·제목·발췌·메타 바). 절제된 shimmer.
private struct SkeletonCard: View {
    let cover: Bool

    var body: some View {
        Group {
            if cover {
                RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous)
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
                    in: RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous)
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
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    travel = true
                }
            }
    }
}
