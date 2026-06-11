//
//  RootView.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

struct RootView: View {
    var body: some View {
        // 스레드식 하단바: 라벨 없는 아이콘-온리 탭 + 스크롤 내릴 때 바가 최소화되는
        // iOS 26 네이티브 동작. 검색에 role 을 주지 않는 건 의도 — role: .search 는
        // Liquid Glass 가 검색을 독립 pill 로 분리하는데, 한 바에 4탭이 모이는 쪽을 택했다.
        TabView {
            Tab("", systemImage: "doc.text.image") {
                FeedView()
            }
            Tab("", systemImage: "safari") {
                DiscoverView()
            }
            Tab("", systemImage: "magnifyingglass") {
                SearchView()
            }
            Tab("", systemImage: "person.crop.circle") {
                AccountView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(.brand)
    }
}

#Preview {
    RootView()
}
