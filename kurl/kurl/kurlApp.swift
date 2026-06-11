//
//  kurlApp.swift
//  kurl
//
//  Created by 김동현 on 6/7/26.
//

import SwiftUI

@main
struct kurlApp: App {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                if showSplash {
                    SplashView()
                        .zIndex(1)
                        .transition(.opacity)
                }
            }
            .task {
                // 마크 드로잉(~0.4s)+워드마크(~0.8s)가 끝나고 한 박자 머문 뒤 걷는다.
                try? await Task.sleep(for: .seconds(reduceMotion ? 0.6 : 1.6))
                withAnimation(.easeOut(duration: 0.35)) {
                    showSplash = false
                }
            }
        }
    }
}
