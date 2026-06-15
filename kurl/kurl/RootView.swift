//
//  RootView.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

/// 탭 전환의 단일 손잡이 — 빈 상태의 "발견에서 찾기" 같은 행동 문이 다른 화면에서
/// 탭을 갈아탈 때 쓴다(빈 상태는 막다른 길이면 안 된다 — AGENTS 폴리시).
@MainActor
@Observable
final class TabRouter {
    static let shared = TabRouter()

    var selection: Int

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
}

struct RootView: View {
    @State private var showDebug = false

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
        } else if Config.launchValue(after: "--screen") == "collections" {
            // 컬렉션 프로토타입 — 계정 탭 안 푸시라 simctl 로 못 띄운다, 검증 진입로.
            NavigationStack { CollectionsListView() }
        } else if Config.launchValue(after: "--screen") == "collection-detail" {
            // 컬렉션 상세 — 목록 탭으로만 들어가 simctl 로 못 띄운다, 검증 진입로.
            NavigationStack {
                CollectionDetailView(collection: CollectionsMock.slowThinking)
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
            }
        } else if Config.launchValue(after: "--screen") == "connect" {
            // "연결" 시트 — 인게이지에서만 떠 simctl 로 못 띄운다, 검증 진입로.
            Color(uiColor: .systemBackground).ignoresSafeArea()
                .sheet(isPresented: .constant(true)) {
                    ConnectSheet(targetKind: "글", targetTitle: "헥사고날로 갈아탄 지 석 달")
                }
        } else {
            tabs
        }
    }

    private var tabs: some View {
        @Bindable var router = TabRouter.shared
        return tabView(selection: $router.selection)
    }

    private func tabView(selection: Binding<Int>) -> some View {
        // 가입 직후 핸들 정하기 — me 로드 후 username 이 비어 있으면(특히 애플 신규) 풀스크린 게이트.
        let needsUsername = AuthStore.shared.isSignedIn
            && AuthStore.shared.me != nil
            && (AuthStore.shared.me?.username ?? "").isEmpty
        // 스레드식 하단바: 라벨 없는 아이콘-온리 탭 + 스크롤 내릴 때 바가 최소화되는
        // iOS 26 네이티브 동작. 검색에 role 을 주지 않는 건 의도 — role: .search 는
        // Liquid Glass 가 검색을 독립 pill 로 분리하는데, 한 바에 4탭이 모이는 쪽을 택했다.
        // 최소화는 27.0 베타에선 시뮬·실기기 모두 OS 가 안 태운다(2026-06-13 교과서
        // 케이스로 실기기 확정 — 우리 구조 무관). 동작하는 OS 가 오면 그대로 산다.
        return TabView(selection: selection) {
            // 빈 시각 라벨(스레드식)을 유지하면서 VoiceOver 라벨만 단다.
            Tab("", systemImage: "doc.text.image", value: 0) {
                FeedView()
            }
            .accessibilityLabel(Text("피드"))
            Tab("", systemImage: "safari", value: 1) {
                DiscoverView()
            }
            .accessibilityLabel(Text("발견"))
            Tab("", systemImage: "square.and.pencil", value: 2) {
                StudioView()
            }
            .accessibilityLabel(Text("글쓰기"))
            Tab("", systemImage: "magnifyingglass", value: 3) {
                SearchView()
            }
            .accessibilityLabel(Text("검색"))
            Tab("", systemImage: "person.crop.circle", value: 4) {
                AccountView()
            }
            .accessibilityLabel(Text("내 계정"))
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(.brand)
        // Dynamic Type 은 따르되 상한을 둔다 — 그 위 극단 크기는 카드/덱 레이아웃이 깨진다.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .modifier(ToastHost())
        // 관리자만 — 기기를 흔들면 현재 API·앱·유저·기기 진단 화면이 뜬다.
        .sheet(isPresented: $showDebug) { AdminDebugView() }
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
}

#Preview {
    RootView()
}
