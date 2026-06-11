//
//  RootView.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Tab("피드", systemImage: "doc.text.image") {
                FeedView()
            }
            Tab("발견", systemImage: "sparkles") {
                DiscoverView()
            }
            Tab("검색", systemImage: "magnifyingglass", role: .search) {
                SearchView()
            }
            Tab("내 계정", systemImage: "person.crop.circle") {
                AccountView()
            }
        }
        .tint(.brand)
    }
}

#Preview {
    RootView()
}
