//
//  FeedView.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

struct FeedView: View {
    @State private var selection: FeedSource = .recent
    @Namespace private var zoomNS
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                ForEach(FeedSource.allCases) { source in
                    FeedPage(source: source, active: source == selection, zoom: zoomNS)
                        .opacity(source == selection ? 1 : 0)
                        .allowsHitTesting(source == selection)
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: selection)
            .simultaneousGesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        guard abs(dx) > 60, abs(dx) > abs(dy) * 1.5 else { return }
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
                            let all = FeedSource.allCases
                            guard let idx = all.firstIndex(of: selection) else { return }
                            let next = dx < 0 ? min(idx + 1, all.count - 1) : max(idx - 1, 0)
                            selection = all[next]
                        }
                    }
            )
            // 고정 스트립 대신 떠 있는 유리 — 카드가 캡슐 양옆·뒤로 그대로 흐른다.
            .safeAreaInset(edge: .top) {
                GlassSegmentSwitcher(items: FeedSource.allCases, selection: $selection) { $0.label }
                    .padding(.top, 2)
                    .padding(.bottom, 8)
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
                ProgressView().tint(Palette.accent)
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
    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    NavigationLink(value: Route.post(username: item.author.username, slug: item.slug)) {
                        BlogCard(item: item, featured: index == 0 && source == .recent)
                    }
                    .buttonStyle(CardButtonStyle())
                    .modifier(ZoomSource(
                        active: active,
                        id: "post-\(item.author.username)-\(item.slug)",
                        ns: zoom))
                    .modifier(QuietAppear(index: index))
                    .modifier(CardScrollFade())
                    .task { await model.loadMoreIfNeeded(current: item) }
                }
                if model.isLoadingMore {
                    ProgressView().tint(Palette.accent)
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                }
                if model.items.isEmpty {
                    ContentUnavailableView("아직 글이 없습니다", systemImage: "doc.text")
                        .padding(.top, 80)
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
