//
//  RootView.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

struct RootView: View {
    @State private var selection = Self.initialTab

    /// `--tab write|discover|search|account` — simctl 은 터치를 못 넣으니 스크린샷/목 검증용 진입로.
    private static var initialTab: Int {
        switch Config.launchValue(after: "--tab") {
        case "discover": 1
        case "write": 2
        case "search": 3
        case "account": 4
        default: 0
        }
    }

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
        } else {
            tabs
        }
    }

    private var tabs: some View {
        // 스레드식 하단바: 라벨 없는 아이콘-온리 탭 + 스크롤 내릴 때 바가 최소화되는
        // iOS 26 네이티브 동작. 검색에 role 을 주지 않는 건 의도 — role: .search 는
        // Liquid Glass 가 검색을 독립 pill 로 분리하는데, 한 바에 4탭이 모이는 쪽을 택했다.
        // 최소화는 27.0 베타에선 시뮬·실기기 모두 OS 가 안 태운다(2026-06-13 교과서
        // 케이스로 실기기 확정 — 우리 구조 무관). 동작하는 OS 가 오면 그대로 산다.
        TabView(selection: $selection) {
            // 빈 시각 라벨(스레드식)을 유지하면서 VoiceOver 라벨만 단다.
            Tab("", systemImage: "doc.text.image", value: 0) {
                FeedView()
            }
            .accessibilityLabel(Text("피드"))
            Tab("", systemImage: "safari", value: 1) {
                DiscoverDeckView()
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
    }
}

#Preview {
    RootView()
}
