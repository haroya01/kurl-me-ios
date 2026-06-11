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
        // iOS 26 네이티브 동작. 검색은 role 로 분리돼 Liquid Glass 의 독립 pill 이 된다.
        TabView {
            Tab("", systemImage: "doc.text.image") {
                FeedView()
            }
            Tab("", systemImage: "sparkles") {
                DiscoverView()
            }
            Tab("", systemImage: "person.crop.circle") {
                AccountView()
            }
            Tab("", systemImage: "magnifyingglass", role: .search) {
                SearchView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(.brand)
    }
}

#Preview {
    RootView()
}
